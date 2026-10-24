#!/usr/bin/env bash
set -euo pipefail

# Single source of truth for the app version, kept in git tags.
# Apple's CFBundleShortVersionString requires exactly three period-separated
# integers (digits and periods only), so tags are bare MAJOR.MINOR.PATCH.
#
#   scripts/version.sh            -> print the current version (newest tag)
#   scripts/version.sh patch      -> bump and tag HEAD (major | minor | patch)
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT="0.1.0"
STEP="${1:-}"

validate() {
  if [[ ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: version '$1' is not Apple-compatible (need MAJOR.MINOR.PATCH, digits only)." >&2
    exit 1
  fi
}

current="$(git -C "$ROOT_DIR" tag --sort=-version:refname | head -1 || true)"
[ -n "$current" ] && validate "$current"

if [ -z "$STEP" ]; then
  VERSION="${current:-$DEFAULT}"
  validate "$VERSION"
  echo "$VERSION"
  exit 0
fi

case "$STEP" in major|minor|patch) ;; *) echo "Usage: $0 [major|minor|patch]"; exit 1 ;; esac

IFS='.' read -r MAJOR MINOR PATCH <<< "${current:-0.0.0}"
case "$STEP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

VERSION="$MAJOR.$MINOR.$PATCH"
validate "$VERSION"
git -C "$ROOT_DIR" tag "$VERSION"
echo "Bumped ${current:-0.0.0} -> $VERSION (tagged HEAD)"