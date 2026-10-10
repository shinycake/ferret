#!/usr/bin/env bash
# Ad-hoc sign the Release Ferret.app and zip it into dist/Ferret-<shortsha>.zip (+ .sha256).
# On CI it also runs the extra proof (snapshots, app tests) and a smoke run from the unzipped copy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="${APP:-build/dd/Build/Products/Release/Ferret.app}"
if [ ! -d "$APP" ]; then
  echo "error: app not found at $APP" >&2
  exit 1
fi
mkdir -p proof

if [ "${CI:-}" = "true" ] && [ -z "${SKIP_CI_PROOF:-}" ]; then
  scripts/ci-proof.sh 2>&1 | tee proof/ci-proof.log
fi

scripts/sign-adhoc.sh "$APP"

SHA="$(git rev-parse --short HEAD)"
mkdir -p dist
ZIP="dist/Ferret-${SHA}.zip"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
(cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
cat "${ZIP}.sha256" | tee proof/sha256.txt
echo "packaged $ZIP"

if [ "${CI:-}" = "true" ]; then
  # Smoke: unzip into a fresh dir and render the cheat sheet from that copy.
  FRESH="$(mktemp -d)/fresh"
  mkdir -p "$FRESH"
  ditto -x -k "$ZIP" "$FRESH"
  test -d "$FRESH/Ferret.app"
  codesign --verify --deep --strict "$FRESH/Ferret.app"
  OUT="$ROOT/proof/snapshots/01-cheatsheet-from-zip.png"
  FERRET_DEMO=1 "$FRESH/Ferret.app/Contents/MacOS/Ferret" --demo-snapshot --screen cheatsheet --out "$OUT" </dev/null >proof/zip-smoke.log 2>&1 &
  pid=$!
  for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "zip smoke timed out"; cat proof/zip-smoke.log; exit 1; fi
  wait "$pid"
  cat proof/zip-smoke.log
  test -s "$OUT"
  echo "zip smoke ok: $OUT"
fi
