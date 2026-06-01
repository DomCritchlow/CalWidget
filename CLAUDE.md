# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

CalWidget — a minimal **macOS** day-rail calendar widget (SwiftUI). It sits on
the desktop as a narrow always-visible timeline of today's events. Distributed
**outside the App Store**: Developer ID-signed, Apple-notarized, with in-app
auto-updates via Sparkle. Public repo.

- Min OS: macOS 14.0 · Bundle ID: `com.domcritchlow.calwidget` · Team: `WYU5QYFS2X`
- App Sandbox **and** Hardened Runtime are both enabled.
- Runs as an agent (`LSUIElement = YES`): **no Dock icon, no menu-bar icon.**
  Entry points are its window and the in-app gear → Settings.

## Architecture (all source under `CalWidget/`)

- `CalWidgetApp.swift` — `@main` App. A `Window` (the rail, id `"rail"`) + a
  `Settings` scene. (An earlier `MenuBarExtra` was removed — don't reintroduce it
  without reason.)
- `ContentView.swift` — the day-rail timeline, current-time marker, lane-packed
  overlapping events, event detail panel, and the `SettingsFooter` gear button.
- `CalendarStore.swift` — EventKit access + event loading (`@EnvironmentObject`).
- `SettingsView.swift` — calendar filtering, day range, time zones, and the
  Check for Updates / Quit buttons. Takes an `UpdaterCoordinator`.
- `UpdaterCoordinator.swift` — Sparkle wrapper, guarded by `#if canImport(Sparkle)`
  so the project still builds if SPM hasn't resolved Sparkle.
- `WindowAccessor.swift` — bridges to AppKit `NSWindow` for window styling.

## ⚠️ Xcode synchronized folders — read this first

The project uses **`PBXFileSystemSynchronizedRootGroup`**. That means **any
`.swift` file you add under `CalWidget/` is compiled automatically** — you do
**not** (and must not) add file references to `project.pbxproj`. Conversely,
deleting a file removes it from the build. Don't hand-edit the pbxproj to
register sources.

`Info.plist` is **generated** (`GENERATE_INFOPLIST_FILE = YES`); plist values
live as `INFOPLIST_KEY_*` build settings in `project.pbxproj`, not a plist file.

When editing `project.pbxproj`, values with special characters (`/`, `=`, `+`)
**must be quoted** — it's an old-style plist and an unquoted `=` breaks parsing.
Sanity-check with `plutil -convert xml1 -o /dev/null CalWidget.xcodeproj/project.pbxproj`.

## Build / run / test

```sh
# Build (no signing needed for a local check)
xcodebuild build -project CalWidget.xcodeproj -scheme CalWidget \
  -configuration Debug CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS'

# Resolve SPM deps if you hit "No such module 'Sparkle'"
xcodebuild -resolvePackageDependencies -project CalWidget.xcodeproj
```

## Releasing (see SHIPPING.md for full detail)

**Normal flow is just a tag push** — CI does everything:
```sh
# bump MARKETING_VERSION in project.pbxproj + add a CHANGELOG entry, commit, then:
git tag vX.Y.Z && git push && git push --tags
```
`.github/workflows/release.yml` (on `v*.*.*` tags) builds, signs, notarizes,
signs the appcast, creates the GitHub release, and commits `appcast.xml`.
A plain push to `main` triggers **nothing**. The tag must match `MARKETING_VERSION`.

Two hard-won gotchas (also in SHIPPING.md):
- **Notarization uses an App Store Connect API key, not an app-specific
  password** — the signing account is a Managed Apple ID and can't use the latter.
- **`scripts/release.sh` signs the appcast with `sign_update`, not
  `generate_appcast`** — that tool omits the `sparkle:edSignature` for DMGs and
  appends duplicate items. After any release, `grep edSignature appcast.xml`
  should show a signature, or auto-update silently fails.

## Conventions

- Match the surrounding SwiftUI style; small focused `private struct` views.
- Never commit signing material (`.p8`, `.p12`, `*-private.key`) — `.gitignore`
  covers them; secrets live in GitHub Actions secrets + 1Password.
- Don't change `INFOPLIST_KEY_SUPublicEDKey` or rotate the Sparkle key without
  understanding it breaks auto-update for all installed users.
