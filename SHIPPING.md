# Shipping CalWidget

Developer-facing runbook for cutting and publishing a release. End-user docs
live in [README.md](README.md).

## First-time setup

You do these once per machine. After that, every release is a tag push.

### 1. Generate a Sparkle signing key

The EdDSA key signs every release so users only auto-install builds that came
from you, even if your appcast or DMG host is compromised.

Fetch Sparkle's helper tools into `vendor/Sparkle/` (same layout CI uses, and
where [scripts/release.sh](scripts/release.sh) looks for them). The brew cask
is **not** recommended — it ships the binaries with `com.apple.quarantine`,
so Gatekeeper flags `generate_keys` as malware on first run.

```sh
SPARKLE_VERSION="2.6.4"
curl -L "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    -o /tmp/sparkle.tar.xz
mkdir -p vendor/Sparkle
tar -xf /tmp/sparkle.tar.xz -C vendor/Sparkle

# Generates the key, stores private in Keychain, prints the public to stdout.
vendor/Sparkle/bin/generate_keys
```

Copy the printed public key into `CalWidget.xcodeproj/project.pbxproj`,
replacing `REPLACE_WITH_YOUR_SPARKLE_PUBLIC_KEY` in the
`INFOPLIST_KEY_SUPublicEDKey` setting (Release config).

Export the private key to a file so `release.sh` (and CI) can sign appcasts:

```sh
vendor/Sparkle/bin/generate_keys -x ~/.calwidget-sparkle-private.key
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
print the exact `notarytool store-credentials` command to register an **App
Store Connect API key** under the keychain profile `calwidget-notary`. The
signing account is a Managed Apple ID, which cannot use an app-specific
password for notarization — use an API key (create one at App Store Connect →
Users and Access → Integrations).

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
5. Sign the DMG with Sparkle's `sign_update` and rewrite `appcast.xml` as a
   single signed `<item>` for this version (we don't use `generate_appcast` —
   in Sparkle 2.6.4 it omits the EdDSA signature for DMGs)

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
| `DEVELOPER_ID_CERT_P12_BASE64` | `base64 -i DeveloperID.p12` of your exported cert + private key |
| `DEVELOPER_ID_CERT_PASSWORD` | Password set when exporting the .p12 |
| `KEYCHAIN_PASSWORD` | Any string — used to lock the temporary keychain on the runner |
| `ASC_API_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8` of your App Store Connect API key |
| `ASC_API_KEY_ID` | The 10-char Key ID for that API key |
| `ASC_API_ISSUER_ID` | The Issuer ID (UUID) from App Store Connect → Integrations |
| `SPARKLE_PRIVATE_KEY_BASE64` | `base64 -i ~/.calwidget-sparkle-private.key` |

Notarization uses an **App Store Connect API key**, not an Apple ID + app-specific
password — the signing account is a Managed Apple ID, and Managed Apple IDs
cannot use app-specific passwords with `notarytool` (they 401). The
`.p8`, Key ID, and Issuer ID live in 1Password; create the key at App Store
Connect → Users and Access → Integrations → App Store Connect API (Developer role).

To export the cert from Keychain Access: select **Developer ID Application:
Dominic Critchlow** + its private key (cmd-click both), right-click → Export
2 items → `.p12` format. The team ID (`WYU5QYFS2X`) is hardcoded in
`scripts/release.sh`, so it is not a secret.

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
  signing key; they have to manually re-download once. Confirm the keys line
  up: `vendor/Sparkle/bin/generate_keys -p` must equal `INFOPLIST_KEY_SUPublicEDKey`.
- **Update silently never appears / appcast `<enclosure>` has no
  `sparkle:edSignature`** → an unsigned appcast got published. `release.sh`
  aborts rather than publish unsigned, but if you hand-edit, verify with
  `grep edSignature appcast.xml`. Do **not** use `generate_appcast` here — it
  drops the signature for DMGs in our Sparkle version.
- **Build error: `No such module 'Sparkle'`** → SPM dependencies didn't
  resolve. Run `xcodebuild -resolvePackageDependencies` from the repo root.
  The `#if canImport(Sparkle)` guard in `UpdaterCoordinator.swift` lets the
  project build even if Sparkle is temporarily unavailable; Check for
  Updates is a no-op in that case.

