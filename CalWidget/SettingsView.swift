//
//  SettingsView.swift
//  CalWidget
//
//  Created by Codex.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(CalendarPreferences.selectedCalendarIDsKey)
    private var selectedCalendarIDsData = Data()
    @AppStorage(CalendarPreferences.dayStartHourKey)
    private var dayStartHour = 8
    @AppStorage(CalendarPreferences.dayEndHourKey)
    private var dayEndHour = 18
    @AppStorage(CalendarPreferences.enableEventLaunchKey)
    private var enableEventLaunch = true
    @AppStorage(CalendarPreferences.use24HourTimeKey)
    private var use24HourTime = true
    @AppStorage(CalendarPreferences.additionalTimeZoneIdentifiersKey)
    private var additionalTimeZonesData = Data()
    @AppStorage(CalendarPreferences.colorModeKey)
    private var colorModeRaw = ColorMode.status.rawValue

    @EnvironmentObject private var calendarStore: CalendarStore

    let updaterCoordinator: UpdaterCoordinator

    private var formatting: TimeFormatting {
        TimeFormatting(use24Hour: use24HourTime)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Timeline")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text("Set the visible day range.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Picker("Start", selection: startHourBinding) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(hourLabel(for: hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Picker("End", selection: endHourBinding) {
                            ForEach(1...24, id: \.self) { hour in
                                Text(endHourLabel(for: hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }

                Toggle("Enable event details", isOn: $enableEventLaunch)
                    .font(.system(size: 12))

                Divider()

                Text("Time format")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Picker("Display times in", selection: $use24HourTime) {
                    Text("24-hour (14:30)").tag(true)
                    Text("12-hour (2:30 PM)").tag(false)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .font(.system(size: 12))

                Divider()

                Text("Appearance")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text("Status colors fade past events and tint the currently running event in green. The rest of the timeline stays black & white.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Picker("Color mode", selection: $colorModeRaw) {
                    Text("Off (black & white)").tag(ColorMode.off.rawValue)
                    Text("Status colors").tag(ColorMode.status.rawValue)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .font(.system(size: 12))

                Divider()

                AdditionalTimeZonesSection(
                    additionalTimeZonesData: $additionalTimeZonesData,
                    formatting: formatting,
                    now: calendarStore.now
                )

                Divider()

                Text("Calendars")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text("Choose which calendars appear. If nothing is selected, all calendars are shown.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if calendarStore.hasCalendarAccess {
                    LazyVStack(spacing: 8) {
                        ForEach(calendarStore.availableCalendars) { calendar in
                            Toggle(isOn: binding(for: calendar.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(calendar.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(calendar.accountName)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }

                    HStack {
                        Button("Show All") {
                            selectedCalendarIDs = []
                        }

                        Button("Select All") {
                            selectedCalendarIDs = calendarStore.availableCalendars.map(\.id)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(calendarStore.authorizationMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Button("Connect Calendar") {
                            calendarStore.requestAccess()
                        }
                    }
                }

                Divider()

                Text("Application")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                HStack {
                    Button("Check for Updates…") {
                        updaterCoordinator.checkForUpdates()
                    }
                    .disabled(!updaterCoordinator.canCheckForUpdates)

                    Button("Quit CalWidget") {
                        NSApp.terminate(nil)
                    }
                }
                .font(.system(size: 12, weight: .medium))
            }
            .padding(18)
        }
        .frame(width: 360, height: 560)
    }

    private var selectedCalendarIDs: [String] {
        get {
            (try? JSONDecoder().decode([String].self, from: selectedCalendarIDsData)) ?? []
        }
        nonmutating set {
            selectedCalendarIDsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    private var startHourBinding: Binding<Int> {
        Binding {
            dayStartHour
        } set: { newValue in
            dayStartHour = min(newValue, dayEndHour - 1)
        }
    }

    private var endHourBinding: Binding<Int> {
        Binding {
            dayEndHour
        } set: { newValue in
            dayEndHour = max(newValue, dayStartHour + 1)
        }
    }

    private func binding(for calendarID: String) -> Binding<Bool> {
        Binding {
            selectedCalendarIDs.contains(calendarID)
        } set: { isSelected in
            var currentIDs = selectedCalendarIDs

            if isSelected {
                if !currentIDs.contains(calendarID) {
                    currentIDs.append(calendarID)
                }
            } else {
                currentIDs.removeAll { $0 == calendarID }
            }

            selectedCalendarIDs = currentIDs
        }
    }

    private func hourLabel(for hour: Int) -> String {
        formatting.hourLabel(forHour: hour)
    }

    private func endHourLabel(for hour: Int) -> String {
        hour == 24 ? "Midnight" : formatting.hourLabel(forHour: hour % 24)
    }
}

private struct AdditionalTimeZonesSection: View {
    @Binding var additionalTimeZonesData: Data
    let formatting: TimeFormatting
    let now: Date

    private var identifiers: [String] {
        (try? JSONDecoder().decode([String].self, from: additionalTimeZonesData)) ?? []
    }

    private func write(_ ids: [String]) {
        additionalTimeZonesData = (try? JSONEncoder().encode(ids)) ?? Data()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timezones")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text("Show event times in up to \(CalendarPreferences.maxAdditionalTimeZones) extra timezones in the event detail panel.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ForEach(identifiers, id: \.self) { identifier in
                let timeZone = TimeZone(identifier: identifier)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timeZoneTitle(for: identifier))
                            .font(.system(size: 12, weight: .medium))
                        if let timeZone {
                            Text("\(timeZone.abbreviation(for: now) ?? identifier) · \(TimeFormatting(use24Hour: formatting.use24Hour, timeZone: timeZone).time(now))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        var ids = identifiers
                        ids.removeAll { $0 == identifier }
                        write(ids)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            if identifiers.count < CalendarPreferences.maxAdditionalTimeZones {
                Menu {
                    ForEach(TimeZoneCatalog.regions, id: \.name) { region in
                        Menu(region.name) {
                            ForEach(region.identifiers, id: \.self) { identifier in
                                Button(timeZoneTitle(for: identifier)) {
                                    var ids = identifiers
                                    if !ids.contains(identifier) {
                                        ids.append(identifier)
                                        write(ids)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Add Timezone", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .menuStyle(.borderlessButton)
                .frame(width: 160, alignment: .leading)
            }
        }
    }

    private func timeZoneTitle(for identifier: String) -> String {
        identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? identifier
    }
}

private enum TimeZoneCatalog {
    struct Region {
        let name: String
        let identifiers: [String]
    }

    static let regions: [Region] = {
        let grouped = Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers) { identifier -> String in
            identifier.split(separator: "/").first.map(String.init) ?? "Other"
        }
        return grouped
            .map { Region(name: $0.key, identifiers: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }()
}

#Preview {
    SettingsView(updaterCoordinator: UpdaterCoordinator())
        .environmentObject(CalendarStore())
}
