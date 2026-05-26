# Shipping CalWidget

Developer-facing runbook for cutting and publishing a release. End-user docs
live in [README.md](README.md).

## First-time setup

You do these once per machine. After that, every release is a tag push.

### 1. Generate a Sparkle signing key

The EdDSA key signs every release so users only auto-install builds that came
from you, even if your appcast or DMG host is compromised.

```sh
# Install Sparkle's helper tools — required for generate_keys / generate_appcast.
brew install --cask sparkle

# Generates the key, stores private in Keychain, prints the public to stdout.
generate_keys
```

Copy the printed public key into `CalWidget.xcodeproj/project.pbxproj`,
replacing `REPLACE_WITH_YOUR_SPARKLE_PUBLIC_KEY` in the
`INFOPLIST_KEY_SUPublicEDKey` setting (Release config).

Export the private key to a file so `release.sh` (and CI) can sign appcasts:

```sh
generate_keys -x ~/.calwidget-sparkle-private.key
chmod 600 ~/.calwidget-sparkle-private.key
echo 'export SPARKLE_PRIVATE_KEY_FILE=~/.calwidget-sparkle-private.key' >> ~/.zshrc
```

**Do not commit the private key.** Losing it means every user has to
manually reinstall the app to trust new releases.

### 2. Walk through the signing checklist

```sh
scripts/setup-signing.sh
```

It will tell you whether your Developer ID Application cert is present, and
print the exact `notarytool store-credentials` command to register an
app-specific password under the keychain profile `calwidget-notary`.

### 3. Point the appcast URL at your repo

The `INFOPLIST_KEY_SUFeedURL` build setting currently points at
`https://raw.githubusercontent.com/domcritchlow/CalWidget/main/appcast.xml`.
Once you push the repo to GitHub under that path, the URL will resolve.
Adjust if you fork or rename.

## Cutting a release locally

```sh
# Bump MARKETING_VERSION in CalWidget.xcodeproj (or pass as arg)
# Add a section to CHANGELOG.md
scripts/release.sh 1.0.0
```

`release.sh` does:

1. `xcodebuild archive` with hardened runtime + Developer ID signing
2. Export the .app via `developer-id` method
3. Submit `.app` to Apple notary service, wait for ticket, staple
4. Build a UDZO DMG, sign it, notarize it, staple it
5. Run Sparkle's `generate_appcast` against `dist/releases/` and update
   `appcast.xml` with the new entry signed by your EdDSA key

Final artifacts land in `dist/`:

- `dist/CalWidget-1.0.0.dmg` — what users download
- `appcast.xml` (in repo root) — what Sparkle polls

## Publishing

```sh
git add CHANGELOG.md appcast.xml
git commit -m "release: v1.0.0"
git tag v1.0.0
git push && git push --tags

gh release create v1.0.0 dist/CalWidget-1.0.0.dmg \
    --title "CalWidget 1.0.0" \
    --notes-file CHANGELOG.md
```

Existing users get an update prompt within 24 hours (Sparkle polls daily by
default). They can also trigger it manually from `CalWidget → Check for
Updates…`.

## Cutting a release via GitHub Actions

Push a `v*.*.*` tag and the workflow at
[.github/workflows/release.yml](.github/workflows/release.yml) does all of
the above on a macOS runner and attaches the DMG to the release.

It needs these repository secrets:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 < DeveloperID.p12` of your exported cert + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | Any string — used to lock the temporary keychain on the runner |
| `APPLE_ID` | Your Apple ID email |
| `APPLE_TEAM_ID` | `WYU5QYFS2X` |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |
| `SPARKLE_PRIVATE_KEY_BASE64` | `base64 < ~/.calwidget-sparkle-private.key` |

To export the cert from Keychain Access: select **Developer ID Application:
Dominic Critchlow** + its private key (cmd-click both), right-click → Export
Items → `.p12` format.

## Common gotchas

- **"App can't be opened because Apple cannot check it for malicious
  software"** → stapling didn't run, or the user downloaded a build that
  wasn't notarized. Re-run `xcrun stapler validate /path/to/CalWidget.app`
  on the artifact.
- **Notarization rejects with "hardened runtime not enabled"** → check
  that `ENABLE_HARDENED_RUNTIME = YES` survived the build (`codesign
  -d --entitlements - /path/to/CalWidget.app` should show the hardened
  runtime flag).
- **Sparkle update fails with "signature does not match"** → the
  `SUPublicEDKey` in the *installed* version doesn't match the private key
  that signed the appcast. Users on old builds won't auto-update to the new
  signing key; they have to manually re-download once.
- **Build error: `No such module 'Sparkle'`** → SPM dependencies didn't
  resolve. Run `xcodebuild -resolvePackageDependencies` from the repo root.
  The `#if canImport(Sparkle)` guard in `UpdaterCoordinator.swift` lets the
  project build even if Sparkle is temporarily unavailable; Check for
  Updates is a no-op in that case.
