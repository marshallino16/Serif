import UserNotifications
import Intents

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let content = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        let userInfo = request.content.userInfo
        let type = userInfo["type"] as? String ?? ""

        // Multi-message: just deliver as-is
        guard type == "new_email" else {
            contentHandler(content)
            return
        }

        let senderName = userInfo["senderName"] as? String ?? content.title
        let senderEmail = userInfo["senderEmail"] as? String ?? ""
        let subject = userInfo["subject"] as? String ?? ""
        let snippet = userInfo["snippet"] as? String ?? ""

        // Title = subject (bold), body = snippet preview
        if !subject.isEmpty { content.title = subject }
        content.body = snippet.isEmpty ? content.body : snippet

        // Build ordered list of avatar URLs to try:
        // 1. Google Contact photo  2. Gravatar  3. BIMI  4. Clearbit logo
        var avatarURLs: [URL] = []
        if let url = nonEmptyURL(userInfo["contactPhotoUrl"]) { avatarURLs.append(url) }
        if let url = nonEmptyURL(userInfo["avatarUrl"]) { avatarURLs.append(url) }
        if let url = nonEmptyURL(userInfo["bimiUrl"]) { avatarURLs.append(url) }
        if let url = nonEmptyURL(userInfo["logoDevUrl"]) { avatarURLs.append(url) }

        tryDownloadAvatar(urls: avatarURLs, index: 0) { [weak self] avatarData in
            self?.createCommunicationNotification(
                content: content,
                senderName: senderName,
                senderEmail: senderEmail,
                avatarData: avatarData,
                contentHandler: contentHandler
            )
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Avatar download with fallback chain

    /// Tries each URL in order until one succeeds with a valid raster image.
    private func tryDownloadAvatar(urls: [URL], index: Int, completion: @escaping (Data?) -> Void) {
        guard index < urls.count else {
            completion(nil)
            return
        }
        downloadImage(from: urls[index]) { [weak self] imageData in
            guard let self else { completion(nil); return }
            if let imageData, !self.isSVG(imageData) {
                completion(imageData)
            } else {
                self.tryDownloadAvatar(urls: urls, index: index + 1, completion: completion)
            }
        }
    }

    // MARK: - Communication Notification (avatar display)

    private func createCommunicationNotification(
        content: UNMutableNotificationContent,
        senderName: String,
        senderEmail: String,
        avatarData: Data?,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let handle = INPersonHandle(value: senderEmail, type: .emailAddress)

        var avatar: INImage?
        if let data = avatarData {
            avatar = INImage(imageData: data)
        }

        let sender = INPerson(
            personHandle: handle,
            nameComponents: nil,
            displayName: senderName,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: senderEmail,
            isMe: false,
            suggestionType: .none
        )

        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: senderEmail,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate { _ in }

        do {
            let updatedContent = try content.updating(from: intent)
            contentHandler(updatedContent)
        } catch {
            contentHandler(content)
        }
    }

    // MARK: - Helpers

    private func nonEmptyURL(_ value: Any?) -> URL? {
        guard let str = value as? String, !str.isEmpty else { return nil }
        return URL(string: str)
    }

    private func downloadImage(from url: URL, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let data, !data.isEmpty {
                completion(data)
            } else {
                completion(nil)
            }
        }.resume()
    }

    /// Detect SVG data (not usable by INImage — needs raster PNG/JPEG)
    private func isSVG(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        let prefix = String(data: data.prefix(256), encoding: .utf8) ?? ""
        return prefix.contains("<svg") || prefix.contains("<?xml")
    }
}
