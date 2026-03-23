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
        let snippet = userInfo["snippet"] as? String ?? ""
        let avatarUrl = userInfo["avatarUrl"] as? String

        // Enrich body with snippet (like Gmail: subject + snippet preview)
        if !snippet.isEmpty {
            content.body = "\(content.body)\n\(snippet)"
        }

        // Subtitle: sender email
        if !senderEmail.isEmpty {
            content.subtitle = senderEmail
        }

        // Download avatar and create Communication Notification
        if let avatarUrl, let url = URL(string: avatarUrl) {
            downloadImage(from: url) { [weak self] imageData in
                self?.createCommunicationNotification(
                    content: content,
                    senderName: senderName,
                    senderEmail: senderEmail,
                    avatarData: imageData,
                    contentHandler: contentHandler
                )
            }
        } else {
            createCommunicationNotification(
                content: content,
                senderName: senderName,
                senderEmail: senderEmail,
                avatarData: nil,
                contentHandler: contentHandler
            )
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
}
