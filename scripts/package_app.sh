#!/bin/zsh

set -euo pipefail
export COPYFILE_DISABLE=1

PROJECT_DIR=${0:A:h:h}
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/medialatch-package.XXXXXX")
trap 'rm -rf -- "$STAGING_DIR"' EXIT
APP_DIR="$STAGING_DIR/MediaLatch.app"
CONTENTS_DIR="$APP_DIR/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MACOS_DIR="$CONTENTS_DIR/MacOS"
VENDOR_BIN="$PROJECT_DIR/.vendor/bin"
ICON_SOURCE="$PROJECT_DIR/.build/MediaLatch-1024.png"
ICONSET_DIR="$PROJECT_DIR/.build/AppIcon.iconset"
BUILD_MODE=${MEDIALATCH_BUILD_MODE:-universal}
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/Resources/Info.plist")
BUILD_LABEL=$BUILD_MODE
LOCAL_ZIP="$PROJECT_DIR/dist/MediaLatch-$VERSION-macOS-$BUILD_LABEL-local.zip"
LOCAL_APP="$PROJECT_DIR/dist/MediaLatch.app"
YTDLP_VERSION=2026.11.23
YTDLP_RELEASE="https://github.com/yt-dlp/yt-dlp/releases/download/$YTDLP_VERSION"
YTDLP_BINARY="$VENDOR_BIN/yt-dlp-$YTDLP_VERSION"

cd "$PROJECT_DIR"
if [[ "$BUILD_MODE" == "universal" ]]; then
    swift build --configuration release --arch arm64 --arch x86_64
    APP_BINARY_SOURCE="$(swift build --configuration release --arch arm64 --arch x86_64 --show-bin-path)/MediaLatch"
else
    swift build --configuration release
    APP_BINARY_SOURCE="$(swift build --configuration release --show-bin-path)/MediaLatch"
fi

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR/bin" "$VENDOR_BIN" "$ICONSET_DIR" "$PROJECT_DIR/dist"

if [[ ! -x "$YTDLP_BINARY" ]]; then
    curl --fail --location --silent --show-error "$YTDLP_RELEASE/yt-dlp_macos" \
        --output "$STAGING_DIR/yt-dlp_macos"
    curl --fail --location --silent --show-error "$YTDLP_RELEASE/SHA2-256SUMS" \
        --output "$STAGING_DIR/SHA2-256SUMS"
    awk '$2 == "yt-dlp_macos" { print }' "$STAGING_DIR/SHA2-256SUMS" > "$STAGING_DIR/yt-dlp.sha256"
    (cd "$STAGING_DIR" && shasum -a 256 -c yt-dlp.sha256)
    chmod 755 "$STAGING_DIR/yt-dlp_macos"
    mv "$STAGING_DIR/yt-dlp_macos" "$YTDLP_BINARY"
fi

xcrun swift "$PROJECT_DIR/scripts/make_icon.swift" "$ICON_SOURCE"

sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil --convert icns "$ICONSET_DIR" --output "$RESOURCES_DIR/AppIcon.icns"

cp "$APP_BINARY_SOURCE" "$MACOS_DIR/MediaLatch"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$YTDLP_BINARY" "$RESOURCES_DIR/bin/yt-dlp"
chmod 755 "$MACOS_DIR/MediaLatch" "$RESOURCES_DIR/bin/yt-dlp"

if [[ "$BUILD_MODE" == "universal" ]]; then
    YTDLP_ARCHITECTURES=$(lipo -archs "$RESOURCES_DIR/bin/yt-dlp")
    if [[ "$YTDLP_ARCHITECTURES" != *arm64* || "$YTDLP_ARCHITECTURES" != *x86_64* ]]; then
        echo "The bundled download engine is not universal (arm64 + x86_64): $YTDLP_ARCHITECTURES" >&2
        exit 1
    fi
fi

xattr -cr "$APP_DIR"
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" >/dev/null
xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
xattr -d com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
codesign --verify --deep --strict "$APP_DIR"

ditto --norsrc -c -k --keepParent "$APP_DIR" "$STAGING_DIR/${LOCAL_ZIP:t}"

# Replace the previous local build only after the new one passes signature checks.
if [[ -e "$LOCAL_APP" ]]; then
    mv "$LOCAL_APP" "$STAGING_DIR/previous.app"
fi
if ! mv "$APP_DIR" "$LOCAL_APP"; then
    if [[ -e "$STAGING_DIR/previous.app" ]]; then
        mv "$STAGING_DIR/previous.app" "$LOCAL_APP"
    fi
    exit 1
fi
mv -f "$STAGING_DIR/${LOCAL_ZIP:t}" "$LOCAL_ZIP"

echo "Local app: $LOCAL_APP"
echo "Local archive: $LOCAL_ZIP"
echo "Architectures: $(lipo -archs "$LOCAL_APP/Contents/MacOS/MediaLatch")"
