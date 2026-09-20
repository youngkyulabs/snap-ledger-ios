"""Tag-triggered release helper for App Store Connect.

Does the parts fastlane deliver cannot: matching a Xcode Cloud build to the
tagged commit, waiting for it to process, and linking it to the version.
"""
from __future__ import annotations

import os
import re
import time

from scripts.asc_client import ASCError

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


def find_editable_version(client, app_id):
    status, body = client.request("GET", "/v1/apps/%s/appStoreVersions?limit=20" % app_id)
    if status != 200:
        raise ASCError("could not list versions (%s): %s" % (status, body))
    for version in body.get("data", []):
        if version.get("attributes", {}).get("appStoreState") in EDITABLE_STATES:
            return version
    return None


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


def _run_workflow_id(run):
    relationship = (run.get("relationships") or {}).get("workflow") or {}
    return (relationship.get("data") or {}).get("id")


def find_build_run(client, product_id, workflow_id, commit_sha):
    path = "/v1/ciProducts/%s/buildRuns?limit=50&include=workflow" % product_id
    status, body = client.request("GET", path)
    if status != 200:
        raise ASCError("could not list build runs (%s): %s" % (status, body))

    matches = []
    for run in body.get("data", []):
        attributes = run.get("attributes") or {}
        source = attributes.get("sourceCommit") or {}
        if source.get("commitSha") != commit_sha:
            continue
        found_workflow = _run_workflow_id(run)
        # sourceBranchOrTag comes back null, so the workflow relationship is
        # what separates the tag run from the main-push run on the same commit.
        if found_workflow is not None and found_workflow != workflow_id:
            continue
        matches.append(run)

    if not matches:
        return None
    matches.sort(key=lambda run: (run.get("attributes") or {}).get("number") or 0)
    return matches[-1]


def wait_for_valid_build(client, run_id, timeout_s=2400, interval_s=30, sleep=time.sleep, now=time.monotonic):
    deadline = now() + timeout_s
    while True:
        status, body = client.request("GET", "/v1/ciBuildRuns/%s/builds" % run_id)
        if status == 200 and body.get("data"):
            build_id = body["data"][0]["id"]
            build_status, build_body = client.request("GET", "/v1/builds/%s" % build_id)
            if build_status == 200:
                state = build_body["data"]["attributes"].get("processingState")
                if state == "VALID":
                    return build_id
                if state in BUILD_FAILURE_STATES:
                    raise ASCError("build %s finished processing as %s" % (build_id, state))
        if now() >= deadline:
            raise ASCError("timed out after %ds waiting for a VALID build from run %s" % (timeout_s, run_id))
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
