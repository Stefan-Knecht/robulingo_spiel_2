#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: tools/android/setup_android_keystore.sh [options]

Create an Android upload keystore and android/key.properties.

Options:
  --store-file <path>       Keystore path relative to android/ (default: upload-keystore.jks)
  --alias <name>            Key alias (default: upload)
  --store-pass <password>   Store password (required)
  --key-pass <password>     Key password (required)
  --dname <dname>           keytool DN (default: CN=DailyWords,O=DailyWords,C=DE)
  --force                   Overwrite existing key.properties
  -h, --help                Show this help
EOF
}

if ! command -v keytool >/dev/null 2>&1; then
  echo "keytool not found on PATH (install JDK)." >&2
  exit 1
fi

STORE_FILE_REL="upload-keystore.jks"
KEY_ALIAS="upload"
STORE_PASS=""
KEY_PASS=""
DNAME="CN=DailyWords,O=DailyWords,C=DE"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --store-file)
      STORE_FILE_REL="${2:-}"
      shift 2
      ;;
    --alias)
      KEY_ALIAS="${2:-}"
      shift 2
      ;;
    --store-pass)
      STORE_PASS="${2:-}"
      shift 2
      ;;
    --key-pass)
      KEY_PASS="${2:-}"
      shift 2
      ;;
    --dname)
      DNAME="${2:-}"
      shift 2
      ;;
    --force)
      FORCE=1
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

if [[ -z "$STORE_PASS" || -z "$KEY_PASS" ]]; then
  echo "--store-pass and --key-pass are required." >&2
  exit 3
fi

KEY_PROPERTIES="$ROOT_DIR/android/key.properties"
STORE_FILE_ABS="$ROOT_DIR/android/$STORE_FILE_REL"

if [[ -f "$KEY_PROPERTIES" && "$FORCE" -ne 1 ]]; then
  echo "$KEY_PROPERTIES already exists. Use --force to overwrite." >&2
  exit 4
fi

mkdir -p "$(dirname "$STORE_FILE_ABS")"
if [[ ! -f "$STORE_FILE_ABS" ]]; then
  keytool -genkeypair -v \
    -keystore "$STORE_FILE_ABS" \
    -alias "$KEY_ALIAS" \
    -storepass "$STORE_PASS" \
    -keypass "$KEY_PASS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "$DNAME"
fi

cat > "$KEY_PROPERTIES" <<EOF
storeFile=$STORE_FILE_REL
storePassword=$STORE_PASS
keyAlias=$KEY_ALIAS
keyPassword=$KEY_PASS
EOF

echo "Created:"
echo "  $STORE_FILE_ABS"
echo "  $KEY_PROPERTIES"
