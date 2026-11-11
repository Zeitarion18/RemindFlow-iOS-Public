import Foundation
import Combine
import UserNotifications

/// Private on-device audit trail. No network services or analytics.
@MainActor
final class RFHistoryStore: ObservableObject {
    static let shared = RFHistoryStore()

    @Published private(set) var entries: [RFHistoryEntry] = []
    private let storageKey = "rf.history.v023"
    private let deliveryKey = "rf.history.deliveredIDs.v023"
    private let maxEntries = 5_000
    private var deliveredKeys: Set<String> = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([RFHistoryEntry].self, from: data) {
            entries = Array(saved.sorted { $0.date > $1.date }.prefix(maxEntries))
        }
        deliveredKeys = Set(UserDefaults.standard.stringArray(forKey: deliveryKey) ?? [])
    }

    func record(_ kind: RFHistoryKind, reminderID: UUID?,
                title: String, detail: String? = nil) {
        entries.insert(RFHistoryEntry(kind: kind, reminderID: reminderID,
                                     reminderTitle: title, detail: detail), at: 0)
        if entries.count > maxEntries { entries = Array(entries.prefix(maxEntries)) }
        save()
    }

    /// iOS does not expose a complete historic feed of dismissed notifications.
    /// Log foreground presentations and notifications still delivered in the system center.
    func recordDeliveryIfNeeded(requestID: String, reminderID: UUID?,
                                title: String, at date: Date) {
        let key = requestID + "#" + String(Int(date.timeIntervalSince1970))
        guard !deliveredKeys.contains(key) else { return }
        deliveredKeys.insert(key)
        record(.delivered, reminderID: reminderID, title: title)
        UserDefaults.standard.set(Array(deliveredKeys.suffix(maxEntries)), forKey: deliveryKey)
    }

    func scanDeliveredNotifications() async {
        let notifications = await UNUserNotificationCenter.current().deliveredNotifications()
        for notification in notifications {
            guard let raw = notification.request.content.userInfo[NotificationManager.reminderIDKey] as? String,
                  let id = UUID(uuidString: raw) else { continue }
            recordDeliveryIfNeeded(requestID: notification.request.identifier,
                                   reminderID: id,
                                   title: notification.request.content.title,
                                   at: notification.date)
        }
    }

    func importMissing(_ imported: [RFHistoryEntry]) -> Int {
        var ids = Set(entries.map(\.id))
        var added = 0
        for entry in imported where ids.insert(entry.id).inserted {
            entries.append(entry)
            added += 1
        }
        if added > 0 {
            entries = Array(entries.sorted { $0.date > $1.date }.prefix(maxEntries))
            save()
        }
        return added
    }

    func clear() {
        entries = []
        deliveredKeys = []
        UserDefaults.standard.removeObject(forKey: deliveryKey)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
