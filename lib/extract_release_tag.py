#!/usr/bin/env python3
"""Read a Codeberg release JSON payload from stdin and print its tag_name.

Used as the fallback for extract_release_tag() in update-librewolf.sh when jq
is not available. Exits non-zero if tag_name is missing or not a string.
"""

import json
import sys


def main() -> int:
    release = json.load(sys.stdin)
    tag = release.get("tag_name")
    if not isinstance(tag, str):
        raise ValueError("missing tag_name")
    print(tag)
    return 0


if __name__ == "__main__":
    sys.exit(main())
