import SwiftUI
import UserNotifications

struct SettingsView: View {
    var showsDoneButton = true
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ReminderStore
    @AppStorage("rf.defaultSilent") private var defaultSilent = false
    @State private var permissionText = "Проверяем..."
    @State private var showCategoryManager = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Уведомления") {
                    LabeledContent("Разрешение iOS", value: permissionText)
                    Button("Запросить разрешение") {
                        Task { await requestPermission() }
                    }
                    Button("Открыть настройки iPhone") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Toggle("Без звука по умолчанию", isOn: $defaultSilent)
                        .tint(RFTheme.accent)
                }
                Section {
                    Button {
                        Task { await createTestReminder() }
                    } label: {
                        Label("Тестовое уведомление через 1 минуту", systemImage: "bell.badge")
                    }
                } header: {
                    Text("Проверка на iPhone и Apple Watch")
                } footer: {
                    Text("Создаст настоящую задачу с откладыванием на 1 минуту. Закрой приложение и заблокируй iPhone, чтобы проверить системное уведомление.")
                }
                if #available(iOS 26.0, *) {
                    Section("Проверка системного будильника") {
                        Button("Проверить системный будильник (1 мин)") {
                            Task { await createAlarmTest() }
                        }
                    }
                }
                Section("Организация задач") {
                    Button {
                        showCategoryManager = true
                    } label: {
                        Label("Мои категории", systemImage: "square.grid.2x2.fill")
                            .foregroundStyle(RFTheme.accent)
                    }
                    Text("Создавай собственные категории, выбирай цвета и иконки. Настройки применяются ко всем связанным задачам.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Данные и история") {
                    NavigationLink {
                        RFHistoryView()
                    } label: {
                        Label("История действий", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        RFBackupView()
                    } label: {
                        Label("Резервная копия", systemImage: "externaldrive.fill.badge.timemachine")
                    }
                }
                Section("Диагностика") {
                    NavigationLink {
                        NotificationDiagnosticsView()
                    } label: {
                        Label("Проверить расписание iOS", systemImage: "stethoscope")
                    }
                }
                Section("О приложении") {
                    LabeledContent("Версия", value: "iOS 0.2.3 · History & Backup")
                    LabeledContent("Хранение", value: "Локально на iPhone")
                    LabeledContent("Подписка", value: "Не требуется")
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFTheme.background)
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsDoneButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCategoryManager) {
                RFCategoryManagerView()
            }
            .task { await updatePermission() }
            .alert("RemindFlow", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("ОК", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
        .tint(RFTheme.accent)
    }

    private func updatePermission() async {
        let status = await NotificationManager.authorizationStatus()
        switch status {
        case .authorized: permissionText = "Разрешено"
        case .provisional: permissionText = "Тихо разрешено"
        case .ephemeral: permissionText = "Временно"
        case .denied: permissionText = "Запрещено"
        case .notDetermined: permissionText = "Не запрошено"
        @unknown default: permissionText = "Неизвестно"
        }
    }

    private func requestPermission() async {
        do {
            let allowed = try await NotificationManager.requestPermission()
            await updatePermission()
            if !allowed {
                message = "Уведомления выключены. Разреши их в настройках iOS."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    @available(iOS 26.0, *)
    private func createAlarmTest() async {
        let date = Date().addingTimeInterval(65)
        let reminder = Reminder(title: "Тест будильника RemindFlow",
            details: "Проверка системного экрана и повтора",
            eventDate: date,
            firstAlertDate: date, nextAlertDate: date,
            snoozeMinutes: 1, silent: false,
            alertMode: .alarm, notifyAtEvent: true)
        do {
            try await store.save(reminder)
            message = "Будильник запланирован примерно через минуту."
        } catch { message = error.localizedDescription }
    }
    private func createTestReminder() async {
        let now = Date()
        let notificationDate = now.addingTimeInterval(60)
        let reminder = Reminder(
            title: "🔔 Проверка RemindFlow",
            details: "Проверь кнопки «Выполнено» и «Отложить на 1 мин»",
            eventDate: notificationDate,
            firstAlertDate: notificationDate,
            nextAlertDate: notificationDate,
            snoozeMinutes: 1,
            silent: defaultSilent,
            autoRepeatEnabled: true,
            autoRepeatMinutes: 1,
            autoRepeatCount: 2,
            unifiedRepeatMinutes: 1,
            seriesStartOrdinal: 0
        )
        do {
            try await store.save(reminder)
            message = "Тест создан. Уведомление запланировано примерно через минуту. Заблокируй iPhone для проверки Apple Watch."
        } catch {
            message = "Не удалось запланировать тест: \(error.localizedDescription)"
        }
    }
}
