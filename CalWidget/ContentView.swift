//
//  ContentView.swift
//  CalWidget
//
//  Created by Dominic Critchlow on 4/28/26.
//

import AppKit
import SwiftUI

private enum TimelineLayout {
    static let hourLabelWidth: CGFloat = 42
    static let topInset: CGFloat = 4
    static let minHourHeight: CGFloat = 44
    static let laneSpacing: CGFloat = 4
    static let minEventWidth: CGFloat = 54
    static let minTitleHeight: CGFloat = 16
    static let cornerRadius: CGFloat = 8
}

struct ContentView: View {
    @EnvironmentObject private var calendarStore: CalendarStore
    @AppStorage(CalendarPreferences.enableEventLaunchKey) private var enableEventLaunch = true
    @State private var selectedEvent: TimelineEvent?

    private var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: TimelineLayout.cornerRadius,
            topTrailingRadius: TimelineLayout.cornerRadius
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 1) {
                HeaderView()

                if calendarStore.hasCalendarAccess {
                    DayTimelineView { event in
                        if enableEventLaunch {
                            selectedEvent = event
                        }
                    }
                } else {
                    CalendarAccessView()
                }

                SettingsFooter()
            }

            if let selectedEvent, enableEventLaunch {
                Color.black.opacity(0.08)
                    .ignoresSafeArea()
                    .onTapGesture {
                        self.selectedEvent = nil
                    }

                EventDetailView(event: selectedEvent) {
                    self.selectedEvent = nil
                }
                .padding(.horizontal, 6)
                .padding(.top, 22)
                .padding(.bottom, 10)
                .zIndex(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(width: 320)
        .frame(minHeight: 700)
        .background(panelShape.fill(Color(NSColor.windowBackgroundColor)))
        .clipShape(panelShape)
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var calendarStore: CalendarStore
    @AppStorage(CalendarPreferences.use24HourTimeKey) private var use24HourTime = true

    private var formatting: TimeFormatting {
        TimeFormatting(use24Hour: use24HourTime)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                calendarStore.showPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .frame(width: 22, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Text(calendarStore.selectedDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 11, weight: .medium))

                Text("|")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(formatting.time(calendarStore.now))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()

                Button("Today") {
                    calendarStore.showToday()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background {
                    Rectangle()
                        .fill(calendarStore.isShowingToday ? Color.clear : Color.primary.opacity(0.05))
                }
                .overlay {
                    Rectangle()
                        .stroke(Color.primary.opacity(calendarStore.isShowingToday ? 0.08 : 0.18), lineWidth: 0.5)
                }
                .foregroundStyle(calendarStore.isShowingToday ? .secondary : .primary)
                .disabled(calendarStore.isShowingToday)
            }
            .fixedSize()

            Spacer(minLength: 0)

            Button {
                calendarStore.showNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .frame(width: 22, alignment: .trailing)
        }
        .padding(.top, 2)
    }
}

private struct SettingsFooter: View {
    var body: some View {
        HStack(spacing: 0) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            // The app is a menu bar agent (LSUIElement / .accessory), so opening the
            // Settings scene does not bring the app forward on its own. Activate
            // explicitly — immediately and again after the window has been created —
            // so the Settings window becomes key and accepts edits.
            .simultaneousGesture(
                TapGesture().onEnded {
                    activateApp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        activateApp()
                    }
                }
            )
            .cursor(.pointingHand)

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func activateApp() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first { $0.title == "Settings" || $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }?
            .makeKeyAndOrderFront(nil)
    }
}

private struct CalendarAccessView: View {
    @EnvironmentObject private var calendarStore: CalendarStore

    var body: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 30, weight: .medium))

            Text("Calendar access is required")
                .font(.system(size: 18, weight: .semibold, design: .rounded))

            Text(calendarStore.authorizationMessage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)

            Button("Connect Calendar") {
                calendarStore.requestAccess()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DayTimelineView: View {
    @EnvironmentObject private var calendarStore: CalendarStore
    @AppStorage(CalendarPreferences.dayStartHourKey) private var dayStartHour = 8
    @AppStorage(CalendarPreferences.dayEndHourKey) private var dayEndHour = 18
    @AppStorage(CalendarPreferences.enableEventLaunchKey) private var enableEventLaunch = true
    @AppStorage(CalendarPreferences.use24HourTimeKey) private var use24HourTime = true
    @AppStorage(CalendarPreferences.colorModeKey) private var colorModeRaw = ColorMode.status.rawValue
    let onSelectEvent: (TimelineEvent) -> Void

    private var formatting: TimeFormatting {
        TimeFormatting(use24Hour: use24HourTime)
    }

    private var colorMode: ColorMode {
        ColorMode(rawValue: colorModeRaw) ?? .off
    }

    var body: some View {
        VStack(spacing: 10) {
            if !calendarStore.allDayEvents.isEmpty {
                AllDayStrip(events: calendarStore.allDayEvents, onSelect: onSelectEvent)
            }

            GeometryReader { proxy in
                let visibleStartHour = max(0, min(dayStartHour, 23))
                let visibleEndHour = max(visibleStartHour + 1, min(dayEndHour, 24))
                let visibleStartSeconds = Double(visibleStartHour) * 3600
                let visibleEndSeconds = Double(visibleEndHour) * 3600
                let visibleDurationHours = Double(visibleEndHour - visibleStartHour)
                let timelineHeight = max(proxy.size.height - TimelineLayout.topInset, CGFloat(visibleDurationHours) * TimelineLayout.minHourHeight)
                let hourHeight = timelineHeight / CGFloat(visibleDurationHours)
                let visibleEvents = calendarStore.laidOutTimedEvents.filter {
                    $0.event.endSeconds > visibleStartSeconds && $0.event.startSeconds < visibleEndSeconds
                }

                ZStack(alignment: .topLeading) {
                    ForEach(visibleStartHour...visibleEndHour, id: \.self) { hour in
                        let y = TimelineLayout.topInset + CGFloat(hour - visibleStartHour) * hourHeight

                        Path { path in
                            path.move(to: CGPoint(x: TimelineLayout.hourLabelWidth, y: y))
                            path.addLine(to: CGPoint(x: proxy.size.width - 14, y: y))
                        }
                        .stroke(Color.primary.opacity(0.1), lineWidth: hour == visibleEndHour ? 0 : 1)

                        if hour < visibleEndHour {
                            Text(formatting.hourLabel(forHour: hour, on: calendarStore.selectedDate))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: TimelineLayout.hourLabelWidth - 10, alignment: .trailing)
                                .offset(x: 0, y: y - 7)
                        }
                    }

                    ForEach(visibleEvents) { event in
                        let blockHeight = event.height(
                            hourHeight: hourHeight,
                            visibleStartSeconds: visibleStartSeconds,
                            visibleEndSeconds: visibleEndSeconds
                        )

                        Button {
                            if enableEventLaunch {
                                onSelectEvent(event.event)
                            }
                        } label: {
                            EventBlockView(
                                event: event.event,
                                availableHeight: blockHeight,
                                status: status(of: event.event),
                                colorMode: colorMode
                            )
                            .frame(
                                width: eventWidth(for: event, totalWidth: proxy.size.width - TimelineLayout.hourLabelWidth - 22),
                                height: blockHeight
                            )
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(enableEventLaunch)
                        .cursor(enableEventLaunch ? .pointingHand : .arrow)
                        .offset(
                            x: TimelineLayout.hourLabelWidth + 8 + eventXOffset(for: event, totalWidth: proxy.size.width - TimelineLayout.hourLabelWidth - 22),
                            y: TimelineLayout.topInset + event.yOffset(
                                hourHeight: hourHeight,
                                visibleStartSeconds: visibleStartSeconds
                            )
                        )
                    }

                    if calendarStore.isShowingToday {
                        let nowSeconds = calendarStore.now.timeIntervalSince(calendarStore.calendar.startOfDay(for: calendarStore.selectedDate))
                        if nowSeconds >= visibleStartSeconds, nowSeconds <= visibleEndSeconds {
                            CurrentTimeLine(
                                nowSeconds: nowSeconds,
                                timelineStartX: TimelineLayout.hourLabelWidth,
                                timelineEndX: proxy.size.width - 14,
                                hourHeight: hourHeight,
                                topInset: TimelineLayout.topInset,
                                visibleStartSeconds: visibleStartSeconds
                            )
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
        }
    }

    private func hourLabel(for hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func eventWidth(for event: PositionedEvent, totalWidth: CGFloat) -> CGFloat {
        let laneCount = CGFloat(max(event.laneCount, 1))
        return max((totalWidth - TimelineLayout.laneSpacing * (laneCount - 1)) / laneCount, TimelineLayout.minEventWidth)
    }

    private func eventXOffset(for event: PositionedEvent, totalWidth: CGFloat) -> CGFloat {
        CGFloat(event.lane) * (eventWidth(for: event, totalWidth: totalWidth) + TimelineLayout.laneSpacing)
    }

    private func status(of event: TimelineEvent) -> EventStatus {
        guard calendarStore.isShowingToday else {
            return .upcoming
        }
        let now = calendarStore.now
        if now >= event.endDate {
            return .past
        }
        if now >= event.startDate {
            return .current
        }
        return .upcoming
    }
}

private struct AllDayStrip: View {
    let events: [TimelineEvent]
    let onSelect: (TimelineEvent) -> Void

    @AppStorage(CalendarPreferences.enableEventLaunchKey) private var enableEventLaunch = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("All Day")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(events) { event in
                    Button {
                        if enableEventLaunch {
                            onSelect(event)
                        }
                    } label: {
                        Text(event.title)
                            .font(.system(size: 10, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(enableEventLaunch)
                    .cursor(enableEventLaunch ? .pointingHand : .arrow)
                }
            }
        }
        .frame(height: 20)
    }
}

private struct EventBlockView: View {
    let event: TimelineEvent
    let availableHeight: CGFloat
    let status: EventStatus
    let colorMode: ColorMode

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(fillColor)

            if availableHeight >= TimelineLayout.minTitleHeight {
                Text(event.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .opacity(textOpacity)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
        }
        .overlay(
            Rectangle()
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
        .clipped()
    }

    private var fillColor: Color {
        switch colorMode {
        case .off:
            return status == .current ? Color.primary.opacity(0.14) : Color(NSColor.windowBackgroundColor)
        case .status:
            switch status {
            case .past: return Color(NSColor.windowBackgroundColor)
            case .current: return Color.green.opacity(0.15)
            case .upcoming: return Color(NSColor.windowBackgroundColor)
            }
        }
    }

    private var borderColor: Color {
        switch colorMode {
        case .off:
            return Color.primary.opacity(status == .current ? 0.28 : 0.14)
        case .status:
            switch status {
            case .past: return Color.primary.opacity(0.10)
            case .current: return Color.green.opacity(0.55)
            case .upcoming: return Color.primary.opacity(0.18)
            }
        }
    }

    private var textOpacity: Double {
        colorMode == .status && status == .past ? 0.45 : 1
    }
}

private struct EventDetailView: View {
    let event: TimelineEvent
    let onClose: () -> Void

    @AppStorage(CalendarPreferences.use24HourTimeKey) private var use24HourTime = true
    @AppStorage(CalendarPreferences.additionalTimeZoneIdentifiersKey) private var additionalTimeZonesData = Data()

    private var localFormatting: TimeFormatting {
        TimeFormatting(use24Hour: use24HourTime)
    }

    private var additionalTimeZones: [TimeZone] {
        guard let ids = try? JSONDecoder().decode([String].self, from: additionalTimeZonesData) else {
            return []
        }
        return ids.compactMap(TimeZone.init(identifier:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 18, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    if event.isAllDay {
                        Text(event.timeRangeText(using: localFormatting))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.timeRangeText(using: localFormatting))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)

                            ForEach(additionalTimeZones, id: \.identifier) { timeZone in
                                HStack(spacing: 6) {
                                    Text(timeZoneAbbreviation(for: timeZone))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    Text(event.timeRangeText(
                                        using: TimeFormatting(use24Hour: use24HourTime, timeZone: timeZone)
                                    ))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Spacer()

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let meetingURL = event.meetingURL {
                        MetadataBlock(title: "Join") {
                            Text(meetingURL.absoluteString)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .lineLimit(2)
                                .truncationMode(.middle)

                            HStack(spacing: 10) {
                                Button("Open Link") {
                                    NSWorkspace.shared.open(meetingURL)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))

                                Button("Copy Link") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(meetingURL.absoluteString, forType: .string)
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .semibold))
                            }
                        }
                    }

                    if let location = event.location, !location.isEmpty {
                        MetadataBlock(title: "Location") {
                            Text(location)
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let notes = event.notes, !notes.isEmpty {
                        MetadataBlock(title: "Notes") {
                            Text(notesAttributedString(notes))
                                .font(.system(size: 11))
                                .textSelection(.enabled)
                                .tint(.accentColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Divider()

            HStack {
                if let calendarURL = event.calendarEventURL {
                    Button("Open In Calendar") {
                        NSWorkspace.shared.open(calendarURL)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
        )
    }

    private func notesAttributedString(_ notes: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: notes, options: options) {
            return attributed
        }
        return AttributedString(notes)
    }

    private func timeZoneAbbreviation(for timeZone: TimeZone) -> String {
        timeZone.abbreviation(for: event.startDate) ?? timeZone.identifier
    }
}

private struct MetadataBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.primary.opacity(0.03))
                .overlay(
                    Rectangle()
                        .stroke(Color.primary.opacity(0.14), lineWidth: 0.5)
                )
        }
    }
}

private struct CursorModifier: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}

private struct CurrentTimeLine: View {
    let nowSeconds: TimeInterval
    let timelineStartX: CGFloat
    let timelineEndX: CGFloat
    let hourHeight: CGFloat
    let topInset: CGFloat
    let visibleStartSeconds: TimeInterval

    var body: some View {
        let y = topInset + CGFloat((nowSeconds - visibleStartSeconds) / 3600) * hourHeight

        Path { path in
            path.move(to: CGPoint(x: timelineStartX, y: y))
            path.addLine(to: CGPoint(x: timelineEndX, y: y))
        }
        .stroke(Color(red: 0.89, green: 0.19, blue: 0.27), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
    }
}

#Preview {
    ContentView()
        .environmentObject(CalendarStore())
}
