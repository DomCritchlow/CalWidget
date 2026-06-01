#!/usr/bin/env bash
#
# release.sh — build, sign, notarize, and package CalWidget for distribution.
#
# Requirements (set up once via scripts/setup-signing.sh):
#   - "Developer ID Application" certificate in the login keychain
#   - notarytool credential profile named "calwidget-notary".
#     This account (a Managed Apple ID) must use an App Store Connect API key,
#     not an app-specific password:
#       xcrun notarytool store-credentials calwidget-notary \
#           --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
#   - Sparkle sign_update tool on PATH or in ./vendor/Sparkle/bin/
#   - SPARKLE_PRIVATE_KEY_FILE env var pointing at the EdDSA private key file
#     (generated once with `generate_keys` from Sparkle; never commit). If unset,
#     sign_update falls back to the key stored in the Keychain.
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
DOWNLOAD_URL="https://github.com/domcritchlow/CalWidget/releases/download/v$VERSION/$APP_NAME-$VERSION.dmg"

# We sign the DMG directly with sign_update rather than relying on
# generate_appcast: that tool (Sparkle 2.6.4) does NOT embed sparkle:edSignature
# for DMGs and appends a duplicate <item> when the build number changes. Since
# Sparkle only needs the latest version's entry, we emit a single signed item.
if command -v sign_update >/dev/null 2>&1; then
    SIGN_UPDATE="sign_update"
elif [[ -x "$ROOT/vendor/Sparkle/bin/sign_update" ]]; then
    SIGN_UPDATE="$ROOT/vendor/Sparkle/bin/sign_update"
else
    echo "!! sign_update not found (expected on PATH or vendor/Sparkle/bin/)." >&2
    echo "   Cannot sign the appcast; aborting so we never publish an unsigned update." >&2
    exit 1
fi

# Prints: sparkle:edSignature="..." length="..."  — embedded verbatim below.
# With SPARKLE_PRIVATE_KEY_FILE set it uses that key; otherwise the Keychain.
SIG_AND_LENGTH="$("$SIGN_UPDATE" "$DMG_PATH" ${SPARKLE_PRIVATE_KEY_FILE:+--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE"})"
if [[ "$SIG_AND_LENGTH" != *edSignature* ]]; then
    echo "!! sign_update did not return a signature. Aborting." >&2
    exit 1
fi

PUB_DATE="$(date "+%a, %d %b %Y %H:%M:%S %z")"

cat > "$APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
    <channel>
        <title>CalWidget</title>
        <link>https://raw.githubusercontent.com/domcritchlow/CalWidget/main/appcast.xml</link>
        <description>Most recent CalWidget updates.</description>
        <language>en</language>
        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL" $SIG_AND_LENGTH type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

echo "    Signed appcast item written for $VERSION (build $BUILD)."

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
