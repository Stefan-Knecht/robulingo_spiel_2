#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: tools/android/upload_dailywords_apk_r2.sh [options]

Upload a built dailywords APK to Cloudflare R2 via Wrangler.

Options:
  --apk <path>              APK file path (default: build/releases/android/dailywords/dailywords-latest.apk)
  --bucket <name>           R2 bucket name (or env R2_APK_BUCKET)
  --prefix <path>           Object key prefix (default: releases/android/dailywords)
  --public-base-url <url>   Public base URL for download links (optional)
  --wrangler-config <path>  Wrangler config path (default: tools/worker/wrangler.toml if present)
  --local                   Upload to Wrangler local storage (default is remote Cloudflare R2)
  --skip-login              Skip automatic interactive Wrangler login check
  -h, --help                Show this help
EOF
}

if ! command -v wrangler >/dev/null 2>&1; then
  echo "wrangler not found on PATH (install: npm i -g wrangler)" >&2
  exit 1
fi
if ! command -v shasum >/dev/null 2>&1; then
  echo "shasum not found on PATH" >&2
  exit 1
fi

APK_PATH="$ROOT_DIR/build/releases/android/dailywords/dailywords-latest.apk"
BUCKET="${R2_APK_BUCKET:-}"
PREFIX="releases/android/dailywords"
PUBLIC_BASE_URL="${R2_APK_PUBLIC_BASE_URL:-}"
WRANGLER_CONFIG=""
SKIP_LOGIN=0
USE_LOCAL=0

DEFAULT_WRANGLER_CONFIG="$ROOT_DIR/tools/worker/wrangler.toml"
if [[ -f "$DEFAULT_WRANGLER_CONFIG" ]]; then
  WRANGLER_CONFIG="$DEFAULT_WRANGLER_CONFIG"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apk)
      APK_PATH="${2:-}"
      shift 2
      ;;
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
    --wrangler-config)
      WRANGLER_CONFIG="${2:-}"
      shift 2
      ;;
    --local)
      USE_LOCAL=1
      shift
      ;;
    --skip-login)
      SKIP_LOGIN=1
      shift
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
  echo "Missing --bucket (or env R2_APK_BUCKET)." >&2
  exit 3
fi
if [[ ! -f "$APK_PATH" ]]; then
  echo "APK file not found: $APK_PATH" >&2
  exit 4
fi

if [[ "$USE_LOCAL" -eq 0 && "$SKIP_LOGIN" -eq 0 ]] && ! wrangler whoami >/dev/null 2>&1; then
  echo "Wrangler is not authenticated."
  "$ROOT_DIR/tools/android/cloudflare_wrangler_login.sh"
fi

PREFIX="${PREFIX#/}"
PREFIX="${PREFIX%/}"
APK_FILE="$(basename "$APK_PATH")"
APK_KEY="${PREFIX}/${APK_FILE}"
SHA_KEY="${APK_KEY}.sha256"
METADATA_KEY="${PREFIX}/${APK_FILE%.apk}.json"
LATEST_KEY="${PREFIX}/latest.json"

SHA256="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"
SIZE_BYTES="$(wc -c <"$APK_PATH" | tr -d ' ')"
STAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VERSION=""
VERSION_NAME=""
VERSION_CODE=0

METADATA_SOURCE="${APK_PATH%.apk}.json"
if [[ -f "$METADATA_SOURCE" ]]; then
  VERSION="$(sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$METADATA_SOURCE" | head -n1)"
  VERSION_NAME="$(sed -nE 's/.*"version_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$METADATA_SOURCE" | head -n1)"
  VERSION_CODE_RAW="$(sed -nE 's/.*"version_code"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$METADATA_SOURCE" | head -n1)"
  if [[ -n "${VERSION_CODE_RAW:-}" ]]; then
    VERSION_CODE="$VERSION_CODE_RAW"
  fi
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/apk-r2-upload.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

SHA_FILE="$TMP_DIR/${APK_FILE}.sha256"
META_FILE="$TMP_DIR/${APK_FILE%.apk}.json"
LATEST_FILE="$TMP_DIR/latest.json"

printf '%s  %s\n' "$SHA256" "$APK_FILE" > "$SHA_FILE"

cat > "$META_FILE" <<EOF
{
  "flavor": "dailywords",
  "uploaded_at_utc": "$STAMP_UTC",
  "version": "$VERSION",
  "version_name": "$VERSION_NAME",
  "version_code": $VERSION_CODE,
  "apk_file": "$APK_FILE",
  "r2_key": "$APK_KEY",
  "sha256": "$SHA256",
  "size_bytes": $SIZE_BYTES
}
EOF

if [[ -n "$PUBLIC_BASE_URL" ]]; then
  BASE_URL="${PUBLIC_BASE_URL%/}"
  APK_URL="$BASE_URL/$APK_KEY"
  SHA_URL="$BASE_URL/$SHA_KEY"
  META_URL="$BASE_URL/$METADATA_KEY"
else
  APK_URL=""
  SHA_URL=""
  META_URL=""
fi

cat > "$LATEST_FILE" <<EOF
{
  "flavor": "dailywords",
  "uploaded_at_utc": "$STAMP_UTC",
  "version": "$VERSION",
  "version_name": "$VERSION_NAME",
  "version_code": $VERSION_CODE,
  "apk_file": "$APK_FILE",
  "r2_key": "$APK_KEY",
  "sha256": "$SHA256",
  "size_bytes": $SIZE_BYTES,
  "apk_url": "$APK_URL",
  "sha256_url": "$SHA_URL",
  "metadata_url": "$META_URL"
}
EOF

wrangler_put() {
  local key="$1"
  local file="$2"
  local content_type="$3"
  local storage_flag="--remote"
  if [[ "$USE_LOCAL" -eq 1 ]]; then
    storage_flag="--local"
  fi
  if [[ -n "$WRANGLER_CONFIG" ]]; then
    wrangler --config "$WRANGLER_CONFIG" r2 object put "$BUCKET/$key" "$storage_flag" \
      --file "$file" \
      --content-type "$content_type"
  else
    wrangler r2 object put "$BUCKET/$key" "$storage_flag" \
      --file "$file" \
      --content-type "$content_type"
  fi
}

echo "Uploading APK to r2://$BUCKET/$APK_KEY"
wrangler_put "$APK_KEY" "$APK_PATH" "application/vnd.android.package-archive"

echo "Uploading checksum to r2://$BUCKET/$SHA_KEY"
wrangler_put "$SHA_KEY" "$SHA_FILE" "text/plain"

echo "Uploading metadata to r2://$BUCKET/$METADATA_KEY"
wrangler_put "$METADATA_KEY" "$META_FILE" "application/json"

echo "Updating latest manifest at r2://$BUCKET/$LATEST_KEY"
wrangler_put "$LATEST_KEY" "$LATEST_FILE" "application/json"

echo
echo "Upload complete."
echo "  r2://$BUCKET/$APK_KEY"
echo "  r2://$BUCKET/$SHA_KEY"
echo "  r2://$BUCKET/$METADATA_KEY"
echo "  r2://$BUCKET/$LATEST_KEY"
if [[ -n "$PUBLIC_BASE_URL" ]]; then
  echo
  echo "Public links:"
  echo "  $APK_URL"
  echo "  $SHA_URL"
  echo "  $META_URL"
fi
