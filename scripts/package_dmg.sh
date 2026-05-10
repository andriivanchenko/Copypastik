#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Copypastik}"
PROJECT="${PROJECT:-${APP_NAME}.xcodeproj}"
SCHEME="${SCHEME:-${APP_NAME}}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-build/DerivedData}"
DIST_DIR="${DIST_DIR:-dist}"
DMG_NAME="${DMG_NAME:-${APP_NAME}}"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME}}"
APP_PATH="${APP_PATH:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<EOF
Usage:
  scripts/package_dmg.sh
  APP_PATH=/path/to/${APP_NAME}.app scripts/package_dmg.sh

Environment:
  APP_NAME       App bundle/product name. Default: ${APP_NAME}
  PROJECT        Xcode project path. Default: ${PROJECT}
  SCHEME         Xcode scheme. Default: ${SCHEME}
  CONFIGURATION  Build configuration. Default: ${CONFIGURATION}
  CODE_SIGNING_ALLOWED
                 Whether xcodebuild may code sign. Default: ${CODE_SIGNING_ALLOWED}
  DERIVED_DATA   Derived data path. Default: ${DERIVED_DATA}
  DIST_DIR       Output directory. Default: ${DIST_DIR}
  DMG_NAME       Output DMG base name. Default: ${DMG_NAME}
  VOLUME_NAME    Mounted volume name. Default: ${VOLUME_NAME}
  APP_PATH       Existing .app path to package instead of building.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $arg"
      ;;
  esac
done

command -v hdiutil >/dev/null || fail "hdiutil is required to create a DMG"

mkdir -p "$DIST_DIR"

if [[ -z "$APP_PATH" ]]; then
  [[ -d "$PROJECT" ]] || fail "project not found: $PROJECT"
  [[ -f "$PROJECT/project.pbxproj" ]] || fail "project is missing project.pbxproj: $PROJECT"

  echo "Building ${APP_NAME} (${CONFIGURATION})..."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    build

  APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/${APP_NAME}.app"
fi

[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"
[[ "$APP_PATH" == *.app ]] || fail "APP_PATH must point to a .app bundle"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.dmg-work.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
RW_DMG="$WORK_DIR/${APP_NAME}.rw.dmg"
MOUNT_DIR="$WORK_DIR/mount"
FINAL_DMG="$DIST_DIR/${DMG_NAME}.dmg"
DEVICE=""

cleanup() {
  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "Preparing DMG contents..."
mkdir -p "$STAGING_DIR" "$MOUNT_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "Creating temporary disk image..."
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

echo "Applying Finder layout..."
DEVICE="$(
  hdiutil attach "$RW_DMG" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" |
  awk '/\/dev\/disk/ { print $1; exit }'
)"

if ! osascript >/dev/null <<EOF
tell application "Finder"
  set dmgFolder to POSIX file "${MOUNT_DIR}" as alias
  open dmgFolder
  delay 1
  set dmgWindow to container window of dmgFolder
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to {100, 100, 640, 430}
  set viewOptions to the icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set position of item "${APP_NAME}.app" of dmgFolder to {170, 165}
  set position of item "Applications" of dmgFolder to {430, 165}
  close dmgWindow
  open dmgFolder
  update dmgFolder without registering applications
  delay 1
end tell
EOF
then
  echo "warning: Finder layout could not be applied; continuing with default layout" >&2
fi

sync
hdiutil detach "$DEVICE" -quiet
DEVICE=""

echo "Compressing DMG..."
hdiutil convert \
  "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG" \
  -ov >/dev/null

echo "Created $FINAL_DMG"
