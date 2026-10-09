#!/usr/bin/env bash
# Zip the Release Ferret.app into dist/Ferret-<shortsha>.zip.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${APP:-build/dd/Build/Products/Release/Ferret.app}"
if [ ! -d "$APP" ]; then
  echo "error: app not found at $APP" >&2
  exit 1
fi

SHA="$(git rev-parse --short HEAD)"
mkdir -p dist
ZIP="dist/Ferret-${SHA}.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" > "${ZIP}.sha256"
echo "packaged $ZIP"
