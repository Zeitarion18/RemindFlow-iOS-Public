import Foundation

/// Russian date and time are intentionally independent of the iPhone's system language.
/// Keep the device's local time zone so notification text matches its scheduled moment.
enum RFDateFormat {
    static func display(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMMM, HH:mm"
        return formatter.string(from: date)
    }

    static func clock(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

enum ReminderOptions {
    static let snoozeMinutes = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120, 180, 1440]
    static let autoRepeatMinutes = [1, 2, 3, 5, 10, 15, 20, 30]
    static let maxAutoRepeats = 10
    static let recurringWindowSize = 3
    /// Times before the event; short offsets use local wall-clock minutes,
    /// days use calendar-day subtraction to preserve the local time through DST.
    static let advanceNoticeOptions = [10080, 4320, 1440, 720, 180, 60, 30, 15]
    static let defaultAdvanceNotices = [10080, 1440, 60, 15]
    static func advanceLabel(_ minutes: Int) -> String {
        switch minutes {
        case 10080: return "За неделю"
        case 4320: return "За 3 дня"
        case 1440: return "За день"
        case 720: return "За 12 часов"
        case 180: return "За 3 часа"
        case 60: return "За час"
        case 30: return "За 30 минут"
        case 15: return "За 15 минут"
        default: return "Заранее"
        }
    }
    static func advanceDate(minutes: Int, eventDate: Date, calendar: Calendar = .current) -> Date? {
        guard advanceNoticeOptions.contains(minutes) else { return nil }
        if minutes >= 1440 && minutes.isMultiple(of: 1440) {
            return calendar.date(byAdding: .day, value: -(minutes / 1440), to: eventDate)
        }
        return calendar.date(byAdding: .minute, value: -minutes, to: eventDate)
    }

    static func intervalLabel(_ minutes: Int) -> String {
        switch minutes {
        case 60: return "1 час"
        case 120: return "2 часа"
        case 180: return "3 часа"
        case 1440: return "1 день"
        default: return "\(minutes) мин"
        }
    }
}

enum RFRecurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "Не повторять"
        case .daily: return "Каждый день"
        case .weekly: return "По дням недели"
        case .monthly: return "Каждый месяц"
        case .yearly: return "Каждый год"
        }
    }
}

enum ReminderAlertMode: String, Codable, CaseIterable, Identifiable {
    case notification, alarm
    var id: String { rawValue }
}
enum ReminderAlertPhase: String { case early, event }

struct Reminder: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var details: String
    var eventDate: Date
    var firstAlertDate: Date
    var nextAlertDate: Date?
    var snoozeMinutes: Int
    var silent: Bool
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    // Optionals preserve decoding of reminders saved by 0.1.0.
    var alertMode: ReminderAlertMode? = nil
    var notifyAtEvent: Bool? = nil
    // Optional persisted properties: reminders created before 0.1.5 decode unchanged.
    var autoRepeatEnabled: Bool? = nil
    var autoRepeatMinutes: Int? = nil
    var autoRepeatCount: Int? = nil
    // 0.1.6: one interval controls both manual snooze and automatic repeats.
    // Optional fields keep older saved reminders readable without migration loss.
    var unifiedRepeatMinutes: Int? = nil
    var seriesStartOrdinal: Int? = nil
    // Optional so reminders from 0.1.6 and earlier decode with no new stages.
    var advanceNoticeMinutes: [Int]? = nil
    // Optional fields are backward-compatible with all reminders saved by 0.1.7.
    var recurrence: RFRecurrence? = nil
    /// Calendar weekday: Sunday=1 ... Saturday=7.
    var recurrenceWeekdays: [Int]? = nil
    /// Original calendar date so monthly/yearly rules never drift across shorter months.
    var recurrenceAnchorDate: Date? = nil
    /// Legacy first-alert offset. For 0.2.2 and newer events this is zero.
    var recurrenceFirstLeadSeconds: Double? = nil
    var finishedOccurrenceCount: Int? = nil
    var lastOccurrenceCompletedAt: Date? = nil
    // 0.2.1 metadata is optional: older tasks decode unchanged.
    var categoryID: String? = nil
    var priority: RFReminderPriority? = nil
    var effectivePriority: RFReminderPriority { priority ?? .normal }
    var effectiveRecurrence: RFRecurrence { recurrence ?? .none }
    var isRecurring: Bool { effectiveRecurrence != .none }
    var weekdaysForRecurrence: [Int] {
        let valid = Set((recurrenceWeekdays ?? []).filter { (1...7).contains($0) })
        return valid.isEmpty ? [Calendar.current.component(.weekday, from: recurrenceAnchorDate ?? eventDate)] : valid.sorted()
    }
    var originalFirstLeadSeconds: Double {
        recurrenceFirstLeadSeconds ?? firstAlertDate.timeIntervalSince(recurrenceAnchorDate ?? eventDate)
    }

    /// 0.2.2: the event is the single starting point for new notification chains.
    /// Legacy persisted fields stay for old documents and explicit snoozes.
    /// An in-flight snooze can be retained while future recurrences use event time.
    func alignedToEvent(preserveInFlightFollowUp: Bool = false) -> Reminder {
        var copy = self
        copy.firstAlertDate = eventDate
        copy.recurrenceFirstLeadSeconds = isRecurring ? 0 : nil
        if !preserveInFlightFollowUp {
            copy.nextAlertDate = eventDate
            copy.seriesStartOrdinal = 0
        }
        return copy
    }

    /// Repeats are calendar-based, not fixed 24-hour seconds, preserving local wall-clock times.
    /// Months without the selected day and non-leap years for Feb 29 are skipped.
    func followingEvent(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isRecurring else { return nil }
        let source = recurrenceAnchorDate ?? eventDate
        let original = calendar.dateComponents([.month, .day, .hour, .minute], from: source)
        let clockHour = original.hour ?? 9
        let clockMinute = original.minute ?? 0
        func makeDate(year: Int, month: Int, day: Int) -> Date? {
            let components = DateComponents(timeZone: calendar.timeZone, year: year, month: month,
                                            day: day, hour: clockHour, minute: clockMinute)
            guard let result = calendar.date(from: components) else { return nil }
            let check = calendar.dateComponents([.year, .month, .day], from: result)
            return (check.year == year && check.month == month && check.day == day) ? result : nil
        }
        switch effectiveRecurrence {
        case .none: return nil
        case .daily, .weekly:
            // Starting at the next calendar day avoids repeating the same event.
            for offset in 1...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard effectiveRecurrence == .daily || weekdaysForRecurrence.contains(weekday) else { continue }
                let comps = calendar.dateComponents([.year, .month, .day], from: day)
                if let next = makeDate(year: comps.year!, month: comps.month!, day: comps.day!),
                   next > date { return next }
            }
            return nil
        case .monthly:
            guard let monthOrigin = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
                return nil
            }
            for offset in 1...24 {
                guard let base = calendar.date(byAdding: .month, value: offset, to: monthOrigin) else { continue }
                let comps = calendar.dateComponents([.year, .month], from: base)
                if let next = makeDate(year: comps.year!, month: comps.month!, day: original.day!),
                   next > date { return next }
            }
            return nil
        case .yearly:
            let currentYear = calendar.component(.year, from: date)
            for year in (currentYear+1)...(currentYear+8) {
                if let next = makeDate(year: year, month: original.month!, day: original.day!),
                   next > date { return next }
            }
            return nil
        }
    }
    func upcomingOccurrences(now: Date = Date(), limit: Int = 3,
                             calendar: Calendar = .current) -> [Date] {
        guard isRecurring, limit > 0 else { return [] }
        var event = eventDate
        var scanned = 0
        // For daily recurrences this also fast-forwards after a long period without opening the app.
        while event < now.addingTimeInterval(-1), scanned < 5000 {
            guard let next = followingEvent(after: event, calendar: calendar) else { return [] }
            event = next
            scanned += 1
        }
        var result: [Date] = []
        while result.count < limit {
            if event > now.addingTimeInterval(-1) { result.append(event) }
            guard let next = followingEvent(after: event, calendar: calendar) else { break }
            event = next
        }
        return result
    }
    /// The first recurrence is the next matching local calendar time after now.
    /// Used by the editor so a repeating trigger never fires before the series starts.
    func firstMatchingOccurrence(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isRecurring else { return eventDate }
        let clock = calendar.dateComponents([.month, .day, .hour, .minute], from: eventDate)
        let day = clock.day ?? 1
        let month = clock.month ?? 1
        let hour = clock.hour ?? 9
        let minute = clock.minute ?? 0
        func exactDate(year: Int, month: Int, day: Int) -> Date? {
            let c = DateComponents(timeZone: calendar.timeZone, year: year, month: month,
                                   day: day, hour: hour, minute: minute)
            guard let d = calendar.date(from: c) else { return nil }
            let check = calendar.dateComponents([.year, .month, .day], from: d)
            return check.year == year && check.month == month && check.day == day ? d : nil
        }
        switch effectiveRecurrence {
        case .none: return eventDate
        case .daily, .weekly:
            for offset in 0...14 {
                guard let reference = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                if effectiveRecurrence == .weekly &&
                    !weekdaysForRecurrence.contains(calendar.component(.weekday, from: reference)) {
                    continue
                }
                let c = calendar.dateComponents([.year, .month, .day], from: reference)
                if let d = exactDate(year: c.year!, month: c.month!, day: c.day!),
                   d > now.addingTimeInterval(1) { return d }
            }
        case .monthly:
            guard let monthBase = calendar.date(from: calendar.dateComponents([.year, .month],
                                                                               from: now)) else { return nil }
            for offset in 0...24 {
                guard let reference = calendar.date(byAdding: .month, value: offset, to: monthBase) else {
                    continue
                }
                let c = calendar.dateComponents([.year, .month], from: reference)
                if let d = exactDate(year: c.year!, month: c.month!, day: day),
                   d > now.addingTimeInterval(1) { return d }
            }
        case .yearly:
            let year = calendar.component(.year, from: now)
            for y in year...(year+8) {
                if let d = exactDate(year: y, month: month, day: day),
                   d > now.addingTimeInterval(1) { return d }
            }
        }
        return nil
    }

    /// Preview and schedule an instance without changing the persistent series template.
    func occurrence(on date: Date) -> Reminder {
        var copy = self
        if abs(date.timeIntervalSince(eventDate)) < 1 { return copy }
        copy.eventDate = date
        let first = date.addingTimeInterval(originalFirstLeadSeconds)
        copy.firstAlertDate = first
        copy.nextAlertDate = first
        copy.seriesStartOrdinal = 0
        return copy
    }
    /// Completing a recurring occurrence advances only one occurrence, not the series.
    func advancedAfterCompletion(of occurrence: Date, at now: Date = Date(),
                                 calendar: Calendar = .current) -> Reminder? {
        guard isRecurring else { return nil }
        var copy = self
        var selected = max(eventDate, occurrence)
        var iterations = 0
        repeat {
            guard let next = followingEvent(after: selected, calendar: calendar) else { return nil }
            selected = next
            iterations += 1
        } while selected <= now && iterations < 5000
        guard selected > now else { return nil }
        copy.eventDate = selected
        copy.firstAlertDate = selected.addingTimeInterval(originalFirstLeadSeconds)
        copy.nextAlertDate = copy.firstAlertDate
        copy.seriesStartOrdinal = 0
        copy.finishedOccurrenceCount = (finishedOccurrenceCount ?? 0) + 1
        copy.lastOccurrenceCompletedAt = now
        return copy
    }

    var effectiveAdvanceNoticeMinutes: [Int] {
        let chosen = Set(advanceNoticeMinutes ?? [])
        return ReminderOptions.advanceNoticeOptions.filter { chosen.contains($0) }
    }
    /// Single-shot advance alerts; never kick off the repeated alert series.
    func advanceNoticePlan(now: Date = Date(), calendar: Calendar = .current) -> [(Int, Date)] {
        guard !isCompleted else { return [] }
        return effectiveAdvanceNoticeMinutes.compactMap { minutes in
            guard let date = ReminderOptions.advanceDate(minutes: minutes, eventDate: eventDate,
                                                        calendar: calendar),
                  date > now.addingTimeInterval(1) else { return nil }
            // Do not duplicate the main event or an explicit follow-up.
            if abs(date.timeIntervalSince(eventDate)) < 60 { return nil }
            if let nextAlertDate, abs(date.timeIntervalSince(nextAlertDate)) < 60 { return nil }
            return (minutes, date)
        }
    }
    func alarmID(forAdvanceMinutes minutes: Int) -> UUID {
        Self.alarmID(for: id, advanceMinutes: minutes)
    }
    static func alarmID(for id: UUID, advanceMinutes minutes: Int) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0x7E
        bytes.1 ^= UInt8(minutes & 0xFF)
        bytes.2 ^= UInt8((minutes >> 8) & 0xFF)
        return UUID(uuid: bytes)
    }
    var usesAutoRepeats: Bool { (autoRepeatEnabled ?? false) && effectiveAutoRepeatCount > 0 }
    var effectiveUnifiedIntervalMinutes: Int {
        if let minutes = unifiedRepeatMinutes, ReminderOptions.snoozeMinutes.contains(minutes) {
            return minutes
        }
        // 0.1.5 used two intervals; prefer its auto-repeat setting when enabled.
        if autoRepeatEnabled ?? false { return effectiveAutoRepeatMinutes }
        return ReminderOptions.snoozeMinutes.contains(snoozeMinutes) ? snoozeMinutes : 5
    }
    var currentRepeatOrdinal: Int {
        min(effectiveAutoRepeatCount, max(0, seriesStartOrdinal ?? 0))
    }
    /// Number of intervals elapsed since the current chain anchor.
    /// The manually snoozed notification itself consumes a repeat slot.
    func repeatSlotsUsed(asOf date: Date) -> Int {
        guard usesAutoRepeats, let anchor = nextAlertDate else { return 0 }
        let remaining = max(0, effectiveAutoRepeatCount - currentRepeatOrdinal)
        let elapsedSeconds = max(0, date.timeIntervalSince(anchor))
        let period = Double(effectiveUnifiedIntervalMinutes * 60)
        let elapsed = Int(min(Double(remaining), floor(elapsedSeconds / period)))
        return min(effectiveAutoRepeatCount, currentRepeatOrdinal + elapsed)
    }
    func snoozed(at date: Date = Date()) -> Reminder {
        var copy = self
        let interval = effectiveUnifiedIntervalMinutes
        let consumed = repeatSlotsUsed(asOf: date)
        copy.seriesStartOrdinal = usesAutoRepeats
            ? min(effectiveAutoRepeatCount, consumed + 1) : 0
        copy.nextAlertDate = date.addingTimeInterval(TimeInterval(interval * 60))
        copy.snoozeMinutes = interval
        copy.autoRepeatMinutes = interval
        copy.unifiedRepeatMinutes = interval
        return copy
    }
    var effectiveAutoRepeatMinutes: Int {
        let value = autoRepeatMinutes ?? 5
        return ReminderOptions.autoRepeatMinutes.contains(value) ? value : 5
    }
    var effectiveAutoRepeatCount: Int {
        min(ReminderOptions.maxAutoRepeats, max(0, autoRepeatCount ?? 10))
    }
    func alarmID(forRepeatIndex index: Int) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0xC3
        bytes.1 ^= UInt8(clamping: index)
        return UUID(uuid: bytes)
    }
    /// Pre-scheduled local alerts keep working when RemindFlow isn't running.
    /// Skip near-duplicate alerts at the independent event time.
    func autoRepeatPlan(now: Date = Date()) -> [(Int, Date)] {
        guard !isCompleted, usesAutoRepeats, let anchor = nextAlertDate,
              effectiveAutoRepeatCount > 0 else { return [] }
        let interval = TimeInterval(effectiveUnifiedIntervalMinutes * 60)
        let advanceDates = advanceNoticePlan(now: now).map(\.1)
        let firstIndex = currentRepeatOrdinal + 1
        guard firstIndex <= effectiveAutoRepeatCount else { return [] }
        return (firstIndex...effectiveAutoRepeatCount).compactMap { index in
            // The ordinal is a cumulative counter, not an offset from the new anchor.
            let offsetFromAnchor = index - currentRepeatOrdinal
            let date = anchor.addingTimeInterval(TimeInterval(offsetFromAnchor) * interval)
            guard date > now.addingTimeInterval(1),
                  abs(date.timeIntervalSince(eventDate)) >= 60,
                  !advanceDates.contains(where: { abs($0.timeIntervalSince(date)) < 60 })
                else { return nil }
            return (index, date)
        }
    }
    var effectiveAlertMode: ReminderAlertMode { alertMode ?? .notification }
    // Older records can contain notifyAtEvent=false (v0.1.2).
    // Keep the field decodable, but the main event is mandatory from v0.1.3.
    var shouldNotifyAtEvent: Bool { true }
    func alarmID(for phase: ReminderAlertPhase) -> UUID { Self.alarmID(for: id, phase: phase) }
    static func alarmID(for id: UUID, phase: ReminderAlertPhase) -> UUID {
        guard phase == .event else { return id }
        var bytes = id.uuid
        bytes.0 ^= 0xA5; bytes.1 ^= 0x5A
        return UUID(uuid: bytes)
    }
    func alertPlan(now: Date = Date()) -> [(ReminderAlertPhase, Date)] {
        guard !isCompleted else { return [] }
        var plan: [(ReminderAlertPhase, Date)] = []
        if let date = nextAlertDate, date > now.addingTimeInterval(1),
           abs(date.timeIntervalSince(eventDate)) >= 60 {
            plan.append((.early, date))
        }
        if eventDate > now.addingTimeInterval(1) {
            plan.append((.event, eventDate))
        }
        return plan
    }

    var isCompleted: Bool { completedAt != nil }
}
