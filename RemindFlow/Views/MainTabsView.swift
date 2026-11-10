import SwiftUI

private enum RFMainTab: Hashable {
    case home
    case calendar
    case settings
}

/// Three native, persistent iPhone tabs; each tab keeps its own navigation state.
struct RFMainTabsView: View {
    @State private var selectedTab: RFMainTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Главная", systemImage: "house.fill")
                }
                .tag(RFMainTab.home)
            CalendarView()
                .tabItem {
                    Label("Календарь", systemImage: "calendar")
                }
                .tag(RFMainTab.calendar)
            SettingsView(showsDoneButton: false)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
                .tag(RFMainTab.settings)
        }
        .tint(RFTheme.accent)
    }
}
