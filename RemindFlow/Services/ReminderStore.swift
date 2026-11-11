import Foundation
import Combine
import UserNotifications

@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()
    @Published private(set) var reminders: [Reminder] = []
    @Published var lastError: String?
    // Non-fatal capacity information belongs in diagnostics, not an "Error"
    // modal which appears on every launch for recurring reminders.
    @Published private(set) var schedulingNotices: [UUID: String] = [:]
    private let storageKey = "remindflow.reminders.v1"
    private let russianNotificationMigrationKey = "rf.localizedNotifications.ru.v014"
    private let unifiedRepeatMigrationKey = "rf.unifiedRepeat.v016"
    private let eventOnlyMigrationKey = "rf.eventOnly.v022"
    private var recurringRefreshInProgress = false
    private init() { reloadFromDisk() }
    func reloadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do { reminders = try JSONDecoder().decode([Reminder].self, from: data) }
        catch { lastError = "Не удалось прочитать задачи: \(error.localizedDescription)" }
    }
    private func persist() {
        do { UserDefaults.standard.set(try JSONEncoder().encode(reminders), forKey: storageKey) }
        catch { lastError = "Ошибка сохранения: \(error.localizedDescription)" }
    }
    private func cancelScheduled(_ id: UUID) async {
        NotificationManager.removeNotifications(for: id)
        await AlarmScheduler.remove(id)
        await RecurringScheduler.cancel(id)
    }
    private func schedule(_ reminder: Reminder) async throws {
        if reminder.isRecurring {
            schedulingNotices[reminder.id] = try await RecurringScheduler.schedule(reminder)
            return
        }
        let plan = reminder.alertPlan()
        let repeats = reminder.autoRepeatPlan()
        let advance = reminder.advanceNoticePlan()
        guard !plan.isEmpty || !repeats.isEmpty || !advance.isEmpty else {
            throw SchedulingError.dateInPast
        }
        switch reminder.effectiveAlertMode {
        case .notification:
            let status = await NotificationManager.authorizationStatus()
            if status != .authorized && status != .provisional && status != .ephemeral {
                guard try await NotificationManager.requestPermission() else {
                    throw SchedulingError.notificationPermissionDenied
                }
            }
            let pending = await NotificationManager.pendingRequests()
            let existingOthers = pending.filter { !NotificationManager.isRequest($0.identifier, for: reminder.id) }
            let roomForCore = NotificationManager.conservativePendingLimit - existingOthers.count
            guard roomForCore >= plan.count + advance.count else {
                throw SchedulingError.tooManyPending
            }
            for (phase,date) in plan.sorted(by: { $0.0 == .event && $1.0 != .event }) {
                try await NotificationManager.schedule(reminder, phase: phase, at: date)
            }
            for (minutes, date) in advance {
                try await NotificationManager.schedule(reminder, advanceMinutes: minutes, at: date)
            }
            let availableExtras = max(0, roomForCore - plan.count - advance.count)
            let repeatPlan = repeats
            for (index,date) in repeatPlan.prefix(availableExtras) {
                try await NotificationManager.schedule(reminder, repeatIndex: index, at: date)
            }
            schedulingNotices[reminder.id] = availableExtras < repeatPlan.count
                ? "Для «\(reminder.title)» не все автоповторы поместились в очередь iOS. Основное событие сохранено."
                : nil
        case .alarm:
            try await AlarmScheduler.requestPermissionIfNeeded()
            for (phase,date) in plan.sorted(by: { $0.0 == .event && $1.0 != .event }) {
                try await AlarmScheduler.schedule(reminder, phase: phase, at: date)
            }
            for (minutes, date) in advance {
                try await AlarmScheduler.schedule(reminder, advanceMinutes: minutes, at: date)
            }
            for (index,date) in repeats {
                try await AlarmScheduler.schedule(reminder, repeatIndex: index, at: date)
            }
            schedulingNotices[reminder.id] = nil
        }
    }
    // Diagnose actual system requests, not merely the dates stored in UserDefaults.
    // Existing live requests are left untouched to avoid changing their timing.
    func restoreMissingAlerts() async -> [String] {
        var pending = await NotificationManager.pendingIDs()
        let alarms = AlarmScheduler.activeIDs()
        var report: [String] = []
        for reminder in activeReminders where !reminder.isRecurring {
            for (phase, date) in reminder.alertPlan() {
                let present: Bool
                if reminder.effectiveAlertMode == .notification {
                    present = pending.contains(NotificationManager.requestID(for: reminder.id, phase: phase))
                } else {
                    present = alarms.contains(reminder.alarmID(for: phase))
                }
                guard !present else { continue }
                do {
                    if reminder.effectiveAlertMode == .notification {
                        try await NotificationManager.schedule(reminder, phase: phase, at: date)
                        pending.insert(NotificationManager.requestID(for: reminder.id, phase: phase))
                    } else {
                        try await AlarmScheduler.requestPermissionIfNeeded()
                        try await AlarmScheduler.schedule(reminder, phase: phase, at: date)
                    }
                    report.append("Восстановлено: \(reminder.title) (\(phase == .event ? "событие" : "первое уведомление"))")
                } catch {
                    report.append("Ошибка «\(reminder.title)»: \(error.localizedDescription)")
                }
            }
        }
        var alarmsNow = AlarmScheduler.activeIDs()
        for reminder in activeReminders where !reminder.isRecurring {
            for (minutes, date) in reminder.advanceNoticePlan() {
                let key = NotificationManager.requestID(for: reminder.id, advanceMinutes: minutes)
                let present = reminder.effectiveAlertMode == .notification
                    ? pending.contains(key)
                    : alarmsNow.contains(reminder.alarmID(forAdvanceMinutes: minutes))
                guard !present else { continue }
                do {
                    if reminder.effectiveAlertMode == .notification {
                        guard pending.count < NotificationManager.conservativePendingLimit else {
                            report.append("Недостаточно мест для этапа \(ReminderOptions.advanceLabel(minutes)): \(reminder.title)")
                            continue
                        }
                        try await NotificationManager.schedule(reminder, advanceMinutes: minutes, at: date)
                        pending.insert(key)
                    } else {
                        try await AlarmScheduler.requestPermissionIfNeeded()
                        try await AlarmScheduler.schedule(reminder, advanceMinutes: minutes, at: date)
                        alarmsNow.insert(reminder.alarmID(forAdvanceMinutes: minutes))
                    }
                    report.append("Восстановлено \(ReminderOptions.advanceLabel(minutes).lowercased()): \(reminder.title)")
                } catch {
                    report.append("Ошибка предварительного этапа «\(reminder.title)»: \(error.localizedDescription)")
                }
            }
        }
        for reminder in activeReminders where !reminder.isRecurring {
            for (index,date) in reminder.autoRepeatPlan() {
                let key = NotificationManager.requestID(for: reminder.id, repeatIndex: index)
                let present = reminder.effectiveAlertMode == .notification
                    ? pending.contains(key)
                    : alarmsNow.contains(reminder.alarmID(forRepeatIndex: index))
                guard !present else { continue }
                do {
                    if reminder.effectiveAlertMode == .notification {
                        guard pending.count < NotificationManager.conservativePendingLimit else { continue }
                        try await NotificationManager.schedule(reminder, repeatIndex: index, at: date)
                        pending.insert(key)
                    } else {
                        try await AlarmScheduler.requestPermissionIfNeeded()
                        try await AlarmScheduler.schedule(reminder, repeatIndex: index, at: date)
                        alarmsNow.insert(reminder.alarmID(forRepeatIndex: index))
                    }
                    report.append("Восстановлен автоповтор №\(index): \(reminder.title)")
                } catch {
                    report.append("Ошибка автоповтора «\(reminder.title)»: \(error.localizedDescription)")
                }
            }
        }
        if report.isEmpty { report.append("Отсутствующих будущих оповещений не найдено.") }
        return report
    }
    /// Previously scheduled alerts keep their original English notification text.
    /// Replace only existing future notification requests once after upgrading.
    /// The same identifiers and dates preserve the pending schedule and the action buttons.
    func updateExistingNotificationLanguageIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: russianNotificationMigrationKey) else { return }
        let pending = await NotificationManager.pendingIDs()
        var succeeded = true
        for reminder in activeReminders where reminder.effectiveAlertMode == .notification {
            for (phase, date) in reminder.alertPlan() {
                guard pending.contains(NotificationManager.requestID(for: reminder.id, phase: phase)) else { continue }
                do {
                    try await NotificationManager.schedule(reminder, phase: phase, at: date)
                } catch {
                    succeeded = false
                    lastError = "Не удалось обновить язык уведомления «\(reminder.title)»: \(error.localizedDescription)"
                }
            }
        }
        if succeeded { UserDefaults.standard.set(true, forKey: russianNotificationMigrationKey) }
    }

    func migrateToUnifiedRepeatsIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: unifiedRepeatMigrationKey) else { return }
        var allSucceeded = true
        for old in activeReminders where old.unifiedRepeatMinutes == nil {
            var updated = old
            let interval = old.effectiveUnifiedIntervalMinutes
            updated.unifiedRepeatMinutes = interval
            updated.snoozeMinutes = interval
            updated.autoRepeatMinutes = interval
            updated.seriesStartOrdinal = 0
            let hasFuture = !updated.alertPlan().isEmpty || !updated.autoRepeatPlan().isEmpty
            if hasFuture {
                do {
                    try await save(updated)
                } catch {
                    allSucceeded = false
                    lastError = "Не удалось обновить расписание «\(old.title)»: \(error.localizedDescription)"
                }
            } else if let index = reminders.firstIndex(where: { $0.id == old.id }) {
                reminders[index] = updated
                persist()
            }
        }
        if allSucceeded {
            UserDefaults.standard.set(true, forKey: unifiedRepeatMigrationKey)
        }
    }

    /// Upgrade future 0.2.1 alerts to the event-based schedule exactly once.
    /// Old reminder records remain decodable, and an already-started chain or
    /// explicit snooze retains its next scheduled signal instead of being lost.
    func migrateToEventOnlyIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: eventOnlyMigrationKey) else { return }
        var succeeded = true
        let now = Date()
        for old in activeReminders {
            let snoozed = old.nextAlertDate.map {
                $0 > now.addingTimeInterval(1) &&
                abs($0.timeIntervalSince(old.firstAlertDate)) >= 60
            } ?? false
            // For an overdue event, keep its already-running follow-up chain.
            let preserveInFlight = old.eventDate <= now || snoozed
            let updated = old.alignedToEvent(preserveInFlightFollowUp: preserveInFlight)
            guard updated != old else { continue }
            let hasFuture = !updated.alertPlan(now: now).isEmpty ||
                !updated.autoRepeatPlan(now: now).isEmpty ||
                !updated.advanceNoticePlan(now: now).isEmpty
            if !updated.isRecurring && !hasFuture {
                // Completed/overdue old events should not be rescheduled in the past.
                // Only normalize their metadata; preserve their event date and state.
                if let index = reminders.firstIndex(where: { $0.id == old.id }) {
                    reminders[index] = updated
                    persist()
                }
                await cancelScheduled(old.id)
                continue
            }
            do {
                try await save(updated)
            } catch {
                succeeded = false
                lastError = "Не удалось обновить событие «\(old.title)»: \(error.localizedDescription)"
            }
        }
        if succeeded { UserDefaults.standard.set(true, forKey: eventOnlyMigrationKey) }
    }

    /// Rebuild the rolling buffer while retaining indefinite calendar event rules.
    func replenishRecurringSchedules() async {
        guard !recurringRefreshInProgress else { return }
        recurringRefreshInProgress = true
        defer { recurringRefreshInProgress = false }
        for reminder in activeReminders where reminder.isRecurring {
            await cancelScheduled(reminder.id)
            do { try await schedule(reminder) }
            catch {
                lastError = "Не удалось обновить серию «\(reminder.title)»: \(error.localizedDescription)"
            }
        }
    }

    private func matchingOccurrence(for reminder: Reminder, observed: Date?) -> Date {
        guard reminder.isRecurring, let observed else { return reminder.eventDate }
        var occurrence = reminder.eventDate
        var count = 0
        while let next = reminder.followingEvent(after: occurrence),
              next <= observed.addingTimeInterval(90), count < 5000 {
            occurrence = next
            count += 1
        }
        return occurrence
    }

    func stopRepeating(_ id: UUID) async {
        guard let old = reminders.first(where: { $0.id == id }), old.isRecurring else { return }
        var single = old
        single.recurrence = RFRecurrence.none
        single.recurrenceWeekdays = nil
        single.recurrenceAnchorDate = nil
        single.recurrenceFirstLeadSeconds = nil
        if single.alertPlan().isEmpty && single.autoRepeatPlan().isEmpty &&
           single.advanceNoticePlan().isEmpty {
            await cancelScheduled(id)
            if let index = reminders.firstIndex(where: { $0.id == id }) {
                reminders[index] = single
                reminders[index].completedAt = Date()
                reminders[index].nextAlertDate = nil
                persist()
            }
            return
        }
        do { try await save(single) }
        catch { lastError = "Не удалось отключить серию: \(error.localizedDescription)" }
    }

    func save(_ reminder: Reminder) async throws {
        let old = reminders.first { $0.id == reminder.id }
        if reminder.effectiveAlertMode == .alarm { try await AlarmScheduler.requestPermissionIfNeeded() }
        await cancelScheduled(reminder.id)
        do {
            try await schedule(reminder)
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index] = reminder
            } else { reminders.insert(reminder, at: 0) }
            persist()
        } catch {
            await cancelScheduled(reminder.id)
            if let old { try? await schedule(old) }
            throw error
        }
    }
    func complete(_ id: UUID, eventOccurrence: Date? = nil) async {
        guard let index = reminders.firstIndex(where: { $0.id == id }),
              !reminders[index].isCompleted else { return }
        let old = reminders[index]
        if old.isRecurring {
            let occurrence = matchingOccurrence(for: old, observed: eventOccurrence)
            guard occurrence >= old.eventDate.addingTimeInterval(-90) else { return }
            guard let updated = old.advancedAfterCompletion(of: occurrence) else {
                lastError = "Не удалось вычислить следующую дату повторяющейся задачи."
                return
            }
            do { try await save(updated) }
            catch { lastError = "Не удалось завершить текущее событие: \(error.localizedDescription)" }
            return
        }
        reminders[index].completedAt = Date()
        reminders[index].nextAlertDate = nil
        persist()
        await cancelScheduled(id)
    }

    func snooze(_ id: UUID, eventOccurrence: Date? = nil) async {
        guard let index = reminders.firstIndex(where: { $0.id == id }),
              !reminders[index].isCompleted else { return }
        let old = reminders[index]
        var source = old
        if old.isRecurring {
            let occurrence = matchingOccurrence(for: old, observed: eventOccurrence)
            guard occurrence >= old.eventDate.addingTimeInterval(-90) else { return }
            source = old.occurrence(on: occurrence)
        }
        do { try await save(source.snoozed(at: Date())) }
        catch { lastError = "Не удалось отложить: \(error.localizedDescription)" }
    }

    /// Removing a category clears only task metadata; existing system notifications are untouched.
    func clearCategoryReferences(categoryID: String) {
        var modified = false
        for index in reminders.indices where reminders[index].categoryID == categoryID {
            reminders[index].categoryID = nil
            modified = true
        }
        if modified { persist() }
    }

    func remove(_ id: UUID) {
        schedulingNotices[id] = nil
        reminders.removeAll { $0.id == id }
        persist()
        NotificationManager.removeNotifications(for: id)
        Task {
            await AlarmScheduler.remove(id)
            await RecurringScheduler.cancel(id)
        }
    }
    func handleAction(_ action: String, reminderID: UUID, eventOccurrence: Date? = nil) async {
        switch action {
        case NotificationManager.doneActionID:
            await complete(reminderID, eventOccurrence: eventOccurrence)
        case NotificationManager.snoozeActionID:
            await snooze(reminderID, eventOccurrence: eventOccurrence)
        default: break
        }
    }
    var activeReminders: [Reminder] {
        reminders.filter { !$0.isCompleted }.sorted {
            min($0.nextAlertDate ?? .distantFuture, $0.eventDate) <
            min($1.nextAlertDate ?? .distantFuture, $1.eventDate)
        }
    }
    var completedReminders: [Reminder] {
        reminders.filter(\.isCompleted).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
}
