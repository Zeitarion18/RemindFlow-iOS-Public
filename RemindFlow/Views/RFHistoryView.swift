import SwiftUI

private enum RFHistoryPeriod: String, CaseIterable, Identifiable {
    case today = "Сегодня"
    case week = "7 дней"
    case month = "30 дней"
    case all = "Всё"

    var id: String { rawValue }

    func includes(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let start: Date
        switch self {
        case .today: start = calendar.startOfDay(for: Date())
        case .week: start = calendar.date(byAdding: .day, value: -6,
                                          to: calendar.startOfDay(for: Date())) ?? .distantPast
        case .month: start = calendar.date(byAdding: .day, value: -29,
                                           to: calendar.startOfDay(for: Date())) ?? .distantPast
        case .all: return true
        }
        return date >= start
    }
}

struct RFHistoryView: View {
    @EnvironmentObject private var history: RFHistoryStore
    @State private var period: RFHistoryPeriod = .week
    @State private var selectedKind: RFHistoryKind?
    @State private var confirmClear = false

    private var filtered: [RFHistoryEntry] {
        history.entries.filter {
            period.includes($0.date) && (selectedKind == nil || $0.kind == selectedKind)
        }
    }

    private var dates: [Date] {
        Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.date) }))
            .sorted(by: >)
    }

    var body: some View {
        List {
            Section {
                Picker("Период", selection: $period) {
                    ForEach(RFHistoryPeriod.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                Menu {
                    Button("Все действия") { selectedKind = nil }
                    ForEach(RFHistoryKind.allCases) { kind in
                        Button(kind.title) { selectedKind = kind }
                    }
                } label: {
                    LabeledContent("Тип действия", value: selectedKind?.title ?? "Все действия")
                }
            }
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView("История пока пуста",
                                           systemImage: "clock.arrow.circlepath",
                                           description: Text("Новые действия появятся здесь автоматически."))
                }
            } else {
                ForEach(dates, id: \.self) { day in
                    Section(day.formatted(.dateTime.day().month(.wide).year())) {
                        ForEach(filtered.filter {
                            Calendar.current.isDate($0.date, inSameDayAs: day)
                        }) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.kind.symbol)
                                    .foregroundStyle(item.kind == .completed ? .green : RFTheme.accent)
                                    .font(.title3)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.reminderTitle)
                                        .font(.body.weight(.medium))
                                    Text(item.kind.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Text(item.date.formatted(.dateTime.hour().minute()))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            Section {
                Text("История начинается с версии 0.2.3. iOS не позволяет узнать обо всех уже закрытых уведомлениях, поэтому фиксируются доступные системе события и действия с задачами.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !history.entries.isEmpty {
                    Button("Очистить историю", role: .destructive) { confirmClear = true }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(RFTheme.background)
        .navigationTitle("История")
        .confirmationDialog("Удалить всю историю действий?", isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Удалить историю", role: .destructive) { history.clear() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Напоминания останутся без изменений.")
        }
    }
}
