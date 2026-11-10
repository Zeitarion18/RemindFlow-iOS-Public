import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        NotificationManager.registerCategories()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let isSilent = notification.request.content.userInfo[NotificationManager.silentKey] as? Bool ?? false
        completionHandler(isSilent ? [.banner, .list] : [.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard let rawID = response.notification.request.content.userInfo[NotificationManager.reminderIDKey] as? String,
              let id = UUID(uuidString: rawID) else {
            completionHandler()
            return
        }
        let timestamp = response.notification.request.content.userInfo[
            NotificationManager.occurrenceTimestampKey] as? Double
        let occurrence = timestamp.map { Date(timeIntervalSince1970: $0) }
            ?? response.notification.date
        Task { @MainActor in
            await ReminderStore.shared.handleAction(response.actionIdentifier,
                                                   reminderID: id,
                                                   eventOccurrence: occurrence)
            completionHandler()
        }
    }
}

@main
struct RemindFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ReminderStore.shared
    @StateObject private var categoryStore = RFCategoryStore.shared

    var body: some Scene {
        WindowGroup {
            RFMainTabsView()
                .environmentObject(store)
                .environmentObject(categoryStore)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .preferredColorScheme(.dark)
        }
    }
}
