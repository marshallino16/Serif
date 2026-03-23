#if os(iOS)
import UIKit
import FirebaseMessaging
import FirebaseFirestore

/// Manages FCM token registration, Gmail watch(), and Firestore device sync.
@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    private let db = Firestore.firestore()
    private let topicName = "projects/marsha-prd-488320/topics/gmail-push"

    @Published var isRegistered = false
    @Published var notificationsEnabled = false

    /// Which inbox categories trigger push notifications.
    /// Maps to Gmail label IDs: CATEGORY_PERSONAL, CATEGORY_SOCIAL, etc.
    /// Empty = all inbox messages.
    @Published var notifyCategories: Set<String> = []

    /// All available categories for the settings UI.
    static let allCategories: [(id: String, name: String)] = [
        ("CATEGORY_PERSONAL", "Primary"),
        ("CATEGORY_SOCIAL", "Social"),
        ("CATEGORY_PROMOTIONS", "Promotions"),
        ("CATEGORY_UPDATES", "Updates"),
        ("CATEGORY_FORUMS", "Forums"),
    ]

    private var pendingEmail: String?
    private var pendingRefreshToken: String?
    private var pendingAccountID: String?
    private var currentEmail: String?

    private override init() {
        super.init()
        Messaging.messaging().delegate = self
    }

    // MARK: - Permission

    /// Request notification permission and register for remote notifications.
    /// Call this at sign-in, not at app launch.
    func requestPermissionAndRegister(email: String, refreshToken: String, accountID: String) async {
        // Request permission
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        notificationsEnabled = granted

        guard granted else {
            print("[Push] Notification permission denied")
            return
        }

        // Register for remote notifications (triggers APNs token → FCM token)
        UIApplication.shared.registerForRemoteNotifications()

        // FCM token might not be ready yet — store pending info
        if let fcmToken = Messaging.messaging().fcmToken {
            await completeRegistration(email: email, fcmToken: fcmToken, refreshToken: refreshToken, accountID: accountID)
        } else {
            // Will be completed in messaging(_:didReceiveRegistrationToken:)
            pendingEmail = email
            pendingRefreshToken = refreshToken
            pendingAccountID = accountID
            print("[Push] Waiting for FCM token...")
        }
    }

    /// Check current state on app open (after already signed in).
    func checkAndReregisterIfNeeded(email: String, refreshToken: String, accountID: String) async {
        currentEmail = email
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized

        guard notificationsEnabled else { return }
        guard let fcmToken = Messaging.messaging().fcmToken else { return }

        // Load saved categories from Firestore
        let ref = db.collection("users").document(email)
        if let doc = try? await ref.getDocument(), doc.exists {
            let data = doc.data() ?? [:]
            if let cats = data["notifyCategories"] as? [String] {
                notifyCategories = Set(cats)
            } else {
                // First time: default to all
                notifyCategories = Set(Self.allCategories.map(\.id))
            }
            // Check if device is already registered
            if let devices = data["devices"] as? [[String: Any]],
               devices.contains(where: { ($0["token"] as? String) == fcmToken }) {
                isRegistered = true
                return
            }
        }

        // Not registered yet — do it now
        await completeRegistration(email: email, fcmToken: fcmToken, refreshToken: refreshToken, accountID: accountID)
    }

    /// Call on sign-out to remove this device.
    func unregister(email: String) async {
        guard let fcmToken = Messaging.messaging().fcmToken else { return }
        let ref = db.collection("users").document(email)
        do {
            let doc = try await ref.getDocument()
            guard var devices = doc.data()?["devices"] as? [[String: Any]] else { return }
            devices.removeAll { ($0["token"] as? String) == fcmToken }
            try await ref.updateData(["devices": devices])
            isRegistered = false
        } catch {
            print("[Push] Unregister error: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal

    private func completeRegistration(email: String, fcmToken: String, refreshToken: String, accountID: String) async {
        await saveDevice(email: email, fcmToken: fcmToken, refreshToken: refreshToken)
        await setupGmailWatch(email: email, accountID: accountID)
        // Default: notify for all categories
        if notifyCategories.isEmpty {
            notifyCategories = Set(Self.allCategories.map(\.id))
            await saveNotifyCategories(email: email)
        }
        currentEmail = email
        isRegistered = true
        pendingEmail = nil
        pendingRefreshToken = nil
        pendingAccountID = nil
        print("[Push] Registration complete for \(email)")
    }

    // MARK: - Notification Categories

    /// Toggle a category on/off and persist to Firestore.
    func toggleCategory(_ categoryID: String) async {
        if notifyCategories.contains(categoryID) {
            notifyCategories.remove(categoryID)
        } else {
            notifyCategories.insert(categoryID)
        }
        if let email = currentEmail {
            await saveNotifyCategories(email: email)
        }
    }

    private func saveNotifyCategories(email: String) async {
        let ref = db.collection("users").document(email)
        try? await ref.updateData(["notifyCategories": Array(notifyCategories)])
    }

    // MARK: - Firestore

    private func saveDevice(email: String, fcmToken: String, refreshToken: String) async {
        let ref = db.collection("users").document(email)
        let deviceName = UIDevice.current.name

        let newDevice: [String: Any] = [
            "token": fcmToken,
            "platform": "ios",
            "name": deviceName,
        ]

        do {
            let doc = try await ref.getDocument()
            if doc.exists {
                var devices = doc.data()?["devices"] as? [[String: Any]] ?? []
                devices.removeAll { ($0["token"] as? String) == fcmToken }
                devices.append(newDevice)
                try await ref.updateData([
                    "devices": devices,
                    "refreshToken": refreshToken,
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
            } else {
                try await ref.setData([
                    "devices": [newDevice],
                    "refreshToken": refreshToken,
                    "historyId": NSNull(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ])
            }
        } catch {
            print("[Push] Firestore save error: \(error.localizedDescription)")
        }
    }

    // MARK: - Gmail Watch

    private func setupGmailWatch(email: String, accountID: String) async {
        do {
            let body: [String: Any] = [
                "topicName": topicName,
                "labelIds": ["INBOX"],
            ]
            let data = try JSONSerialization.data(withJSONObject: body)
            let response: GmailWatchResponse = try await GmailAPIClient.shared.request(
                path: "/users/me/watch",
                method: "POST",
                body: data,
                contentType: "application/json",
                accountID: accountID
            )
            let ref = db.collection("users").document(email)
            try await ref.updateData(["historyId": response.historyId])
            print("[Push] Gmail watch active, historyId: \(response.historyId)")
        } catch {
            print("[Push] Gmail watch error: \(error.localizedDescription)")
        }
    }
}

// MARK: - FCM Delegate

extension PushNotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("[Push] FCM token received: \(token.prefix(20))...")
        Task { @MainActor in
            // Complete pending registration if we were waiting for the token
            if let email = self.pendingEmail,
               let refreshToken = self.pendingRefreshToken,
               let accountID = self.pendingAccountID {
                await self.completeRegistration(
                    email: email, fcmToken: token,
                    refreshToken: refreshToken, accountID: accountID
                )
            }
        }
    }
}

// MARK: - Gmail Watch Response

struct GmailWatchResponse: Codable {
    let historyId: String
    let expiration: String
}
#endif
