import Foundation

@main
struct CalendarSmokeTest {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        func make(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 11) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d,
                                               hour: h, minute: 0))!
        }
        let november = make(2026, 11, 4)
        let grid = RFCalendarEngine.monthGrid(for: november, calendar: calendar)
        assert(grid.count == 42)
        assert(calendar.component(.weekday, from: grid[0]) == 2)
        assert(calendar.isDate(grid[0], inSameDayAs: make(2026, 10, 26)))
        assert(calendar.isDate(grid[41], inSameDayAs: make(2026, 12, 6)))
        assert(calendar.component(.month, from: RFCalendarEngine.nextMonth(
            after: november, delta: 1, calendar: calendar)) == 12)
        let jan31 = make(2027, 1, 31)
        let mar31 = make(2027, 3, 31)
        var monthly = Reminder(title: "Подписка", details: "Ежемесячно",
                               eventDate: jan31, firstAlertDate: jan31.addingTimeInterval(-1800),
                               nextAlertDate: jan31.addingTimeInterval(-1800),
                               snoozeMinutes: 5, silent: false)
        monthly.recurrence = .monthly
        monthly.recurrenceAnchorDate = jan31
        monthly.recurrenceFirstLeadSeconds = -1800
        let winterSpring = DateInterval(start: make(2027, 1, 1), end: make(2027, 4, 1))
        let months = RFCalendarEngine.occurrenceDates(for: monthly, in: winterSpring, calendar: calendar)
        assert(months == [jan31, mar31]) // February has no 31st.
        let marchItems = RFCalendarEngine.items(on: mar31, reminders: [monthly], calendar: calendar)
        assert(marchItems.count == 1 && marchItems[0].occurrenceDate == mar31)
        assert(!RFCalendarEngine.isOutstanding(marchItems[0])) // Future projection, not current task.
        let januaryItems = RFCalendarEngine.items(on: jan31, reminders: [monthly], calendar: calendar)
        assert(januaryItems.count == 1 && RFCalendarEngine.isOutstanding(januaryItems[0]))
        // A completed one-time task remains visible on its original calendar day.
        var completed = monthly
        completed.id = UUID()
        completed.recurrence = .none
        completed.eventDate = make(2026, 11, 3)
        completed.completedAt = make(2026, 11, 3, 12)
        assert(RFCalendarEngine.items(on: completed.eventDate, reminders: [completed],
                                      calendar: calendar).first?.isCompleted == true)
        // No phantom overdue alerts for recurrence previews.
        let oldOneShot = Reminder(title: "Старое дело", details: "",
                                 eventDate: make(2026, 11, 2),
                                 firstAlertDate: make(2026, 11, 2),
                                 nextAlertDate: nil, snoozeMinutes: 5, silent: true)
        let due = RFCalendarEngine.overdue(from: [monthly, completed, oldOneShot], now: november)
        assert(due.count == 1 && due[0].id == oldOneShot.id)
        // Selected day never includes occurrences outside the day's local midnight boundaries.
        let day = RFCalendarEngine.dayInterval(november, calendar: calendar)
        assert(day.contains(make(2026, 11, 4, 23)) && !day.contains(make(2026, 11, 5)))
        // DST transition is a 23-hour local calendar day, not 24 hours by UTC.
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let dstStart = newYork.date(from: DateComponents(year: 2026, month: 3, day: 8))!
        let dstInterval = RFCalendarEngine.dayInterval(dstStart, calendar: newYork)
        assert(abs(dstInterval.duration - 23*3600) < 1)
        // Weekly recurrence is projected onto the right dates of the displayed month.
        let monday = make(2026, 11, 2)
        var weekly = monthly
        weekly.id = UUID()
        weekly.eventDate = monday
        weekly.recurrenceAnchorDate = monday
        weekly.recurrence = .weekly
        weekly.recurrenceWeekdays = [2, 4, 6] // Monday, Wednesday, Friday.
        let week = DateInterval(start: monday, end: make(2026, 11, 9))
        let dates = RFCalendarEngine.occurrenceDates(for: weekly, in: week, calendar: calendar)
        assert(dates == [monday, make(2026, 11, 4), make(2026, 11, 6)])
        assert(RFCalendarEngine.items(from: [weekly, oldOneShot], in: week,
                calendar: calendar).count == 4)
        print("PASS: Calendar 0.2.0 month grid, recurrence, 31st, overdue, completion, DST, weekly")
    }
}
