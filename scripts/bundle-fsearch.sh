#!/usr/bin/env bash
# Copy the pinned fsearch binary, license, and pin SHA into the app bundle.
set -euo pipefail

ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
BIN_SRC="${ROOT}/build/fsearch/fsearch"
LICENSE_SRC="${ROOT}/build/fsearch/fsearch-LICENSE.txt"
PIN_FILE="${ROOT}/third_party/fsearch.pin"

if [ ! -x "${BIN_SRC}" ]; then
  echo "error: bundled fsearch binary is missing at ${BIN_SRC}; run scripts/build-fsearch.sh first" >&2
  exit 1
fi
if [ ! -f "${LICENSE_SRC}" ]; then
  echo "error: fsearch license is missing at ${LICENSE_SRC}; run scripts/build-fsearch.sh first" >&2
  exit 1
fi

: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is not set}"
: "${EXECUTABLE_FOLDER_PATH:?EXECUTABLE_FOLDER_PATH is not set}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?UNLOCALIZED_RESOURCES_FOLDER_PATH is not set}"

DEST_BIN="${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/fsearch"
LICENSE_DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/ThirdPartyLicenses"
PIN_DEST="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/FSearchPin.txt"

mkdir -p "$(dirname "${DEST_BIN}")" "${LICENSE_DEST}"
cp "${BIN_SRC}" "${DEST_BIN}"
chmod +x "${DEST_BIN}"
cp "${LICENSE_SRC}" "${LICENSE_DEST}/fsearch-LICENSE.txt"
sed -n '2p' "${PIN_FILE}" > "${PIN_DEST}"
