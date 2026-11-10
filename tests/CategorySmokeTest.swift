import Foundation

@main
struct CategorySmokeTest {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let original = Reminder(title: "Купить карту", details: "Apple",
            eventDate: now.addingTimeInterval(3600),
            firstAlertDate: now.addingTimeInterval(3000),
            nextAlertDate: now.addingTimeInterval(3000),
            snoozeMinutes: 5, silent: false)
        // 0.2.0 documents keep their old dates and default to normal, no category.
        let legacy = try JSONDecoder().decode(Reminder.self,
                                               from: JSONEncoder().encode(original))
        assert(legacy.categoryID == nil)
        assert(legacy.effectivePriority == .normal)
        assert(legacy.eventDate == original.eventDate)
        let basePlan = legacy.alertPlan(now: now)
        var important = legacy
        important.id = UUID()
        important.priority = .critical
        important.categoryID = "work"
        important.title = "Работа"
        assert(important.alertPlan(now: now).count == basePlan.count)
        assert(important.alertPlan(now: now)[0].1 == basePlan[0].1)
        let encoded = try JSONEncoder().encode(important)
        let decoded = try JSONDecoder().decode(Reminder.self, from: encoded)
        assert(decoded.categoryID == "work")
        assert(decoded.effectivePriority == .critical)
        let defaultCategories = RFCategoryCatalog.defaults
        assert(defaultCategories.count == 4)
        assert(Set(defaultCategories.map(\.id)).count == 4)
        let custom = RFCategory(id: UUID().uuidString, name: "Подписки",
                                colorKey: "pink", iconName: "creditcard.fill")
        let saved = RFCategoryCatalog.mergedWithDefaults([custom, custom])
        assert(saved.count == 5)
        assert(saved.last?.name == "Здоровье")
        assert(saved.contains(where: { $0.id == custom.id }))
        assert(RFCategoryCatalog.normalized("  Привет \n") == "Привет")
        assert(RFCategoryCatalog.validColor("not-a-color") == "cyan")
        assert(RFCategoryCatalog.validIcon("not-an-icon") == "folder.fill")
        var personal = original
        personal.id = UUID()
        personal.categoryID = "personal"
        personal.priority = .low
        personal.title = "Аренда"
        personal.eventDate = now.addingTimeInterval(7200)
        var plain = original
        plain.id = UUID()
        plain.categoryID = nil
        plain.title = "Без категории"
        let tasks = [plain, personal, important]
        assert(RFTaskPresentation.filtered(tasks, categoryID: "work").map(\.id) == [important.id])
        assert(RFTaskPresentation.filtered(tasks, categoryID: nil).count == 3)
        assert(RFTaskPresentation.filtered(tasks, categoryID:
            RFTaskPresentation.uncategorizedID).map(\.id) == [plain.id])
        assert(RFTaskPresentation.sorted(tasks, by: .priority).first?.id == important.id)
        assert(RFTaskPresentation.sorted(tasks, by: .date).last?.id == personal.id)
        assert(RFTaskPresentation.sorted(tasks, by: .title).first?.id == personal.id)
        assert(RFReminderPriority.allCases.count == 4)
        print("PASS: 0.2.1 old data, persistence, four categories, palette, filtering and sorting")
    }
}
