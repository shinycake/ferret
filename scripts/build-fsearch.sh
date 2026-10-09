#!/usr/bin/env bash
# Build the pinned fsearch commit as a universal macOS binary.
set -euo pipefail

URL=$(sed -n 1p third_party/fsearch.pin)
SHA=$(sed -n 2p third_party/fsearch.pin)
SRC=build/fsearch-src
OUT=build/fsearch
mkdir -p "$OUT"
[ -d "$SRC/.git" ] || git clone --filter=blob:none "$URL" "$SRC"
git -C "$SRC" fetch --depth 1 origin "$SHA" && git -C "$SRC" checkout --detach "$SHA"
test "$(git -C "$SRC" rev-parse HEAD)" = "$SHA" || { echo "pin mismatch"; exit 1; }
for T in aarch64-apple-darwin x86_64-apple-darwin; do
  cargo build --release --locked --manifest-path "$SRC/Cargo.toml" --target "$T"
done
lipo -create -output "$OUT/fsearch" \
  "$SRC"/target/aarch64-apple-darwin/release/fsearch \
  "$SRC"/target/x86_64-apple-darwin/release/fsearch
strip -S "$OUT/fsearch"
lipo -info "$OUT/fsearch"
cp "$SRC/LICENSE" "$OUT/fsearch-LICENSE.txt"
# Ad-hoc sign so the usage check can execute. A later codesign --force replaces it.
codesign --force --sign - "$OUT/fsearch"
# usage on stderr, exit 0. Avoid `cmd | head` under pipefail (SIGPIPE exits 141).
usage_err=$(mktemp)
set +e
"$OUT/fsearch" >"${usage_err}.out" 2>"$usage_err"
status=$?
set -e
head -2 "$usage_err"
test "$status" -eq 0
rm -f "$usage_err" "${usage_err}.out"
