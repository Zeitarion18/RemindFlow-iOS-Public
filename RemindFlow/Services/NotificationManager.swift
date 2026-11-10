import Foundation
import UserNotifications

enum NotificationManager {
    static let doneActionID = "RF_DONE"
    static let snoozeActionID = "RF_SNOOZE"
    static let reminderIDKey = "reminderID"
    static let silentKey = "silent"
    static let occurrenceTimestampKey = "occurrenceTimestamp"
    // Preserve headroom for base alerts when several tasks have automatic repeats.
    static let conservativePendingLimit = 60

    static func categoryID(for minutes: Int) -> String { "RF_INTERVAL_\(minutes)" }
    static func requestID(for id: UUID) -> String { "rf.reminder.\(id.uuidString)" }
    static func requestID(for id: UUID, phase: ReminderAlertPhase) -> String {
        "rf.reminder.\(id.uuidString).\(phase.rawValue)"
    }
    static func requestID(for id: UUID, repeatIndex: Int) -> String {
        "rf.reminder.\(id.uuidString).auto.\(repeatIndex)"
    }
    static func requestID(for id: UUID, advanceMinutes: Int) -> String {
        "rf.reminder.\(id.uuidString).advance.\(advanceMinutes)"
    }
    static func isRequest(_ requestID: String, for id: UUID) -> Bool {
        requestID.hasPrefix("rf.reminder.\(id.uuidString)")
    }
    static func allRequestIDs(for id: UUID) -> [String] {
        [requestID(for: id), requestID(for: id, phase: .early),
         requestID(for: id, phase: .event)] +
        (1...ReminderOptions.maxAutoRepeats).map { requestID(for: id, repeatIndex: $0) } +
        ReminderOptions.advanceNoticeOptions.map { requestID(for: id, advanceMinutes: $0) }
    }
    static func recurringEventKeys(_ reminder: Reminder) -> [Int] {
        reminder.effectiveRecurrence == .weekly ? reminder.weekdaysForRecurrence : [0]
    }
    static func recurringEventID(for id: UUID, weekday: Int) -> String {
        "rf.reminder.\(id.uuidString).recurring.event.\(weekday)"
    }
    static func recurringSignalID(for id: UUID, slot: Int, kind: String, value: Int) -> String {
        "rf.reminder.\(id.uuidString).recurring.slot.\(slot).\(kind).\(value)"
    }
    static func recurringIDs(for id: UUID) -> [String] {
        var ids = (0...7).map { recurringEventID(for: id, weekday: $0) }
        for slot in 0..<ReminderOptions.recurringWindowSize {
            ids.append(recurringSignalID(for: id, slot: slot, kind: "event", value: 0))
            ids.append(recurringSignalID(for: id, slot: slot, kind: "early", value: 0))
            for n in ReminderOptions.advanceNoticeOptions {
                ids.append(recurringSignalID(for: id, slot: slot, kind: "advance", value: n))
            }
            for n in 1...ReminderOptions.maxAutoRepeats {
                ids.append(recurringSignalID(for: id, slot: slot, kind: "auto", value: n))
            }
        }
        return ids
    }
    static func removeRecurringNotifications(for id: UUID) {
        let ids = recurringIDs(for: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// Indefinite repeating main event; avoids a time-limited queue for ordinary alerts.
    static func scheduleRecurringEvents(_ reminder: Reminder) async throws {
        guard reminder.isRecurring else { return }
        let reference = reminder.recurrenceAnchorDate ?? reminder.eventDate
        let cal = Calendar.current
        let units = cal.dateComponents([.month, .day, .hour, .minute], from: reference)
        for weekday in recurringEventKeys(reminder) {
            var components = DateComponents()
            components.calendar = cal
            components.timeZone = .current
            components.hour = units.hour
            components.minute = units.minute
            components.second = 0
            switch reminder.effectiveRecurrence {
            case .none: continue
            case .daily: break
            case .weekly: components.weekday = weekday
            case .monthly: components.day = units.day
            case .yearly:
                components.month = units.month
                components.day = units.day
            }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.details.isEmpty
                ? "Время повторяющегося события!"
                : "Время события: \(reminder.details)"
            content.categoryIdentifier = categoryID(for: reminder.effectiveUnifiedIntervalMinutes)
            content.userInfo = [reminderIDKey: reminder.id.uuidString, silentKey: reminder.silent]
            if !reminder.silent { content.sound = .default }
            let request = UNNotificationRequest(
                identifier: recurringEventID(for: reminder.id, weekday: weekday),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
            try await UNUserNotificationCenter.current().add(request)
        }
    }
    static func scheduleRecurringSignal(_ signal: RecurringScheduler.PlannedSignal) async throws {
        let reminder = signal.instance
        let label: String
        switch signal.kind {
        case "early": label = "Скоро событие"
        case "advance": label = "Событие скоро — \(ReminderOptions.advanceLabel(signal.value).lowercased())"
        case "auto": label = "Повторное напоминание \(signal.value)/\(reminder.effectiveAutoRepeatCount)"
        default: label = "Время события!"
        }
        try await schedule(reminder,
            identifier: recurringSignalID(for: reminder.id, slot: signal.slot,
                                          kind: signal.kind, value: signal.value),
            prefix: label, at: signal.date, occurrence: reminder.eventDate)
    }
    static func registerCategories() {
        let categories = ReminderOptions.snoozeMinutes.map { minutes in
            UNNotificationCategory(identifier: categoryID(for: minutes),
                actions: [
                    UNNotificationAction(identifier: doneActionID, title: "Выполнено", options: []),
                    UNNotificationAction(identifier: snoozeActionID,
                        title: "Отложить на \(ReminderOptions.intervalLabel(minutes))", options: [])
                ], intentIdentifiers: [], options: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories))
    }
    static func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge])
    }
    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    static func schedule(_ reminder: Reminder, phase: ReminderAlertPhase, at date: Date) async throws {
        let prefix = phase == .event ? "Время события!" : "Скоро событие"
        try await schedule(reminder, identifier: requestID(for: reminder.id, phase: phase),
                           prefix: prefix, at: date)
    }
    static func schedule(_ reminder: Reminder, advanceMinutes: Int, at date: Date) async throws {
        try await schedule(reminder, identifier: requestID(for: reminder.id, advanceMinutes: advanceMinutes),
                           prefix: "Событие скоро — \(ReminderOptions.advanceLabel(advanceMinutes).lowercased())",
                           at: date)
    }
    static func schedule(_ reminder: Reminder, repeatIndex: Int, at date: Date) async throws {
        try await schedule(reminder, identifier: requestID(for: reminder.id, repeatIndex: repeatIndex),
                           prefix: "Повторное напоминание \(repeatIndex)/\(reminder.effectiveAutoRepeatCount)",
                           at: date)
    }
    private static func schedule(_ reminder: Reminder, identifier: String,
                                 prefix: String, at date: Date,
                                 occurrence: Date? = nil) async throws {
        guard !reminder.isCompleted else { return }
        guard date.timeIntervalSinceNow > 1 else { throw SchedulingError.dateInPast }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        let moment = RFDateFormat.display(reminder.eventDate)
        content.body = reminder.details.isEmpty ? "\(prefix) · \(moment)" :
            "\(prefix): \(reminder.details) · \(moment)"
        content.categoryIdentifier = categoryID(for: reminder.effectiveUnifiedIntervalMinutes)
        var data: [String: Any] = [reminderIDKey: reminder.id.uuidString,
                                   silentKey: reminder.silent]
        if let occurrence { data[occurrenceTimestampKey] = occurrence.timeIntervalSince1970 }
        content.userInfo = data
        if !reminder.silent { content.sound = .default }
        let components = Calendar.current.dateComponents(in: .current, from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: identifier, content: content, trigger: trigger))
    }
    static func schedule(_ reminder: Reminder) async throws {
        guard let date = reminder.nextAlertDate else { throw SchedulingError.dateInPast }
        try await schedule(reminder, phase: .early, at: date)
    }
    static func pendingIDs() async -> Set<String> {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return Set(requests.map(\.identifier))
    }
    static func requestNextDate(_ request: UNNotificationRequest) -> Date? {
        if let calendar = request.trigger as? UNCalendarNotificationTrigger { return calendar.nextTriggerDate() }
        if let timer = request.trigger as? UNTimeIntervalNotificationTrigger { return timer.nextTriggerDate() }
        return nil
    }
    static func pendingRequests() async -> [UNNotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests()
    }
    static func removeNotifications(for id: UUID) {
        let ids = allRequestIDs(for: id)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }
}
enum SchedulingError: LocalizedError {
    case dateInPast, alarmRequiresIOS26, alarmPermissionDenied, notificationPermissionDenied, tooManyPending
    var errorDescription: String? {
        switch self {
        case .dateInPast: return "Выбери будущее время уведомления или события."
        case .alarmRequiresIOS26: return "Режим будильника требует iOS 26 или новее."
        case .alarmPermissionDenied: return "Разреши будильники RemindFlow в настройках iOS."
        case .notificationPermissionDenied: return "Разреши уведомления RemindFlow в настройках iOS."
        case .tooManyPending: return "В iOS слишком много ожидающих напоминаний. Выполни ненужные задачи или отключи часть автоповторов."
        }
    }
}
