import Foundation

/// UI-only projections: never changes the persisted reminder or its notification schedule.
struct RFCalendarItem: Identifiable {
    let reminder: Reminder
    let occurrenceDate: Date

    var id: String { "\(reminder.id.uuidString)-\(Int(occurrenceDate.timeIntervalSince1970))" }
    var isCompleted: Bool { reminder.isCompleted }
    var isOverdue: Bool {
        !isCompleted && occurrenceDate == reminder.eventDate && occurrenceDate < Date()
    }
}

/// Dates are calculated with Calendar, not by adding fixed 24-hour intervals.
/// Future occurrences are previews of a recurrence; only the store's current
/// reminder.eventDate is an actionable outstanding occurrence.
enum RFCalendarEngine {
    static func monthStart(for day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: day))
            ?? calendar.startOfDay(for: day)
    }

    /// Exactly six rows give the calendar a stable height when switching months.
    /// The first day of the week follows the device calendar (Russian UI: Monday).
    static func monthGrid(for month: Date, calendar: Calendar = .current) -> [Date] {
        let start = monthStart(for: month, calendar: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -delta, to: start) else {
            return [start]
        }
        return (0..<42).compactMap {
            calendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    static func nextMonth(after month: Date, delta: Int,
                          calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: delta, to: monthStart(for: month, calendar: calendar))
            ?? month
    }

    static func occurrenceDates(for reminder: Reminder, in interval: DateInterval,
                                calendar: Calendar = .current, maxCount: Int = 100) -> [Date] {
        guard maxCount > 0, reminder.eventDate < interval.end else { return [] }
        if !reminder.isRecurring {
            return reminder.eventDate >= interval.start && reminder.eventDate < interval.end
                ? [reminder.eventDate] : []
        }
        var current = reminder.eventDate
        var scans = 0
        // A bounded scan avoids hangs for corrupt or decades-old recurrence data.
        while current < interval.start && scans < 10000 {
            guard let next = reminder.followingEvent(after: current, calendar: calendar),
                  next > current else { return [] }
            current = next
            scans += 1
        }
        var result: [Date] = []
        while current < interval.end && result.count < maxCount {
            if current >= interval.start { result.append(current) }
            guard let next = reminder.followingEvent(after: current, calendar: calendar),
                  next > current else { break }
            current = next
        }
        return result
    }

    static func items(from reminders: [Reminder], in interval: DateInterval,
                      calendar: Calendar = .current,
                      perReminderLimit: Int = 70) -> [RFCalendarItem] {
        var result: [RFCalendarItem] = []
        for reminder in reminders {
            for occurrence in occurrenceDates(for: reminder, in: interval,
                                               calendar: calendar, maxCount: perReminderLimit) {
                result.append(RFCalendarItem(reminder: reminder, occurrenceDate: occurrence))
            }
        }
        return result.sorted {
            if $0.occurrenceDate != $1.occurrenceDate {
                return $0.occurrenceDate < $1.occurrenceDate
            }
            return $0.reminder.title.localizedStandardCompare($1.reminder.title) == .orderedAscending
        }
    }

    static func dayInterval(_ day: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }

    static func items(on day: Date, reminders: [Reminder],
                      calendar: Calendar = .current) -> [RFCalendarItem] {
        items(from: reminders, in: dayInterval(day, calendar: calendar), calendar: calendar)
    }

    static func isOutstanding(_ item: RFCalendarItem) -> Bool {
        !item.reminder.isCompleted &&
        abs(item.occurrenceDate.timeIntervalSince(item.reminder.eventDate)) < 1
    }

    /// Only the currently outstanding occurrence is overdue. Later hypothetical
    /// instances of the same recurring series are never counted as missed tasks.
    static func overdue(from reminders: [Reminder], now: Date = Date()) -> [Reminder] {
        reminders.filter { !$0.isCompleted && $0.eventDate < now }
            .sorted { $0.eventDate < $1.eventDate }
    }
}
