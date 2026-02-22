#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/android/cloudflare_wrangler_login.sh [options]

Open interactive Cloudflare login via Wrangler (browser-based).

Options:
  --force      Always run login even if already authenticated
  -h, --help   Show this help
EOF
}

if ! command -v wrangler >/dev/null 2>&1; then
  echo "wrangler not found on PATH (install: npm i -g wrangler)" >&2
  exit 1
fi

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
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

if [[ "$FORCE" -eq 0 ]] && wrangler whoami >/dev/null 2>&1; then
  echo "Wrangler is already authenticated."
  wrangler whoami || true
  exit 0
fi

echo "Starting Cloudflare login in your browser..."
wrangler login

echo
echo "Authentication status:"
wrangler whoami
