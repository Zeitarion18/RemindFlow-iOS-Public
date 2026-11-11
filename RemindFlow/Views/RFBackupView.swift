import SwiftUI
import UniformTypeIdentifiers

struct RFBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else {
            throw RFBackupError.invalidFile
        }
        data = bytes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct RFBackupView: View {
    @EnvironmentObject private var reminders: ReminderStore
    @EnvironmentObject private var categories: RFCategoryStore
    @EnvironmentObject private var history: RFHistoryStore
    @AppStorage("rf.defaultSilent") private var defaultSilent = false

    @State private var exporting = false
    @State private var importing = false
    @State private var exportDocument: RFBackupDocument?
    @State private var pendingImport: RFBackup?
    @State private var confirmImport = false
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        Form {
            Section("Сохранить копию") {
                LabeledContent("Напоминания", value: "\(reminders.reminders.count)")
                LabeledContent("Категории", value: "\(categories.categories.count)")
                LabeledContent("Записи истории", value: "\(history.entries.count)")
                Button {
                    do {
                        let backup = RFBackup(reminders: reminders.reminders,
                                              categories: categories.categories,
                                              history: history.entries,
                                              defaultSilent: defaultSilent)
                        exportDocument = RFBackupDocument(data: try RFBackupCodec.encode(backup))
                        exporting = true
                    } catch { message = error.localizedDescription }
                } label: {
                    Label("Экспортировать в «Файлы»", systemImage: "square.and.arrow.up")
                }
            }
            Section {
                Button {
                    importing = true
                } label: {
                    Label("Импортировать резервную копию", systemImage: "square.and.arrow.down")
                }
                .disabled(busy)
            } header: {
                Text("Восстановление")
            } footer: {
                Text("Безопасный импорт: добавляются только отсутствующие задачи, категории и записи истории. Существующие задачи и настройки не перезаписываются. Для импортированных задач приложение попробует восстановить уведомления.")
            }
            Section("Приватность") {
                Label("Все данные остаются на устройстве", systemImage: "iphone")
                Text("Файл содержит названия и описания задач. Храни резервные копии в защищённом месте.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(RFTheme.background)
        .navigationTitle("Резервная копия")
        .fileExporter(isPresented: $exporting,
                      document: exportDocument,
                      contentType: .json,
                      defaultFilename: "RemindFlow-backup-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
            if case .failure(let error) = result { message = error.localizedDescription }
            exportDocument = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json],
                      allowsMultipleSelection: false) { result in
            Task { @MainActor in
                do {
                    let urls = try result.get()
                    guard let url = urls.first else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    pendingImport = try RFBackupCodec.decode(Data(contentsOf: url))
                    confirmImport = true
                } catch { message = error.localizedDescription }
            }
        }
        .confirmationDialog("Импорт резервной копии",
                            isPresented: $confirmImport,
                            titleVisibility: .visible) {
            Button("Добавить недостающие данные") {
                guard let backup = pendingImport else { return }
                Task { await importBackup(backup) }
            }
            Button("Отмена", role: .cancel) { pendingImport = nil }
        } message: {
            if let backup = pendingImport {
                Text("Файл от \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)). Задач: \(backup.reminders.count), категорий: \(backup.categories.count), записей истории: \(backup.history.count). Текущие записи останутся без изменений.")
            }
        }
        .alert("RemindFlow", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("ОК", role: .cancel) { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    @MainActor
    private func importBackup(_ backup: RFBackup) async {
        guard !busy else { return }
        busy = true
        defer { busy = false; pendingImport = nil }
        let wasEmpty = reminders.reminders.isEmpty
        let newCategories = categories.importMissing(backup.categories)
        let report = await reminders.importMissingReminders(backup.reminders)
        let newHistory = history.importMissing(backup.history)
        if wasEmpty { defaultSilent = backup.defaultSilent }
        var summary = "Добавлено задач: \(report.added), категорий: \(newCategories), записей истории: \(newHistory). Пропущено существующих задач: \(report.skipped)."
        if !report.warnings.isEmpty {
            summary += "\n\nНе удалось запланировать \(report.warnings.count) уведомлений. Проверь экран диагностики:\n" +
                report.warnings.prefix(4).joined(separator: "\n")
        }
        message = summary
    }
}
