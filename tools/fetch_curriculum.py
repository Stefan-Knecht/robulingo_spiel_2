#!/usr/bin/env python3
"""Download a start curriculum JSON from the Cloudflare R2 bucket."""

from __future__ import annotations

import argparse
import pathlib
import sys

import requests


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch start_curriculum_l_el.json from the curriculum bucket."
    )
    parser.add_argument(
        "--url",
        default="https://aec343e9a0970f4dcdf10224e7414efb.r2.cloudflarestorage.com/curriculum/start_curriculum_l_el.json",
        help="The URL to download (defaults to the Greek reading curriculum).",
    )
    parser.add_argument(
        "--output",
        type=pathlib.Path,
        help="Where to save the JSON (writes to stdout when omitted).",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        response = requests.get(args.url, timeout=15)
        response.raise_for_status()
    except requests.RequestException as err:
        print(f"Failed to fetch curriculum: {err}", file=sys.stderr)
        return 1

    payload = response.text
    if args.output:
        args.output.write_text(payload, encoding="utf-8")
        print(f"Wrote curriculum to {args.output}")
    else:
        print(payload)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
