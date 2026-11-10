import Foundation
import UserNotifications

/// Rolling window for advance notices and automatic repeats. The ordinary
/// recurring event itself is registered with an indefinite calendar trigger.
/// AlarmKit's fixed-date mode keeps a rolling window of future alarm occurrences.
@MainActor
enum RecurringScheduler {
    static let windowSize = ReminderOptions.recurringWindowSize

    struct PlannedSignal {
        let slot: Int
        let instance: Reminder
        let kind: String
        let value: Int
        let date: Date
    }

    static func plannedSignals(for reminder: Reminder, now: Date = Date()) -> (
        essentials: [PlannedSignal], extras: [PlannedSignal]
    ) {
        guard reminder.isRecurring else { return ([], []) }
        var occurrences = reminder.upcomingOccurrences(now: now, limit: windowSize)
        // After a user snoozes an alert belonging to an already-started event,
        // preserve that event's active trailing notifications as slot zero.
        let trailing = (reminder.nextAlertDate.map { $0 > now.addingTimeInterval(1) } ?? false)
            || !reminder.autoRepeatPlan(now: now).isEmpty
        if reminder.eventDate < now && trailing {
            occurrences.insert(reminder.eventDate, at: 0)
            occurrences = Array(occurrences.prefix(windowSize))
        }
        var essentials: [PlannedSignal] = []
        var extras: [PlannedSignal] = []
        for (slot, date) in occurrences.enumerated() {
            let instance = reminder.occurrence(on: date)
            for (phase, moment) in instance.alertPlan(now: now) {
                // The event has its own permanent UNCalendarNotificationTrigger,
                // but AlarmKit still needs an explicit fixed alarm for each slot.
                if phase == .early {
                    essentials.append(PlannedSignal(slot: slot, instance: instance,
                                                    kind: "early", value: 0, date: moment))
                }
                if phase == .event {
                    essentials.append(PlannedSignal(slot: slot, instance: instance,
                                                    kind: "event", value: 0, date: moment))
                }
            }
            for (minutes, moment) in instance.advanceNoticePlan(now: now) {
                essentials.append(PlannedSignal(slot: slot, instance: instance,
                                                kind: "advance", value: minutes, date: moment))
            }
            for (index, moment) in instance.autoRepeatPlan(now: now) {
                extras.append(PlannedSignal(slot: slot, instance: instance,
                                            kind: "auto", value: index, date: moment))
            }
        }
        // A separate signal for the same minute only adds confusion. Preserve
        // priority: event > initial > advance > automatic repeated alert.
        let priority: [String: Int] = ["event": 0, "early": 1, "advance": 2, "auto": 3]
        var covered: [Date] = []
        func unique(_ values: [PlannedSignal]) -> [PlannedSignal] {
            var result: [PlannedSignal] = []
            for value in values.sorted(by: {
                if $0.date != $1.date { return $0.date < $1.date }
                return (priority[$0.kind] ?? 9) < (priority[$1.kind] ?? 9)
            }) {
                guard !covered.contains(where: { abs($0.timeIntervalSince(value.date)) < 60 }) else { continue }
                result.append(value)
                covered.append(value.date)
            }
            return result
        }
        let important = unique(essentials)
        let repeating = unique(extras)
        return (important, repeating)
    }

    static func schedule(_ reminder: Reminder) async throws -> String? {
        guard reminder.isRecurring else { return nil }
        let plans = plannedSignals(for: reminder)
        switch reminder.effectiveAlertMode {
        case .notification:
            let status = await NotificationManager.authorizationStatus()
            if status != .authorized && status != .provisional && status != .ephemeral {
                guard try await NotificationManager.requestPermission() else {
                    throw SchedulingError.notificationPermissionDenied
                }
            }
            let pending = await NotificationManager.pendingRequests()
            let otherCount = pending.filter {
                !NotificationManager.isRequest($0.identifier, for: reminder.id)
            }.count
            var slots = max(0, NotificationManager.conservativePendingLimit - otherCount)
            let ruleCount = NotificationManager.recurringEventKeys(reminder).count
            guard slots >= ruleCount + 1 else { throw SchedulingError.tooManyPending }
            try await NotificationManager.scheduleRecurringEvents(reminder)
            slots -= ruleCount
            var scheduled = 0
            var omitted = 0
            // Recurring system event is permanent and doesn't consume an extra
            // scheduled one-off per occurrence.
            for signal in plans.essentials where signal.kind != "event" {
                if slots > 0 {
                    try await NotificationManager.scheduleRecurringSignal(signal)
                    slots -= 1
                    scheduled += 1
                } else { omitted += 1 }
            }
            for signal in plans.extras {
                if slots > 0 {
                    try await NotificationManager.scheduleRecurringSignal(signal)
                    slots -= 1
                    scheduled += 1
                } else { omitted += 1 }
            }
            return omitted > 0 ? "Ограничение iOS: для «\(reminder.title)» \(omitted) дополнительных сигналов пока не помещаются в расписание. Основное повторяющееся событие сохранено." : nil
        case .alarm:
            try await AlarmScheduler.requestPermissionIfNeeded()
            // Fixed alarms for the nearest three cycles. AlarmKit uses a
            // different mechanism from UNUserNotificationCenter.
            for signal in plans.essentials where signal.kind == "event" {
                try await AlarmScheduler.scheduleRecurringSignal(signal)
            }
            for signal in plans.essentials where signal.kind != "event" {
                try await AlarmScheduler.scheduleRecurringSignal(signal)
            }
            for signal in plans.extras {
                try await AlarmScheduler.scheduleRecurringSignal(signal)
            }
            return nil
        }
    }

    static func cancel(_ id: UUID) async {
        NotificationManager.removeRecurringNotifications(for: id)
        await AlarmScheduler.removeRecurring(id)
    }
}
