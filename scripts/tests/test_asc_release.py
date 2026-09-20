import unittest

from scripts.asc_client import ASCError
from scripts.asc_release import (
    assert_version_matches,
    parse_version_from_tag,
    read_marketing_version,
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


import os
import tempfile

from scripts.asc_release import (
    APP_INFO_FIELDS,
    VERSION_FIELDS,
    check_limits,
    diff_metadata,
    read_metadata_dir,
)


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


if __name__ == "__main__":
    unittest.main()
