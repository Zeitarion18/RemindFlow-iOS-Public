import Foundation

@main
struct BackupSmokeTest {
    static func main() throws {
        let event = Date(timeIntervalSince1970: 2_000_000_000)
        let item = Reminder(title: "Сдать проект", details: "До пятницы",
                            eventDate: event, firstAlertDate: event,
                            nextAlertDate: event, snoozeMinutes: 10, silent: false)
        let eventRecord = RFHistoryEntry(kind: .created, reminderID: item.id,
                                         reminderTitle: item.title, date: event)
        let backup = RFBackup(reminders: [item],
                              categories: RFCategoryCatalog.defaults,
                              history: [eventRecord],
                              defaultSilent: true, createdAt: event)
        let bytes = try RFBackupCodec.encode(backup)
        let restored = try RFBackupCodec.decode(bytes)
        assert(restored.formatVersion == 1)
        assert(restored.application == "app.remindflow.personal")
        assert(restored.defaultSilent)
        assert(restored.reminders.count == 1)
        assert(restored.reminders[0].id == item.id)
        assert(restored.categories.count == RFCategoryCatalog.defaults.count)
        assert(restored.history[0].kind == .created)
        assert(restored.history[0].reminderID == item.id)
        do {
            _ = try RFBackupCodec.decode(Data("not JSON".utf8))
            assertionFailure("Must reject invalid JSON")
        } catch RFBackupError.invalidFile {
            // expected
        }
        print("RemindFlow backup codec smoke test passed")
    }
}
