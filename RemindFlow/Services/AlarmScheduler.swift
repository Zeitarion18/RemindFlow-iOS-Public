import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
import AppIntents
#endif

enum AlarmScheduler {
    static func requestPermissionIfNeeded() async throws {
        guard #available(iOS 26.0, *) else { throw SchedulingError.alarmRequiresIOS26 }
        #if canImport(AlarmKit)
        if AlarmManager.shared.authorizationState != .authorized {
            let state = try await AlarmManager.shared.requestAuthorization()
            guard state == .authorized else { throw SchedulingError.alarmPermissionDenied }
        }
        #endif
    }
    static func schedule(_ reminder: Reminder, phase: ReminderAlertPhase, at date: Date) async throws {
        try await scheduleAlarm(reminder, id: reminder.alarmID(for: phase),
                                label: phase.rawValue, at: date)
    }
    static func schedule(_ reminder: Reminder, advanceMinutes: Int, at date: Date) async throws {
        try await scheduleAlarm(reminder, id: reminder.alarmID(forAdvanceMinutes: advanceMinutes),
                                label: "advance-\(advanceMinutes)", at: date)
    }
    static func schedule(_ reminder: Reminder, repeatIndex: Int, at date: Date) async throws {
        try await scheduleAlarm(reminder, id: reminder.alarmID(forRepeatIndex: repeatIndex),
                                label: "auto-\(repeatIndex)", at: date)
    }
    private static func scheduleAlarm(_ reminder: Reminder, id: UUID, label: String, at date: Date) async throws {
        guard #available(iOS 26.0, *) else { throw SchedulingError.alarmRequiresIOS26 }
        #if canImport(AlarmKit)
        let stop = AlarmButton(text: "Выполнено", textColor: .white,
                               systemImageName: "checkmark.circle")
        let snooze = AlarmButton(text: "Повторить", textColor: .white,
                                 systemImageName: "arrow.clockwise")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: reminder.title), stopButton: stop,
                            secondaryButton: snooze, secondaryButtonBehavior: .countdown)
        let attributes = AlarmAttributes<RFAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: RFAlarmMetadata(title: reminder.title, phase: label),
            tintColor: .cyan)
        let configuration = AlarmManager.AlarmConfiguration<RFAlarmMetadata>(
            countdownDuration: Alarm.CountdownDuration(
                preAlert: nil, postAlert: TimeInterval(reminder.effectiveUnifiedIntervalMinutes * 60)),
            schedule: .fixed(date), attributes: attributes,
            stopIntent: RFCompleteAlarmIntent(reminderID: reminder.id.uuidString,
                                                occurrenceTimestamp: reminder.eventDate.timeIntervalSince1970), sound: .default)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
        #endif
    }
    static func recurringAlarmID(_ id: UUID, slot: Int, kind: String, value: Int) -> UUID {
        var bytes = id.uuid
        bytes.0 ^= 0x91
        bytes.1 ^= UInt8(slot)
        let kindCode: UInt8
        switch kind {
        case "event": kindCode = 1
        case "early": kindCode = 2
        case "advance": kindCode = 3
        default: kindCode = 4
        }
        bytes.2 ^= kindCode
        bytes.3 ^= UInt8(value & 0xFF)
        bytes.4 ^= UInt8((value >> 8) & 0xFF)
        return UUID(uuid: bytes)
    }
    static func scheduleRecurringSignal(_ signal: RecurringScheduler.PlannedSignal) async throws {
        try await scheduleAlarm(signal.instance,
            id: recurringAlarmID(signal.instance.id, slot: signal.slot,
                                 kind: signal.kind, value: signal.value),
            label: "recurring-\(signal.kind)-\(signal.slot)-\(signal.value)",
            at: signal.date)
    }
    static func removeRecurring(_ id: UUID) async {
        guard #available(iOS 26.0, *) else { return }
        #if canImport(AlarmKit)
        let active = activeIDs()
        for slot in 0..<ReminderOptions.recurringWindowSize {
            let indexes: [(String, [Int])] = [
                ("event", [0]), ("early", [0]),
                ("advance", ReminderOptions.advanceNoticeOptions),
                ("auto", Array(1...ReminderOptions.maxAutoRepeats))
            ]
            for (kind, values) in indexes {
                for value in values {
                    let alarm = recurringAlarmID(id, slot: slot, kind: kind, value: value)
                    if active.contains(alarm) {
                        try? await AlarmManager.shared.cancel(id: alarm)
                    }
                }
            }
        }
        #endif
    }
    static func activeIDs() -> Set<UUID> {
        guard #available(iOS 26.0, *) else { return [] }
        #if canImport(AlarmKit)
        return Set(((try? AlarmManager.shared.alarms) ?? []).map(\.id))
        #else
        return []
        #endif
    }
    static func remove(_ id: UUID) async {
        guard #available(iOS 26.0, *) else { return }
        #if canImport(AlarmKit)
        for phase: ReminderAlertPhase in [.early, .event] {
            try? await AlarmManager.shared.cancel(id: Reminder.alarmID(for: id, phase: phase))
        }
        for index in 1...ReminderOptions.maxAutoRepeats {
            var bytes = id.uuid
            bytes.0 ^= 0xC3
            bytes.1 ^= UInt8(index)
            try? await AlarmManager.shared.cancel(id: UUID(uuid: bytes))
        }
        for minutes in ReminderOptions.advanceNoticeOptions {
            try? await AlarmManager.shared.cancel(id: Reminder.alarmID(for: id, advanceMinutes: minutes))
        }
        #endif
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct RFCompleteAlarmIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Выполнить напоминание"
    static var description = IntentDescription("Пометить напоминание выполненным.")
    static var openAppWhenRun: Bool = false
    @Parameter(title: "ID напоминания") var reminderID: String
    @Parameter(title: "Время события") var occurrenceTimestamp: Double
    init(reminderID: String, occurrenceTimestamp: Double) {
        self.reminderID = reminderID
        self.occurrenceTimestamp = occurrenceTimestamp
    }
    init() {
        reminderID = ""
        occurrenceTimestamp = 0
    }
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: reminderID) {
            await ReminderStore.shared.complete(id, eventOccurrence: occurrenceTimestamp > 0
                ? Date(timeIntervalSince1970: occurrenceTimestamp) : nil)
        }
        return .result()
    }
}
#endif
