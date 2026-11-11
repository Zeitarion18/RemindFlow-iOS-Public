import Foundation

enum RFHistoryKind: String, Codable, CaseIterable, Identifiable {
    case created, edited, deleted, completed, snoozed, delivered, repeatStopped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .created: return "Создано"
        case .edited: return "Изменено"
        case .deleted: return "Удалено"
        case .completed: return "Выполнено"
        case .snoozed: return "Отложено"
        case .delivered: return "Уведомление получено"
        case .repeatStopped: return "Повторение отключено"
        }
    }

    var symbol: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .edited: return "pencil.circle.fill"
        case .deleted: return "trash.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .snoozed: return "clock.arrow.circlepath"
        case .delivered: return "bell.badge.fill"
        case .repeatStopped: return "repeat.circle.fill"
        }
    }
}

struct RFHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var kind: RFHistoryKind
    var reminderID: UUID?
    var reminderTitle: String
    var date: Date
    var detail: String?

    init(kind: RFHistoryKind, reminderID: UUID?, reminderTitle: String,
         date: Date = Date(), detail: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.reminderID = reminderID
        self.reminderTitle = reminderTitle
        self.date = date
        self.detail = detail
    }
}
