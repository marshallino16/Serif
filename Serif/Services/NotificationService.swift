import Foundation
@preconcurrency import UserNotifications
import AppKit

@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    var onNotificationTapped: ((String, String) -> Void)?  // (gmailMessageID, accountID)
    /// The account ID whose inbox is currently being viewed (nil if not on inbox).
    var viewingInboxAccountID: String?

    private let center = UNUserNotificationCenter.current()
    private let nonPrimaryLabels: Set<String> = [
        "CATEGORY_SOCIAL", "CATEGORY_PROMOTIONS", "CATEGORY_UPDATES", "CATEGORY_FORUMS"
    ]

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestPermission() {
        let center = self.center
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    // MARK: - Dispatch

    func notifyNewEmails(_ messages: [GmailMessage], accountEmail: String) {
        let enabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard enabled else { return }

        let eligible = messages.filter { msg in
            let labels = Set(msg.labelIds ?? [])
            guard labels.contains("INBOX") else { return false }
            guard labels.isDisjoint(with: nonPrimaryLabels) else { return false }
            guard !labels.contains("DRAFT") else { return false }
            let fromEmail = GmailDataTransformer.parseContact(msg.from).email.lowercased()
            return fromEmail != accountEmail.lowercased()
        }

        guard !eligible.isEmpty else { return }
        if NSApplication.shared.isActive && viewingInboxAccountID == accountEmail { return }

        let isMultiAccount = AccountStore.shared.accounts.count > 1
        let accountName = isMultiAccount
            ? AccountStore.shared.accounts.first(where: { $0.email == accountEmail })?.displayName
            : nil

        if eligible.count > 3 {
            sendSummaryNotification(count: eligible.count, accountEmail: accountEmail, accountName: accountName)
        } else {
            for msg in eligible {
                sendIndividualNotification(msg, accountEmail: accountEmail, accountName: accountName)
            }
        }
    }

    // MARK: - Badge

    func updateBadge(unreadCount: Int) {
        NSApplication.shared.dockTile.badgeLabel = unreadCount > 0 ? "\(unreadCount)" : nil
    }

    // MARK: - Private

    private func sendIndividualNotification(_ message: GmailMessage, accountEmail: String, accountName: String?) {
        let content = UNMutableNotificationContent()
        let sender = GmailDataTransformer.parseContact(message.from)
        content.title = sender.name
        if let accountName { content.subtitle = accountName }
        content.body = [message.subject, message.snippet ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " — ")
        content.threadIdentifier = accountEmail
        content.userInfo = ["gmailMessageID": message.id, "accountID": accountEmail]
        let soundEnabled = UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true
        if soundEnabled { content.sound = .default }

        let request = UNNotificationRequest(identifier: "newmail.\(message.id)", content: content, trigger: nil)
        center.add(request)
    }

    private func sendSummaryNotification(count: Int, accountEmail: String, accountName: String?) {
        let content = UNMutableNotificationContent()
        content.title = "\(count) new emails"
        if let accountName { content.subtitle = accountName }
        content.body = "You have \(count) new emails in your inbox"
        content.threadIdentifier = accountEmail
        content.userInfo = ["accountID": accountEmail]
        let soundEnabled = UserDefaults.standard.object(forKey: "notificationSoundEnabled") as? Bool ?? true
        if soundEnabled { content.sound = .default }

        let id = "newmail.batch.\(accountEmail).\(Int(Date().timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let messageID = userInfo["gmailMessageID"] as? String,
              let accountID = userInfo["accountID"] as? String else {
            completionHandler()
            return
        }
        Task { @MainActor in
            self.onNotificationTapped?(messageID, accountID)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
