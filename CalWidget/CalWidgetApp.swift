//
//  CalWidgetApp.swift
//  CalWidget
//
//  Created by Dominic Critchlow on 4/28/26.
//

import SwiftUI

@main
struct CalWidgetApp: App {
    @StateObject private var calendarStore = CalendarStore()
    private let updaterCoordinator = UpdaterCoordinator()

    var body: some Scene {
        WindowGroup {
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
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updaterCoordinator.checkForUpdates()
                }
                .disabled(!updaterCoordinator.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .windowArrangement) { }
        }

        Settings {
            SettingsView()
                .environmentObject(calendarStore)
        }
    }
}
