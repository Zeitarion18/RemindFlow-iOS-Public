import Foundation

struct RFBackup: Codable {
    let formatVersion: Int
    let application: String
    let createdAt: Date
    let reminders: [Reminder]
    let categories: [RFCategory]
    let history: [RFHistoryEntry]
    let defaultSilent: Bool

    init(reminders: [Reminder], categories: [RFCategory],
         history: [RFHistoryEntry], defaultSilent: Bool, createdAt: Date = Date()) {
        self.formatVersion = 1
        self.application = "app.remindflow.personal"
        self.createdAt = createdAt
        self.reminders = reminders
        self.categories = categories
        self.history = history
        self.defaultSilent = defaultSilent
    }
}

enum RFBackupError: LocalizedError {
    case invalidFile, incompatibleVersion, tooLarge, duplicateIdentifiers

    var errorDescription: String? {
        switch self {
        case .invalidFile: return "Файл не является корректной резервной копией RemindFlow."
        case .incompatibleVersion: return "Эта версия резервной копии пока не поддерживается."
        case .tooLarge: return "Резервная копия слишком большая."
        case .duplicateIdentifiers: return "В резервной копии найдены повторяющиеся идентификаторы."
        }
    }
}

enum RFBackupCodec {
    static func encode(_ backup: RFBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> RFBackup {
        guard !data.isEmpty, data.count <= 15_000_000 else { throw RFBackupError.tooLarge }
        let decoder = JSONDecoder()
        let backup: RFBackup
        do { backup = try decoder.decode(RFBackup.self, from: data) }
        catch { throw RFBackupError.invalidFile }
        guard backup.application == "app.remindflow.personal" else {
            throw RFBackupError.invalidFile
        }
        guard backup.formatVersion == 1 else { throw RFBackupError.incompatibleVersion }
        guard backup.reminders.count <= 25_000,
              backup.categories.count <= 5_000,
              backup.history.count <= 50_000,
              backup.reminders.allSatisfy({
                  !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              }),
              backup.categories.allSatisfy({ !$0.id.isEmpty && !$0.name.isEmpty }) else {
            throw RFBackupError.invalidFile
        }
        guard Set(backup.reminders.map(\.id)).count == backup.reminders.count,
              Set(backup.categories.map(\.id)).count == backup.categories.count,
              Set(backup.history.map(\.id)).count == backup.history.count else {
            throw RFBackupError.duplicateIdentifiers
        }
        return backup
    }
}
