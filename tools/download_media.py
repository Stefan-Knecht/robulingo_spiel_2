#!/usr/bin/env python3
"""Download media assets (images + audio) for the first N items of a pick manifest."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from typing import Iterable, Sequence

import requests


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Save image/audio assets for manifest entries.")
    parser.add_argument(
        "--manifest",
        default="pick_hoeflich.json",
        help="Manifest key (default: %(default)s).",
    )
    parser.add_argument(
        "--count",
        type=int,
        default=10,
        help="Number of items to download (default: %(default)s).",
    )
    parser.add_argument(
        "--host",
        default="robulingo-api.knechtipad-aec.workers.dev",
        help="Worker host to query (default: %(default)s).",
    )
    parser.add_argument(
        "--prefix",
        default="/api",
        help="API prefix to use (default: %(default)s).",
    )
    parser.add_argument(
        "--dest",
        type=pathlib.Path,
        default=pathlib.Path("downloads"),
        help="Directory where assets are stored (default: %(default)s).",
    )
    return parser.parse_args()


def _build_file_url(host: str, prefix: str, key: str) -> str:
    prefix = prefix if prefix.startswith("/") else f"/{prefix}"
    return f"https://{host}{prefix}/file?key={key}"


def _resolve_entry_list(data: object) -> Sequence[object]:
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        for key in ("entries", "item_order", "items"):
            value = data.get(key)
            if isinstance(value, list):
                return value
        for wrapper in ("manifest", "curriculum"):
            value = data.get(wrapper)
            if isinstance(value, dict):
                inner = value.get("items")
                if isinstance(inner, list):
                    return inner
        if isinstance(data.get("uuids"), list):
            return data["uuids"]  # type: ignore[return-value]
    raise ValueError(f"Cannot extract entries from manifest payload ({type(data).__name__})")


def _iter_item_uuids(entries: Sequence[object]) -> Iterable[str]:
    for entry in entries:
        if isinstance(entry, str):
            yield entry
            continue
        if isinstance(entry, dict):
            uuid = entry.get("uuid") or entry.get("id")
            if isinstance(uuid, str) and uuid:
                yield uuid


def _download_binary(session: requests.Session, url: str, dest: pathlib.Path) -> pathlib.Path:
    dest.parent.mkdir(parents=True, exist_ok=True)
    resp = session.get(url, timeout=20)
    resp.raise_for_status()
    dest.write_bytes(resp.content)
    return dest


def main() -> int:
    args = _parse_args()
    session = requests.Session()
    manifest_url = _build_file_url(args.host, args.prefix, args.manifest)
    try:
        resp = session.get(manifest_url, timeout=20)
        resp.raise_for_status()
    except requests.RequestException as err:
        print(f"Failed to download manifest {args.manifest}: {err}", file=sys.stderr)
        return 1

    try:
        manifest = resp.json()
    except ValueError as err:
        print(f"Invalid JSON for manifest {args.manifest}: {err}", file=sys.stderr)
        return 1

    try:
        entries = _resolve_entry_list(manifest)
    except ValueError as err:
        print(f"{err}", file=sys.stderr)
        return 1

    uuids = list(_iter_item_uuids(entries))
    if not uuids:
        print("No UUIDs found in manifest.", file=sys.stderr)
        return 1

    dest_root = args.dest / args.manifest.replace("/", "_")
    downloaded = 0

    for uuid in uuids[: args.count]:
        print(f"Processing {uuid} ({downloaded + 1}/{args.count})")
        metadata_url = _build_file_url(args.host, args.prefix, f"{uuid}.json")
        try:
            meta_resp = session.get(metadata_url, timeout=20)
            meta_resp.raise_for_status()
        except requests.RequestException as err:
            print(f"  ⚠️ Failed to fetch metadata: {err}", file=sys.stderr)
            continue

        try:
            meta = meta_resp.json()
        except ValueError as err:
            print(f"  ⚠️ Invalid JSON for {uuid}: {err}", file=sys.stderr)
            continue

        filenames = meta.get("filenames") or {}
        audio_key = filenames.get("audio") or meta.get("audio")
        images = filenames.get("images") or []
        if isinstance(images, dict):
            images = list(images.values())

        to_download = []
        if isinstance(audio_key, str) and audio_key:
            to_download.append(("audio", audio_key))
        if isinstance(images, list):
            to_download.extend(("images", key) for key in images if isinstance(key, str) and key)

        if not to_download:
            print("  ⚠️ No media references found.", file=sys.stderr)
            continue

        for media_dir, key in to_download:
            url = _build_file_url(args.host, args.prefix, key)
            target = dest_root / media_dir / key
            if target.exists():
                print(f"    Skipping already-downloaded {key}")
                continue
            try:
                _download_binary(session, url, target)
                print(f"    Downloaded {media_dir}/{key}")
            except requests.RequestException as err:
                print(f"    ⚠️ Failed download {key}: {err}", file=sys.stderr)
        downloaded += 1

    print(f"Finished downloading {downloaded} items into {dest_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
