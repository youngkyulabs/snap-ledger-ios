import contextlib
import io
import itertools
import os
import tempfile
import unittest

from scripts.asc_client import ASCError, ASCTransportError
from scripts.asc_release import (
    preflight_problems,
    find_editable_version,
    missing_metadata_files,
    wait_for_build_run,
    APP_INFO_FIELDS,
    VERSION_FIELDS,
    assert_version_matches,
    FATAL_STATUSES,
    check_limits,
    conflicting_draft,
    diff_metadata,
    find_build_run,
    find_editable_versions,
    link_build,
    list_app_store_versions,
    main,
    parse_version_from_tag,
    published_release_notes,
    read_marketing_version,
    read_metadata_dir,
    wait_for_valid_build,
    MAX_PAGES,
    RELEASE_NOTES_FILE,
)



def advancing_clock(step=10.0):
    """A clock that always moves forward.

    A constant `now` plus a no-op `sleep` lets a loop that should have raised
    spin forever, so a bug shows up as a hung suite instead of a red test.
    Advancing means every loop eventually meets its deadline and fails loudly.
    """
    ticks = itertools.count(0.0, step)
    return lambda: next(ticks)


class ParseVersionTests(unittest.TestCase):
    def test_accepts_two_and_three_part_versions(self):
        self.assertEqual(parse_version_from_tag("v1.5"), "1.5")
        self.assertEqual(parse_version_from_tag("v1.5.1"), "1.5.1")
        self.assertEqual(parse_version_from_tag("v10.20.30"), "10.20.30")

    def test_rejects_malformed_tags(self):
        for bad in ["1.5", "v1", "v1.5-beta", "release-1.5", "v", "v1.5.1.2", ""]:
            with self.subTest(tag=bad):
                with self.assertRaises(ASCError):
                    parse_version_from_tag(bad)


class MarketingVersionTests(unittest.TestCase):
    def test_reads_single_value_repeated_across_configs(self):
        text = "\n".join([
            "\t\t\t\tMARKETING_VERSION = 1.4;",
            "\t\t\t\tCURRENT_PROJECT_VERSION = 1;",
            "\t\t\t\tMARKETING_VERSION = 1.4;",
        ])
        self.assertEqual(read_marketing_version(text), "1.4")

    def test_rejects_versions_that_differ_across_configs(self):
        text = "MARKETING_VERSION = 1.4;\nMARKETING_VERSION = 1.5;"
        with self.assertRaises(ASCError) as ctx:
            read_marketing_version(text)
        self.assertIn("1.4", str(ctx.exception))
        self.assertIn("1.5", str(ctx.exception))

    def test_rejects_missing_marketing_version(self):
        with self.assertRaises(ASCError):
            read_marketing_version("CURRENT_PROJECT_VERSION = 1;")


class VersionGuardTests(unittest.TestCase):
    def test_passes_when_no_editable_version_exists(self):
        assert_version_matches(None, "1.5")

    def test_passes_when_editable_version_matches(self):
        editable = {"id": "x", "attributes": {"versionString": "1.5"}}
        assert_version_matches(editable, "1.5")

    def test_blocks_when_editable_version_is_a_different_version(self):
        editable = {"id": "x", "attributes": {"versionString": "1.6"}}
        with self.assertRaises(ASCError) as ctx:
            assert_version_matches(editable, "1.5")
        message = str(ctx.exception)
        self.assertIn("1.6", message)
        self.assertIn("1.5", message)


class ReadMetadataDirTests(unittest.TestCase):
    def test_reads_known_files_and_ignores_others(self):
        with tempfile.TemporaryDirectory() as tmp:
            with open(os.path.join(tmp, "description.txt"), "w", encoding="utf-8") as handle:
                handle.write("설명입니다\n")
            with open(os.path.join(tmp, "notes.md"), "w", encoding="utf-8") as handle:
                handle.write("ignored")
            files = read_metadata_dir(tmp)
        self.assertEqual(files, {"description.txt": "설명입니다"})


class CheckLimitsTests(unittest.TestCase):
    def test_flags_promotional_text_over_170_characters(self):
        errors = check_limits({"promotional_text.txt": "가" * 171})
        self.assertEqual(len(errors), 1)
        self.assertIn("promotionalText", errors[0])
        self.assertIn("171", errors[0])

    def test_accepts_text_at_exactly_the_limit(self):
        self.assertEqual(check_limits({"promotional_text.txt": "가" * 170}), [])

    def test_flags_subtitle_and_keywords_independently(self):
        errors = check_limits({"subtitle.txt": "가" * 31, "keywords.txt": "나" * 101})
        self.assertEqual(len(errors), 2)


class DiffMetadataTests(unittest.TestCase):
    def test_trailing_newline_is_not_a_difference(self):
        files = {"description.txt": "설명"}
        live = {"description": "설명\n"}
        self.assertEqual(diff_metadata(files, live, VERSION_FIELDS), [])

    def test_missing_live_value_is_reported(self):
        files = {"promotional_text.txt": "홍보 문구"}
        live = {"promotionalText": None}
        self.assertEqual(diff_metadata(files, live, VERSION_FIELDS), [("promotionalText", "홍보 문구", "")])

    def test_files_without_a_mapping_entry_are_skipped(self):
        self.assertEqual(diff_metadata({"unknown.txt": "x"}, {}, VERSION_FIELDS), [])

    def test_app_info_fields_use_their_own_mapping(self):
        files = {"subtitle.txt": "새 부제"}
        live = {"subtitle": "옛 부제"}
        self.assertEqual(diff_metadata(files, live, APP_INFO_FIELDS), [("subtitle", "새 부제", "옛 부제")])


class FakeClient:
    """Replays queued (status, body) pairs per path prefix and records PATCHes."""

    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        for prefix, queue in self.responses.items():
            if path.startswith(prefix):
                return queue.pop(0) if len(queue) > 1 else queue[0]
        raise AssertionError("unexpected request: %s %s" % (method, path))


def _run(number, sha, workflow_id):
    return {
        "id": "run-%d" % number,
        "attributes": {"number": number, "sourceCommit": {"commitSha": sha}},
        "relationships": {"workflow": {"data": {"type": "ciWorkflows", "id": workflow_id}}},
    }


class FindBuildRunTests(unittest.TestCase):
    def test_picks_the_tag_workflow_run_when_two_runs_share_a_commit(self):
        client = FakeClient({"/v1/ciProducts": [(200, {"data": [
            _run(60, "abc123", "MAIN-WF"),
            _run(61, "abc123", "TAG-WF"),
        ]})]})
        run = find_build_run(client, "PRODUCT", "TAG-WF", "abc123")
        self.assertEqual(run["id"], "run-61")

    def test_picks_the_highest_numbered_run_on_a_rerun(self):
        client = FakeClient({"/v1/ciProducts": [(200, {"data": [
            _run(61, "abc123", "TAG-WF"),
            _run(63, "abc123", "TAG-WF"),
            _run(62, "abc123", "TAG-WF"),
        ]})]})
        self.assertEqual(find_build_run(client, "PRODUCT", "TAG-WF", "abc123")["id"], "run-63")

    def test_returns_none_when_no_run_matches_the_commit(self):
        client = FakeClient({"/v1/ciProducts": [(200, {"data": [_run(60, "other", "TAG-WF")]})]})
        self.assertIsNone(find_build_run(client, "PRODUCT", "TAG-WF", "abc123"))


class WaitForValidBuildTests(unittest.TestCase):
    def test_returns_build_id_once_processing_state_is_valid(self):
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {"number": 61, "completionStatus": None}}})],
            "/v1/builds/": [
                (200, {"data": {"attributes": {"processingState": "PROCESSING"}}}),
                (200, {"data": {"attributes": {"processingState": "VALID"}}}),
            ],
        })
        slept = []
        self.assertEqual(
            wait_for_valid_build(client, "run-1", interval_s=5, sleep=slept.append, now=advancing_clock()),
            "build-1",
        )
        self.assertEqual(slept, [5])

    def test_raises_when_the_build_fails_processing(self):
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {"number": 61, "completionStatus": None}}})],
            "/v1/builds/": [(200, {"data": {"attributes": {"processingState": "INVALID"}}})],
        })
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", sleep=lambda _: None, now=advancing_clock())
        self.assertIn("finished processing as INVALID", str(ctx.exception))
        self.assertNotIn("timed out", str(ctx.exception))

    def test_raises_after_the_timeout_elapses(self):
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": []})],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {"number": 61, "completionStatus": None}}})],
        })
        clock = iter([0.0, 10.0, 9999.0])
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", timeout_s=60, sleep=lambda _: None, now=lambda: next(clock))
        self.assertIn("timed out", str(ctx.exception))


class LinkBuildTests(unittest.TestCase):
    def test_skips_the_patch_when_the_build_is_already_linked(self):
        client = FakeClient({"/v1/appStoreVersions": [(200, {"data": {
            "relationships": {"build": {"data": {"type": "builds", "id": "build-1"}}}
        }})]})
        self.assertFalse(link_build(client, "version-1", "build-1"))
        self.assertEqual([method for method, _, _ in client.calls], ["GET"])

    def test_patches_when_a_different_build_is_linked(self):
        client = FakeClient({
            "/v1/appStoreVersions/version-1?": [(200, {"data": {
                "relationships": {"build": {"data": {"type": "builds", "id": "build-0"}}}
            }})],
            "/v1/appStoreVersions/version-1/relationships/build": [(204, b"")],
        })
        self.assertTrue(link_build(client, "version-1", "build-1"))
        self.assertEqual([method for method, _, _ in client.calls], ["GET", "PATCH"])


class MainTests(unittest.TestCase):
    def test_no_command_returns_usage_error(self):
        self.assertEqual(main([]), 2)

    def test_unknown_command_exits_with_argparse_error(self):
        # argparse rejects an unknown subcommand before main() can dispatch it.
        with contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as ctx:
                main(["nonsense-command"])
        self.assertEqual(ctx.exception.code, 2)

    def test_help_returns_zero(self):
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as ctx:
                main(["--help"])
        self.assertEqual(ctx.exception.code, 0)


class FindEditableVersionTests(unittest.TestCase):
    def test_picks_the_version_matching_the_tag_not_the_first_editable_one(self):
        client = FakeClient({"/v1/apps": [(200, {"data": [
            {"id": "old", "attributes": {"versionString": "1.4", "appStoreState": "DEVELOPER_REJECTED"}},
            {"id": "new", "attributes": {"versionString": "1.5", "appStoreState": "PREPARE_FOR_SUBMISSION"}},
        ]})]})
        self.assertEqual(find_editable_version(client, "APP", "1.5")["id"], "new")

    def test_without_a_version_returns_the_only_editable_one(self):
        client = FakeClient({"/v1/apps": [(200, {"data": [
            {"id": "old", "attributes": {"versionString": "1.4", "appStoreState": "DEVELOPER_REJECTED"}},
        ]})]})
        self.assertEqual(find_editable_version(client, "APP")["id"], "old")

    def test_without_a_version_the_highest_wins_whatever_the_response_order(self):
        rows = [
            {"id": "old", "attributes": {"versionString": "1.4", "appStoreState": "DEVELOPER_REJECTED"}},
            {"id": "new", "attributes": {"versionString": "1.10", "appStoreState": "PREPARE_FOR_SUBMISSION"}},
        ]
        for order in (rows, list(reversed(rows))):
            with self.subTest(order=[row["id"] for row in order]):
                client = FakeClient({"/v1/apps": [(200, {"data": list(order)})]})
                self.assertEqual(find_editable_version(client, "APP")["id"], "new")

    def test_non_editable_states_are_dropped(self):
        client = FakeClient({"/v1/apps": [(200, {"data": [
            {"id": "live", "attributes": {"versionString": "1.4", "appStoreState": "READY_FOR_SALE"}},
        ]})]})
        self.assertEqual(find_editable_versions(client, "APP"), [])
        self.assertIsNone(find_editable_version(client, "APP"))


class ConflictingDraftTests(unittest.TestCase):
    """Which open draft, if any, deliver would rename out from under us."""

    @staticmethod
    def _draft(version_string):
        return {"id": version_string, "attributes": {"versionString": version_string}}

    def test_nothing_open_is_no_conflict(self):
        self.assertIsNone(conflicting_draft([], "1.5"))

    def test_a_draft_for_our_own_version_is_no_conflict(self):
        drafts = [self._draft("1.5")]
        self.assertIsNone(conflicting_draft(drafts, "1.5"))

    def test_another_version_alone_is_the_conflict(self):
        drafts = [self._draft("1.6")]
        self.assertEqual(conflicting_draft(drafts, "1.5")["id"], "1.6")

    def test_a_stale_draft_beside_our_own_does_not_block(self):
        # A lingering DEVELOPER_REJECTED 1.4 next to the real 1.5 draft used to
        # block the release or not depending on the order ASC listed them in.
        drafts = [self._draft("1.4"), self._draft("1.5")]
        self.assertIsNone(conflicting_draft(drafts, "1.5"))
        self.assertIsNone(conflicting_draft(list(reversed(drafts)), "1.5"))


def _version_row(item_id, version_string, state):
    return {"id": item_id,
            "attributes": {"versionString": version_string, "appStoreState": state}}


class PagingClient:
    """Serves canned appStoreVersions pages and records the paths asked for."""

    def __init__(self, pages):
        self.pages = list(pages)
        self.paths = []

    def request(self, method, path, body=None):
        self.paths.append(path)
        return self.pages.pop(0)


NEXT_PAGE = "https://api.appstoreconnect.apple.com/v1/apps/APP/appStoreVersions?cursor=2"


class VersionPagingTests(unittest.TestCase):
    """One capped page made the rename guard depend on what fit in it."""

    def test_a_draft_beyond_the_first_page_is_still_found(self):
        client = PagingClient([
            (200, {"data": [_version_row("live", "1.4", "READY_FOR_SALE")],
                   "links": {"next": NEXT_PAGE}}),
            (200, {"data": [_version_row("draft", "1.6", "PREPARE_FOR_SUBMISSION")]}),
        ])
        self.assertEqual([v["id"] for v in find_editable_versions(client, "APP")], ["draft"])
        self.assertEqual(client.paths[1], NEXT_PAGE)

    def test_a_draft_on_a_later_page_still_blocks_the_rename(self):
        client = PagingClient([
            (200, {"data": [_version_row("live", "1.4", "READY_FOR_SALE")],
                   "links": {"next": NEXT_PAGE}}),
            (200, {"data": [_version_row("draft", "1.6", "PREPARE_FOR_SUBMISSION")]}),
        ])
        conflict = conflicting_draft(find_editable_versions(client, "APP"), "1.5")
        self.assertEqual(conflict["id"], "draft")

    def test_a_repeating_next_link_does_not_loop_forever(self):
        same = NEXT_PAGE
        client = PagingClient([(200, {"data": [], "links": {"next": same}})] * 2)
        self.assertEqual(list_app_store_versions(client, "APP"), [])
        self.assertEqual(len(client.paths), 2)

    def test_an_endless_pager_gives_up_instead_of_spinning(self):
        class EndlessPager:
            def __init__(self):
                self.calls = 0

            def request(self, method, path, body=None):
                self.calls += 1
                return (200, {"data": [],
                              "links": {"next": "%s&p=%d" % (NEXT_PAGE, self.calls)}})

        client = EndlessPager()
        with self.assertRaises(ASCError):
            list_app_store_versions(client, "APP")
        self.assertEqual(client.calls, MAX_PAGES)


class PublishedReleaseNotesTests(unittest.TestCase):
    """The notes the store already shows, so a forgotten rewrite is visible."""

    @staticmethod
    def _client(localizations):
        return FakeClient({"/v1/appStoreVersions/": [(200, {"data": localizations})]})

    def test_reads_the_newest_version_that_is_not_ours(self):
        versions = [
            _version_row("a", "1.3", "REPLACED_WITH_NEW_VERSION"),
            _version_row("b", "1.4", "READY_FOR_SALE"),
            _version_row("c", "1.5", "PREPARE_FOR_SUBMISSION"),
        ]
        client = self._client([{"attributes": {"locale": "ko", "whatsNew": "1.4 notes"}}])
        self.assertEqual(published_release_notes(client, versions, "1.5"), ("1.4", "1.4 notes"))
        self.assertEqual(client.calls[0][1],
                         "/v1/appStoreVersions/b/appStoreVersionLocalizations")

    def test_nothing_to_compare_when_ours_is_the_only_version(self):
        versions = [_version_row("c", "1.5", "PREPARE_FOR_SUBMISSION")]
        self.assertIsNone(published_release_notes(FakeClient({}), versions, "1.5"))

    def test_nothing_to_compare_without_a_ko_localization(self):
        versions = [_version_row("b", "1.4", "READY_FOR_SALE")]
        client = self._client([{"attributes": {"locale": "en-US", "whatsNew": "x"}}])
        self.assertIsNone(published_release_notes(client, versions, "1.5"))


class StaleReleaseNotesTests(unittest.TestCase):
    """release_notes.txt passes presence and length checks while stale."""

    def _files(self, notes):
        files = {name: "x" for name in VERSION_FIELDS}
        files.update({name: "x" for name in APP_INFO_FIELDS})
        files[RELEASE_NOTES_FILE] = notes
        return files

    def test_blocks_notes_identical_to_the_published_ones(self):
        problems = preflight_problems(
            tag="v1.5", marketing_version="1.5", files=self._files("• 1.4 이야기"),
            editable=None, workflow_id="WF", published_notes=("1.4", "• 1.4 이야기\n"))
        self.assertTrue(any(RELEASE_NOTES_FILE in p and "1.4" in p for p in problems),
                        problems)

    def test_allows_notes_that_were_actually_rewritten(self):
        self.assertEqual(preflight_problems(
            tag="v1.5", marketing_version="1.5", files=self._files("• 1.5 이야기"),
            editable=None, workflow_id="WF", published_notes=("1.4", "• 1.4 이야기")), [])

    def test_no_comparison_available_does_not_block(self):
        self.assertEqual(preflight_problems(
            tag="v1.5", marketing_version="1.5", files=self._files("• 1.4 이야기"),
            editable=None, workflow_id="WF", published_notes=None), [])


class BuildRunPreferenceTests(unittest.TestCase):
    def test_confirmed_workflow_run_beats_a_higher_numbered_unknown_run(self):
        unknown = _run(62, "abc123", "TAG-WF")
        unknown["relationships"] = {}
        client = FakeClient({"/v1/ciProducts": [(200, {"data": [_run(61, "abc123", "TAG-WF"), unknown]})]})
        self.assertEqual(find_build_run(client, "PRODUCT", "TAG-WF", "abc123")["id"], "run-61")

    def test_falls_back_to_unknown_runs_when_none_are_confirmed(self):
        unknown = _run(62, "abc123", "TAG-WF")
        unknown["relationships"] = {}
        client = FakeClient({"/v1/ciProducts": [(200, {"data": [unknown]})]})
        self.assertEqual(find_build_run(client, "PRODUCT", "TAG-WF", "abc123")["id"], "run-62")


class WaitForBuildRunTests(unittest.TestCase):
    def test_returns_the_run_once_it_appears(self):
        client = FakeClient({"/v1/ciProducts": [
            (200, {"data": []}),
            (200, {"data": [_run(61, "abc123", "TAG-WF")]}),
        ]})
        run = wait_for_build_run(client, "PRODUCT", "TAG-WF", "abc123",
                                 interval_s=7, sleep=lambda _: None, now=advancing_clock())
        self.assertEqual(run["id"], "run-61")

    def test_raises_when_the_run_never_appears(self):
        client = FakeClient({"/v1/ciProducts": [(200, {"data": []})]})
        clock = iter([0.0, 5.0, 9999.0])
        with self.assertRaises(ASCError) as ctx:
            wait_for_build_run(client, "PRODUCT", "TAG-WF", "abc123",
                               timeout_s=60, sleep=lambda _: None, now=lambda: next(clock))
        self.assertIn("no Xcode Cloud run", str(ctx.exception))


class BuildRunFailureTests(unittest.TestCase):
    def test_fails_fast_when_the_run_itself_failed(self):
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": []})],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {
                "number": 61, "executionProgress": "COMPLETE", "completionStatus": "FAILED"}}})],
        })
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", sleep=lambda _: None, now=advancing_clock())
        message = str(ctx.exception)
        self.assertIn("no build to link", message)
        self.assertNotIn("timed out", message)
        self.assertIn("FAILED", message)
        self.assertIn("61", message)


class MissingMetadataTests(unittest.TestCase):
    def test_reports_a_metadata_file_that_is_absent(self):
        files = {name: "x" for name in VERSION_FIELDS}
        files.update({name: "x" for name in APP_INFO_FIELDS})
        del files["promotional_text.txt"]
        self.assertEqual(missing_metadata_files(files), ["promotional_text.txt"])

    def test_reports_nothing_when_every_file_is_present(self):
        files = {name: "x" for name in VERSION_FIELDS}
        files.update({name: "x" for name in APP_INFO_FIELDS})
        self.assertEqual(missing_metadata_files(files), [])


class PreflightProblemsTests(unittest.TestCase):
    """The gate that must run BEFORE fastlane deliver touches anything."""

    def _files(self):
        files = {name: "x" for name in VERSION_FIELDS}
        files.update({name: "x" for name in APP_INFO_FIELDS})
        return files

    def test_clean_when_everything_lines_up(self):
        self.assertEqual(
            preflight_problems(tag="v1.5", marketing_version="1.5", files=self._files(),
                               editable=None, workflow_id="WF"), [])

    def test_blocks_a_malformed_tag(self):
        problems = preflight_problems(tag="v1.5-beta", marketing_version="1.5",
                                      files=self._files(), editable=None, workflow_id="WF")
        self.assertTrue(any("v1.5-beta" in p for p in problems))

    def test_blocks_when_marketing_version_disagrees(self):
        problems = preflight_problems(tag="v1.5", marketing_version="1.4",
                                      files=self._files(), editable=None, workflow_id="WF")
        self.assertTrue(any("MARKETING_VERSION" in p for p in problems))

    def test_blocks_when_another_version_draft_is_open(self):
        editable = {"id": "x", "attributes": {"versionString": "1.6"}}
        problems = preflight_problems(tag="v1.5", marketing_version="1.5",
                                      files=self._files(), editable=editable, workflow_id="WF")
        self.assertTrue(any("1.6" in p for p in problems))

    def test_blocks_a_missing_metadata_file(self):
        files = self._files()
        del files["promotional_text.txt"]
        problems = preflight_problems(tag="v1.5", marketing_version="1.5", files=files,
                                      editable=None, workflow_id="WF")
        self.assertTrue(any("promotional_text.txt" in p for p in problems))

    def test_blocks_text_over_the_character_limit(self):
        files = self._files()
        files["promotional_text.txt"] = "가" * 171
        problems = preflight_problems(tag="v1.5", marketing_version="1.5", files=files,
                                      editable=None, workflow_id="WF")
        self.assertTrue(any("promotionalText" in p for p in problems))

    def test_blocks_an_empty_workflow_id(self):
        problems = preflight_problems(tag="v1.5", marketing_version="1.5", files=self._files(),
                                      editable=None, workflow_id="")
        self.assertTrue(any("workflow" in p.lower() for p in problems))



class TransientFailureTests(unittest.TestCase):
    """An App Store Connect blip must not end a release deliver already wrote."""

    class FlakyClient:
        """Raises a transport error the first `failures` times, then replays."""

        def __init__(self, failures, inner):
            self.failures = failures
            self.inner = inner
            self.raised = 0

        def request(self, method, path, body=None):
            if self.raised < self.failures:
                self.raised += 1
                raise ASCTransportError("GET %s failed after 3 attempts (HTTP 503)" % path)
            return self.inner.request(method, path, body)

    def test_build_poll_outlasts_a_transport_error(self):
        inner = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {"number": 61, "completionStatus": None}}})],
            "/v1/builds/": [(200, {"data": {"attributes": {"processingState": "VALID"}}})],
        })
        client = self.FlakyClient(2, inner)
        self.assertEqual(
            wait_for_valid_build(client, "run-1", interval_s=5, sleep=lambda _: None, now=advancing_clock()),
            "build-1",
        )
        self.assertEqual(client.raised, 2)

    def test_a_failed_build_still_raises_through_the_new_handler(self):
        # The guard must swallow transport errors only; a terminal INVALID has
        # to escape. A handler one notch too broad (except ASCError) would
        # swallow it and poll out the whole timeout instead, so this asserts the
        # loop never slept -- the message alone would not catch that, because the
        # timeout text quotes last_problem and would contain "INVALID" too.
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {"number": 61, "completionStatus": None}}})],
            "/v1/builds/": [(200, {"data": {"attributes": {"processingState": "INVALID"}}})],
        })
        slept = []
        clock = iter([0.0, 10.0, 9999.0])
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", timeout_s=60,
                                 sleep=slept.append, now=lambda: next(clock))
        self.assertIn("finished processing as INVALID", str(ctx.exception))
        self.assertNotIn("timed out", str(ctx.exception))
        self.assertEqual(slept, [])
        self.assertNotIsInstance(ctx.exception, ASCTransportError)

    def test_timeout_message_names_the_transport_problem(self):
        inner = FakeClient({"/v1/ciProducts": [(200, {"data": []})]})
        client = self.FlakyClient(99, inner)
        clock = iter([0.0, 5.0, 9999.0])
        with self.assertRaises(ASCError) as ctx:
            wait_for_build_run(client, "PRODUCT", "TAG-WF", "abc123",
                               timeout_s=60, sleep=lambda _: None, now=lambda: next(clock))
        self.assertIn("HTTP 503", str(ctx.exception))

    def test_run_poll_outlasts_a_transport_error(self):
        inner = FakeClient({"/v1/ciProducts": [(200, {"data": [_run(61, "abc123", "TAG-WF")]})]})
        client = self.FlakyClient(1, inner)
        run = wait_for_build_run(client, "PRODUCT", "TAG-WF", "abc123",
                                 interval_s=7, sleep=lambda _: None, now=advancing_clock())
        self.assertEqual(run["id"], "run-61")



class FatalStatusTests(unittest.TestCase):
    """401/403 is the same answer on every poll -- leave, do not wait it out."""

    def test_an_unauthorized_builds_listing_fails_immediately(self):
        client = FakeClient({"/v1/ciBuildRuns/run-1/builds": [(401, {"errors": []})]})
        slept = []
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", timeout_s=2400,
                                 sleep=slept.append, now=advancing_clock())
        self.assertIn("401", str(ctx.exception))
        self.assertNotIn("timed out", str(ctx.exception))
        self.assertEqual(slept, [])

    def test_a_forbidden_build_detail_fails_immediately(self):
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/builds/": [(403, {"errors": []})],
        })
        slept = []
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", timeout_s=2400,
                                 sleep=slept.append, now=advancing_clock())
        self.assertIn("403", str(ctx.exception))
        self.assertEqual(slept, [])

    def test_a_transient_500_is_still_waited_out(self):
        # Only permanent answers are fatal; a 5xx that reaches here keeps polling.
        self.assertNotIn(500, FATAL_STATUSES)
        self.assertNotIn(404, FATAL_STATUSES)
        client = FakeClient({
            "/v1/ciBuildRuns/run-1/builds": [
                (500, {"errors": []}),
                (200, {"data": [{"id": "build-1"}]}),
            ],
            "/v1/ciBuildRuns/run-1": [(200, {"data": {"attributes": {"number": 61, "completionStatus": None}}})],
            "/v1/builds/": [(200, {"data": {"attributes": {"processingState": "VALID"}}})],
        })
        slept = []
        self.assertEqual(
            wait_for_valid_build(client, "run-1", interval_s=5,
                                 sleep=slept.append, now=advancing_clock()),
            "build-1")
        self.assertEqual(slept, [5])


if __name__ == "__main__":
    unittest.main()
