#!/usr/bin/env bash
# Extra CI proof: app tests and UI snapshots. Called by scripts/package.sh on CI
# (the workflow file is frozen for this token, so new proof lives here).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p proof/snapshots

snap() { # snap <screen> <file>
  local screen=$1 out="$PWD/proof/snapshots/$2"
  local APP="build/dd/Build/Products/Release/Ferret.app"
  FERRET_DEMO=1 "$APP/Contents/MacOS/Ferret" --demo-snapshot --screen "$screen" --out "$out" >"proof/snap-$screen.log" 2>&1 &
  local pid=$! status=0
  for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if kill -0 "$pid" 2>/dev/null; then kill "$pid"; echo "snapshot $screen timed out"; cat "proof/snap-$screen.log"; return 1; fi
  wait "$pid" || status=$?
  cat "proof/snap-$screen.log"
  test "$status" -eq 0
  python3 -c 'import sys; d=open(sys.argv[1],"rb").read(); assert d[:8]==b"\x89PNG\r\n\x1a\n" and len(d)>2000' "$out"
  echo "snapshot $screen ok: $out"
}

if [ -f scripts/ci-snapshots.txt ]; then
  while read -r screen file; do
    [ -z "${screen:-}" ] && continue
    case "$screen" in \#*) continue;; esac
    snap "$screen" "$file"
  done < scripts/ci-snapshots.txt
fi

# App tests (Debug build; the Release app being packaged is untouched).
set -euo pipefail
mkdir -p proof
xcodebuild build-for-testing \
  -project Ferret.xcodeproj \
  -scheme Ferret \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_TESTABILITY=YES \
  2>&1 | tee proof/apptests-build.log
APP="build/dd/Build/Products/Debug/Ferret.app"
codesign --force --sign - "$APP/Contents/MacOS/fsearch"
codesign --force --sign - "$APP/Contents/PlugIns/FerretFinderSync.appex"
codesign --force --sign - "$APP"
if [ -d build/dd/Build/Products/Debug/AppTests.xctest ]; then
  codesign --force --sign - build/dd/Build/Products/Debug/AppTests.xctest
fi
xctestrun=""
while IFS= read -r -d '' candidate; do
  xctestrun=$candidate
  break
done < <(find build/dd/Build/Products -name '*.xctestrun' -maxdepth 2 -print0)
test -n "$xctestrun"
echo "xctestrun $xctestrun" | tee proof/apptests.log
set +e
set +o pipefail
xcodebuild test-without-building \
  -xctestrun "$xctestrun" \
  -destination 'platform=macOS' \
  -resultBundlePath "$PWD/proof/AppTests.xcresult" \
  -parallel-testing-enabled NO \
  2>&1 | tee -a proof/apptests.log
code=${PIPESTATUS[0]}
set -o pipefail
set -e
if ! xcrun xcresulttool get test-results summary --path proof/AppTests.xcresult > proof/apptests-summary.json 2>proof/xcresulttool.err; then
  xcrun xcresulttool get --legacy --format json --path proof/AppTests.xcresult > proof/apptests-summary.json 2>>proof/xcresulttool.err || true
fi
echo "app tests exit ${code}" | tee -a proof/apptests.log
exit "$code"
