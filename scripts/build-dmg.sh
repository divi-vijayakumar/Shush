#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/Shush.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/Shush.iconset"
ASSET_CATALOG_DIR="$BUILD_DIR/ShushAssets.xcassets"
DMG_STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/Shush-0.2.0-arm64.dmg"
SIGN_IDENTITY="${SHUSH_SIGN_IDENTITY:--}"
NOTARY_PROFILE="${SHUSH_NOTARY_PROFILE:-}"

if [[ -n "$NOTARY_PROFILE" && "$SIGN_IDENTITY" == "-" ]]; then
  echo "SHUSH_NOTARY_PROFILE requires a Developer ID Application identity in SHUSH_SIGN_IDENTITY." >&2
  exit 1
fi

export CLANG_MODULE_CACHE_PATH="/private/tmp/shush-clang"
export SWIFTPM_MODULECACHE_OVERRIDE="/private/tmp/shush-swiftpm"

mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

cd "$ROOT_DIR"
swift build -c release --disable-sandbox

rm -rf "$APP_DIR" "$ICONSET_DIR" "$ASSET_CATALOG_DIR" "$DMG_STAGE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$ASSET_CATALOG_DIR/AppIcon.appiconset" "$DMG_STAGE"

cp "$ROOT_DIR/.build/release/Shush" "$MACOS_DIR/Shush"
cp "$ROOT_DIR/Vendor/agent-vault" "$RESOURCES_DIR/agent-vault"
cp "$ROOT_DIR/.build/release/shush-cli" "$RESOURCES_DIR/shush"
cp "$ROOT_DIR/Vendor/AGENT_VAULT_LICENSE.txt" "$RESOURCES_DIR/AGENT_VAULT_LICENSE.txt"
chmod 755 "$MACOS_DIR/Shush" "$RESOURCES_DIR/agent-vault" "$RESOURCES_DIR/shush"

sips -z 16 16 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ROOT_DIR/Assets/ShushIcon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

cp "$ICONSET_DIR"/*.png "$ASSET_CATALOG_DIR/AppIcon.appiconset/"
cp "$ROOT_DIR/Packaging/AppIconContents.json" "$ASSET_CATALOG_DIR/AppIcon.appiconset/Contents.json"
cp "$ROOT_DIR/Packaging/AssetCatalogContents.json" "$ASSET_CATALOG_DIR/Contents.json"
xcrun actool \
  --compile "$RESOURCES_DIR" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$BUILD_DIR/AppIconInfo.plist" \
  "$ASSET_CATALOG_DIR" >/dev/null

cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$RESOURCES_DIR/agent-vault"
  codesign --force --sign - "$RESOURCES_DIR/shush"
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$RESOURCES_DIR/agent-vault"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$RESOURCES_DIR/shush"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

cp -R "$APP_DIR" "$DMG_STAGE/Shush.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$ROOT_DIR/Packaging/README.txt" "$DMG_STAGE/README.txt"

hdiutil create \
  -volname "Shush" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"

echo "$DMG_PATH"
echo "$DMG_PATH.sha256"
