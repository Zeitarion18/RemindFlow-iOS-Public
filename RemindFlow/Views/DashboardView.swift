import SwiftUI

private enum RFHomeScope: String, CaseIterable, Identifiable {
    case today = "Сегодня"
    case tomorrow = "Завтра"
    case week = "Неделя"
    case all = "Все"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var categories: RFCategoryStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showEditor = false
    @State private var editing: Reminder?
    @State private var scope: RFHomeScope = .all
    @State private var categoryFilterID: String? = nil
    @State private var sortOrder: RFTaskSort = .date
    @State private var showCompleted = false
    @State private var showPermissionAlert = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                RFTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        heading
                        hero
                        summaryStrip
                        scopeSelector
                        categorySelector
                        if !overdueReminders.isEmpty {
                            overdueSection
                        }
                        HStack {
                            Text("АКТИВНЫЕ НАПОМИНАНИЯ")
                                .font(.caption.weight(.bold))
                                .tracking(1.5)
                                .foregroundStyle(RFTheme.muted)
                            Spacer()
                            Text("\(visibleReminders.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(RFTheme.accent)
                        }
                        if visibleReminders.isEmpty {
                            RFCard {
                                VStack(alignment: .leading, spacing: 11) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 34)).foregroundStyle(RFTheme.accent)
                                    Text(emptyStateTitle)
                                        .font(.headline)
                                    Text(emptyStateMessage)
                                        .font(.subheadline).foregroundStyle(RFTheme.muted)
                                }
                            }
                        } else {
                            ForEach(visibleReminders) { item in
                                reminderCard(item)
                            }
                        }
                        if !store.completedReminders.isEmpty {
                            DisclosureGroup(isExpanded: $showCompleted) {
                                VStack(spacing: 10) {
                                    ForEach(store.completedReminders) { item in
                                        reminderCard(item)
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                Label("Выполненные (\(store.completedReminders.count))", systemImage: "checkmark.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(RFTheme.muted)
                            }
                            .tint(RFTheme.accent)
                        }
                        Text("RemindFlow · 0.2.1 Categories & Priorities · Без подписок")
                            .font(.caption2)
                            .foregroundStyle(RFTheme.muted.opacity(0.65))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showEditor) {
                ReminderEditor(existing: editing) { reminder in
                    try await store.save(reminder)
                }
            }
            .task {
                await checkPermission()
                // Restores missing event signals for reminders created in earlier versions.
                await store.migrateToUnifiedRepeatsIfNeeded()
                _ = await store.restoreMissingAlerts()
                await store.updateExistingNotificationLanguageIfNeeded()
                await store.replenishRecurringSchedules()
            }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active {
                    Task { await store.replenishRecurringSchedules() }
                }
            }
            .alert("Нужен доступ к уведомлениям", isPresented: $showPermissionAlert) {
                Button("Понятно", role: .cancel) { }
            } message: {
                Text("Открой настройки iOS → RemindFlow → Уведомления и разреши их, иначе напоминания могут не появиться.")
            }
            .alert("Ошибка", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("ОК", role: .cancel) { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "Неизвестная ошибка")
            }
        }
        .tint(RFTheme.accent)
    }

    private var heading: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(RFTheme.accent.opacity(0.13))
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(RFTheme.accent)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text("RemindFlow")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("План на каждый день")
                    .font(.caption)
                    .foregroundStyle(RFTheme.muted)
            }
            Spacer()
        }
    }

    private var emptyStateTitle: String {
        switch scope {
        case .today: return "На сегодня дел нет"
        case .tomorrow: return "На завтра дел нет"
        case .week: return "На этой неделе дел нет"
        case .all: return store.completedReminders.isEmpty
            ? "Пока ничего не запланировано" : "Все текущие задачи выполнены"
        }
    }

    private var emptyStateMessage: String {
        if categoryFilterID != nil {
            return "В этой категории пока нет задач для выбранного периода. Выбери «Все» или другую категорию."
        }
        if scope == .all && store.reminders.isEmpty {
            return "Нажми «Новое напоминание», чтобы добавить первое дело."
        }
        if scope == .all {
            return "Новых задач пока нет. Можно запланировать следующее дело."
        }
        return "Другие запланированные задачи остались на своих датах. Выбери другой период или открой календарь."
    }

    private var overdueReminders: [Reminder] {
        RFTaskPresentation.sorted(
            RFTaskPresentation.filtered(
                RFCalendarEngine.overdue(from: store.activeReminders),
                categoryID: categoryFilterID),
            by: sortOrder)
    }

    private var visibleReminders: [Reminder] {
        RFTaskPresentation.sorted(
            RFTaskPresentation.filtered(scopedReminders, categoryID: categoryFilterID),
            by: sortOrder)
    }

    private var scopedReminders: [Reminder] {
        guard scope != .all else { return store.activeReminders }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start: Date
        let end: Date
        switch scope {
        case .today:
            start = today
            end = cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
        case .tomorrow:
            start = cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86400)
            end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        case .week:
            start = today
            end = cal.date(byAdding: .day, value: 7, to: today) ?? today.addingTimeInterval(7*86400)
        case .all:
            return store.activeReminders
        }
        return store.activeReminders.filter { reminder in
            !RFCalendarEngine.occurrenceDates(for: reminder,
                in: DateInterval(start: start, end: end),
                calendar: cal, maxCount: 1).isEmpty
        }
    }

    private var summaryStrip: some View {
        let todayCount = RFCalendarEngine.items(on: Date(), reminders: store.activeReminders)
            .filter { !$0.isCompleted }.count
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7,
            to: Calendar.current.startOfDay(for: Date())) ?? Date().addingTimeInterval(604800)
        let weekCount = RFCalendarEngine.items(from: store.activeReminders,
            in: DateInterval(start: Calendar.current.startOfDay(for: Date()), end: weekEnd))
            .filter { !$0.isCompleted }.count
        return HStack(spacing: 9) {
            summaryTile(value: todayCount, label: "Сегодня", symbol: "sun.max",
                        selected: scope == .today) { scope = .today }
            summaryTile(value: weekCount, label: "На неделе", symbol: "calendar",
                        selected: scope == .week) { scope = .week }
            summaryTile(value: overdueReminders.count, label: "Просрочено",
                        symbol: "exclamationmark.circle", selected: false) { scope = .all }
        }
    }

    private func summaryTile(value: Int, label: String, symbol: String,
                             selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(label == "Просрочено" && value > 0 ? .orange : RFTheme.accent)
                Text("\(value)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(RFTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(selected ? RFTheme.card.opacity(0.95) : RFTheme.card,
                        in: RoundedRectangle(cornerRadius: 17))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(selected ? RFTheme.accent.opacity(0.7) : Color.white.opacity(0.04),
                            lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var categorySelector: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("КАТЕГОРИИ")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(RFTheme.muted)
                Spacer()
                Menu {
                    Picker("Сортировка", selection: $sortOrder) {
                        ForEach(RFTaskSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RFTheme.accent)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    categoryChip(id: nil, name: "Все", icon: "square.grid.2x2.fill",
                                 color: RFTheme.accent)
                    categoryChip(id: RFTaskPresentation.uncategorizedID,
                                 name: "Без категории", icon: "folder",
                                 color: RFTheme.muted)
                    ForEach(categories.categories) { item in
                        categoryChip(id: item.id, name: item.name, icon: item.iconName,
                                     color: RFTheme.categoryColor(item.colorKey))
                    }
                }
            }
        }
    }

    private func categoryChip(id: String?, name: String, icon: String, color: Color) -> some View {
        let selected = categoryFilterID == id
        return Button {
            categoryFilterID = id
        } label: {
            Label(name, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? RFTheme.background : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(selected ? color : RFTheme.card,
                            in: Capsule())
                .overlay {
                    Capsule().stroke(selected ? Color.clear : color.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var scopeSelector: some View {
        HStack(spacing: 6) {
            ForEach(RFHomeScope.allCases) { choice in
                Button {
                    scope = choice
                } label: {
                    Text(choice.rawValue)
                        .font(.subheadline.weight(scope == choice ? .bold : .medium))
                        .foregroundStyle(scope == choice ? RFTheme.background : RFTheme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(scope == choice ? RFTheme.accent : RFTheme.card,
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.circle.fill")
                Text("ПРОСРОЧЕННЫЕ")
                    .tracking(1)
                Spacer()
                Text("\(overdueReminders.count)")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.orange)
            ForEach(overdueReminders.prefix(3)) { item in
                HStack(alignment: .center, spacing: 11) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Срок: \(RFDateFormat.display(item.eventDate))")
                            .font(.caption2)
                            .foregroundStyle(RFTheme.muted)
                    }
                    Spacer()
                    Button {
                        Task { await store.complete(item.id) }
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RFTheme.background)
                            .padding(11)
                            .background(RFTheme.accent, in: Circle())
                    }
                    .accessibilityLabel("Выполнить \(item.title)")
                }
                .padding(12)
                .background(RFTheme.card, in: RoundedRectangle(cornerRadius: 15))
            }
            if overdueReminders.count > 3 {
                Text("И ещё \(overdueReminders.count - 3) просроченных задач")
                    .font(.caption)
                    .foregroundStyle(RFTheme.muted)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(RFTheme.accent)
                Text("НЕ ЗАБЫТЬ ВАЖНОЕ")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(RFTheme.accent)
                Spacer()
            }
            Text(store.activeReminders.isEmpty ? "Освободи голову.\nМы напомним." : "Всё важное\nпод рукой.")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            Button {
                editing = nil
                showEditor = true
            } label: {
                Label("Новое напоминание", systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(RFTheme.background)
                    .background(RFTheme.accent, in: RoundedRectangle(cornerRadius: 13))
            }
        }
        .padding(20)
        .background(
            LinearGradient(colors: [Color(red: 0.095, green: 0.20, blue: 0.29), RFTheme.card],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 23)
        )
    }

    private func reminderCard(_ item: Reminder) -> some View {
        RFCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "clock.badge")
                        .foregroundStyle(item.isCompleted ? Color.green : RFTheme.accent)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if !item.details.isEmpty {
                            Text(item.details)
                                .font(.subheadline)
                                .foregroundStyle(RFTheme.muted)
                                .lineLimit(3)
                        }
                    }
                    Spacer(minLength: 4)
                    Menu {
                        if !item.isCompleted {
                            Button("Изменить", systemImage: "pencil") {
                                editing = item
                                showEditor = true
                            }
                        }
                        if item.isRecurring && !item.isCompleted {
                            Button("Отключить повторение", systemImage: "repeat.1") {
                                Task { await store.stopRepeating(item.id) }
                            }
                        }
                        Button(item.isRecurring ? "Удалить всю серию" : "Удалить", systemImage: "trash", role: .destructive) {
                            store.remove(item.id)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(RFTheme.muted)
                            .frame(width: 30, height: 26)
                    }
                }
                HStack(spacing: 9) {
                    if let category = categories.category(for: item.categoryID) {
                        Label(category.name, systemImage: category.iconName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(RFTheme.categoryColor(category.colorKey))
                    } else {
                        Label("Без категории", systemImage: "folder")
                            .font(.caption)
                            .foregroundStyle(RFTheme.muted)
                    }
                    Spacer()
                    if item.effectivePriority != .normal {
                        Label(item.effectivePriority.title, systemImage: item.effectivePriority.icon)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(RFTheme.priorityColor(item.effectivePriority))
                    }
                }
                Divider().overlay(.white.opacity(0.08))
                Label("Событие: \(RFDateFormat.display(item.eventDate))", systemImage: "calendar")
                    .font(.caption).foregroundStyle(RFTheme.muted)
                if item.eventDate < Date(), !item.isCompleted {
                    Label("Просрочено", systemImage: "exclamationmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if item.isRecurring {
                    Label("Повторение: \(item.effectiveRecurrence.label)", systemImage: "repeat")
                        .font(.caption).foregroundStyle(RFTheme.accent)
                    if let count = item.finishedOccurrenceCount, count > 0 {
                        Label("Выполнено событий: \(count)", systemImage: "checkmark.circle")
                            .font(.caption).foregroundStyle(RFTheme.muted)
                    }
                }
                if let next = item.nextAlertDate {
                    Label("Следующее: \(RFDateFormat.display(next))", systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(next < Date() ? Color.orange : RFTheme.accent)
                }
                Label(item.effectiveAlertMode == .alarm ? "Системный будильник" : (item.silent ? "Без звука" : "Со звуком"),
                      systemImage: item.effectiveAlertMode == .alarm ? "alarm" : (item.silent ? "speaker.slash" : "speaker.wave.2"))
                    .font(.caption).foregroundStyle(RFTheme.muted)
                if !item.isCompleted && !item.effectiveAdvanceNoticeMinutes.isEmpty {
                    Label("Заранее: " + item.effectiveAdvanceNoticeMinutes
                        .map(ReminderOptions.advanceLabel).joined(separator: " · "),
                        systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(RFTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.isCompleted && item.usesAutoRepeats {
                    Label("Повторы: каждые \(ReminderOptions.intervalLabel(item.effectiveUnifiedIntervalMinutes)) · до \(item.effectiveAutoRepeatCount) раз",
                          systemImage: "repeat")
                        .font(.caption)
                        .foregroundStyle(RFTheme.muted)
                }
                if !item.isCompleted {
                    HStack(spacing: 9) {
                        Button {
                            Task { await store.complete(item.id) }
                        } label: {
                            Label("Выполнено", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RFActionButtonStyle(prominent: true))
                        Button {
                            Task { await store.snooze(item.id) }
                        } label: {
                            Label(ReminderOptions.intervalLabel(item.effectiveUnifiedIntervalMinutes), systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(RFActionButtonStyle(prominent: false))
                    }
                }
            }
        }
    }

    private func checkPermission() async {
        let status = await NotificationManager.authorizationStatus()
        if status == .notDetermined {
            let allowed = (try? await NotificationManager.requestPermission()) ?? false
            if !allowed { showPermissionAlert = true }
        } else if status == .denied {
            showPermissionAlert = true
        }
    }
}

private struct RFActionButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .padding(.vertical, 12)
            .padding(.horizontal, 5)
            .foregroundStyle(prominent ? RFTheme.background : RFTheme.accent)
            .background(prominent ? RFTheme.accent : RFTheme.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
