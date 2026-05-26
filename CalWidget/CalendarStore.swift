//
//  CalendarStore.swift
//  CalWidget
//
//  Created by Codex.
//

import Combine
import EventKit
import Foundation
import SwiftUI

enum CalendarPreferences {
    static let selectedCalendarIDsKey = "selectedCalendarIDs"
    static let dayStartHourKey = "dayStartHour"
    static let dayEndHourKey = "dayEndHour"
    static let enableEventLaunchKey = "enableEventLaunch"
    static let use24HourTimeKey = "use24HourTime"
    static let additionalTimeZoneIdentifiersKey = "additionalTimeZoneIdentifiers"
    static let maxAdditionalTimeZones = 3
    static let colorModeKey = "colorMode"
}

enum ColorMode: String, CaseIterable {
    case off
    case status
}

enum EventStatus {
    case past
    case current
    case upcoming
}

struct TimeFormatting {
    let use24Hour: Bool
    let timeZone: TimeZone

    init(use24Hour: Bool, timeZone: TimeZone = .current) {
        self.use24Hour = use24Hour
        self.timeZone = timeZone
    }

    private var locale: Locale {
        var components = Locale.Components(locale: .current)
        components.hourCycle = use24Hour ? .zeroToTwentyThree : .oneToTwelve
        return Locale(components: components)
    }

    func time(_ date: Date) -> String {
        date.formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone)
                .locale(locale)
        )
    }

    func hourLabel(forHour hour: Int, on referenceDate: Date = Date()) -> String {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let startOfDay = calendar.startOfDay(for: referenceDate)
        guard let date = calendar.date(byAdding: .hour, value: hour, to: startOfDay) else {
            return String(format: "%02d:00", hour)
        }
        return time(date)
    }
}

@MainActor
final class CalendarStore: ObservableObject {
    @Published private(set) var authorizationStatus: EKAuthorizationStatus
    @Published private(set) var allDayEvents: [TimelineEvent] = []
    @Published private(set) var timedEvents: [TimelineEvent] = []
    @Published private(set) var laidOutTimedEvents: [PositionedEvent] = []
    @Published private(set) var availableCalendars: [CalendarSource] = []
    @Published private(set) var now = Date()
    @Published var selectedDate = Date()

    let calendar = Calendar.autoupdatingCurrent

    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private var eventStoreChangedObserver: NSObjectProtocol?
    private var dayChangedObserver: NSObjectProtocol?
    private var selectedCalendarsObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var lastRenderedDay = Calendar.autoupdatingCurrent.startOfDay(for: Date())

    init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        observeCalendarChanges()
        observeClock()

        Task {
            await refreshAccessAndEvents()
        }
    }

    deinit {
        if let eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(eventStoreChangedObserver)
        }

        if let dayChangedObserver {
            NotificationCenter.default.removeObserver(dayChangedObserver)
        }

        selectedCalendarsObservation?.invalidate()
        timer?.invalidate()
    }

    var hasCalendarAccess: Bool {
        authorizationStatus == .fullAccess
    }

    var isShowingToday: Bool {
        calendar.isDate(selectedDate, inSameDayAs: now)
    }

    var authorizationMessage: String {
        switch authorizationStatus {
        case .denied, .restricted:
            return "Allow calendar access in System Settings so the timeline can show your events."
        case .writeOnly:
            return "This app needs full calendar access so it can read today’s events."
        case .notDetermined:
            return "Connect Apple Calendar once, and any Google Calendar accounts synced through macOS will appear here too."
        default:
            return "Calendar access is required to load your events."
        }
    }

    func showPreviousDay() {
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: selectedDate) else {
            return
        }

        selectedDate = previousDay
        fetchEvents()
    }

    func showNextDay() {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDate) else {
            return
        }

        selectedDate = nextDay
        fetchEvents()
    }

    func showToday() {
        selectedDate = now
        fetchEvents()
    }

    func requestAccess() {
        Task {
            await refreshAccessAndEvents(forceRequest: true)
        }
    }

    private func refreshAccessAndEvents(forceRequest: Bool = false) async {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        if authorizationStatus == .notDetermined || forceRequest {
            do {
                let granted = try await requestCalendarAccess()
                authorizationStatus = granted ? EKEventStore.authorizationStatus(for: .event) : .denied
            } catch {
                authorizationStatus = .denied
            }
        }

        if hasCalendarAccess {
            fetchEvents()
        } else {
            allDayEvents = []
            timedEvents = []
            laidOutTimedEvents = []
        }
    }

    private func requestCalendarAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await eventStore.requestFullAccessToEvents()
        } else {
            return try await eventStore.requestAccess(to: .event)
        }
    }

    private func fetchEvents() {
        guard hasCalendarAccess else {
            availableCalendars = []
            return
        }

        let calendars = eventStore.calendars(for: .event)
            .filter { !$0.isSubscribed || $0.allowsContentModifications || !$0.title.isEmpty }
            .sorted {
                if $0.source.title == $1.source.title {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }

                return $0.source.title.localizedCaseInsensitiveCompare($1.source.title) == .orderedAscending
            }

        availableCalendars = calendars.map(CalendarSource.init)
        let filteredCalendars = selectedCalendars(from: calendars)

        let startOfDay = calendar.startOfDay(for: selectedDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: filteredCalendars)
        let events = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { TimelineEvent(event: $0, calendar: calendar, for: startOfDay) }
            .sorted { lhs, rhs in
                if lhs.isAllDay == rhs.isAllDay {
                    return lhs.startDate < rhs.startDate
                }

                return lhs.isAllDay && !rhs.isAllDay
            }

        allDayEvents = events.filter(\.isAllDay)
        timedEvents = events.filter { !$0.isAllDay }
        laidOutTimedEvents = PositionedEvent.laidOut(from: timedEvents)
    }

    private func observeCalendarChanges() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchEvents()
            }
        }

        dayChangedObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleClockChange()
            }
        }

        // KVO on the specific defaults key so unrelated toggles don't re-fetch events.
        selectedCalendarsObservation = defaults.observe(
            \.selectedCalendarIDs,
             options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.fetchEvents()
            }
        }
    }

    private func observeClock() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleClockChange()
            }
        }
        handleClockChange()
    }

    private func handleClockChange() {
        now = Date()

        let currentDay = calendar.startOfDay(for: now)
        guard currentDay != lastRenderedDay else {
            return
        }

        let wasShowingToday = calendar.isDate(selectedDate, inSameDayAs: lastRenderedDay)
        lastRenderedDay = currentDay

        if wasShowingToday {
            selectedDate = now
        }

        fetchEvents()
    }

    private func selectedCalendars(from calendars: [EKCalendar]) -> [EKCalendar]? {
        let selectedIDs = Set(storedSelectedCalendarIDs())
        guard !selectedIDs.isEmpty else {
            return nil
        }

        let matches = calendars.filter { selectedIDs.contains($0.calendarIdentifier) }
        return matches.isEmpty ? nil : matches
    }

    private func storedSelectedCalendarIDs() -> [String] {
        guard let data = defaults.data(forKey: CalendarPreferences.selectedCalendarIDsKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }
}

// KVO needs an @objc-exposed property keyed on the same defaults key the rest of the app writes to.
extension UserDefaults {
    @objc dynamic var selectedCalendarIDs: Data? {
        data(forKey: CalendarPreferences.selectedCalendarIDsKey)
    }
}

struct TimelineEvent: Identifiable {
    let id: String
    let eventIdentifier: String
    let title: String
    let location: String?
    let notes: String?
    let url: URL?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let startSeconds: TimeInterval
    let endSeconds: TimeInterval

    init(event: EKEvent, calendar: Calendar, for dayStart: Date) {
        let start = max(event.startDate, dayStart)
        let end = min(
            event.endDate,
            calendar.date(byAdding: .day, value: 1, to: dayStart) ?? event.endDate
        )

        // Combine the event identifier with the occurrence start so recurring events get distinct IDs.
        let baseID = event.eventIdentifier ?? event.calendarItemIdentifier
        eventIdentifier = baseID
        id = "\(baseID)@\(event.startDate.timeIntervalSinceReferenceDate)"
        title = event.title?.isEmpty == false ? event.title : "Untitled"
        location = event.location
        notes = event.notes
        url = event.url
        startDate = start
        endDate = max(end, start)
        isAllDay = event.isAllDay
        startSeconds = max(start.timeIntervalSince(dayStart), 0)
        endSeconds = min(endDate.timeIntervalSince(dayStart), 24 * 60 * 60)
    }

    var durationSeconds: TimeInterval {
        max(endSeconds - startSeconds, 1)
    }

    func timeRangeText(using formatting: TimeFormatting) -> String {
        if isAllDay {
            return "All Day"
        }

        return "\(formatting.time(startDate)) – \(formatting.time(endDate))"
    }

    var meetingURL: URL? {
        if let url, isSupportedMeetingURL(url) {
            return url
        }

        for candidate in [notes, location] {
            if let url = extractMeetingURL(from: candidate) {
                return url
            }
        }

        return nil
    }

    var calendarEventURL: URL? {
        URL(string: "ical://ekevent/\(eventIdentifier)")
    }

    private func extractMeetingURL(from text: String?) -> URL? {
        guard let text, !text.isEmpty else {
            return nil
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            guard let range = Range(match.range, in: text),
                  let url = URL(string: String(text[range])),
                  isSupportedMeetingURL(url) else {
                continue
            }

            return url
        }

        return nil
    }

    private func isSupportedMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else {
            return false
        }

        let supportedHosts = [
            "meet.google.com",
            "zoom.us",
            "teams.microsoft.com",
            "webex.com",
            "gotomeeting.com"
        ]

        return supportedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }
}

struct CalendarSource: Identifiable, Hashable {
    let id: String
    let title: String
    let accountName: String

    init(calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        title = calendar.title
        accountName = calendar.source.title
    }
}

struct PositionedEvent: Identifiable {
    let id: String
    let event: TimelineEvent
    let lane: Int
    let laneCount: Int

    func yOffset(hourHeight: CGFloat, visibleStartSeconds: TimeInterval) -> CGFloat {
        CGFloat(max(event.startSeconds - visibleStartSeconds, 0) / 3600) * hourHeight
    }

    func height(hourHeight: CGFloat, visibleStartSeconds: TimeInterval, visibleEndSeconds: TimeInterval) -> CGFloat {
        let clippedStart = max(event.startSeconds, visibleStartSeconds)
        let clippedEnd = min(event.endSeconds, visibleEndSeconds)
        return CGFloat(max(clippedEnd - clippedStart, 1) / 3600) * hourHeight
    }

    // Single-pass sweep-line layout: assign lanes, group into overlap clusters,
    // then stamp every event in a cluster with the cluster's lane count.
    static func laidOut(from events: [TimelineEvent]) -> [PositionedEvent] {
        let sorted = events.sorted { $0.startDate < $1.startDate }
        var laneEndDates: [Date] = []
        var assignments: [(event: TimelineEvent, lane: Int)] = []
        var clusters: [(range: Range<Int>, laneCount: Int)] = []
        var clusterStart = 0
        var clusterEnd: Date?

        for event in sorted {
            if let end = clusterEnd, event.startDate >= end {
                clusters.append((clusterStart..<assignments.count, laneEndDates.count))
                clusterStart = assignments.count
                laneEndDates.removeAll(keepingCapacity: true)
                clusterEnd = nil
            }

            let lane: Int
            if let index = laneEndDates.firstIndex(where: { $0 <= event.startDate }) {
                lane = index
                laneEndDates[index] = event.endDate
            } else {
                lane = laneEndDates.count
                laneEndDates.append(event.endDate)
            }

            assignments.append((event, lane))
            clusterEnd = max(clusterEnd ?? event.endDate, event.endDate)
        }

        if clusterStart < assignments.count {
            clusters.append((clusterStart..<assignments.count, laneEndDates.count))
        }

        var positioned: [PositionedEvent] = []
        positioned.reserveCapacity(assignments.count)
        for cluster in clusters {
            for index in cluster.range {
                let assignment = assignments[index]
                positioned.append(
                    PositionedEvent(
                        id: assignment.event.id,
                        event: assignment.event,
                        lane: assignment.lane,
                        laneCount: cluster.laneCount
                    )
                )
            }
        }

        return positioned
    }
}
