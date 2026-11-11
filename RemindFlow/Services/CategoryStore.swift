import Foundation
import Combine

enum RFCategoryError: LocalizedError {
    case emptyName, duplicateName, immutableBuiltin
    var errorDescription: String? {
        switch self {
        case .emptyName: return "Введи название категории."
        case .duplicateName: return "Категория с таким названием уже существует."
        case .immutableBuiltin: return "Стандартную категорию нельзя удалить."
        }
    }
}

/// Stored separately from reminder data so new labels never change alerts.
@MainActor
final class RFCategoryStore: ObservableObject {
    static let shared = RFCategoryStore()
    @Published private(set) var categories: [RFCategory] = RFCategoryCatalog.defaults
    private let key = "remindflow.categories.v021"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([RFCategory].self, from: data) {
            categories = RFCategoryCatalog.mergedWithDefaults(saved)
        }
    }

    func category(for id: String?) -> RFCategory? {
        guard let id else { return nil }
        return categories.first(where: { $0.id == id })
    }

    @discardableResult
    func save(name raw: String, colorKey: String, iconName: String,
              editingID: String? = nil) throws -> RFCategory {
        let name = RFCategoryCatalog.normalized(raw)
        guard !name.isEmpty else { throw RFCategoryError.emptyName }
        guard !categories.contains(where: {
            $0.id != editingID &&
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { throw RFCategoryError.duplicateName }

        let existing = categories.first(where: { $0.id == editingID })
        let category = RFCategory(id: existing?.id ?? UUID().uuidString,
                                  name: name,
                                  colorKey: RFCategoryCatalog.validColor(colorKey),
                                  iconName: RFCategoryCatalog.validIcon(iconName),
                                  isBuiltin: existing?.isBuiltin ?? false)
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        persist()
        return category
    }

    func delete(id: String) throws {
        guard let category = category(for: id) else { return }
        guard !category.isBuiltin else { throw RFCategoryError.immutableBuiltin }
        categories.removeAll(where: { $0.id == id })
        persist()
    }

    /// Only add categories not already present, preserving all local changes.
    @discardableResult
    func importMissing(_ imported: [RFCategory]) -> Int {
        var ids = Set(categories.map(\.id))
        let additions = imported.filter { ids.insert($0.id).inserted }
        guard !additions.isEmpty else { return 0 }
        categories = RFCategoryCatalog.mergedWithDefaults(categories + additions)
        persist()
        return additions.count
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(categories) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
