//
//  CalWidgetApp.swift
//  CalWidget
//
//  Created by Dominic Critchlow on 4/28/26.
//

import SwiftUI

private enum WindowID {
    static let rail = "rail"
}

@main
struct CalWidgetApp: App {
    @StateObject private var calendarStore = CalendarStore()
    private let updaterCoordinator = UpdaterCoordinator()

    var body: some Scene {
        Window("CalWidget", id: WindowID.rail) {
            ContentView()
                .environmentObject(calendarStore)
                .background(
                    WindowAccessor { window in
                        WindowStyleCoordinator.apply(to: window)
                    }
                )
        }
        .defaultSize(width: 320, height: 900)
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(calendarStore)
        }

        MenuBarExtra {
            MenuBarContentBridge(updaterCoordinator: updaterCoordinator)
        } label: {
            Image(systemName: "calendar")
        }
    }
}

// Bridge view so MenuBarContent can use `openWindow` from the environment.
private struct MenuBarContentBridge: View {
    let updaterCoordinator: UpdaterCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarContent(
            updaterCoordinator: updaterCoordinator,
            openWindow: { openWindow(id: WindowID.rail) }
        )
    }
}
