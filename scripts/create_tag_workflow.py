"""One-shot: create the Xcode Cloud 'Tag Release' workflow.

Deliberately has NO filesAndFoldersRule. Release tags sit on docs commits
(v1.3 -> 1a66996), which a path filter would skip entirely.
"""
from __future__ import annotations

import json
import sys

from scripts.asc_client import ASCError, Client

PRODUCT_ID = "D3A25FB4-477F-477F-98A3-5D0449AA4DDC"
REPOSITORY_ID = "5943e6a7-2168-41d1-b9e8-e2706e92f3a9"
XCODE_VERSION_ID = "31ce63a2-a54f-3e25-b883-dc13290abb7f"
MACOS_VERSION_ID = "31ce63a2-a54f-3e25-b883-dc13290abb7f"

BODY = {
    "data": {
        "type": "ciWorkflows",
        "attributes": {
            "name": "Tag Release",
            "description": "Archive and upload to TestFlight on version tags",
            "isEnabled": True,
            "isLockedForEditing": False,
            "clean": True,
            "containerFilePath": "SnapLedger.xcodeproj",
            "actions": [{
                "name": "Archive - iOS",
                "actionType": "ARCHIVE",
                "platform": "IOS",
                "scheme": "SnapLedger",
                "buildDistributionAudience": "APP_STORE_ELIGIBLE",
                "isRequiredToPass": True,
            }],
            "tagStartCondition": {
                "source": {"isAllMatch": False, "patterns": [{"pattern": "v", "isPrefix": True}]},
                "autoCancel": False,
            },
        },
        "relationships": {
            "product": {"data": {"type": "ciProducts", "id": PRODUCT_ID}},
            "repository": {"data": {"type": "scmRepositories", "id": REPOSITORY_ID}},
            "xcodeVersion": {"data": {"type": "ciXcodeVersions", "id": XCODE_VERSION_ID}},
            "macOsVersion": {"data": {"type": "ciMacOsVersions", "id": MACOS_VERSION_ID}},
        },
    }
}


def main():
    client = Client.from_env()
    status, body = client.request("GET", "/v1/ciProducts/%s/workflows?limit=20" % PRODUCT_ID)
    if status != 200:
        raise ASCError("could not list workflows (%s): %s" % (status, body))
    for workflow in body.get("data", []):
        if workflow["attributes"].get("name") == "Tag Release":
            print("Tag Release already exists: %s" % workflow["id"])
            return 0

    status, body = client.request("POST", "/v1/ciWorkflows", BODY)
    if status not in (200, 201):
        print(json.dumps(body, indent=2, ensure_ascii=False), file=sys.stderr)
        raise ASCError("could not create workflow (%s)" % status)
    print("created Tag Release: %s" % body["data"]["id"])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ASCError as error:
        print("error: %s" % error, file=sys.stderr)
        sys.exit(1)
