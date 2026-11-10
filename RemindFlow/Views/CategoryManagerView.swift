import SwiftUI

private enum RFCategorySheet: Identifiable {
    case create
    case edit(RFCategory)
    var id: String {
        switch self {
        case .create: return "new"
        case .edit(let category): return category.id
        }
    }
    var category: RFCategory? {
        if case .edit(let category) = self { return category }
        return nil
    }
}

struct RFCategoryManagerView: View {
    @EnvironmentObject private var categories: RFCategoryStore
    @EnvironmentObject private var reminders: ReminderStore
    @State private var editing: RFCategorySheet?
    @State private var deleteCandidate: RFCategory?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories.categories) { category in
                        HStack(spacing: 12) {
                            Image(systemName: category.iconName)
                                .font(.title3)
                                .foregroundStyle(RFTheme.categoryColor(category.colorKey))
                                .frame(width: 44, height: 44)
                                .background(RFTheme.categoryColor(category.colorKey).opacity(0.14),
                                            in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name)
                                    .font(.headline)
                                Text(category.isBuiltin ? "Стандартная категория" : "Моя категория")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                editing = .edit(category)
                            } label: {
                                Image(systemName: "pencil")
                                    .foregroundStyle(RFTheme.accent)
                                    .frame(width: 36, height: 36)
                            }
                            .accessibilityLabel("Изменить \(category.name)")
                        }
                        .swipeActions(edge: .trailing) {
                            if !category.isBuiltin {
                                Button(role: .destructive) {
                                    deleteCandidate = category
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Категории")
                } footer: {
                    Text("Можно переименовать и перекрасить любую категорию. Стандартные категории нельзя удалить, а свои — можно.")
                }
                Section {
                    Button {
                        editing = .create
                    } label: {
                        Label("Новая категория", systemImage: "plus.circle.fill")
                            .foregroundStyle(RFTheme.accent)
                    }
                }
                Section {
                    Text("Категории и приоритеты влияют только на оформление, фильтры и сортировку. Время уведомлений не меняется.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFTheme.background)
            .navigationTitle("Категории")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = .create
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { sheet in
                RFCategoryEditorView(existing: sheet.category)
                    .environmentObject(categories)
            }
            .confirmationDialog("Удалить категорию?",
                                isPresented: Binding(
                                    get: { deleteCandidate != nil },
                                    set: { if !$0 { deleteCandidate = nil } }
                                ), titleVisibility: .visible) {
                if let candidate = deleteCandidate {
                    Button("Удалить «\(candidate.name)»", role: .destructive) {
                        do {
                            reminders.clearCategoryReferences(categoryID: candidate.id)
                            try categories.delete(id: candidate.id)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        deleteCandidate = nil
                    }
                }
                Button("Отмена", role: .cancel) { deleteCandidate = nil }
            } message: {
                Text("Задачи останутся на месте. Удалённая категория будет заменена на «Без категории».")
            }
            .alert("Категории RemindFlow", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Понятно", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(RFTheme.accent)
    }
}

private struct RFCategoryEditorView: View {
    @EnvironmentObject private var store: RFCategoryStore
    @Environment(\.dismiss) private var dismiss
    private let existing: RFCategory?
    @State private var name: String
    @State private var colorKey: String
    @State private var iconName: String
    @State private var errorMessage: String?

    init(existing: RFCategory?) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _colorKey = State(initialValue: existing?.colorKey ?? "cyan")
        _iconName = State(initialValue: existing?.iconName ?? "folder.fill")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: iconName)
                            .font(.system(size: 27, weight: .medium))
                            .foregroundStyle(RFTheme.categoryColor(colorKey))
                            .frame(width: 64, height: 64)
                            .background(RFTheme.categoryColor(colorKey).opacity(0.17),
                                        in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? "Новая категория" : name)
                                .font(.headline)
                            Text("Предпросмотр")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("Название категории", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section("Цвет") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                              spacing: 14) {
                        ForEach(RFCategoryCatalog.colors, id: \.self) { color in
                            Button {
                                colorKey = color
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(RFTheme.categoryColor(color))
                                        .frame(width: 43, height: 43)
                                    if colorKey == color {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.heavy))
                                            .foregroundStyle(RFTheme.background)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Цвет \(color)")
                        }
                    }
                    .padding(.vertical, 7)
                }
                Section("Иконка") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                              spacing: 13) {
                        ForEach(RFCategoryCatalog.icons, id: \.self) { icon in
                            Button {
                                iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .foregroundStyle(iconName == icon ? RFTheme.background : RFTheme.accent)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(iconName == icon ? RFTheme.accent : RFTheme.card,
                                                in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Иконка \(icon)")
                        }
                    }
                    .padding(.vertical, 5)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RFTheme.background)
            .navigationTitle(existing == nil ? "Новая категория" : "Изменить категорию")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        do {
                            try store.save(name: name, colorKey: colorKey,
                                           iconName: iconName, editingID: existing?.id)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("Не удалось сохранить", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("ОК", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(RFTheme.accent)
    }
}
