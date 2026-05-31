#!/usr/bin/env bash
#
# setup-signing.sh — one-time bootstrap for the local release pipeline.
#
# This script does NOT modify anything. It walks you through the four pieces
# you need configured once on this machine before scripts/release.sh will work.

set -euo pipefail

APPLE_TEAM_ID="WYU5QYFS2X"
NOTARY_PROFILE="calwidget-notary"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }

bold "1. Developer ID Application certificate"
echo "   Required to sign builds for distribution outside the App Store."
echo "   Currently in your keychain:"
security find-identity -p codesigning -v | grep -E "Developer ID Application|Apple Development" || true
echo ""
echo "   If 'Developer ID Application' is missing:"
echo "     - Open Xcode > Settings > Accounts > [your Apple ID] > Manage Certificates"
echo "     - Click + and choose 'Developer ID Application'"
echo "     - Or visit https://developer.apple.com/account/resources/certificates/list"
echo ""

bold "2. App-specific password for notarytool"
echo "   Generate one at https://appleid.apple.com under 'App-Specific Passwords'."
echo "   Then store it in keychain under the profile name '$NOTARY_PROFILE':"
echo ""
echo "     xcrun notarytool store-credentials $NOTARY_PROFILE \\"
echo "         --apple-id 'you@example.com' \\"
echo "         --team-id $APPLE_TEAM_ID \\"
echo "         --password 'xxxx-xxxx-xxxx-xxxx'"
echo ""
echo "   Verify with:"
echo "     xcrun notarytool history --keychain-profile $NOTARY_PROFILE"
echo ""

bold "3. Sparkle EdDSA signing key"
echo "   Used to sign update payloads so users only auto-install your builds."
echo "   Fetch the helper tools into vendor/Sparkle/ and generate a key once."
echo "   (Don't use 'brew install --cask sparkle' — its binaries are quarantined"
echo "    and Gatekeeper will flag generate_keys as malware.)"
echo ""
echo "     SPARKLE_VERSION=2.6.4"
echo "     curl -L \"https://github.com/sparkle-project/Sparkle/releases/download/\$SPARKLE_VERSION/Sparkle-\$SPARKLE_VERSION.tar.xz\" -o /tmp/sparkle.tar.xz"
echo "     mkdir -p vendor/Sparkle && tar -xf /tmp/sparkle.tar.xz -C vendor/Sparkle"
echo "     vendor/Sparkle/bin/generate_keys    # stores private key in your Keychain"
echo ""
echo "   To export the private key to a file for CI:"
echo "     vendor/Sparkle/bin/generate_keys -x ~/.calwidget-sparkle-private.key"
echo "     export SPARKLE_PRIVATE_KEY_FILE=~/.calwidget-sparkle-private.key"
echo ""
echo "   Then copy the *public* key it prints and paste it into:"
echo "     CalWidget.xcodeproj/project.pbxproj"
echo "     replacing the placeholder INFOPLIST_KEY_SUPublicEDKey value."
echo ""

bold "4. Optional: create-dmg for prettier installer windows"
echo "   The default release.sh uses hdiutil which produces a plain DMG."
echo "   If you want a styled DMG with a drag-to-Applications layout:"
echo "     brew install create-dmg"
echo ""
echo "   You can then swap the hdiutil block in scripts/release.sh."
echo ""

bold "Ready."
echo "Once the above are configured, run: scripts/release.sh"
