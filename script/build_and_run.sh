#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Codex Inner IDE"
PROCESS_NAME="CodexPetIDEController"
BUNDLE_ID="com.local.codex-pet-ide"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/codex-python-ide"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="/tmp/codex-inner-ide-dist"
STAGE_APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
USER_APPLICATIONS_DIR="${CODEX_INNER_IDE_INSTALL_DIR:-${HOME}/Applications}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Packaging/Info.plist")"
RELEASE_LABEL="${VERSION}-preview"
BUILD_ARCH="$(uname -m)"
LEGACY_DIST_APP="$DIST_DIR/Codex Pet IDE.app"
APP_ARCHIVE="$DIST_DIR/$APP_NAME-v$RELEASE_LABEL-macos-$BUILD_ARCH.zip"
CHECKSUM_FILE="$APP_ARCHIVE.sha256"
PLUGIN_NAME="codex-inner-edit"
PLUGIN_VERSION="0.1.0"
PLUGIN_DIR="$ROOT_DIR/plugins/$PLUGIN_NAME"
PLUGIN_ARCHIVE="$DIST_DIR/$PLUGIN_NAME-v$PLUGIN_VERSION.zip"
PLUGIN_CHECKSUM_FILE="$PLUGIN_ARCHIVE.sha256"
ARCHIVE_FILENAME="${APP_ARCHIVE##*/}"
CHECKSUM_FILENAME="${CHECKSUM_FILE##*/}"
LEGACY_APP_ARCHIVE="$DIST_DIR/Codex Pet IDE.zip"
APP_CONTENTS="$STAGE_APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PROCESS_NAME"
SWIFT_SCRATCH="/tmp/codex-inner-ide-release-build"
CLANG_CACHE="/tmp/codex-inner-ide-clang-cache"
SWIFT_CACHE="/tmp/codex-inner-ide-swift-cache"

INSTALL_DIR="$USER_APPLICATIONS_DIR"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME.app"
LEGACY_APP_BUNDLE="$INSTALL_DIR/Codex Pet IDE.app"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--build-only|build-only) ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--build-only]" >&2
    exit 2
    ;;
esac

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
fi

npm --prefix "$FRONTEND_DIR" run build
mkdir -p "$CLANG_CACHE" "$SWIFT_CACHE" "$SWIFT_SCRATCH"
CLANG_MODULE_CACHE_PATH="$CLANG_CACHE" \
SWIFTPM_MODULECACHE_OVERRIDE="$SWIFT_CACHE" \
swift build -c release --package-path "$ROOT_DIR" --scratch-path "$SWIFT_SCRATCH"

BUILD_BINARY="$SWIFT_SCRATCH/arm64-apple-macosx/release/$PROCESS_NAME"
if [[ ! -x "$BUILD_BINARY" ]]; then
  BUILD_BINARY="$SWIFT_SCRATCH/release/$PROCESS_NAME"
fi
if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "release binary not found in $SWIFT_SCRATCH" >&2
  exit 1
fi

rm -rf "$STAGE_APP_BUNDLE"
rm -rf "$LEGACY_DIST_APP"
rm -f "$APP_ARCHIVE"
rm -f "$CHECKSUM_FILE"
rm -f "$PLUGIN_ARCHIVE"
rm -f "$PLUGIN_CHECKSUM_FILE"
rm -f "$LEGACY_APP_ARCHIVE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES/Renderer"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_CONTENTS/Info.plist"
node "$FRONTEND_DIR/scripts/stage-renderer.mjs" "$FRONTEND_DIR/dist" "$APP_RESOURCES/Renderer"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$APP_RESOURCES/THIRD_PARTY_NOTICES.md"
xattr -cr "$STAGE_APP_BUNDLE"
codesign --force --sign - --identifier "$BUNDLE_ID" "$STAGE_APP_BUNDLE"
codesign --verify --deep --strict "$STAGE_APP_BUNDLE"
mkdir -p "$DIST_DIR"
/usr/bin/ditto -c -k --keepParent --norsrc "$STAGE_APP_BUNDLE" "$APP_ARCHIVE"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$ARCHIVE_FILENAME" > "$CHECKSUM_FILENAME"
)
/usr/bin/ditto -c -k --keepParent --norsrc "$PLUGIN_DIR" "$PLUGIN_ARCHIVE"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "${PLUGIN_ARCHIVE##*/}" > "${PLUGIN_CHECKSUM_FILE##*/}"
)

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  mkdir -p "$INSTALL_DIR"
  rm -rf "$APP_BUNDLE"
  rm -rf "$LEGACY_APP_BUNDLE"
  /usr/bin/ditto "$STAGE_APP_BUNDLE" "$APP_BUNDLE"
  xattr -cr "$APP_BUNDLE"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
  codesign --verify --deep --strict "$APP_BUNDLE"
fi

echo "Archive: $APP_ARCHIVE"
echo "SHA-256: $CHECKSUM_FILE"
echo "Plugin: $PLUGIN_ARCHIVE"
echo "Plugin SHA-256: $PLUGIN_CHECKSUM_FILE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  --build-only|build-only) ;;
esac
