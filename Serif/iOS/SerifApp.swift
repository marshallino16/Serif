import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
struct SerifiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            iOSContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self

        // Clear badge when app opens
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { _ in
            UNUserNotificationCenter.current().setBadgeCount(0)
        }

        return true
    }

    // Forward APNs token to FCM
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    // Show notification when app is in foreground — recalculate badge for all accounts
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Recalculate total unread across all accounts for accurate badge
        Task {
            let total = await Self.totalUnreadCount()
            try? await UNUserNotificationCenter.current().setBadgeCount(total)
        }
        completionHandler([.banner, .sound])
    }

    static func totalUnreadCount() async -> Int {
        let allAccountIDs = TokenStore.shared.allAccountIDs()
        var total = 0
        for id in allAccountIDs {
            do {
                let label: GmailLabel = try await GmailAPIClient.shared.request(
                    path: "/users/me/labels/INBOX",
                    accountID: id
                )
                total += label.messagesUnread ?? 0
            } catch { continue }
        }
        return total
    }

    // Handle notification tap
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let messageId = userInfo["messageId"] as? String {
            NotificationCenter.default.post(
                name: .pushNotificationTapped,
                object: nil,
                userInfo: ["messageId": messageId]
            )
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
