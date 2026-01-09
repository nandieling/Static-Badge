#!/usr/bin/env bash
set -euo pipefail

APP_NAME="静态勋章制作"
ENTRYPOINT="main.py"
DIST_DIR="dist_x64"
BUILD_DIR="build_x64"
ICON_FILE="1.icns"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only." >&2
  exit 1
fi

python3 -m venv .venv
source .venv/bin/activate

python -m pip install -U pip
python -m pip install -r requirements.txt pyinstaller

ICON_ARGS=()
if [[ -f "${ICON_FILE}" ]]; then
  ICON_ARGS+=(--icon "${ICON_FILE}")
else
  echo "Warning: ${ICON_FILE} not found, building without icon." >&2
fi

PYINSTALLER_CONFIG_DIR="$(pwd)/.pyinstaller" python -m PyInstaller \
  --clean \
  --windowed \
  --noconfirm \
  --name "${APP_NAME}" \
  --distpath "${DIST_DIR}" \
  --workpath "${BUILD_DIR}" \
  "${ICON_ARGS[@]}" \
  "${ENTRYPOINT}"

echo
echo "Built app: ${DIST_DIR}/${APP_NAME}.app"
echo "Zipping..."
ditto -c -k --sequesterRsrc --keepParent "${DIST_DIR}/${APP_NAME}.app" "${DIST_DIR}/${APP_NAME}-mac-x64.zip"
echo "Zip: ${DIST_DIR}/${APP_NAME}-mac-x64.zip"
