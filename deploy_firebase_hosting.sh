#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "git not found on PATH" >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter not found on PATH" >&2
  exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
  echo "firebase CLI not found on PATH (install: npm i -g firebase-tools)" >&2
  exit 1
fi

MODE="${1:-prod}"
SOURCE_REF="${SOURCE_REF:-origin/main}"

echo "Fetching latest refs from origin..."
git fetch origin

WORKTREE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/firebase-deploy.XXXXXX")"
cleanup() {
  git worktree remove --force "$WORKTREE_DIR" >/dev/null 2>&1 || true
  rm -rf "$WORKTREE_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Creating temporary worktree at ref: $SOURCE_REF"
git worktree add --detach "$WORKTREE_DIR" "$SOURCE_REF"
cd "$WORKTREE_DIR"

echo "Building Flutter web (release)..."
flutter build web --release

case "$MODE" in
  prod)
    echo "Deploying to Firebase Hosting (production)..."
    firebase deploy --only hosting
    ;;
  preview)
    CHANNEL="${2:-}"
    if [[ -z "$CHANNEL" ]]; then
      echo "Usage: tools/deploy_firebase_hosting.sh preview <channel>" >&2
      exit 2
    fi
    echo "Deploying to Firebase Hosting preview channel: $CHANNEL"
    firebase hosting:channel:deploy "$CHANNEL" --only hosting
    ;;
  *)
    echo "Usage: tools/deploy_firebase_hosting.sh [prod|preview <channel>]" >&2
    exit 2
    ;;
esac