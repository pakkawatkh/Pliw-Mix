#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_DIR}"

echo "🔨 Ensuring latest release build of Pliw Mix.app..."
./scripts/build_app.sh

if [ -d "$(cd "${PROJECT_DIR}/.." && pwd)/public" ]; then
    PLIW_PORTAL_DIR="$(cd "${PROJECT_DIR}/.." && pwd)/public/public/pliw-mix"
else
    PLIW_PORTAL_DIR="$(cd "${PROJECT_DIR}/.." && pwd)/Pliw-App/pliw-mix"
fi
mkdir -p "${PLIW_PORTAL_DIR}"

DMG_TMP="$(mktemp -d)"
trap 'rm -rf "${DMG_TMP}"' EXIT
DMG_OUTPUT="${PLIW_PORTAL_DIR}/pliw-mix-Installer.dmg"
ZIP_OUTPUT="${PLIW_PORTAL_DIR}/pliw-mix.zip"

echo "📦 Preparing DMG installer directory structure..."
mkdir -p "${DMG_TMP}"

cp -R "${PROJECT_DIR}/Pliw Mix.app" "${DMG_TMP}/Pliw Mix.app"
ln -s /Applications "${DMG_TMP}/Applications"

cat << 'EOF' > "${DMG_TMP}/How to Install.txt"
===================================================
  🎚️ Pliw Mix — Per-App Audio Mixer for macOS
===================================================

1. INSTALLATION:
   Drag "Pliw Mix.app" into the "Applications" shortcut icon.

2. FIRST-TIME OPEN (macOS Gatekeeper):
   If macOS warns "cannot be opened because the developer cannot be verified":
   - Open System Settings > Privacy & Security, click "Open Anyway", OR
   - Run in Terminal: xattr -cr "/Applications/Pliw Mix.app"

3. SYSTEM AUDIO PERMISSION:
   - Enable Pliw Mix in System Settings > Privacy & Security > Screen & System Audio Recording (System Audio Recording Only).

4. USAGE:
   - Click the speaker icon in the Menu Bar to adjust per-app volume, mute, or route individual apps to different output devices.
===================================================
EOF

echo "📀 Creating DMG disk image: ${DMG_OUTPUT}..."
rm -f "${DMG_OUTPUT}" "${PROJECT_DIR}/pliw-mix-Installer.dmg"
hdiutil create -volname "Pliw Mix Installer" -srcfolder "${DMG_TMP}" -ov -format UDZO "${DMG_OUTPUT}"

echo "🗜️ Creating ZIP archive for in-app updates: ${ZIP_OUTPUT}..."
rm -f "${ZIP_OUTPUT}" "${PROJECT_DIR}/pliw-mix.zip"
ditto -c -k --keepParent "${PROJECT_DIR}/Pliw Mix.app" "${ZIP_OUTPUT}"

# Remove temporary local .app bundle so build outputs stay only in public/
rm -rf "${PROJECT_DIR}/Pliw Mix.app"

echo "🎉 DMG and ZIP packages successfully created in ${PLIW_PORTAL_DIR}!"
ls -lh "${DMG_OUTPUT}" "${ZIP_OUTPUT}"
