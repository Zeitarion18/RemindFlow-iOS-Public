import Foundation

@main
struct EventOnlySmokeTest {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let event = now.addingTimeInterval(7200)
        var item = Reminder(
            title: "Оплатить подписку",
            details: "Без раннего уведомления",
            eventDate: event,
            firstAlertDate: event,
            nextAlertDate: event,
            snoozeMinutes: 5,
            silent: true
        )
        item.autoRepeatEnabled = false
        item.autoRepeatCount = 0
        item.advanceNoticeMinutes = []
        item.categoryID = "personal"
        item.priority = .high

        // Exactly one initial notification at the chosen event time.
        assert(item.alertPlan(now: now).count == 1)
        assert(item.alertPlan(now: now)[0].0 == .event)
        assert(item.alertPlan(now: now)[0].1 == event)
        assert(item.advanceNoticePlan(now: now).isEmpty)
        assert(item.autoRepeatPlan(now: now).isEmpty)

        // Opt-in auto repeats start AFTER the event, never before or at it.
        var repeating = item
        repeating.autoRepeatEnabled = true
        repeating.autoRepeatCount = 3
        repeating.unifiedRepeatMinutes = 5
        assert(repeating.alertPlan(now: now).count == 1)
        let repeatingPlan = repeating.autoRepeatPlan(now: now)
        assert(repeatingPlan.map(\.0) == [1, 2, 3])
        assert(repeatingPlan.map(\.1) == [
            event.addingTimeInterval(300),
            event.addingTimeInterval(600),
            event.addingTimeInterval(900)
        ])

        // Snooze still schedules a *distinct* follow-up, without resetting quota.
        let snoozed = repeating.snoozed(at: event.addingTimeInterval(60))
        assert(snoozed.alertPlan(now: now).count == 2)
        assert(snoozed.alertPlan(now: now).contains(where: {
            $0.0 == .early && $0.1 == event.addingTimeInterval(360)
        }))
        assert(snoozed.seriesStartOrdinal == 1)
        assert(snoozed.autoRepeatPlan(now: now).map(\.0) == [2, 3])

        // Legacy task with first alert 30 min early migrates to event-only.
        var legacy = item
        legacy.firstAlertDate = event.addingTimeInterval(-1800)
        legacy.nextAlertDate = legacy.firstAlertDate
        legacy.autoRepeatEnabled = true
        legacy.autoRepeatCount = 2
        let migrated = legacy.alignedToEvent()
        assert(migrated.eventDate == event)
        assert(migrated.firstAlertDate == event)
        assert(migrated.nextAlertDate == event)
        assert(migrated.alertPlan(now: now).map(\.0) == [.event])
        assert(migrated.autoRepeatPlan(now: now).map(\.1) == [
            event.addingTimeInterval(300),
            event.addingTimeInterval(600)
        ])
        assert(migrated.categoryID == "personal")
        assert(migrated.priority == .high)
        assert(migrated.title == item.title)

        // An already-snoozed event preserves the scheduled signal and quota.
        var inFlight = legacy
        inFlight.nextAlertDate = event.addingTimeInterval(-900)
        inFlight.seriesStartOrdinal = 1
        let protected = inFlight.alignedToEvent(preserveInFlightFollowUp: true)
        assert(protected.firstAlertDate == event)
        assert(protected.nextAlertDate == inFlight.nextAlertDate)
        assert(protected.seriesStartOrdinal == 1)
        assert(protected.alertPlan(now: now).contains(where: {
            $0.0 == .early && $0.1 == inFlight.nextAlertDate
        }))

        // Keep the permanent event rule for three forecast cycles, but
        // limit long repeat chains to the next two occurrences.
        assert(ReminderOptions.recurringWindowSize == 3)
        assert(ReminderOptions.recurringAutoRepeatWindowSize == 2)

        // Future recurrences use the event clock, not the old first-alert offset.
        var recurring = legacy
        recurring.recurrence = .daily
        recurring.recurrenceAnchorDate = event
        recurring.recurrenceFirstLeadSeconds = -1800
        let normalized = recurring.alignedToEvent()
        assert(normalized.recurrenceFirstLeadSeconds == 0)
        let tomorrow = normalized.followingEvent(after: event)!
        let projected = normalized.occurrence(on: tomorrow)
        assert(projected.firstAlertDate == tomorrow)
        assert(projected.nextAlertDate == tomorrow)
        assert(projected.alertPlan(now: now).map(\.0) == [.event])
        assert(projected.autoRepeatPlan(now: now).first!.1 == tomorrow.addingTimeInterval(300))

        // Existing saved task shape is still readable; changes are round-trippable.
        let originalBytes = try JSONEncoder().encode(legacy)
        let oldDecoded = try JSONDecoder().decode(Reminder.self, from: originalBytes)
        assert(oldDecoded == legacy)
        let newBytes = try JSONEncoder().encode(migrated)
        let newDecoded = try JSONDecoder().decode(Reminder.self, from: newBytes)
        assert(newDecoded == migrated)
        assert(newDecoded.id == legacy.id)
        print("PASS: 0.2.2 event-only schedules, opt-in repeats, snoozes, migration and recurrence")
    }
}
