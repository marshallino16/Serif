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
        let avatarUrl = userInfo["avatarUrl"] as? String
        let bimiUrl = userInfo["bimiUrl"] as? String

        // Title = subject (bold), body = snippet preview, no subtitle (no email)
        if !subject.isEmpty { content.title = subject }
        content.body = snippet.isEmpty ? content.body : snippet

        // Download avatar: try Gravatar first, then BIMI logo as fallback
        let bimiURL = (bimiUrl?.isEmpty == false) ? URL(string: bimiUrl!) : nil

        let finalize: (Data?) -> Void = { [weak self] avatarData in
            self?.createCommunicationNotification(
                content: content,
                senderName: senderName,
                senderEmail: senderEmail,
                avatarData: avatarData,
                contentHandler: contentHandler
            )
        }

        if let url = (avatarUrl?.isEmpty == false) ? URL(string: avatarUrl!) : nil {
            downloadImage(from: url) { [weak self] imageData in
                guard let self else { finalize(nil); return }
                if let imageData {
                    finalize(imageData)
                } else if let bimiURL {
                    // Gravatar failed → try BIMI (skip SVG, only use raster)
                    self.downloadImage(from: bimiURL) { bimiData in
                        if let bimiData, !self.isSVG(bimiData) {
                            finalize(bimiData)
                        } else {
                            finalize(nil)
                        }
                    }
                } else {
                    finalize(nil)
                }
            }
        } else if let bimiURL {
            downloadImage(from: bimiURL) { [weak self] bimiData in
                guard let self else { finalize(nil); return }
                if let bimiData, !self.isSVG(bimiData) {
                    finalize(bimiData)
                } else {
                    finalize(nil)
                }
            }
        } else {
            finalize(nil)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
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

    // MARK: - Image Download

    private func downloadImage(from url: URL, completion: @escaping (Data?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Gravatar returns 404 if no avatar exists
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
