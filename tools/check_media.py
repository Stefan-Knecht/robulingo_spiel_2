#!/usr/bin/env python3
"""
Check which items from the start curriculum are usable (JSON + image + audio) on the worker.

Defaults match the app:
  - host: robulingo-api.knechtipad-aec.workers.dev
  - api prefix: /api
  - start file: start_curriculum_a.json
  - image variants: base + _01.._06, _1, _2 with webp/png/gif/jpg/jpeg
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import List, Optional, Sequence, Tuple


DEFAULT_HOST = "robulingo-api.knechtipad-aec.workers.dev"
DEFAULT_API_PREFIX = "/api"
DEFAULT_START_FILE = "start_curriculum_a.json"
DEFAULT_LANGS = ["de", "en", "ar", "fr", "es", "it", "ru", "sv", "el", "zh"]
IMAGE_SUFFIXES = [""] + [f"_{i:02d}" for i in range(1, 7)] + ["_1", "_2"]
IMAGE_EXTS = ["webp", "png", "gif", "jpg", "jpeg"]


@dataclass
class CheckResult:
  uuid: str
  json_ok: bool
  image_ok: bool
  image_variants: int
  missing_langs: List[str]
  errors: List[str]

  @property
  def ok(self) -> bool:
    return self.json_ok and self.image_ok and not self.missing_langs and not self.errors


def _url(host: str, api_prefix: str, path: str, query: Optional[dict] = None) -> str:
  base = f"https://{host}{api_prefix}{path}"
  if query:
    return f"{base}?{urllib.parse.urlencode(query)}"
  return base


def _fetch_json(url: str, timeout: float) -> dict:
  with urllib.request.urlopen(url, timeout=timeout) as resp:
    return json.loads(resp.read())


def _check_url(url: str, timeout: float) -> Tuple[bool, int, Optional[str]]:
  # Try HEAD first
  try:
    req = urllib.request.Request(url, method="HEAD")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
      return resp.status == 200, resp.status, None
  except Exception as e:
    head_err = str(e)
  # Fallback to tiny GET with range
  try:
    req = urllib.request.Request(url, headers={"range": "bytes=0-0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
      status = resp.status
      return status in (200, 206), status, None
  except Exception as e:
    return False, -1, f"HEAD:{head_err}; GET:{e}"


def _check_images(host: str, api_prefix: str, uuid: str, timeout: float) -> Tuple[bool, int]:
  found = 0
  for ext in IMAGE_EXTS:
    for suffix in IMAGE_SUFFIXES:
      url = _url(host, api_prefix, "/file", {"key": f"{uuid}{suffix}.{ext}"})
      ok, status, _ = _check_url(url, timeout)
      if ok:
        found += 1
    if found:
      break  # stick to first found extension to mirror app behavior
  return found > 0, found


def _check_json(host: str, api_prefix: str, uuid: str, timeout: float) -> bool:
  url = _url(host, api_prefix, "/file", {"key": f"{uuid}.json"})
  ok, status, _ = _check_url(url, timeout)
  return ok


def _check_audios(host: str, api_prefix: str, uuid: str, langs: Sequence[str], timeout: float) -> List[str]:
  missing = []
  for lang in langs:
    url = _url(host, api_prefix, "/file", {"key": f"{uuid}_{lang}.mp3"})
    ok, status, err = _check_url(url, timeout)
    if not ok:
      suffix = f"status={status}" if status != -1 else "no response"
      detail = f"{suffix}{'' if not err else f' ({err})'}"
      missing.append(f"{lang}:{detail}")
  return missing


def check_items(
    host: str,
    api_prefix: str,
    start_file: str,
    langs: Sequence[str],
    limit: Optional[int],
    timeout: float,
) -> Tuple[List[CheckResult], int, int]:
  curriculum_url = _url(host, api_prefix, "/file", {"key": start_file})
  data = _fetch_json(curriculum_url, timeout)
  entries = (data.get("items") or data.get("item_order") or [])
  uuids: List[str] = []
  for entry in entries:
    if isinstance(entry, str):
      uuids.append(entry)
    elif isinstance(entry, dict) and "uuid" in entry:
      uuids.append(entry["uuid"])
  total_entries = len(uuids)

  results: List[CheckResult] = []
  scanned = 0
  for uuid in uuids:
    scanned += 1
    errors: List[str] = []
    json_ok = _check_json(host, api_prefix, uuid, timeout)
    image_ok = False
    variants = 0
    missing_langs: List[str] = []
    if json_ok:
      image_ok, variants = _check_images(host, api_prefix, uuid, timeout)
    if json_ok and image_ok:
      missing_langs = _check_audios(host, api_prefix, uuid, langs, timeout)
    result = CheckResult(
        uuid=uuid,
        json_ok=json_ok,
        image_ok=image_ok,
        image_variants=variants,
        missing_langs=missing_langs,
        errors=errors,
    )
    if result.ok:
      results.append(result)
      if limit and len(results) >= limit:
        break
  return results, scanned, total_entries


def main(argv: Optional[Sequence[str]] = None) -> int:
  parser = argparse.ArgumentParser(
      description="Check which items from a start curriculum have image + audio on the worker."
  )
  parser.add_argument("--host", default=DEFAULT_HOST, help="Worker host (default: %(default)s)")
  parser.add_argument("--api-prefix", default=DEFAULT_API_PREFIX, help="API prefix (default: %(default)s)")
  parser.add_argument("--start-file", default=DEFAULT_START_FILE, help="Curriculum file key (default: %(default)s)")
  parser.add_argument(
      "--langs",
      nargs="+",
      default=["de"],
      help="Languages to require audio for (default: de). Use 'all' to check all defaults.",
  )
  parser.add_argument(
      "--limit",
      type=int,
      default=10,
      help="Number of complete items to return (default: %(default)s)",
  )
  parser.add_argument("--timeout", type=float, default=10.0, help="HTTP timeout seconds (default: %(default)s)")
  parser.add_argument("--json", action="store_true", help="Output JSON instead of text")
  parser.add_argument(
      "--summary",
      action="store_true",
      help="Print only curriculum total vs complete count (ignores --limit).",
  )
  args = parser.parse_args(argv)

  langs = DEFAULT_LANGS if args.langs == ["all"] else args.langs
  limit = None
  if not args.summary:
    limit = args.limit if args.limit and args.limit > 0 else None
  try:
    results, scanned, total_entries = check_items(
        host=args.host,
        api_prefix=args.api_prefix,
        start_file=args.start_file,
        langs=langs,
        limit=limit,
        timeout=args.timeout,
    )
  except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    return 1

  if args.summary:
    if args.json:
      payload = {
          "curriculum_total": total_entries,
          "complete": len(results),
          "langs": list(langs),
      }
      print(json.dumps(payload, indent=2))
    else:
      print(f"Curriculum items: {total_entries}")
      print(
          f"Complete items (json+image+audio langs={','.join(langs)}): {len(results)}"
      )
    return 0

  if args.json:
    payload = [
        {
            "uuid": r.uuid,
            "json_ok": r.json_ok,
            "image_ok": r.image_ok,
            "image_variants": r.image_variants,
            "missing_langs": r.missing_langs,
            "ok": r.ok,
        }
        for r in results
    ]
    print(json.dumps(payload, indent=2))
    return 0

  target = args.limit if args.limit and args.limit > 0 else "all"
  print(
      f"Scanned {scanned}/{total_entries} items from {args.start_file} on {args.host} "
      f"(langs={','.join(langs)} target={target}): {len(results)} complete"
  )
  for r in results:
    status = "OK" if r.ok else "MISS"
    parts = [
        f"{status}",
        r.uuid,
        f"json={'1' if r.json_ok else '0'}",
        f"img={r.image_variants if r.image_ok else 0}",
    ]
    if r.missing_langs:
      parts.append(f"audio_missing={';'.join(r.missing_langs)}")
    print(" | ".join(parts))
  return 0


if __name__ == "__main__":
  sys.exit(main())
