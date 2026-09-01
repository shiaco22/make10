#!/usr/bin/env python3
"""Check the store copy in store/play-listing.md against Play's length limits.

Play truncates silently in some places and rejects in others, so the counts are
worth checking before a listing update rather than after.

    python3 tool/branding/check_listing.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LISTING = ROOT / "store/play-listing.md"

# Heading -> Play's maximum length for that field.
LIMITS = {
    "アプリ名": 30,
    "簡単な説明": 80,
    "詳しい説明": 4000,
}


def main() -> int:
    text = LISTING.read_text(encoding="utf-8")
    failures = 0
    for name, limit in LIMITS.items():
        m = re.search(
            rf"^## {re.escape(name)}[^\n]*\n+```\n(.*?)\n```",
            text,
            re.MULTILINE | re.DOTALL,
        )
        if not m:
            print(f"FAIL {name}: no fenced block found under the heading")
            failures += 1
            continue
        body = m.group(1)
        n = len(body)
        status = "ok  " if n <= limit else "FAIL"
        if n > limit:
            failures += 1
        print(f"{status} {name}: {n} / {limit}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
