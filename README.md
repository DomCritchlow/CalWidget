# CalWidget

A minimal macOS day-rail calendar. CalWidget lives on the left edge of your
desktop as a narrow, always-visible timeline of today's events with a live
current-time marker.

<!-- TODO: add screenshot at docs/screenshot.png and reference it here -->

## Install

> macOS 14 (Sonoma) or newer · Apple silicon and Intel · ~10 MB

1. Download the latest `CalWidget-X.Y.Z.dmg` from the
   [Releases page](https://github.com/domcritchlow/CalWidget/releases/latest).
2. Open the DMG and drag **CalWidget** into your Applications folder.
3. Launch CalWidget. When macOS asks, grant Calendar access — this is how
   the timeline reads your events.

The app is signed with a Developer ID and notarized by Apple, so you should
not see any "unidentified developer" warning. Updates are delivered in-app
through Sparkle; you can also check manually in **Settings → Check for
Updates…**.

> **Heads up:** CalWidget runs as a desktop widget with **no Dock icon**. If you
> close its window, bring it back by launching CalWidget again from Spotlight or
> your Applications folder.

### Homebrew

> Coming soon. The cask will wrap the same notarized DMG.

## What it does

- One-day timeline pinned to the left edge of the screen
- Reads from Apple Calendar, including Google calendars synced via macOS Calendar accounts
- Highlights the currently active event
- Click any event to open an in-app detail panel with meeting join links (Meet, Zoom, Teams, Webex, GoToMeeting) plus location, notes, and a fallback to Apple Calendar
- Optional secondary time zones shown alongside each event
- Filter which calendars appear, and zoom the rail into your working hours

## Settings

Open the app's Settings window — the gear button at the top of the rail, or
`⌘,` while CalWidget is focused — to configure:

- Visible start and end hours
- 12- or 24-hour time
- Whether clicking an event opens the detail panel
- Which calendars are visible (defaults to all)
- Up to three additional time zones shown in event details

If no calendars are selected, all available calendars are shown.

## Build from source

```sh
git clone https://github.com/domcritchlow/CalWidget.git
cd CalWidget
open CalWidget.xcodeproj
```

Then build the `CalWidget` target in Xcode 16 or newer. Sparkle is already
wired in as a Swift Package dependency, so in-app updates work in Release
builds out of the box. The `Check for Updates…` button in Settings uses it.

## Project layout

| Path | Purpose |
|---|---|
| [CalWidget/CalWidgetApp.swift](CalWidget/CalWidgetApp.swift) | App entry point and scenes (rail window + Settings) |
| [CalWidget/ContentView.swift](CalWidget/ContentView.swift) | Timeline UI and event detail overlay |
| [CalWidget/CalendarStore.swift](CalWidget/CalendarStore.swift) | EventKit integration, event shaping, lane layout |
| [CalWidget/SettingsView.swift](CalWidget/SettingsView.swift) | Settings window |
| [CalWidget/WindowAccessor.swift](CalWidget/WindowAccessor.swift) | Borderless rail window styling and pin-to-left behavior |
| [CalWidget/UpdaterCoordinator.swift](CalWidget/UpdaterCoordinator.swift) | Sparkle integration, gated by `canImport(Sparkle)` |
| [scripts/release.sh](scripts/release.sh) | One-command build → sign → notarize → DMG → appcast |
| [SHIPPING.md](SHIPPING.md) | Release runbook |

## Notes

CalWidget treats Apple Calendar as the source of truth. Google Calendar
support flows through macOS Calendar account sync, not a direct Google API
integration — so adding a Google account in **System Settings → Internet
Accounts** is enough for those events to appear here.

## License

[MIT](LICENSE). See [SHIPPING.md](SHIPPING.md) for the release process if
you're cutting a build.
