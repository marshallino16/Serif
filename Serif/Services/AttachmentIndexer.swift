import Foundation

actor AttachmentIndexer {
    private let database: AttachmentDatabase
    private let messageService: GmailMessageService
    private let accountID: String
    private var isProcessing = false
    private var isDiscovering = false
    private let maxConcurrent = 3
    private let maxRetries = 3

    /// Called on @MainActor after each indexing batch so the UI can refresh stats.
    var onProgressUpdate: (@MainActor () -> Void)?

    init(database: AttachmentDatabase, messageService: GmailMessageService, accountID: String) {
        self.database = database
        self.messageService = messageService
        self.accountID = accountID
    }

    // MARK: - Discovery

    /// Discover all attachments via Gmail API (has:attachment query).
    /// Fetches messages in "full" format to get attachment parts.
    /// Call on app launch — this is the primary way attachments enter the DB.
    func discoverAttachments() async {
        guard !isDiscovering else { return }
        isDiscovering = true
        defer { isDiscovering = false }

        print("[AttachmentIndexer] Starting attachment discovery...")

        var pageToken: String? = nil
        var totalDiscovered = 0

        repeat {
            do {
                // List messages that have attachments
                let list = try await messageService.listMessages(
                    accountID: accountID,
                    labelIDs: [],
                    query: "has:attachment",
                    pageToken: pageToken,
                    maxResults: 50
                )

                let refs = list.messages ?? []
                pageToken = list.nextPageToken

                guard !refs.isEmpty else { break }

                // Filter out messages we already fully processed
                let newIDs = refs.map(\.id).filter { msgId in
                    !database.hasMessageAttachments(messageId: msgId)
                }

                guard !newIDs.isEmpty else { continue }

                // Fetch in "full" format to get attachment parts
                let fullMessages = try await messageService.getMessages(
                    ids: newIDs,
                    accountID: accountID,
                    format: "full"
                )

                // Register each attachment
                for message in fullMessages {
                    let attachmentParts = message.attachmentParts
                    guard !attachmentParts.isEmpty else { continue }

                    let email = makeMinimalEmail(from: message)

                    for part in attachmentParts {
                        guard let attachmentId = part.body?.attachmentId else { continue }

                        let id = "\(message.id)_\(attachmentId)"
                        guard !database.exists(id: id) else { continue }

                        let name = part.filename ?? "attachment"
                        let ext = String(name.split(separator: ".").last ?? "")

                        let indexed = IndexedAttachment(
                            id: id,
                            messageId: message.id,
                            attachmentId: attachmentId,
                            filename: name,
                            mimeType: part.mimeType,
                            fileType: Attachment.FileType.from(fileExtension: ext).rawValue,
                            size: part.body?.size ?? 0,
                            senderEmail: email.senderEmail,
                            senderName: email.senderName,
                            emailSubject: email.subject,
                            emailDate: email.date,
                            direction: email.direction,
                            indexedAt: nil,
                            indexingStatus: .pending,
                            extractedText: nil
                        )
                        database.insertAttachment(indexed)
                        totalDiscovered += 1
                    }
                }

                // Notify UI after each page
                if let onProgress = onProgressUpdate {
                    await onProgress()
                }

            } catch {
                print("[AttachmentIndexer] Discovery error: \(error)")
                break
            }
        } while pageToken != nil

        print("[AttachmentIndexer] Discovery complete: \(totalDiscovered) new attachments found")

        // Now process the queue to index content
        await processQueue()
    }

    // MARK: - Register (from already-fetched full-format emails)

    /// Register attachments from emails that were fetched in full format (e.g., thread detail view).
    func register(attachments: [(attachment: Attachment, email: Email)]) async {
        for (att, email) in attachments {
            guard let gmailAttachmentId = att.gmailAttachmentId,
                  let gmailMessageId = att.gmailMessageId else { continue }

            let id = "\(gmailMessageId)_\(gmailAttachmentId)"
            guard !database.exists(id: id) else { continue }

            let indexed = IndexedAttachment(
                id: id,
                messageId: gmailMessageId,
                attachmentId: gmailAttachmentId,
                filename: att.name,
                mimeType: att.mimeType,
                fileType: att.fileType.rawValue,
                size: 0,
                senderEmail: email.sender.email,
                senderName: email.sender.name,
                emailSubject: email.subject,
                emailDate: email.date,
                direction: email.folder == .sent ? .sent : .received,
                indexedAt: nil,
                indexingStatus: .pending,
                extractedText: nil
            )
            database.insertAttachment(indexed)
        }
        await processQueue()
    }

    // MARK: - Resume (app launch)

    /// Resume pending + retry failed items. Then discover new attachments.
    func resumeAndDiscover() async {
        database.resetFailedForRetry(maxRetries: maxRetries)
        // Process any pending items from last session first
        await processQueue()
        // Then discover new attachments from Gmail
        await discoverAttachments()
    }

    // MARK: - Process Queue

    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        var pending = database.pendingAttachments(limit: maxConcurrent)
        while !pending.isEmpty {
            await withTaskGroup(of: Void.self) { group in
                for att in pending {
                    group.addTask { [self] in
                        await self.indexAttachment(att)
                    }
                }
            }
            if let onProgress = onProgressUpdate {
                await onProgress()
            }
            pending = database.pendingAttachments(limit: maxConcurrent)
        }
    }

    // MARK: - Index single attachment

    private func indexAttachment(_ att: IndexedAttachment) async {
        do {
            let data = try await messageService.getAttachment(
                messageID: att.messageId,
                attachmentID: att.attachmentId,
                accountID: accountID
            )

            let result = await ContentExtractor.extract(
                from: data,
                mimeType: att.mimeType,
                filename: att.filename
            )

            switch result {
            case .text(let text):
                let embedding = ContentExtractor.generateEmbedding(for: text)
                database.updateIndexedContent(id: att.id, text: text, embedding: embedding, status: .indexed)
                print("[AttachmentIndexer] Indexed: \(att.filename)")
            case .unsupported:
                database.updateIndexedContent(id: att.id, text: nil, embedding: nil, status: .unsupported)
                print("[AttachmentIndexer] Unsupported: \(att.filename)")
            }
        } catch {
            database.incrementRetry(id: att.id)
            print("[AttachmentIndexer] Failed: \(att.filename) — \(error)")
        }
    }

    // MARK: - Helpers

    private struct MinimalEmail {
        let senderEmail: String?
        let senderName: String?
        let subject: String?
        let date: Date?
        let direction: IndexedAttachment.Direction
    }

    private func makeMinimalEmail(from message: GmailMessage) -> MinimalEmail {
        let labels = message.labelIds ?? []
        let direction: IndexedAttachment.Direction = labels.contains("SENT") ? .sent : .received
        let fromRaw = message.from
        let senderEmail = fromRaw.components(separatedBy: "<").last?.replacingOccurrences(of: ">", with: "").trimmingCharacters(in: .whitespaces)
        let senderName = fromRaw.components(separatedBy: "<").first?.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return MinimalEmail(
            senderEmail: senderEmail,
            senderName: senderName,
            subject: message.subject,
            date: message.date,
            direction: direction
        )
    }
}
