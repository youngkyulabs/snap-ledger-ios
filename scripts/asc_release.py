"""Tag-triggered release helper for App Store Connect.

Does the parts fastlane deliver cannot: matching a Xcode Cloud build to the
tagged commit, waiting for it to process, and linking it to the version.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
import time

from scripts.asc_client import ASCError, ASCTransportError

TAG_PATTERN = re.compile(r"^v(\d+\.\d+(?:\.\d+)?)$")
MARKETING_VERSION_PATTERN = re.compile(r"MARKETING_VERSION\s*=\s*([^;]+);")

# States in which App Store Connect still lets you edit a version's metadata.
EDITABLE_STATES = frozenset([
    "PREPARE_FOR_SUBMISSION",
    "METADATA_REJECTED",
    "REJECTED",
    "DEVELOPER_REJECTED",
    "INVALID_BINARY",
])


def parse_version_from_tag(tag):
    match = TAG_PATTERN.match(tag or "")
    if not match:
        raise ASCError("tag must look like v1.5 or v1.5.1, got %r" % (tag,))
    return match.group(1)


def read_marketing_version(pbxproj_text):
    values = set()
    for match in MARKETING_VERSION_PATTERN.finditer(pbxproj_text):
        values.add(match.group(1).strip())
    if not values:
        raise ASCError("MARKETING_VERSION not found in project.pbxproj")
    if len(values) > 1:
        raise ASCError("MARKETING_VERSION differs across build configurations: " + ", ".join(sorted(values)))
    return values.pop()


def _version_sort_key(version_string):
    return [int(part) if part.isdigit() else -1 for part in (version_string or "").split(".")]


def _version_string(editable):
    return (editable or {}).get("attributes", {}).get("versionString")


def find_editable_versions(client, app_id, version=None):
    """Every version App Store Connect still lets us edit, newest first.

    REJECTED and DEVELOPER_REJECTED versions sit in EDITABLE_STATES
    indefinitely, and the list endpoint has no documented order, so callers
    must never depend on "whichever one came back first".
    """
    path = "/v1/apps/%s/appStoreVersions?limit=20" % app_id
    if version is not None:
        path += "&filter[versionString]=%s" % version
    status, body = client.request("GET", path)
    if status != 200:
        raise ASCError("could not list versions (%s): %s" % (status, body))
    found = []
    for item in body.get("data", []):
        attributes = item.get("attributes", {})
        if attributes.get("appStoreState") not in EDITABLE_STATES:
            continue
        if version is not None and attributes.get("versionString") != version:
            continue
        found.append(item)
    found.sort(key=lambda item: _version_sort_key(_version_string(item)), reverse=True)
    return found


def find_editable_version(client, app_id, version=None):
    """The editable version for `version`, or the highest editable one."""
    found = find_editable_versions(client, app_id, version)
    return found[0] if found else None


def conflicting_draft(editables, version):
    """The draft deliver would rename, or None if there is nothing to fear.

    deliver edits the app's editable version, renaming it when its version
    string differs from --app_version. A draft that already *is* `version` is
    exactly what we want, so other drafts only matter when that one is absent.
    Checking membership rather than "the first editable one" keeps the answer
    independent of the order App Store Connect happens to list versions in.
    """
    if any(_version_string(editable) == version for editable in editables):
        return None
    return editables[0] if editables else None


def assert_version_matches(editable, expected):
    if editable is None:
        return
    found = editable.get("attributes", {}).get("versionString")
    if found != expected:
        raise ASCError(
            "App Store Connect has an open %s draft but the tag says %s. "
            "fastlane would silently rename that draft, so this run stops. "
            "Close or finish the %s draft first." % (found, expected, found)
        )


# Metadata file name -> appStoreVersionLocalizations attribute.
VERSION_FIELDS = {
    "description.txt": "description",
    "release_notes.txt": "whatsNew",
    "promotional_text.txt": "promotionalText",
    "keywords.txt": "keywords",
    "support_url.txt": "supportUrl",
}

# Metadata file name -> appInfoLocalizations attribute. These are app-level,
# not version-level; changing subtitle triggers review.
APP_INFO_FIELDS = {
    "subtitle.txt": "subtitle",
    "privacy_url.txt": "privacyPolicyUrl",
}

FIELD_LIMITS = {
    "description": 4000,
    "whatsNew": 4000,
    "promotionalText": 170,
    "keywords": 100,
    "subtitle": 30,
}


def _all_fields():
    merged = {}
    merged.update(VERSION_FIELDS)
    merged.update(APP_INFO_FIELDS)
    return merged


def _normalize(value):
    return (value or "").strip()


def read_metadata_dir(path):
    files = {}
    for name in _all_fields():
        full = os.path.join(path, name)
        if not os.path.isfile(full):
            continue
        with open(full, encoding="utf-8") as handle:
            files[name] = handle.read().strip()
    return files


def missing_metadata_files(files):
    """Expected metadata files that are not on disk.

    deliver silently skips fields whose files are absent — that is how
    Promotional Text went missing from 1.4 — so absence must be reported, not
    treated as "nothing to compare".
    """
    return sorted(name for name in _all_fields() if name not in files)


def check_limits(files):
    errors = []
    mapping = _all_fields()
    for name, text in sorted(files.items()):
        field = mapping.get(name)
        limit = FIELD_LIMITS.get(field)
        if limit is None:
            continue
        length = len(_normalize(text))
        if length > limit:
            errors.append("%s is %d characters, limit is %d (%s)" % (field, length, limit, name))
    return errors


def diff_metadata(files, live, mapping):
    differences = []
    for name, field in sorted(mapping.items()):
        if name not in files:
            continue
        want = _normalize(files[name])
        got = _normalize(live.get(field))
        if want != got:
            differences.append((field, want, got))
    return differences


BUILD_FAILURE_STATES = frozenset(["INVALID", "FAILED"])
RUN_FAILURE_STATES = frozenset(["FAILED", "ERRORED", "CANCELED", "SKIPPED"])


def _run_workflow_id(run):
    relationship = (run.get("relationships") or {}).get("workflow") or {}
    return (relationship.get("data") or {}).get("id")


def find_build_run(client, product_id, workflow_id, commit_sha):
    path = "/v1/ciProducts/%s/buildRuns?limit=50&sort=-number&include=workflow" % product_id
    status, body = client.request("GET", path)
    if status != 200:
        raise ASCError("could not list build runs (%s): %s" % (status, body))

    confirmed = []
    unknown = []
    for run in body.get("data", []):
        attributes = run.get("attributes") or {}
        source = attributes.get("sourceCommit") or {}
        if source.get("commitSha") != commit_sha:
            continue
        found_workflow = _run_workflow_id(run)
        # sourceBranchOrTag comes back null, so the workflow relationship is
        # what separates the tag run from the main-push run on the same commit.
        if found_workflow == workflow_id:
            confirmed.append(run)
        elif found_workflow is None:
            unknown.append(run)

    # A run we positively matched to the tag workflow always wins, even against a
    # higher-numbered run whose workflow relationship the API left out.
    pool = confirmed or unknown
    if not pool:
        return None
    if not confirmed:
        print("warning: no run confirmed for workflow %s; falling back to a run with no "
              "workflow relationship" % workflow_id)
    pool.sort(key=lambda run: (run.get("attributes") or {}).get("number") or 0)
    return pool[-1]


def wait_for_build_run(client, product_id, workflow_id, commit_sha,
                       timeout_s=900, interval_s=30, sleep=time.sleep, now=time.monotonic):
    """Poll until the tag's build run is listed.

    The GHA job and the Xcode Cloud run start from the same tag push, so the run
    may not exist yet when we first look.
    """
    deadline = now() + timeout_s
    last_problem = None
    while True:
        try:
            run = find_build_run(client, product_id, workflow_id, commit_sha)
        except ASCTransportError as error:
            # Client.request already retried; a longer outage is just another
            # unsuccessful poll, not a reason to abandon the release.
            run, last_problem = None, str(error)
        if run is not None:
            return run
        if now() >= deadline:
            detail = " (last problem: %s)" % last_problem if last_problem else ""
            raise ASCError(
                "no Xcode Cloud run appeared for commit %s in workflow %s within %ds%s"
                % (commit_sha, workflow_id, timeout_s, detail))
        sleep(interval_s)


def wait_for_valid_build(client, run_id, timeout_s=2400, interval_s=30, sleep=time.sleep, now=time.monotonic):
    deadline = now() + timeout_s
    last_problem = None
    while True:
        # Only ASCTransportError is swallowed here. A terminal answer -- a build
        # that came back INVALID, a run that failed to archive -- raises plain
        # ASCError and must escape, or we would sit out the whole timeout.
        try:
            status, body = client.request("GET", "/v1/ciBuildRuns/%s/builds" % run_id)
            if status != 200:
                last_problem = "builds returned %s: %s" % (status, body)
            if status == 200 and body.get("data"):
                build_id = body["data"][0]["id"]
                build_status, build_body = client.request("GET", "/v1/builds/%s" % build_id)
                if build_status == 200:
                    state = build_body["data"]["attributes"].get("processingState")
                    if state == "VALID":
                        return build_id
                    if state in BUILD_FAILURE_STATES:
                        raise ASCError("build %s finished processing as %s" % (build_id, state))
                else:
                    last_problem = "build %s returned %s: %s" % (build_id, build_status, build_body)

            # A run that failed to archive never produces a build, so without this
            # the loop would spin for the full timeout and blame the wrong thing.
            run_status, run_body = client.request("GET", "/v1/ciBuildRuns/%s" % run_id)
            if run_status == 200:
                run_attributes = run_body["data"]["attributes"]
                completion = run_attributes.get("completionStatus")
                if completion in RUN_FAILURE_STATES:
                    raise ASCError("Xcode Cloud run #%s finished as %s; no build to link"
                                   % (run_attributes.get("number"), completion))
        except ASCTransportError as error:
            last_problem = str(error)

        if now() >= deadline:
            detail = " (last problem: %s)" % last_problem if last_problem else ""
            raise ASCError("timed out after %ds waiting for a VALID build from run %s%s"
                           % (timeout_s, run_id, detail))
        sleep(interval_s)


def link_build(client, version_id, build_id):
    status, body = client.request("GET", "/v1/appStoreVersions/%s?include=build" % version_id)
    if status == 200:
        relationship = (body["data"].get("relationships") or {}).get("build") or {}
        current = (relationship.get("data") or {}).get("id")
        if current == build_id:
            return False

    status, body = client.request(
        "PATCH",
        "/v1/appStoreVersions/%s/relationships/build" % version_id,
        {"data": {"type": "builds", "id": build_id}},
    )
    if status not in (200, 204):
        raise ASCError("could not link build %s (%s): %s" % (build_id, status, body))
    return True


APP_ID = "6772852897"
PRODUCT_ID = "D3A25FB4-477F-477F-98A3-5D0449AA4DDC"
DEFAULT_METADATA_DIR = "fastlane/metadata/ko"
DEFAULT_PBXPROJ = "SnapLedger.xcodeproj/project.pbxproj"


def preflight_problems(tag, marketing_version, files, editable, workflow_id):
    """Everything that must be true before fastlane deliver writes anything.

    deliver is destructive: it overwrites metadata and, with
    --overwrite_screenshots, deletes the existing screenshots first. Every check
    that could stop a release has to happen before that, not after.
    """
    problems = []

    try:
        version = parse_version_from_tag(tag)
    except ASCError as error:
        return [str(error)]

    if marketing_version != version:
        problems.append("tag %s says version %s but MARKETING_VERSION is %s"
                        % (tag, version, marketing_version))

    if editable is not None:
        found = editable.get("attributes", {}).get("versionString")
        if found != version:
            problems.append(
                "App Store Connect has an open %s draft but the tag says %s; deliver would "
                "silently rename it" % (found, version))

    for name in missing_metadata_files(files):
        problems.append("metadata file missing: %s (deliver would skip that field silently)" % name)

    problems.extend(check_limits(files))

    if not (workflow_id or "").strip():
        problems.append("Xcode Cloud workflow id is empty (set XCODE_CLOUD_TAG_WORKFLOW_ID)")

    return problems


def _cmd_preflight(args, client):
    with open(args.pbxproj, encoding="utf-8") as handle:
        marketing = read_marketing_version(handle.read())
    files = read_metadata_dir(args.metadata_dir)

    editable = None
    try:
        version = parse_version_from_tag(args.tag)
    except ASCError:
        version = None
    if version is not None:
        # Every editable version, not just whichever one came back first: a
        # draft that already matches the tag makes the others harmless.
        editable = conflicting_draft(find_editable_versions(client, APP_ID), version)

    problems = preflight_problems(args.tag, marketing, files, editable, args.workflow_id)
    for problem in problems:
        print("BLOCK  %s" % problem)
    if problems:
        print("preflight failed with %d problem(s); nothing was uploaded" % len(problems))
        return 1
    print("preflight clean for %s" % args.tag)
    return 0


def _localization(client, version_id):
    status, body = client.request(
        "GET", "/v1/appStoreVersions/%s/appStoreVersionLocalizations" % version_id)
    if status != 200:
        raise ASCError("could not read localizations (%s): %s" % (status, body))
    for localization in body.get("data", []):
        if localization["attributes"].get("locale") == "ko":
            return localization
    raise ASCError("no ko localization on version %s" % version_id)


def _app_info_localization(client):
    status, body = client.request("GET", "/v1/apps/%s/appInfos" % APP_ID)
    if status != 200:
        raise ASCError("could not read app infos (%s): %s" % (status, body))
    info_id = body["data"][0]["id"]
    status, body = client.request("GET", "/v1/appInfos/%s/appInfoLocalizations" % info_id)
    if status != 200:
        raise ASCError("could not read app info localizations (%s): %s" % (status, body))
    for localization in body.get("data", []):
        if localization["attributes"].get("locale") == "ko":
            return localization
    raise ASCError("no ko app info localization")


def _cmd_audit(args, client):
    files = read_metadata_dir(args.metadata_dir)
    if not files:
        print("no metadata files found in %s" % args.metadata_dir)
        return 1

    limit_errors = check_limits(files)
    for error in limit_errors:
        print("LIMIT  %s" % error)

    editable = find_editable_version(client, APP_ID, args.version)
    if editable is None:
        print("no editable version on App Store Connect; compared limits only")
        return 1 if limit_errors else 0

    print("comparing against App Store Connect version %s" % _version_string(editable))
    version_live = _localization(client, editable["id"])["attributes"]
    info_live = _app_info_localization(client)["attributes"]
    differences = (
        diff_metadata(files, version_live, VERSION_FIELDS)
        + diff_metadata(files, info_live, APP_INFO_FIELDS)
    )
    for field, want, got in differences:
        print("DIFF   %s: repo=%r asc=%r" % (field, want[:40], got[:40]))

    if not differences and not limit_errors:
        print("metadata matches App Store Connect (version %s)" %
              editable["attributes"].get("versionString"))
        return 0
    return 1


def _cmd_link_build(args, client):
    version = parse_version_from_tag(args.tag)
    with open(args.pbxproj, encoding="utf-8") as handle:
        marketing = read_marketing_version(handle.read())
    if marketing != version:
        raise ASCError("tag %s says version %s but MARKETING_VERSION is %s" % (args.tag, version, marketing))

    editable = find_editable_version(client, APP_ID, version)
    assert_version_matches(editable, version)
    if editable is None:
        raise ASCError("no editable version %s on App Store Connect" % version)

    if args.dry_run:
        run = find_build_run(client, PRODUCT_ID, args.workflow_id, args.commit)
        if run is None:
            raise ASCError("no Xcode Cloud run found for commit %s in workflow %s"
                           % (args.commit, args.workflow_id))
    else:
        run = wait_for_build_run(client, PRODUCT_ID, args.workflow_id, args.commit,
                                 timeout_s=args.run_timeout)
    print("matched build run #%s (%s)" % (run["attributes"].get("number"), run["id"]))

    if args.dry_run:
        print("dry run: stopping before waiting for the build")
        return 0

    build_id = wait_for_valid_build(client, run["id"], timeout_s=args.timeout)
    if link_build(client, editable["id"], build_id):
        print("linked build %s to version %s" % (build_id, version))
    else:
        print("build %s was already linked to version %s" % (build_id, version))
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description="App Store Connect release helper")
    subparsers = parser.add_subparsers(dest="command")

    audit = subparsers.add_parser("audit", help="compare repo metadata against App Store Connect")
    audit.add_argument("--metadata-dir", default=DEFAULT_METADATA_DIR)
    audit.add_argument("--version", default=None,
                       help="version to compare against; default is the highest editable one")

    pre = subparsers.add_parser("preflight", help="block a bad release before deliver writes anything")
    pre.add_argument("--tag", required=True)
    pre.add_argument("--workflow-id", default="")
    pre.add_argument("--metadata-dir", default=DEFAULT_METADATA_DIR)
    pre.add_argument("--pbxproj", default=DEFAULT_PBXPROJ)

    link = subparsers.add_parser("link-build", help="wait for the tagged build and link it")
    link.add_argument("--tag", required=True)
    link.add_argument("--commit", required=True)
    link.add_argument("--workflow-id", required=True)
    link.add_argument("--pbxproj", default=DEFAULT_PBXPROJ)
    link.add_argument("--timeout", type=int, default=2400)
    link.add_argument("--run-timeout", type=int, default=900)
    link.add_argument("--dry-run", action="store_true")

    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_usage(sys.stderr)
        return 2

    handlers = {"audit": _cmd_audit, "preflight": _cmd_preflight, "link-build": _cmd_link_build}
    handler = handlers.get(args.command)
    if handler is None:
        print("unknown command: %s" % args.command, file=sys.stderr)
        return 2

    try:
        from scripts.asc_client import Client
        return handler(args, Client.from_env())
    except ASCError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
