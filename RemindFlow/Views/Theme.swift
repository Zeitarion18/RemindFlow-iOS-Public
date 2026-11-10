import SwiftUI

enum RFTheme {
    static let background = Color(red: 0.035, green: 0.055, blue: 0.105)
    static let card = Color(red: 0.079, green: 0.111, blue: 0.18)
    static let accent = Color(red: 0.27, green: 0.85, blue: 0.88)
    static let muted = Color(red: 0.60, green: 0.68, blue: 0.78)

    static func categoryColor(_ key: String) -> Color {
        switch key {
        case "blue": return Color(red: 0.34, green: 0.61, blue: 1.0)
        case "green": return Color(red: 0.29, green: 0.83, blue: 0.52)
        case "purple": return Color(red: 0.75, green: 0.49, blue: 0.98)
        case "orange": return Color(red: 1.0, green: 0.68, blue: 0.29)
        case "pink": return Color(red: 1.0, green: 0.47, blue: 0.73)
        case "red": return Color(red: 1.0, green: 0.37, blue: 0.41)
        case "yellow": return Color(red: 0.97, green: 0.83, blue: 0.31)
        case "mint": return Color(red: 0.35, green: 0.91, blue: 0.75)
        case "indigo": return Color(red: 0.47, green: 0.53, blue: 0.98)
        default: return accent
        }
    }

    static func priorityColor(_ priority: RFReminderPriority) -> Color {
        switch priority {
        case .low: return muted
        case .normal: return accent
        case .high: return .orange
        case .critical: return Color(red: 1.0, green: 0.38, blue: 0.44)
        }
    }
}

struct RFCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RFTheme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.065), lineWidth: 1)
            )
    }
}
