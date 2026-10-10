#!/usr/bin/env bash
# Ad-hoc sign Ferret.app inside-out (fsearch, Finder Sync appex, app) and verify.
# Releases are unnotarized unless the release workflow has Apple secrets (docs/NOTARIZATION.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${1:-${APP:-build/dd/Build/Products/Release/Ferret.app}}"
mkdir -p proof
codesign --force --sign - --timestamp=none "$APP/Contents/MacOS/fsearch"
codesign --force --sign - --timestamp=none --entitlements FinderSync/FerretFinderSync.entitlements \
  "$APP/Contents/PlugIns/FerretFinderSync.appex"
codesign --force --sign - --timestamp=none --entitlements App/Ferret.entitlements "$APP"
{
  echo "=== codesign --verify --deep --strict ==="
  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1
  echo "=== codesign -dv ==="
  codesign -dv --verbose=2 "$APP" 2>&1 || true
  echo "=== appex entitlements ==="
  codesign -d --entitlements - "$APP/Contents/PlugIns/FerretFinderSync.appex" 2>&1 || true
} | tee proof/codesign.txt
codesign --verify --deep --strict "$APP"
echo "signed $APP"
