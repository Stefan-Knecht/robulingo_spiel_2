#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Usage: tools/android/build_dailywords_release_apk.sh [options]

Build a signed Android release APK for APP_FLAVOR=dailywords.

Options:
  --build-name <name>       Override app version name
  --build-number <number>   Override app version code
  --output-dir <dir>        Output directory (default: build/releases/android/dailywords)
  --skip-pub-get            Skip flutter pub get
  -h, --help                Show this help
EOF
}

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH" >&2
  exit 1
fi
if ! command -v shasum >/dev/null 2>&1; then
  echo "shasum not found on PATH" >&2
  exit 1
fi

BUILD_NAME=""
BUILD_NUMBER=""
OUTPUT_DIR="$ROOT_DIR/build/releases/android/dailywords"
SKIP_PUB_GET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-name)
      BUILD_NAME="${2:-}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="${2:-}"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --skip-pub-get)
      SKIP_PUB_GET=1
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

KEY_PROPERTIES="$ROOT_DIR/android/key.properties"
if [[ ! -f "$KEY_PROPERTIES" ]]; then
  cat >&2 <<EOF
Missing $KEY_PROPERTIES
Create it from android/key.properties.sample and set real signing values.
EOF
  exit 3
fi

read_prop() {
  local key="$1"
  local raw
  raw="$(grep -E "^${key}=" "$KEY_PROPERTIES" | head -n1 | cut -d= -f2- || true)"
  echo "${raw}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

STORE_FILE="$(read_prop storeFile)"
STORE_PASSWORD="$(read_prop storePassword)"
KEY_ALIAS="$(read_prop keyAlias)"
KEY_PASSWORD="$(read_prop keyPassword)"

if [[ -z "$STORE_FILE" || -z "$STORE_PASSWORD" || -z "$KEY_ALIAS" || -z "$KEY_PASSWORD" ]]; then
  echo "android/key.properties is incomplete (storeFile/storePassword/keyAlias/keyPassword required)." >&2
  exit 4
fi

if [[ "$STORE_FILE" = /* ]]; then
  STORE_FILE_RESOLVED="$STORE_FILE"
else
  STORE_FILE_RESOLVED="$ROOT_DIR/android/$STORE_FILE"
fi
if [[ ! -f "$STORE_FILE_RESOLVED" ]]; then
  echo "Keystore file not found: $STORE_FILE_RESOLVED" >&2
  exit 5
fi

if [[ "$SKIP_PUB_GET" -eq 0 ]]; then
  flutter pub get
fi

BUILD_CMD=(flutter build apk --release --dart-define=APP_FLAVOR=dailywords)
if [[ -n "$BUILD_NAME" ]]; then
  BUILD_CMD+=("--build-name=$BUILD_NAME")
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  BUILD_CMD+=("--build-number=$BUILD_NUMBER")
fi

echo "Building release APK for dailywords..."
"${BUILD_CMD[@]}"

APK_SOURCE="$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK_SOURCE" ]]; then
  echo "Expected APK not found: $APK_SOURCE" >&2
  exit 6
fi

mkdir -p "$OUTPUT_DIR"

APP_VERSION="$(awk '/^version:/{print $2; exit}' "$ROOT_DIR/pubspec.yaml")"
if [[ -z "$APP_VERSION" ]]; then
  APP_VERSION="unknown"
fi
VERSION_NAME="$APP_VERSION"
VERSION_CODE=""
if [[ "$APP_VERSION" == *"+"* ]]; then
  VERSION_NAME="${APP_VERSION%%+*}"
  VERSION_CODE="${APP_VERSION##*+}"
fi
if [[ -n "$BUILD_NAME" ]]; then
  VERSION_NAME="$BUILD_NAME"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  VERSION_CODE="$BUILD_NUMBER"
fi
if [[ -z "$VERSION_CODE" ]]; then
  VERSION_CODE="1"
fi
VERSION_TAG="${VERSION_NAME//[^0-9A-Za-z._-]/-}-${VERSION_CODE}"
STAMP_UTC="$(date -u +%Y%m%d-%H%M%S)"
APK_BASENAME="dailywords-${VERSION_TAG}-${STAMP_UTC}.apk"
APK_PATH="$OUTPUT_DIR/$APK_BASENAME"

cp "$APK_SOURCE" "$APK_PATH"

SHA256="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"
SIZE_BYTES="$(wc -c <"$APK_PATH" | tr -d ' ')"

printf '%s  %s\n' "$SHA256" "$APK_BASENAME" > "$APK_PATH.sha256"

METADATA_PATH="$OUTPUT_DIR/${APK_BASENAME%.apk}.json"
cat > "$METADATA_PATH" <<EOF
{
  "flavor": "dailywords",
  "version": "$APP_VERSION",
  "version_name": "$VERSION_NAME",
  "version_code": $VERSION_CODE,
  "build_utc": "$STAMP_UTC",
  "apk_file": "$APK_BASENAME",
  "sha256": "$SHA256",
  "size_bytes": $SIZE_BYTES
}
EOF

cp "$APK_PATH" "$OUTPUT_DIR/dailywords-latest.apk"
cp "$APK_PATH.sha256" "$OUTPUT_DIR/dailywords-latest.apk.sha256"
cp "$METADATA_PATH" "$OUTPUT_DIR/dailywords-latest.json"

echo
echo "Release artifacts written:"
echo "  APK:      $APK_PATH"
echo "  SHA256:   $APK_PATH.sha256"
echo "  Metadata: $METADATA_PATH"
echo
echo "Machine-readable:"
echo "APK_PATH=$APK_PATH"
echo "SHA256=$SHA256"
