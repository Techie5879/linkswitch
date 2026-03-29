#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${REPO_ROOT}/LinkSwitch/LinkSwitch.xcodeproj"
SCHEME="LinkSwitch"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="${REPO_ROOT}/build/DerivedData"
BUILD_APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/LinkSwitch.app"
APP_BUNDLE_ID="dev.helios.LinkSwitch"
DEV_APP_NAME="LinkSwitch Dev.app"
SYSTEM_INSTALL_DIR="/Applications"
HOME_INSTALL_DIR="${HOME}/Applications"
SYSTEM_INSTALL_APP_PATH="${SYSTEM_INSTALL_DIR}/${DEV_APP_NAME}"
HOME_INSTALL_APP_PATH="${HOME_INSTALL_DIR}/${DEV_APP_NAME}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

if [[ -w "${SYSTEM_INSTALL_DIR}" ]]; then
  INSTALL_DIR="${SYSTEM_INSTALL_DIR}"
  INSTALL_APP_PATH="${SYSTEM_INSTALL_APP_PATH}"
else
  INSTALL_DIR="${HOME_INSTALL_DIR}"
  INSTALL_APP_PATH="${HOME_INSTALL_APP_PATH}"
fi

echo "==> Repo root: ${REPO_ROOT}"
echo "==> Cleaning previous derived data at ${DERIVED_DATA_PATH}"
rm -rf "${DERIVED_DATA_PATH}"

echo "==> Regenerating app icon assets from ${REPO_ROOT}/app-icon.svg"
"${REPO_ROOT}/scripts/build-app-icon.sh"

echo "==> Building ${SCHEME} (${CONFIGURATION})"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "platform=macOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  build

if [[ ! -d "${BUILD_APP_PATH}" ]]; then
  echo "Build succeeded but app bundle was not found at ${BUILD_APP_PATH}" >&2
  exit 1
fi

mkdir -p "${INSTALL_DIR}"
if [[ "${INSTALL_DIR}" == "${HOME_INSTALL_DIR}" ]]; then
  chmod 755 "${HOME_INSTALL_DIR}"
fi

echo "==> Quitting any running LinkSwitch instance"
osascript -e "tell application id \"${APP_BUNDLE_ID}\" to quit" >/dev/null 2>&1 || true
sleep 1

echo "==> Removing previous dev installs"
rm -rf "${SYSTEM_INSTALL_APP_PATH}"
rm -rf "${HOME_INSTALL_APP_PATH}"

echo "==> Replacing installed dev app at ${INSTALL_APP_PATH}"
ditto "${BUILD_APP_PATH}" "${INSTALL_APP_PATH}"
xattr -dr com.apple.quarantine "${INSTALL_APP_PATH}" >/dev/null 2>&1 || true

if [[ -x "${LSREGISTER}" ]]; then
  echo "==> Registering installed dev app with Launch Services"
  "${LSREGISTER}" -f -R -trusted "${INSTALL_APP_PATH}" >/dev/null
fi

echo "==> Launching installed dev app"
open "${INSTALL_APP_PATH}"

echo
echo "Installed dev app:"
echo "  ${INSTALL_APP_PATH}"
echo
echo "Next steps in LinkSwitch:"
echo "  1. Open LinkSwitch from the menu bar item."
echo "  2. Choose the fallback browser."
echo "  3. Save the config."
echo "  4. Click 'Set LinkSwitch as HTTP/HTTPS Handler'."
echo
echo "Config path:"
echo "  ~/Library/Application Support/LinkSwitch/router-config.json"
echo
echo "Dev runtime log path:"
echo "  ${REPO_ROOT}/logs/runtime.log"
