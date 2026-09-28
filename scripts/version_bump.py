"""Move MARKETING_VERSION past a released tag.

App Store Connect rejects any build whose version is not above the last
approved one, so once a tag ships, every main-push TestFlight upload fails
until main carries the next version.
"""
from __future__ import annotations

import argparse
import re
import sys

from scripts.asc_client import ASCError
from scripts.asc_release import (
    DEFAULT_PBXPROJ,
    MARKETING_VERSION_PATTERN,
    parse_version_from_tag,
    read_marketing_version,
)

VERSION_PATTERN = re.compile(r"^\d+\.\d+(?:\.\d+)?$")


def _version_key(version):
    if not VERSION_PATTERN.match(version or ""):
        raise ASCError("not a version like 1.5 or 1.5.1: %r" % (version,))
    return tuple(int(part) for part in version.split("."))


def next_version(released):
    """The next minor version: 1.4 -> 1.5, 1.2.1 -> 1.3."""
    major, minor = _version_key(released)[:2]
    return "%d.%d" % (major, minor + 1)


def planned_version(released, current):
    """What main should move to, or None when `current` is already past `released`."""
    if _version_key(current) > _version_key(released):
        return None
    return next_version(released)


def set_marketing_version(pbxproj_text, version):
    _version_key(version)
    updated, count = MARKETING_VERSION_PATTERN.subn("MARKETING_VERSION = %s;" % version, pbxproj_text)
    if count == 0:
        raise ASCError("MARKETING_VERSION not found in project.pbxproj")
    return updated


def main(argv=None):
    """Print the new version after writing it, or nothing when no bump is due."""
    parser = argparse.ArgumentParser(description="move MARKETING_VERSION past a released tag")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--pbxproj", default=DEFAULT_PBXPROJ)
    args = parser.parse_args(argv)

    try:
        released = parse_version_from_tag(args.tag)
        with open(args.pbxproj, encoding="utf-8", newline="") as handle:
            text = handle.read()
        current = read_marketing_version(text)
        version = planned_version(released, current)
        if version is None:
            print("MARKETING_VERSION %s is already past %s; nothing to bump" % (current, released),
                  file=sys.stderr)
            return 0
        updated = set_marketing_version(text, version)
        with open(args.pbxproj, "w", encoding="utf-8", newline="") as handle:
            handle.write(updated)
    except ASCError as error:
        print("error: %s" % error, file=sys.stderr)
        return 1

    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
