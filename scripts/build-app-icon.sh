#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SOURCE_SVG="${REPO_ROOT}/app-icon.svg"
APPICONSET_DIR="${REPO_ROOT}/LinkSwitch/LinkSwitch/Assets.xcassets/AppIcon.appiconset"
WORK_DIR="${REPO_ROOT}/build/app-icon"
MASTER_PNG_PATH="${WORK_DIR}/icon_1024x1024.png"

if [[ ! -f "${SOURCE_SVG}" ]]; then
  echo "Source SVG was not found at ${SOURCE_SVG}" >&2
  exit 1
fi

if [[ ! -d "${APPICONSET_DIR}" ]]; then
  echo "App icon set directory was not found at ${APPICONSET_DIR}" >&2
  exit 1
fi

if ! command -v rsvg-convert >/dev/null 2>&1; then
  echo "rsvg-convert is required to build app icons from ${SOURCE_SVG}" >&2
  exit 1
fi

echo "==> Rendering app icon source ${SOURCE_SVG}"
mkdir -p "${WORK_DIR}"
rsvg-convert --width 1024 --height 1024 "${SOURCE_SVG}" --output "${MASTER_PNG_PATH}"

declare -a ICON_SPECS=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)

for spec in "${ICON_SPECS[@]}"; do
  pixel_size="${spec%%:*}"
  output_filename="${spec#*:}"
  output_path="${APPICONSET_DIR}/${output_filename}"

  if [[ "${pixel_size}" == "1024" ]]; then
    cp "${MASTER_PNG_PATH}" "${output_path}"
    continue
  fi

  sips -z "${pixel_size}" "${pixel_size}" "${MASTER_PNG_PATH}" --out "${output_path}" >/dev/null
done

echo "==> Wrote app icon assets to ${APPICONSET_DIR}"
