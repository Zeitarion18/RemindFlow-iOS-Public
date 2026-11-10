import SwiftUI

struct ReminderEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var categoryStore: RFCategoryStore
    private let existing: Reminder?
    private let onSave: (Reminder) async throws -> Void

    @State private var selectedCategoryID: String?
    @State private var priority: RFReminderPriority
    @State private var showCategoryManager = false
    @State private var title: String
    @State private var details: String
    @State private var eventDate: Date
    @State private var repeatMinutes: Int
    @State private var silent: Bool
    @State private var alertMode: ReminderAlertMode
    @State private var recurrence: RFRecurrence
    @State private var selectedWeekdays: Set<Int>
    @State private var autoRepeatCount: Int
    @State private var advanceNoticeMinutes: Set<Int>
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(existing: Reminder? = nil, onSave: @escaping (Reminder) async throws -> Void) {
        self.existing = existing
        self.onSave = onSave
        let now = Date()
        _selectedCategoryID = State(initialValue: existing?.categoryID)
        _priority = State(initialValue: existing?.effectivePriority ?? .normal)
        _title = State(initialValue: existing?.title ?? "")
        _details = State(initialValue: existing?.details ?? "")
        _eventDate = State(initialValue: existing?.eventDate ?? now.addingTimeInterval(3600))
        _repeatMinutes = State(initialValue: existing?.effectiveUnifiedIntervalMinutes ?? 5)
        _silent = State(initialValue: existing?.silent ?? UserDefaults.standard.bool(forKey: "rf.defaultSilent"))
        _alertMode = State(initialValue: existing?.effectiveAlertMode ?? .notification)
        _recurrence = State(initialValue: existing?.effectiveRecurrence ?? .none)
        _selectedWeekdays = State(initialValue: Set(
            existing?.weekdaysForRecurrence ??
            [Calendar.current.component(.weekday, from: existing?.eventDate ?? now.addingTimeInterval(3600))]
        ))
        _autoRepeatCount = State(initialValue: existing.map {
            $0.usesAutoRepeats ? $0.effectiveAutoRepeatCount : 0
        } ?? 0)
        _advanceNoticeMinutes = State(initialValue: Set(
            existing?.effectiveAdvanceNoticeMinutes ?? []
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Что нужно сделать") {
                    TextField("Например: сдать справку", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Описание (необязательно)", text: $details, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section {
                    Picker("Категория", selection: $selectedCategoryID) {
                        Text("Без категории").tag(nil as String?)
                        ForEach(categoryStore.categories) { category in
                            Label(category.name, systemImage: category.iconName)
                                .tag(Optional(category.id))
                        }
                    }
                    Picker("Приоритет", selection: $priority) {
                        ForEach(RFReminderPriority.allCases) { value in
                            Label(value.title, systemImage: value.icon)
                                .tag(value)
                        }
                    }
                    Button {
                        showCategoryManager = true
                    } label: {
                        Label("Настроить категории", systemImage: "square.grid.2x2")
                            .foregroundStyle(RFTheme.accent)
                    }
                    Text("Приоритет влияет на порядок задач и их оформление, но не на частоту или громкость уведомлений.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Категория и важность")
                }
                Section {
                    DatePicker("Событие", selection: $eventDate,
                               displayedComponents: [.date, .hourAndMinute])
                    Text("Событие: \(RFDateFormat.display(eventDate))")
                        .font(.caption)
                        .foregroundStyle(RFTheme.accent)
                    Label("Уведомление придёт в момент события", systemImage: "bell.badge.fill")
                        .font(.subheadline)
                        .foregroundStyle(RFTheme.accent)
                } header: {
                    Text("Дата и время")
                } footer: {
                    Text("Выбери только дату и время события. Предупреждения заранее и повторы можно включить ниже.")
                }
                Section {
                    ForEach(ReminderOptions.advanceNoticeOptions, id: \.self) { minutes in
                        Toggle(isOn: Binding(
                            get: { advanceNoticeMinutes.contains(minutes) },
                            set: { enabled in
                                if enabled { advanceNoticeMinutes.insert(minutes) }
                                else { advanceNoticeMinutes.remove(minutes) }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(ReminderOptions.advanceLabel(minutes))
                                if let planned = ReminderOptions.advanceDate(
                                    minutes: minutes, eventDate: eventDate
                                ) {
                                    Text(planned > Date() ? RFDateFormat.display(planned) : "Время уже прошло")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .tint(RFTheme.accent)
                    }
                } header: {
                    Text("Предварительные этапы")
                } footer: {
                    Text("По умолчанию предварительных этапов нет. Каждый включённый этап придёт отдельно до события; автоповторы начинаются после события.")
                }
                Section {
                    Picker("Повтор события", selection: $recurrence) {
                        ForEach(RFRecurrence.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    if recurrence == .weekly {
                        Text("Дни недели").font(.subheadline)
                        HStack(spacing: 4) {
                            ForEach([2,3,4,5,6,7,1], id: \.self) { day in
                                Button {
                                    if selectedWeekdays.contains(day) {
                                        selectedWeekdays.remove(day)
                                    } else {
                                        selectedWeekdays.insert(day)
                                    }
                                } label: {
                                    Text(["Вс","Пн","Вт","Ср","Чт","Пт","Сб"][day - 1])
                                        .font(.caption.weight(.semibold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .foregroundStyle(selectedWeekdays.contains(day)
                                            ? RFTheme.background : RFTheme.accent)
                                        .background(selectedWeekdays.contains(day)
                                            ? RFTheme.accent : RFTheme.accent.opacity(0.13),
                                            in: RoundedRectangle(cornerRadius: 9))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if recurrence != .none {
                        if let preview = recurrencePreview {
                            Label("Первое событие: \(RFDateFormat.display(preview))",
                                  systemImage: "calendar.badge.clock")
                                .font(.subheadline)
                                .foregroundStyle(RFTheme.accent)
                        }
                        Text("«Выполнено» завершает только текущее событие. Для отключения всей серии есть отдельное действие на карточке.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if recurrence == .monthly || recurrence == .yearly {
                            Text("Если выбранного числа нет в месяце или году (например, 31 февраля или 29 февраля в обычном году), этот период пропускается.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Повторяющиеся события")
                } footer: {
                    Text("Одно расписание события повторяется по календарю. Предварительные этапы и автоповторы планируются на ближайшие события.")
                }
                Section {
                    Picker("Режим", selection: $alertMode) {
                        Text("Уведомление").tag(ReminderAlertMode.notification)
                        if #available(iOS 26.0, *) {
                            Text("Будильник").tag(ReminderAlertMode.alarm)
                        }
                    }.pickerStyle(.segmented)
                    if alertMode == .alarm {
                        Text("Будильник может звучать даже в беззвучном режиме iPhone.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Picker("Интервал напоминаний", selection: $repeatMinutes) {
                        ForEach(ReminderOptions.snoozeMinutes, id: \.self) { minutes in
                            Text(ReminderOptions.intervalLabel(minutes)).tag(minutes)
                        }
                    }
                    Picker("Максимум повторов", selection: $autoRepeatCount) {
                        Text("Без повторов").tag(0)
                        ForEach(1...ReminderOptions.maxAutoRepeats, id: \.self) { count in
                            Text("\(count) \(count == 1 ? "раз" : count < 5 ? "раза" : "раз")").tag(count)
                        }
                    }
                    Text("Основное уведомление придёт в момент события. Если включить автоповторы, они начнутся через выбранный интервал после события. «Отложить» создаст следующий сигнал, не сбрасывая лимит.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if alertMode == .notification { Toggle(isOn: $silent) {
                        Label("Без звука", systemImage: "speaker.slash")
                    }
                    .tint(RFTheme.accent)
                    }
                } header: {
                    Text("Поведение уведомления")
                } footer: {
                    Text("«Отложить на \(ReminderOptions.intervalLabel(repeatMinutes))» работает на iPhone и Apple Watch. Без автоповторов придёт только сигнал события и выбранные предупреждения заранее.")
                }
            }
            .sheet(isPresented: $showCategoryManager) {
                RFCategoryManagerView()
                    .environmentObject(categoryStore)
            }
            .scrollContentBackground(.hidden)
            .background(RFTheme.background)
            .navigationTitle(existing == nil ? "Новое напоминание" : "Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Создать" : "Сохранить") {
                        Task { await saveReminder() }
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("Не удалось сохранить", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("ОК", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Неизвестная ошибка")
            }
        }
        .tint(RFTheme.accent)
    }

    private var recurrencePreview: Date? {
        guard recurrence != .none else { return nil }
        var probe = Reminder(title: title, details: details,
                             eventDate: eventDate, firstAlertDate: eventDate,
                             nextAlertDate: eventDate, snoozeMinutes: repeatMinutes,
                             silent: silent)
        probe.recurrence = recurrence
        probe.recurrenceWeekdays = Array(selectedWeekdays)
        probe.recurrenceAnchorDate = eventDate
        return probe.firstMatchingOccurrence()
    }

    private func saveReminder() async {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard recurrence != .weekly || !selectedWeekdays.isEmpty else {
            errorMessage = "Выбери хотя бы один день недели."
            return
        }
        if recurrence == .none && eventDate.timeIntervalSinceNow <= 2 {
            errorMessage = "Выбери будущее время события."
            return
        }
        var nextEvent = eventDate
        if recurrence != .none {
            guard let first = recurrencePreview else {
                errorMessage = "Не получилось рассчитать ближайшее событие."
                return
            }
            nextEvent = first
        }
        guard nextEvent.timeIntervalSinceNow > 2 else {
            errorMessage = "Время события должно быть в будущем."
            return
        }
        isSaving = true
        defer { isSaving = false }
        let newReminder = Reminder(
            id: existing?.id ?? UUID(),
            title: normalized,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines),
            eventDate: nextEvent,
            firstAlertDate: nextEvent,
            nextAlertDate: nextEvent,
            snoozeMinutes: repeatMinutes,
            silent: silent,
            completedAt: nil,
            createdAt: existing?.createdAt ?? Date(),
            alertMode: alertMode,
            notifyAtEvent: true,
            autoRepeatEnabled: autoRepeatCount > 0,
            autoRepeatMinutes: repeatMinutes,
            autoRepeatCount: autoRepeatCount,
            unifiedRepeatMinutes: repeatMinutes,
            seriesStartOrdinal: 0,
            advanceNoticeMinutes: ReminderOptions.advanceNoticeOptions.filter {
                advanceNoticeMinutes.contains($0)
            },
            recurrence: recurrence,
            recurrenceWeekdays: recurrence == .weekly ? Array(selectedWeekdays).sorted() : nil,
            recurrenceAnchorDate: recurrence == .none ? nil : nextEvent,
            recurrenceFirstLeadSeconds: recurrence == .none ? nil : 0,
            finishedOccurrenceCount: existing?.finishedOccurrenceCount ?? 0,
            lastOccurrenceCompletedAt: existing?.lastOccurrenceCompletedAt,
            categoryID: selectedCategoryID,
            priority: priority
        )
        do {
            try await onSave(newReminder)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
