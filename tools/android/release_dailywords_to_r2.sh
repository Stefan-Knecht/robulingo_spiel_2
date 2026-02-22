#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: tools/android/release_dailywords_to_r2.sh --bucket <name> [options]

Build + upload a signed dailywords release APK to Cloudflare R2.

Options:
  --bucket <name>           R2 bucket name (required)
  --prefix <path>           Object key prefix (default: releases/android/dailywords)
  --public-base-url <url>   Public base URL for resulting links (optional)
  --build-name <name>       Override app version name
  --build-number <number>   Override app version code
  --skip-pub-get            Skip flutter pub get in build step
  --wrangler-config <path>  Wrangler config path override
  -h, --help                Show this help
EOF
}

BUCKET=""
PREFIX="releases/android/dailywords"
PUBLIC_BASE_URL=""
BUILD_NAME=""
BUILD_NUMBER=""
SKIP_PUB_GET=0
WRANGLER_CONFIG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)
      BUCKET="${2:-}"
      shift 2
      ;;
    --prefix)
      PREFIX="${2:-}"
      shift 2
      ;;
    --public-base-url)
      PUBLIC_BASE_URL="${2:-}"
      shift 2
      ;;
    --build-name)
      BUILD_NAME="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=1
      shift
      ;;
    --wrangler-config)
      WRANGLER_CONFIG="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$BUCKET" ]]; then
  echo "Missing required --bucket option." >&2
  exit 3
fi

BUILD_ARGS=()
if [[ -n "$BUILD_NAME" ]]; then
  BUILD_ARGS+=(--build-name "$BUILD_NAME")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  BUILD_ARGS+=(--build-number "$BUILD_NUMBER")
fi
if [[ "$SKIP_PUB_GET" -eq 1 ]]; then
  BUILD_ARGS+=(--skip-pub-get)
fi

if [[ -n "$BUILD_NAME" || -n "$BUILD_NUMBER" || "$SKIP_PUB_GET" -eq 1 ]]; then
  "$ROOT_DIR/tools/android/build_dailywords_release_apk.sh" "${BUILD_ARGS[@]}"
else
  "$ROOT_DIR/tools/android/build_dailywords_release_apk.sh"
fi

UPLOAD_ARGS=(
  --apk "$ROOT_DIR/build/releases/android/dailywords/dailywords-latest.apk"
  --bucket "$BUCKET"
  --prefix "$PREFIX"
)
if [[ -n "$PUBLIC_BASE_URL" ]]; then
  UPLOAD_ARGS+=(--public-base-url "$PUBLIC_BASE_URL")
fi
if [[ -n "$WRANGLER_CONFIG" ]]; then
  UPLOAD_ARGS+=(--wrangler-config "$WRANGLER_CONFIG")
fi

"$ROOT_DIR/tools/android/upload_dailywords_apk_r2.sh" "${UPLOAD_ARGS[@]}"
