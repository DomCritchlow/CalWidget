#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, and package CalWidget for distribution.
#
# Requirements (set up once via scripts/setup-signing.sh):
#   - "Developer ID Application" certificate in the login keychain
#   - notarytool credential profile named "calwidget-notary"
#       xcrun notarytool store-credentials calwidget-notary \
#           --apple-id "you@example.com" --team-id WYU5QYFS2X --password "app-specific-password"
#   - Sparkle generate_appcast tool on PATH or in ./vendor/Sparkle/bin/
#   - SPARKLE_PRIVATE_KEY_FILE env var pointing at the EdDSA private key file
#     (generated once with `generate_keys` from Sparkle; never commit)
#
# Usage:
#   scripts/release.sh           # uses MARKETING_VERSION from pbxproj
#   scripts/release.sh 1.1.0     # overrides marketing version

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="CalWidget.xcodeproj"
SCHEME="CalWidget"
CONFIG="Release"
APP_NAME="CalWidget"
BUNDLE_ID="com.domcritchlow.calwidget"
TEAM_ID="WYU5QYFS2X"
NOTARY_PROFILE="${NOTARY_PROFILE:-calwidget-notary}"

DIST="$ROOT/dist"
ARCHIVE="$DIST/$APP_NAME.xcarchive"
EXPORT_DIR="$DIST/export"
DMG_STAGING="$DIST/dmg-staging"

mkdir -p "$DIST"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$DMG_STAGING"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /dev/stdin <<<"$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" 2>/dev/null | awk -F' = ' '/MARKETING_VERSION/ {print $2; exit}')" 2>/dev/null || true)"
fi
if [[ -z "$VERSION" ]]; then
    VERSION="$(grep -m1 'MARKETING_VERSION' CalWidget.xcodeproj/project.pbxproj | awk -F' = ' '{gsub(/[ ;]/, "", $2); print $2}')"
fi
BUILD="$(date +%Y%m%d%H%M)"

echo "==> Releasing $APP_NAME $VERSION (build $BUILD)"

echo "==> Archiving"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    clean archive

echo "==> Exporting Developer ID app"
EXPORT_OPTIONS="$DIST/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { echo "Export failed: $APP_PATH not found"; exit 1; }

echo "==> Submitting to Apple notary service"
ZIP_FOR_NOTARY="$DIST/$APP_NAME-notary.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_FOR_NOTARY"
xcrun notarytool submit "$ZIP_FOR_NOTARY" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
rm -f "$ZIP_FOR_NOTARY"

echo "==> Stapling notarization ticket"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

echo "==> Building DMG"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
DMG_PATH="$DIST/$APP_NAME-$VERSION.dmg"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"

echo "==> Signing & stapling DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"

echo "==> Updating appcast"
APPCAST="$ROOT/appcast.xml"
RELEASES="$DIST/releases"
mkdir -p "$RELEASES"
cp "$DMG_PATH" "$RELEASES/"

if command -v generate_appcast >/dev/null 2>&1; then
    GENERATE_APPCAST="generate_appcast"
elif [[ -x "$ROOT/vendor/Sparkle/bin/generate_appcast" ]]; then
    GENERATE_APPCAST="$ROOT/vendor/Sparkle/bin/generate_appcast"
else
    echo "!! generate_appcast not found. Skipping appcast update."
    echo "   Install Sparkle's helper tools and place them at vendor/Sparkle/bin/."
    GENERATE_APPCAST=""
fi

if [[ -n "$GENERATE_APPCAST" ]]; then
    if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
        echo "!! SPARKLE_PRIVATE_KEY_FILE not set; appcast will not be signed."
    fi
    "$GENERATE_APPCAST" \
        --download-url-prefix "https://github.com/domcritchlow/CalWidget/releases/download/v$VERSION/" \
        ${SPARKLE_PRIVATE_KEY_FILE:+--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"} \
        -o "$APPCAST" \
        "$RELEASES"
fi

echo ""
echo "==> Done."
echo "    DMG:     $DMG_PATH"
echo "    Appcast: $APPCAST"
echo ""
echo "Next:"
echo "    1. Edit CHANGELOG.md and commit."
echo "    2. git tag v$VERSION && git push --tags"
echo "    3. gh release create v$VERSION \"$DMG_PATH\" --notes-file CHANGELOG.md"
echo "    4. git add appcast.xml && git commit -m \"release: v$VERSION appcast\" && git push"
