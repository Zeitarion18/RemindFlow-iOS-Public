import SwiftUI
import UserNotifications
#if canImport(AlarmKit)
import AlarmKit
#endif

/// Real-time snapshot of what iOS actually has scheduled.
/// A successful schedule does not promise that Focus/Notification Settings
/// will show a banner, so show both authorization and queued requests.
struct NotificationDiagnosticsView: View {
    @EnvironmentObject private var store: ReminderStore
    @State private var snapshots: [DiagnosticItem] = []
    @State private var permission = "Проверяем…"
    @State private var alertSetting = "—"
    @State private var alarmPermission = "—"
    @State private var lastCheck = ""
    @State private var busy = false
    @State private var repairText: String?

    struct DiagnosticItem: Identifiable {
        let id: String
        let title: String
        let due: String
        let state: String
        let detail: String
        let isMissing: Bool
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Разрешение уведомлений", value: permission)
                LabeledContent("Баннеры iOS", value: alertSetting)
                LabeledContent("Разрешение будильников", value: alarmPermission)
                if !lastCheck.isEmpty {
                    Text("Проверено: \(lastCheck)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Состояние системы")
            } footer: {
                Text("Режим «Фокусирование», сводка уведомлений и настройки Apple Watch могут влиять на показ. Наличие запроса в системе не гарантирует доставку.")
            }
            Section("Будущие оповещения") {
                if snapshots.isEmpty {
                    Text("Будущих запланированных напоминаний нет.")
                        .foregroundStyle(.secondary)
                }
                ForEach(snapshots) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.title).font(.headline)
                            Spacer()
                            Text(item.state)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.isMissing ? Color.orange : Color.green)
                        }
                        Text(item.due).font(.subheadline)
                        Text(item.detail).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
            Section {
                Button {
                    Task { await refresh() }
                } label: {
                    Label("Обновить проверку", systemImage: "arrow.clockwise")
                }
                Button {
                    Task { await restore() }
                } label: {
                    Label("Восстановить отсутствующие сигналы", systemImage: "wrench.adjustable")
                }
            } footer: {
                Text("Кнопка восстановления добавляет только отсутствующие будущие сигналы, не сдвигая уже запланированные.")
            }
        }
        .navigationTitle("Диагностика")
        .overlay { if busy { ProgressView() } }
        .task { await refresh() }
        .alert("Результат проверки", isPresented: Binding(
            get: { repairText != nil },
            set: { if !$0 { repairText = nil } }
        )) {
            Button("ОК") { repairText = nil }
        } message: {
            Text(repairText ?? "")
        }
    }

    private func refresh() async {
        busy = true
        defer { busy = false }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: permission = "Разрешено"
        case .provisional: permission = "Временное / тихое"
        case .denied: permission = "Запрещено"
        case .notDetermined: permission = "Не запрошено"
        case .ephemeral: permission = "Временное"
        @unknown default: permission = "Неизвестно"
        }
        switch settings.alertSetting {
        case .enabled: alertSetting = "Включены"
        case .disabled: alertSetting = "Выключены"
        @unknown default: alertSetting = "Неизвестно"
        }
        if #available(iOS 26.0, *) {
            #if canImport(AlarmKit)
            switch AlarmManager.shared.authorizationState {
            case .authorized: alarmPermission = "Разрешено"
            case .denied: alarmPermission = "Запрещено"
            case .notDetermined: alarmPermission = "Не запрошено"
            @unknown default: alarmPermission = "Неизвестно"
            }
            #endif
        } else {
            alarmPermission = "Требуется iOS 26"
        }
        let requests = await NotificationManager.pendingRequests()
        let requestsByID = Dictionary(uniqueKeysWithValues: requests.map { ($0.identifier, $0) })
        let alarms = AlarmScheduler.activeIDs()
        var rows: [DiagnosticItem] = []
        for reminder in store.activeReminders where !reminder.isRecurring {
            for (phase, date) in reminder.alertPlan() {
                let isAlarm = reminder.effectiveAlertMode == .alarm
                let key = NotificationManager.requestID(for: reminder.id, phase: phase)
                let request = requestsByID[key]
                let exists = isAlarm ? alarms.contains(reminder.alarmID(for: phase)) : request != nil
                let shown = phase == .event ? "Время события" : "Предварительное уведомление"
                let scheduled: Date? = request.flatMap(NotificationManager.requestNextDate)
                let extra = scheduled.map { "Система: \(RFDateFormat.display($0))" }
                    ?? (isAlarm ? "AlarmKit" : "Отсутствует в pendingNotificationRequests")
                rows.append(DiagnosticItem(id: key, title: reminder.title,
                    due: "\(shown) · \(RFDateFormat.display(date))",
                    state: exists ? "В системе" : "Не найдено", detail: extra,
                    isMissing: !exists))
            }
        }
        for reminder in store.activeReminders where !reminder.isRecurring {
            for (minutes, date) in reminder.advanceNoticePlan() {
                let isAlarm = reminder.effectiveAlertMode == .alarm
                let key = NotificationManager.requestID(for: reminder.id, advanceMinutes: minutes)
                let request = requestsByID[key]
                let exists = isAlarm ? alarms.contains(reminder.alarmID(forAdvanceMinutes: minutes)) : request != nil
                rows.append(DiagnosticItem(id: key, title: reminder.title,
                    due: "\(ReminderOptions.advanceLabel(minutes)) · \(RFDateFormat.display(date))",
                    state: exists ? "В системе" : "Не найдено",
                    detail: isAlarm ? "AlarmKit" : "Предварительное уведомление",
                    isMissing: !exists))
            }
        }
        for reminder in store.activeReminders where !reminder.isRecurring {
            for (index, date) in reminder.autoRepeatPlan() {
                let isAlarm = reminder.effectiveAlertMode == .alarm
                let key = NotificationManager.requestID(for: reminder.id, repeatIndex: index)
                let request = requestsByID[key]
                let exists = isAlarm ? alarms.contains(reminder.alarmID(forRepeatIndex: index)) : request != nil
                rows.append(DiagnosticItem(id: key, title: reminder.title,
                    due: "Автоповтор №\(index) · \(RFDateFormat.display(date))",
                    state: exists ? "В системе" : "Не найдено",
                    detail: isAlarm ? "AlarmKit" : "Локальное уведомление",
                    isMissing: !exists))
            }
        }
        // Recurring events have permanent calendar IDs, while lead-time stages
        // and automatic repeats use distinct slots for the next occurrences.
        for reminder in store.activeReminders where reminder.isRecurring {
            if reminder.effectiveAlertMode == .notification {
                for weekday in NotificationManager.recurringEventKeys(reminder) {
                    let key = NotificationManager.recurringEventID(for: reminder.id,
                                                                   weekday: weekday)
                    let request = requestsByID[key]
                    let exists = request != nil
                    let date = request.flatMap(NotificationManager.requestNextDate)
                    rows.append(DiagnosticItem(id: key, title: reminder.title,
                        due: "Повторяющееся событие · " +
                            (date.map { RFDateFormat.display($0) } ?? "Нет данных о дате"),
                        state: exists ? "В системе" : "Не найдено",
                        detail: "Бессрочное календарное правило iOS",
                        isMissing: !exists))
                }
            }
            let plan = RecurringScheduler.plannedSignals(for: reminder)
            for signal in plan.essentials + plan.extras {
                if signal.kind == "event" && reminder.effectiveAlertMode == .notification {
                    continue
                }
                let key = NotificationManager.recurringSignalID(for: reminder.id,
                    slot: signal.slot, kind: signal.kind, value: signal.value)
                let req = requestsByID[key]
                let isAlarm = reminder.effectiveAlertMode == .alarm
                let exists = isAlarm
                    ? alarms.contains(AlarmScheduler.recurringAlarmID(reminder.id,
                        slot: signal.slot, kind: signal.kind, value: signal.value))
                    : req != nil
                rows.append(DiagnosticItem(id: key, title: reminder.title,
                    due: "\(signal.kind == "advance" ? ReminderOptions.advanceLabel(signal.value) : signal.kind == "auto" ? "Автоповтор" : signal.kind == "event" ? "Событие" : "Первое уведомление") · \(RFDateFormat.display(signal.date))",
                    state: exists ? "В системе" : "Не найдено",
                    detail: isAlarm ? "AlarmKit" : "Будущее локальное уведомление",
                    isMissing: !exists))
            }
        }
        snapshots = rows.sorted { $0.due < $1.due }
        lastCheck = RFDateFormat.clock(Date())
    }

    private func restore() async {
        busy = true
        let results = await store.restoreMissingAlerts()
        busy = false
        repairText = results.joined(separator: "\n")
        await refresh()
    }
}
