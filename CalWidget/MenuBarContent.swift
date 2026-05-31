import SwiftUI

struct MenuBarContent: View {
    let updaterCoordinator: UpdaterCoordinator
    let openWindow: () -> Void

    var body: some View {
        Button("Show CalWidget") {
            openWindow()
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Check for Updates…") {
            updaterCoordinator.checkForUpdates()
        }
        .disabled(!updaterCoordinator.canCheckForUpdates)

        Divider()

        Button("Quit CalWidget") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
