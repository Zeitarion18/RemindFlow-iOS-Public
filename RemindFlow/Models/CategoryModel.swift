import Foundation

/// Stable category IDs protect saved tasks when the user renames or recolors a category.
struct RFCategory: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var colorKey: String
    var iconName: String
    var isBuiltin: Bool = false
}

enum RFCategoryCatalog {
    static let colors = ["cyan", "blue", "green", "purple", "orange",
                         "pink", "red", "yellow", "mint", "indigo"]
    static let icons = ["folder.fill", "briefcase.fill", "graduationcap.fill",
                        "heart.fill", "heart.text.square.fill", "house.fill",
                        "creditcard.fill", "cart.fill", "gift.fill", "star.fill",
                        "book.fill", "gamecontroller.fill", "airplane",
                        "figure.walk", "pills.fill", "doc.text.fill",
                        "laptopcomputer", "calendar", "music.note", "bell.fill"]
    static let defaults: [RFCategory] = [
        RFCategory(id: "work", name: "Работа", colorKey: "green",
                   iconName: "briefcase.fill", isBuiltin: true),
        RFCategory(id: "study", name: "Учёба", colorKey: "blue",
                   iconName: "graduationcap.fill", isBuiltin: true),
        RFCategory(id: "personal", name: "Личное", colorKey: "purple",
                   iconName: "heart.fill", isBuiltin: true),
        RFCategory(id: "health", name: "Здоровье", colorKey: "orange",
                   iconName: "heart.text.square.fill", isBuiltin: true)
    ]
    static func normalized(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
    static func validColor(_ key: String) -> String {
        colors.contains(key) ? key : "cyan"
    }
    static func validIcon(_ name: String) -> String {
        icons.contains(name) ? name : "folder.fill"
    }
    static func mergedWithDefaults(_ stored: [RFCategory]) -> [RFCategory] {
        // Built-ins can be recolored/renamed but cannot disappear on a later launch.
        var seen = Set<String>()
        var result: [RFCategory] = []
        for category in stored {
            guard !category.id.isEmpty, !seen.contains(category.id) else { continue }
            let name = normalized(category.name)
            guard !name.isEmpty else { continue }
            seen.insert(category.id)
            var sanitized = category
            sanitized.name = name
            sanitized.colorKey = validColor(category.colorKey)
            sanitized.iconName = validIcon(category.iconName)
            result.append(sanitized)
        }
        for builtin in defaults where !seen.contains(builtin.id) {
            result.insert(builtin, at: min(result.count, defaults.count))
        }
        return result
    }
}

enum RFReminderPriority: Int, Codable, CaseIterable, Identifiable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .low: return "Низкий"
        case .normal: return "Обычный"
        case .high: return "Высокий"
        case .critical: return "Критический"
        }
    }
    var icon: String {
        switch self {
        case .low: return "arrow.down"
        case .normal: return "minus"
        case .high: return "arrow.up"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }
}

enum RFTaskSort: String, CaseIterable, Identifiable {
    case date, priority, title
    var id: String { rawValue }
    var title: String {
        switch self {
        case .date: return "По дате"
        case .priority: return "По приоритету"
        case .title: return "По названию"
        }
    }
}

/// Presentation-only ordering/filtering. Never touches notification timestamps.
enum RFTaskPresentation {
    static let uncategorizedID = "__uncategorized__"

    static func filtered(_ reminders: [Reminder], categoryID: String?) -> [Reminder] {
        guard let categoryID else { return reminders }
        if categoryID == uncategorizedID {
            return reminders.filter { $0.categoryID == nil }
        }
        return reminders.filter { $0.categoryID == categoryID }
    }

    static func sorted(_ reminders: [Reminder], by sort: RFTaskSort) -> [Reminder] {
        reminders.sorted { a, b in
            switch sort {
            case .date:
                if a.eventDate != b.eventDate { return a.eventDate < b.eventDate }
            case .priority:
                if a.effectivePriority != b.effectivePriority {
                    return a.effectivePriority.rawValue > b.effectivePriority.rawValue
                }
                if a.eventDate != b.eventDate { return a.eventDate < b.eventDate }
            case .title:
                let nameOrder = a.title.localizedStandardCompare(b.title)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            }
            return a.id.uuidString < b.id.uuidString
        }
    }
}
