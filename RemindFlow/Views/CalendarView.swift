import SwiftUI

/// Month view and daily agenda. Pure calendar projections: no notification
/// scheduling occurs during scrolling or when browsing dates.
struct CalendarView: View {
    @EnvironmentObject private var store: ReminderStore
    @EnvironmentObject private var categories: RFCategoryStore
    @State private var displayedMonth = Date()
    @State private var selectedDay = Date()
    @State private var editingReminder: Reminder?
    @State private var showEditor = false

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    private var allReminders: [Reminder] {
        store.reminders
    }

    private var monthDays: [Date] {
        RFCalendarEngine.monthGrid(for: displayedMonth, calendar: calendar)
    }

    private var monthOccurrences: [RFCalendarItem] {
        guard let start = monthDays.first, let last = monthDays.last,
              let end = calendar.date(byAdding: .day, value: 1, to: last) else {
            return []
        }
        return RFCalendarEngine.items(from: allReminders,
                                      in: DateInterval(start: start, end: end),
                                      calendar: calendar, perReminderLimit: 48)
    }

    private var selectedOccurrences: [RFCalendarItem] {
        monthOccurrences.filter {
            calendar.isDate($0.occurrenceDate, inSameDayAs: selectedDay)
        }
    }

    private var monthHeading: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: displayedMonth).capitalized
    }

    private var selectedDayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = calendar
        formatter.dateFormat = "d MMMM, EEEE"
        return formatter.string(from: selectedDay)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RFTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        intro
                        monthCard
                        agenda
                        Text("Повторяющиеся события отображаются на будущих датах. Нажатие «Выполнено» относится только к текущему событию серии.")
                            .font(.caption)
                            .foregroundStyle(RFTheme.muted)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 15)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Календарь")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editingReminder = nil
                        showEditor = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(RFTheme.accent)
                    }
                    .accessibilityLabel("Новое напоминание")
                }
            }
            .sheet(isPresented: $showEditor) {
                ReminderEditor(existing: editingReminder) { reminder in
                    try await store.save(reminder)
                }
            }
        }
        .tint(RFTheme.accent)
    }

    private var intro: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("МОИ СОБЫТИЯ")
                    .font(.caption.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(RFTheme.accent)
                Text("Планируй без суеты")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button("Сегодня") {
                let today = Date()
                selectedDay = today
                displayedMonth = today
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(RFTheme.accent)
            .padding(.vertical, 9)
            .padding(.horizontal, 13)
            .background(RFTheme.card, in: Capsule())
        }
    }

    private var monthCard: some View {
        RFCard {
            VStack(spacing: 17) {
                HStack {
                    Button {
                        displayedMonth = RFCalendarEngine.nextMonth(
                            after: displayedMonth, delta: -1, calendar: calendar)
                        selectedDay = displayedMonth
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 36, height: 36)
                            .background(RFTheme.background.opacity(0.7), in: Circle())
                    }
                    .accessibilityLabel("Предыдущий месяц")
                    Spacer()
                    Text(monthHeading)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        displayedMonth = RFCalendarEngine.nextMonth(
                            after: displayedMonth, delta: 1, calendar: calendar)
                        selectedDay = displayedMonth
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 36, height: 36)
                            .background(RFTheme.background.opacity(0.7), in: Circle())
                    }
                    .accessibilityLabel("Следующий месяц")
                }
                .foregroundStyle(RFTheme.accent)

                HStack(spacing: 0) {
                    ForEach(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"], id: \.self) { day in
                        Text(day)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(RFTheme.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7),
                          spacing: 9) {
                    ForEach(monthDays, id: \.self) { day in
                        dayCell(day)
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDay)
        let today = calendar.isDateInToday(date)
        let inMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let events = monthOccurrences.filter {
            calendar.isDate($0.occurrenceDate, inSameDayAs: date)
        }
        let overdue = events.contains {
            RFCalendarEngine.isOutstanding($0) && $0.occurrenceDate < Date()
        }
        return Button {
            selectedDay = date
            if !inMonth { displayedMonth = date }
        } label: {
            VStack(spacing: 5) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 14, weight: selected || today ? .bold : .medium))
                    .foregroundStyle(selected ? RFTheme.background :
                        inMonth ? (today ? RFTheme.accent : Color.white) : RFTheme.muted.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 33)
                    .background(selected ? RFTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        if today && !selected {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(RFTheme.accent.opacity(0.65), lineWidth: 1)
                        }
                    }
                HStack(spacing: 3) {
                    ForEach(Array(events.prefix(3))) { event in
                        Circle()
                            .fill(dotColor(for: event))
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(height: 5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(RFDateFormat.display(date)): \(events.count) событий")
    }

    private func dotColor(for item: RFCalendarItem) -> Color {
        if RFCalendarEngine.isOutstanding(item) && item.occurrenceDate < Date() {
            return .orange
        }
        if let category = categories.category(for: item.reminder.categoryID) {
            return RFTheme.categoryColor(category.colorKey)
        }
        return RFTheme.accent
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedDayTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(selectedOccurrences.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(RFTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RFTheme.card, in: Capsule())
            }
            .padding(.horizontal, 5)

            if selectedOccurrences.isEmpty {
                RFCard {
                    HStack(alignment: .center, spacing: 13) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.title2)
                            .foregroundStyle(RFTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("На этот день дел нет")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Выбери другую дату или добавь напоминание.")
                                .font(.caption)
                                .foregroundStyle(RFTheme.muted)
                        }
                    }
                }
            } else {
                ForEach(selectedOccurrences) { item in
                    agendaRow(item)
                }
            }
        }
    }

    private func agendaRow(_ item: RFCalendarItem) -> some View {
        let current = RFCalendarEngine.isOutstanding(item)
        let overdue = current && item.occurrenceDate < Date()
        return RFCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    Text(clock(item.occurrenceDate))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(overdue ? .orange : RFTheme.accent)
                    Rectangle()
                        .fill(overdue ? Color.orange : RFTheme.accent.opacity(0.5))
                        .frame(width: 2, height: 25)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.reminder.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    if !item.reminder.details.isEmpty {
                        Text(item.reminder.details)
                            .font(.caption)
                            .foregroundStyle(RFTheme.muted)
                            .lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        if let category = categories.category(for: item.reminder.categoryID) {
                            Label(category.name, systemImage: category.iconName)
                                .foregroundStyle(RFTheme.categoryColor(category.colorKey))
                        }
                        if item.reminder.effectivePriority != .normal {
                            Label(item.reminder.effectivePriority.title,
                                  systemImage: item.reminder.effectivePriority.icon)
                                .foregroundStyle(RFTheme.priorityColor(item.reminder.effectivePriority))
                        }
                    }
                    .font(.caption2.weight(.semibold))
                    HStack(spacing: 8) {
                        if item.reminder.isRecurring {
                            Label("Повторяется", systemImage: "repeat")
                        }
                        if item.isCompleted {
                            Label("Выполнено", systemImage: "checkmark.circle")
                        } else if overdue {
                            Label("Просрочено", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        } else if current {
                            Label("Текущее", systemImage: "bell")
                        } else {
                            Label("Будущее", systemImage: "clock")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(RFTheme.muted)
                }
                Spacer(minLength: 0)
                if !item.reminder.isCompleted {
                    Button {
                        editingReminder = item.reminder
                        showEditor = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(RFTheme.accent)
                            .padding(7)
                            .background(RFTheme.background, in: Circle())
                    }
                    .accessibilityLabel("Редактировать \(item.reminder.title)")
                }
            }
        }
    }

    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.calendar = calendar
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
