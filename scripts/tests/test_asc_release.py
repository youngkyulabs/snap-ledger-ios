import contextlib
import io
import os
import tempfile
import unittest

from scripts.asc_client import ASCError
from scripts.asc_release import (
    APP_INFO_FIELDS,
    VERSION_FIELDS,
    assert_version_matches,
    check_limits,
    diff_metadata,
    find_build_run,
    link_build,
    main,
    parse_version_from_tag,
    read_marketing_version,
    read_metadata_dir,
    wait_for_valid_build,
)


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
            "/v1/ciBuildRuns": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/builds/": [
                (200, {"data": {"attributes": {"processingState": "PROCESSING"}}}),
                (200, {"data": {"attributes": {"processingState": "VALID"}}}),
            ],
        })
        slept = []
        self.assertEqual(
            wait_for_valid_build(client, "run-1", interval_s=5, sleep=slept.append, now=lambda: 0.0),
            "build-1",
        )
        self.assertEqual(slept, [5])

    def test_raises_when_the_build_fails_processing(self):
        client = FakeClient({
            "/v1/ciBuildRuns": [(200, {"data": [{"id": "build-1"}]})],
            "/v1/builds/": [(200, {"data": {"attributes": {"processingState": "INVALID"}}})],
        })
        with self.assertRaises(ASCError) as ctx:
            wait_for_valid_build(client, "run-1", sleep=lambda _: None, now=lambda: 0.0)
        self.assertIn("INVALID", str(ctx.exception))

    def test_raises_after_the_timeout_elapses(self):
        client = FakeClient({
            "/v1/ciBuildRuns": [(200, {"data": []})],
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


if __name__ == "__main__":
    unittest.main()
