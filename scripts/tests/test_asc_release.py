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


if __name__ == "__main__":
    unittest.main()
