#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PACKAGE_DIR="${SCRIPT_DIR:h}"
DIST_DIR="${PACKAGE_DIR}/dist"
APP_DIR="${DIST_DIR}/OBS Camera Dock Helper.app"
CACHE_DIR="${PACKAGE_DIR}/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="${PACKAGE_DIR}/.build/module-cache"
export SWIFTPM_HOME="${PACKAGE_DIR}/.build/swiftpm-home"

mkdir -p "${CACHE_DIR}" "${CLANG_MODULE_CACHE_PATH}" "${SWIFTPM_HOME}"
swift build --disable-sandbox --cache-path "${CACHE_DIR}" --package-path "${PACKAGE_DIR}" -c release
BIN_DIR="$(swift build --disable-sandbox --cache-path "${CACHE_DIR}" --package-path "${PACKAGE_DIR}" -c release --show-bin-path)"

if [[ -d "${APP_DIR}" ]]; then
  rm -rf "${APP_DIR}"
fi

mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/CameraDockHelper" "${APP_DIR}/Contents/MacOS/CameraDockHelper"
cp "${SCRIPT_DIR}/Info.plist" "${APP_DIR}/Contents/Info.plist"

RESOURCE_BUNDLE="$(find "${BIN_DIR}" -maxdepth 1 -type d -name '*CameraDockHelper*.bundle' -print -quit)"
if [[ -z "${RESOURCE_BUNDLE}" ]]; then
  print -u2 "Chybí SwiftPM resource bundle."
  exit 1
fi
ditto "${RESOURCE_BUNDLE}" "${APP_DIR}/Contents/Resources/${RESOURCE_BUNDLE:t}"

xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"
xattr -cr "${APP_DIR}"
print "Hotovo: ${APP_DIR}"
