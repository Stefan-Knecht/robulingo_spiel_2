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
CHANNEL=""
LEGACY_FLAVOR_ARG=""

case "$MODE" in
 prod)
   if [[ $# -gt 2 ]]; then
     echo "Usage: tools/deploy_firebase_hosting.sh [prod [robulingo|dailywords] | preview <channel> [robulingo|dailywords]]" >&2
     exit 2
   fi
   LEGACY_FLAVOR_ARG="${2:-}"
   ;;
 preview)
   CHANNEL="${2:-}"
   if [[ -z "$CHANNEL" ]]; then
     echo "Usage: tools/deploy_firebase_hosting.sh preview <channel> [robulingo|dailywords]" >&2
     exit 2
   fi
   if [[ $# -gt 3 ]]; then
     echo "Usage: tools/deploy_firebase_hosting.sh [prod [robulingo|dailywords] | preview <channel> [robulingo|dailywords]]" >&2
     exit 2
   fi
   LEGACY_FLAVOR_ARG="${3:-}"
   ;;
 *)
   echo "Usage: tools/deploy_firebase_hosting.sh [prod [robulingo|dailywords] | preview <channel> [robulingo|dailywords]]" >&2
   exit 2
   ;;
esac

if [[ -n "$LEGACY_FLAVOR_ARG" ]]; then
  case "$LEGACY_FLAVOR_ARG" in
    robulingo|dailywords)
      echo "Note: flavor argument '$LEGACY_FLAVOR_ARG' is ignored. This script now always deploys both robulingo and dailywords."
      ;;
    *)
      echo "Invalid flavor: $LEGACY_FLAVOR_ARG (expected: robulingo|dailywords)" >&2
      exit 2
      ;;
  esac
fi

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

deploy_flavor() {
  local flavor="$1"
  local target="$1"

  echo "Building Flutter web (release, APP_FLAVOR=$flavor)..."
  flutter build web --release --dart-define="APP_FLAVOR=$flavor"

  case "$MODE" in
    prod)
      echo "Deploying to Firebase Hosting target '$target' (production)..."
      firebase deploy --only "hosting:$target"
      ;;
    preview)
      echo "Deploying to Firebase Hosting preview channel '$CHANNEL' for target '$target'..."
      firebase hosting:channel:deploy "$CHANNEL" --only "$target"
      ;;
  esac
}

deploy_flavor "robulingo"
deploy_flavor "dailywords"
