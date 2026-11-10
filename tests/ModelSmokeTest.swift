import Foundation

@main
struct ModelSmokeTest {
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let item = Reminder(
            title: "Сдать справку",
            details: "Кабинет 12",
            eventDate: start.addingTimeInterval(1200),
            firstAlertDate: start,
            nextAlertDate: start,
            snoozeMinutes: 5,
            silent: true
        )
        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([Reminder].self, from: data)
        assert(decoded == [item])
        assert(ReminderOptions.snoozeMinutes.contains(1))
        assert(ReminderOptions.snoozeMinutes.contains(5))
        assert(ReminderOptions.intervalLabel(60) == "1 час")
        assert(!decoded[0].isCompleted)
        // Event must be scheduled even when a legacy record disabled the old toggle.
        let now = start.addingTimeInterval(-60)
        var legacy = item
        legacy.notifyAtEvent = false
        let plan = legacy.alertPlan(now: now)
        assert(plan.count == 2)
        assert(plan.contains(where: { $0.0 == .event && $0.1 == legacy.eventDate }))
        assert(plan.contains(where: { $0.0 == .early && $0.1 == legacy.nextAlertDate }))
        // An additional reminder after the event is still allowed.
        legacy.nextAlertDate = start.addingTimeInterval(1800)
        assert(legacy.alertPlan(now: now).count == 2)
        // When both timestamps coincide, only one event alert should be created.
        legacy.nextAlertDate = legacy.eventDate
        assert(legacy.alertPlan(now: now).count == 1)
        assert(legacy.alertPlan(now: now)[0].0 == .event)
        legacy.completedAt = now
        assert(legacy.alertPlan(now: now).isEmpty)
        // The display must not depend on the device's language or 12-hour clock setting.
        var moscowCalendar = Calendar(identifier: .gregorian)
        moscowCalendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let sample = moscowCalendar.date(from: DateComponents(
            year: 2026, month: 11, day: 4, hour: 11, minute: 0))!
        assert(RFDateFormat.display(sample, timeZone: moscowCalendar.timeZone) == "4 ноября, 11:00")
        assert(RFDateFormat.clock(sample, timeZone: moscowCalendar.timeZone) == "11:00:00")
        // Legacy reminders should never suddenly begin buzzing after an update.
        assert(!decoded[0].usesAutoRepeats)
        assert(decoded[0].autoRepeatPlan(now: now).isEmpty)
        var repeating = item
        repeating.autoRepeatEnabled = true
        repeating.autoRepeatMinutes = 5
        repeating.autoRepeatCount = 10
        let repeats = repeating.autoRepeatPlan(now: now)
        assert(repeats.count == 9) // Auto #4 coincides with the event and is skipped.
        assert(repeats.first!.0 == 1)
        assert(repeats.first!.1 == start.addingTimeInterval(300))
        assert(repeats.last!.0 == 10)
        assert(repeats.last!.1 == start.addingTimeInterval(3000))
        assert(Set(repeats.map { $0.1 }).count == repeats.count)
        // 0.1.5 used separate auto interval and manual snooze interval.
        repeating.snoozeMinutes = 2
        assert(repeating.effectiveUnifiedIntervalMinutes == 5)
        // 0.1.6 uses a single interval and never resets the repeat quota.
        let firstSnooze = repeating.snoozed(at: start.addingTimeInterval(180))
        assert(firstSnooze.nextAlertDate == start.addingTimeInterval(480))
        assert(firstSnooze.seriesStartOrdinal == 1)
        assert(firstSnooze.snoozeMinutes == 5)
        assert(firstSnooze.unifiedRepeatMinutes == 5)
        assert(firstSnooze.autoRepeatPlan(now: now).first!.0 == 2)
        assert(firstSnooze.autoRepeatPlan(now: now).first!.1 == start.addingTimeInterval(780))
        // Ignore two automatic repeats and then snooze: consume previous slots.
        let secondSnooze = firstSnooze.snoozed(at: start.addingTimeInterval(1140))
        assert(secondSnooze.seriesStartOrdinal == 4)
        assert(secondSnooze.nextAlertDate == start.addingTimeInterval(1440))
        assert(secondSnooze.autoRepeatPlan(now: now).first!.0 == 5)
        // At the maximum, an explicit snooze still gives one alert, but no extra auto repeats.
        let late = secondSnooze.snoozed(at: start.addingTimeInterval(100_000))
        assert(late.seriesStartOrdinal == 10)
        assert(late.autoRepeatPlan(now: now).isEmpty)
        assert(late.alertPlan(now: now).contains { $0.0 == .early })
        // Main event remains independent even when the snoozed signal is near it.
        let nearEvent = repeating.snoozed(at: start.addingTimeInterval(900))
        assert(nearEvent.eventDate == repeating.eventDate)
        assert(nearEvent.alertPlan(now: now).contains { $0.0 == .event })
        assert(!nearEvent.alertPlan(now: now).contains { $0.0 == .early })
        assert(repeating.alertPlan(now: now).contains { $0.0 == .event && $0.1 == item.eventDate })
        repeating.completedAt = now
        assert(repeating.autoRepeatPlan(now: now).isEmpty)
        let encoded = try JSONEncoder().encode(repeating)
        let decodedRepeating = try JSONDecoder().decode(Reminder.self, from: encoded)
        assert(decodedRepeating == repeating)
        // 0.1.7: legacy documents never silently acquire advance reminders.
        assert(decoded[0].advanceNoticeMinutes == nil)
        assert(decoded[0].advanceNoticePlan(now: now).isEmpty)
        var staged = item
        staged.advanceNoticeMinutes = [10080, 1440, 60, 15, 15, 999]
        let stages = staged.advanceNoticePlan(now: start.addingTimeInterval(-700_000))
        assert(staged.effectiveAdvanceNoticeMinutes == [10080, 1440, 60, 15])
        assert(stages.count == 4)
        assert(stages[0].1 == start.addingTimeInterval(1200 - 7*86400))
        assert(stages[1].1 == start.addingTimeInterval(1200 - 86400))
        assert(stages[2].1 == start.addingTimeInterval(1200 - 3600))
        assert(stages[3].1 == start.addingTimeInterval(1200 - 900))
        assert(staged.advanceNoticePlan(now: start.addingTimeInterval(-3600)).count == 2)
        // An advance stage coinciding with the first alert is not duplicated.
        staged.nextAlertDate = stages[2].1
        assert(!staged.advanceNoticePlan(now: start.addingTimeInterval(-700_000))
            .contains(where: { $0.0 == 60 }))
        // Prefer the selected advance stage over an automatic repeat when they overlap.
        var overlap = item
        overlap.autoRepeatEnabled = true
        overlap.autoRepeatMinutes = 5
        overlap.autoRepeatCount = 10
        overlap.unifiedRepeatMinutes = 5
        overlap.advanceNoticeMinutes = [15]
        overlap.nextAlertDate = overlap.eventDate.addingTimeInterval(-20*60)
        let overlapStage = overlap.advanceNoticePlan(now: now)
        assert(overlapStage.count == 1)
        assert(!overlap.autoRepeatPlan(now: now)
            .contains(where: { abs($0.1.timeIntervalSince(overlapStage[0].1)) < 60 }))
        // The independent event alert must remain untouched.
        assert(overlap.alertPlan(now: now).contains(where: { $0.0 == .event }))
        // Calendar-day offsets must retain the local clock across DST boundaries.
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let dstEvent = nyCalendar.date(from: DateComponents(
            year: 2026, month: 11, day: 2, hour: 10, minute: 0))!
        let dayBefore = ReminderOptions.advanceDate(minutes: 1440,
            eventDate: dstEvent, calendar: nyCalendar)!
        assert(nyCalendar.component(.hour, from: dayBefore) == 10)
        assert(ReminderOptions.advanceLabel(10080) == "За неделю")
        assert(ReminderOptions.advanceLabel(15) == "За 15 минут")
        let persistedStages = try JSONDecoder().decode(Reminder.self,
            from: JSONEncoder().encode(staged))
        assert(persistedStages == staged)
        let ids = ReminderOptions.advanceNoticeOptions.map {
            staged.alarmID(forAdvanceMinutes: $0)
        }
        assert(Set(ids).count == ids.count)
        assert(!ids.contains(staged.id))
        assert(!ids.contains(staged.alarmID(for: .event)))
        // 0.1.8 recurrence migration and calendar date progression.
        assert(decoded[0].effectiveRecurrence == .none)
        assert(!decoded[0].isRecurring)
        var daily = item
        daily.recurrence = .daily
        daily.recurrenceAnchorDate = item.eventDate
        daily.recurrenceFirstLeadSeconds = -900
        let nextDaily = daily.followingEvent(after: item.eventDate, calendar: moscowCalendar)!
        let firstDaily = daily.firstMatchingOccurrence(now: item.eventDate.addingTimeInterval(-60),
                                                      calendar: moscowCalendar)!
        assert(abs(firstDaily.timeIntervalSince(item.eventDate)) < 60)
        assert(moscowCalendar.dateComponents([.hour, .minute], from: nextDaily).hour == 0 ||
               moscowCalendar.component(.hour, from: nextDaily) ==
               moscowCalendar.component(.hour, from: item.eventDate))
        assert(moscowCalendar.isDate(nextDaily, inSameDayAs:
            moscowCalendar.date(byAdding: .day, value: 1, to: item.eventDate)!))
        let occurrence = daily.occurrence(on: nextDaily)
        assert(occurrence.firstAlertDate == nextDaily.addingTimeInterval(-900))
        assert(occurrence.nextAlertDate == occurrence.firstAlertDate)
        let completedOne = daily.advancedAfterCompletion(of: daily.eventDate,
                                                        at: daily.eventDate, calendar: moscowCalendar)!
        assert(completedOne.eventDate == nextDaily)
        assert(completedOne.finishedOccurrenceCount == 1)
        assert(!completedOne.isCompleted)
        var weekly = daily
        weekly.recurrence = .weekly
        weekly.recurrenceWeekdays = [2,4,6] // Monday, Wednesday, Friday
        let mon = moscowCalendar.date(from: DateComponents(
            year: 2026, month: 11, day: 2, hour: 11, minute: 0))!
        let wed = moscowCalendar.date(from: DateComponents(
            year: 2026, month: 11, day: 4, hour: 11, minute: 0))!
        let fri = moscowCalendar.date(from: DateComponents(
            year: 2026, month: 11, day: 6, hour: 11, minute: 0))!
        weekly.eventDate = mon
        weekly.recurrenceAnchorDate = mon
        assert(weekly.followingEvent(after: mon, calendar: moscowCalendar) == wed)
        assert(weekly.firstMatchingOccurrence(now: mon.addingTimeInterval(60),
                                               calendar: moscowCalendar) == wed)
        assert(weekly.followingEvent(after: wed, calendar: moscowCalendar) == fri)
        var monthly = daily
        monthly.recurrence = .monthly
        let jan31 = moscowCalendar.date(from: DateComponents(
            year: 2027, month: 1, day: 31, hour: 11, minute: 0))!
        let mar31 = moscowCalendar.date(from: DateComponents(
            year: 2027, month: 3, day: 31, hour: 11, minute: 0))!
        monthly.recurrenceAnchorDate = jan31
        assert(monthly.followingEvent(after: jan31, calendar: moscowCalendar) == mar31)
        var yearly = daily
        yearly.recurrence = .yearly
        let leap = moscowCalendar.date(from: DateComponents(
            year: 2028, month: 2, day: 29, hour: 11, minute: 0))!
        yearly.recurrenceAnchorDate = leap
        let nextLeap = moscowCalendar.date(from: DateComponents(
            year: 2032, month: 2, day: 29, hour: 11, minute: 0))!
        assert(yearly.followingEvent(after: leap, calendar: moscowCalendar) == nextLeap)
        daily.eventDate = mon
        daily.recurrenceAnchorDate = mon
        assert(daily.upcomingOccurrences(now: mon, limit: 3, calendar: moscowCalendar).count == 3)
        let roundtrip = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(weekly))
        assert(roundtrip.recurrence == .weekly && roundtrip.recurrenceWeekdays == [2,4,6])
        print("PASS: 0.1.8 recurrence, weekdays, monthly/yearly gaps, migration, schedule and completion")
    }
}
