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
    /// Stores notification tap data for cold-launch scenario (view may not be observing yet).
    static var pendingNotification: [String: String]?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        UNUserNotificationCenter.current().delegate = self

        // Register notification actions
        registerNotificationCategories()

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

    // MARK: - Notification Categories

    private func registerNotificationCategories() {
        let trashAction = UNNotificationAction(
            identifier: "com.serif.action.trash",
            title: "Trash",
            options: [.destructive]
        )

        let replyAction = UNTextInputNotificationAction(
            identifier: "com.serif.action.reply",
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Reply..."
        )

        let emailCategory = UNNotificationCategory(
            identifier: "com.serif.email",
            actions: [replyAction, trashAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([emailCategory])
    }

    // MARK: - Foreground Notification

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task {
            let total = await Self.totalUnreadCount()
            try? await UNUserNotificationCenter.current().setBadgeCount(total)
        }
        completionHandler([.banner, .sound])
    }

    // MARK: - Notification Response (tap + actions)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let messageId = userInfo["messageId"] as? String
        let threadId = userInfo["threadId"] as? String
        let emailAddress = userInfo["emailAddress"] as? String

        switch response.actionIdentifier {
        case "com.serif.action.trash":
            // Trash thread directly from notification
            if let threadId, let emailAddress {
                Task {
                    try? await GmailMessageService.shared.trashThread(id: threadId, accountID: emailAddress)
                    let total = await Self.totalUnreadCount()
                    try? await UNUserNotificationCenter.current().setBadgeCount(total)
                }
            }

        case "com.serif.action.reply":
            if let textResponse = response as? UNTextInputNotificationResponse,
               let messageId, let emailAddress {
                let replyText = textResponse.userText
                Task {
                    await Self.sendQuickReply(
                        text: replyText,
                        messageId: messageId,
                        accountID: emailAddress
                    )
                }
            }

        default:
            // Default tap → open the email in the app
            if let messageId {
                var info: [String: String] = ["messageId": messageId]
                if let emailAddress { info["emailAddress"] = emailAddress }
                // Store for cold-launch (view might not be observing yet)
                AppDelegate.pendingNotification = info
                NotificationCenter.default.post(
                    name: .pushNotificationTapped,
                    object: nil,
                    userInfo: info
                )
            }
        }

        completionHandler()
    }

    // MARK: - Quick Reply from Notification

    private static func sendQuickReply(text: String, messageId: String, accountID: String) async {
        do {
            let msg = try await GmailMessageService.shared.getMessage(
                id: messageId, accountID: accountID, format: "metadata"
            )
            let headers = msg.payload?.headers ?? []
            let from = headers.first { $0.name == "From" }?.value ?? ""
            let subject = headers.first { $0.name == "Subject" }?.value ?? ""
            let replySubject = subject.hasPrefix("Re:") ? subject : "Re: \(subject)"

            // Extract reply-to email
            let replyTo: String
            if let match = from.range(of: #"<([^>]+)>"#, options: .regularExpression) {
                replyTo = String(from[match]).replacingOccurrences(of: "<", with: "").replacingOccurrences(of: ">", with: "")
            } else {
                replyTo = from
            }

            _ = try await GmailSendService.shared.send(
                from: accountID,
                to: [replyTo],
                subject: replySubject,
                body: text,
                threadID: msg.threadId,
                referencesHeader: messageId,
                accountID: accountID
            )
        } catch {
            print("[Push] Quick reply failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Badge

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
}

extension Notification.Name {
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
