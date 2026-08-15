#!/usr/bin/env python3
"""Extract fields from a Forgejo release JSON payload.

Prints tag_name by default, or the optional release body with --body. Used as
update-librewolf.sh's fallback when jq is not available.
"""

import json
import sys


def main() -> int:
    release = json.load(sys.stdin)

    if sys.argv[1:] == ["--body"]:
        body = release.get("body")
        print(body if isinstance(body, str) else "")
        return 0
    if sys.argv[1:]:
        raise ValueError(f"unknown option: {sys.argv[1]}")

    tag = release.get("tag_name")
    if not isinstance(tag, str):
        raise ValueError("missing tag_name")
    print(tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
