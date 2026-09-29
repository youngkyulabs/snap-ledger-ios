import contextlib
import io
import os
import tempfile
import unittest

from scripts.asc_client import ASCError
from scripts.asc_release import DEFAULT_PBXPROJ, read_marketing_version
from scripts.version_bump import main, next_version, planned_version, set_marketing_version

PROJECT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, os.pardir,
                            DEFAULT_PBXPROJ)

TWO_CONFIGS = (
    "\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = \"찰칵가계부\";\n"
    "\t\t\t\tMARKETING_VERSION = 1.4;\n"
    "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.youngkyu.snapledger;\n"
    "\t\t\t\tMARKETING_VERSION = 1.4;\n"
)


class NextVersionTests(unittest.TestCase):
    def test_raises_minor_and_drops_patch(self):
        self.assertEqual(next_version("1.4"), "1.5")
        self.assertEqual(next_version("1.2.1"), "1.3")
        self.assertEqual(next_version("1.9"), "1.10")

    def test_rejects_non_numeric_versions(self):
        for bad in ("1.4-beta", "1", "", None, "1.4\n", "١.٤"):
            with self.assertRaises(ASCError):
                next_version(bad)


class PlannedVersionTests(unittest.TestCase):
    def test_moves_past_a_release_main_still_carries(self):
        self.assertEqual(planned_version("1.4", "1.4"), "1.5")

    def test_skips_when_main_is_already_ahead(self):
        self.assertIsNone(planned_version("1.4", "1.5"))
        self.assertIsNone(planned_version("1.4", "1.4.1"))
        self.assertIsNone(planned_version("1.4", "2.0"))

    def test_compares_numerically_not_as_text(self):
        self.assertIsNone(planned_version("1.9", "1.10"))
        self.assertEqual(planned_version("1.10", "1.9"), "1.11")


class SetMarketingVersionTests(unittest.TestCase):
    def test_rewrites_every_build_configuration_and_nothing_else(self):
        updated = set_marketing_version(TWO_CONFIGS, "1.5")
        self.assertEqual(updated, TWO_CONFIGS.replace("1.4;", "1.5;"))

    def test_rejects_a_malformed_version(self):
        for bad in ("1.5;\n\t\t\t\tFOO = 1", "1.5\n", "١.٥"):
            with self.assertRaises(ASCError):
                set_marketing_version(TWO_CONFIGS, bad)

    def test_real_project_file_stays_uniform(self):
        with open(PROJECT_FILE, encoding="utf-8") as handle:
            original = handle.read()
        current = read_marketing_version(original)
        updated = set_marketing_version(original, "9.9")

        self.assertEqual(read_marketing_version(updated), "9.9")
        restored = updated.replace("MARKETING_VERSION = 9.9;", "MARKETING_VERSION = %s;" % current)
        self.assertEqual(restored, original)


class MainTests(unittest.TestCase):
    def run_main(self, text, tag):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "project.pbxproj")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(text)
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                code = main(["--tag", tag, "--pbxproj", path])
            with open(path, encoding="utf-8") as handle:
                return code, stdout.getvalue(), handle.read()

    def test_writes_the_next_version_and_prints_it(self):
        code, printed, written = self.run_main(TWO_CONFIGS, "v1.4")
        self.assertEqual(code, 0)
        self.assertEqual(printed, "1.5\n")
        self.assertEqual(read_marketing_version(written), "1.5")

    def test_prints_nothing_and_leaves_the_file_when_main_is_ahead(self):
        ahead = TWO_CONFIGS.replace("1.4;", "1.5;")
        code, printed, written = self.run_main(ahead, "v1.4")
        self.assertEqual(code, 0)
        self.assertEqual(printed, "")
        self.assertEqual(written, ahead)

    def test_fails_on_a_malformed_tag_without_touching_the_file(self):
        code, printed, written = self.run_main(TWO_CONFIGS, "release-1.4")
        self.assertEqual(code, 1)
        self.assertEqual(printed, "")
        self.assertEqual(written, TWO_CONFIGS)

    def test_fails_on_a_malformed_marketing_version_without_touching_the_file(self):
        malformed = TWO_CONFIGS.replace("1.4;", "\"$(VERSION)\";")
        code, printed, written = self.run_main(malformed, "v1.4")
        self.assertEqual(code, 1)
        self.assertEqual(printed, "")
        self.assertEqual(written, malformed)


if __name__ == "__main__":
    unittest.main()
