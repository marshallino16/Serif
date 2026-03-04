import SwiftUI

struct EmailDetailView: View {
    let email: Email
    let accountID: String
    var attachmentIndexer: AttachmentIndexer?
    var onArchive:            (() -> Void)?
    var onDelete:             (() -> Void)?
    var onMoveToInbox:        (() -> Void)?
    var onDeletePermanently:  (() -> Void)?
    var onMarkNotSpam:        (() -> Void)?
    var onToggleStar:         ((Bool) -> Void)?
    var onMarkUnread:         (() -> Void)?
    var allLabels:     [GmailLabel]
    var onAddLabel:    ((String) -> Void)?
    var onRemoveLabel: ((String) -> Void)?
    var onReply:       ((ComposeMode) -> Void)?
    var onReplyAll:    ((ComposeMode) -> Void)?
    var onForward:     ((ComposeMode) -> Void)?

    var onCreateAndAddLabel: ((String, @escaping (String?) -> Void) -> Void)?
    var onPreviewAttachment: ((Data, String, Attachment.FileType) -> Void)?
    var onShowOriginal: ((EmailDetailViewModel) -> Void)?
    var onDownloadMessage: ((EmailDetailViewModel) -> Void)?
    var onUnsubscribe: ((URL, Bool, String?) async -> Bool)?
    var onPrint: ((GmailMessage, Email) -> Void)?
    var checkUnsubscribed: ((String) -> Bool)?
    var extractBodyUnsubscribeURL: ((String) -> URL?)?
    var fromAddress: String = ""

    @StateObject private var detailVM: EmailDetailViewModel
    @State private var emailBodyHeight: CGFloat = 100
    @State private var didUnsubscribe = false
    @State private var showSenderInfo = false
    @Environment(\.theme) private var theme

    /// Best available unsubscribe URL: header-based (from full thread) or body-scanned.
    private var resolvedUnsubscribeURL: URL? {
        if let url = detailVM.latestMessage?.unsubscribeURL { return url }
        if let html = detailVM.latestMessage?.htmlBody ?? detailVM.latestMessage?.plainBody,
           let url = extractBodyUnsubscribeURL?(html) { return url }
        return email.unsubscribeURL
    }

    private var isMailingList: Bool {
        detailVM.latestMessage?.isFromMailingList ?? email.isFromMailingList || resolvedUnsubscribeURL != nil
    }

    private var oneClick: Bool {
        detailVM.latestMessage?.supportsOneClickUnsubscribe ?? false
    }

    private var alreadyUnsubscribed: Bool {
        if didUnsubscribe { return true }
        guard let msgID = email.gmailMessageID else { return false }
        return checkUnsubscribed?(msgID) ?? false
    }

    init(
        email: Email,
        accountID: String,
        attachmentIndexer: AttachmentIndexer? = nil,
        onArchive:            (() -> Void)? = nil,
        onDelete:             (() -> Void)? = nil,
        onMoveToInbox:        (() -> Void)? = nil,
        onDeletePermanently:  (() -> Void)? = nil,
        onMarkNotSpam:        (() -> Void)? = nil,
        onToggleStar:         ((Bool) -> Void)? = nil,
        onMarkUnread:         (() -> Void)? = nil,
        allLabels:             [GmailLabel] = [],
        onAddLabel:            ((String) -> Void)? = nil,
        onRemoveLabel:         ((String) -> Void)? = nil,
        onReply:               ((ComposeMode) -> Void)? = nil,
        onReplyAll:            ((ComposeMode) -> Void)? = nil,
        onForward:             ((ComposeMode) -> Void)? = nil,
        onCreateAndAddLabel:   ((String, @escaping (String?) -> Void) -> Void)? = nil,
        onPreviewAttachment:   ((Data, String, Attachment.FileType) -> Void)? = nil,
        onShowOriginal:        ((EmailDetailViewModel) -> Void)? = nil,
        onDownloadMessage:     ((EmailDetailViewModel) -> Void)? = nil,
        onUnsubscribe:         ((URL, Bool, String?) async -> Bool)? = nil,
        onPrint:               ((GmailMessage, Email) -> Void)? = nil,
        checkUnsubscribed:     ((String) -> Bool)? = nil,
        extractBodyUnsubscribeURL: ((String) -> URL?)? = nil,
        fromAddress:           String = ""
    ) {
        self.email              = email
        self.accountID          = accountID
        self.attachmentIndexer  = attachmentIndexer
        self.onArchive          = onArchive
        self.onDelete           = onDelete
        self.onMoveToInbox      = onMoveToInbox
        self.onDeletePermanently = onDeletePermanently
        self.onMarkNotSpam      = onMarkNotSpam
        self.onToggleStar       = onToggleStar
        self.onMarkUnread       = onMarkUnread
        self.allLabels    = allLabels
        self.onAddLabel   = onAddLabel
        self.onRemoveLabel = onRemoveLabel
        self.onReply               = onReply
        self.onReplyAll            = onReplyAll
        self.onForward             = onForward
        self.onCreateAndAddLabel   = onCreateAndAddLabel
        self.onPreviewAttachment   = onPreviewAttachment
        self.onShowOriginal        = onShowOriginal
        self.onDownloadMessage     = onDownloadMessage
        self.onUnsubscribe         = onUnsubscribe
        self.onPrint               = onPrint
        self.checkUnsubscribed     = checkUnsubscribed
        self.extractBodyUnsubscribeURL = extractBodyUnsubscribeURL
        self.fromAddress           = fromAddress
        self._detailVM             = StateObject(wrappedValue: EmailDetailViewModel(accountID: accountID))
    }

    // MARK: - Derived content

    private var displayAttachments: [Attachment] {
        if let latest = detailVM.latestMessage {
            return latest.attachmentParts.map { GmailDataTransformer.makeAttachment(from: $0, messageId: latest.id) }
        }
        return email.attachments
    }

    private var threadMessages: [GmailMessage] {
        let all = detailVM.messages
        guard all.count > 1 else { return [] }
        return Array(all.dropLast())
    }

    private var currentLabelIDs: [String] {
        detailVM.latestMessage?.labelIds ?? email.gmailLabelIDs
    }

    var body: some View {
        VStack(spacing: 0) {
            DetailToolbarView(
                email: email,
                detailVM: detailVM,
                isMailingList: isMailingList,
                resolvedUnsubscribeURL: resolvedUnsubscribeURL,
                oneClick: oneClick,
                alreadyUnsubscribed: alreadyUnsubscribed,
                onArchive: onArchive,
                onDelete: onDelete,
                onMoveToInbox: onMoveToInbox,
                onDeletePermanently: onDeletePermanently,
                onMarkNotSpam: onMarkNotSpam,
                onToggleStar: onToggleStar,
                onMarkUnread: onMarkUnread,
                onReply: onReply,
                onReplyAll: onReplyAll,
                onForward: onForward,
                onShowOriginal: onShowOriginal,
                onDownloadMessage: onDownloadMessage,
                onUnsubscribe: onUnsubscribe,
                onPrint: onPrint,
                replyMode: replyMode,
                replyAllMode: replyAllMode,
                forwardMode: forwardMode,
                didUnsubscribe: $didUnsubscribe
            )

            Divider()
                .background(theme.divider)

            ZStack(alignment: .bottom) {
                if detailVM.isLoading && detailVM.thread == nil {
                    EmailDetailSkeletonView()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            senderHeader
                                .padding(.horizontal, 24)
                                .padding(.top, 24)
                                .padding(.bottom, 16)

                            Text(detailVM.latestMessage?.subject ?? email.subject)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(theme.textPrimary)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 10)

                            LabelEditorView(
                                currentLabelIDs: currentLabelIDs,
                                allLabels: allLabels,
                                detailVM: detailVM,
                                onAddLabel: onAddLabel,
                                onRemoveLabel: onRemoveLabel,
                                onCreateAndAddLabel: onCreateAndAddLabel
                            )
                            .padding(.horizontal, 24)
                            .padding(.bottom, 20)
                            .zIndex(1)

                            if detailVM.hasBlockedTrackers {
                                TrackerBannerView(
                                    trackerCount: detailVM.blockedTrackerCount,
                                    onAllow: { detailVM.allowBlockedContent() }
                                )
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                            }

                            let rawHTML = detailVM.resolvedHTML ?? detailVM.displayHTML ?? detailVM.latestMessage?.htmlBody ?? ""
                            let htmlToRender = rawHTML.isEmpty
                                ? "<p>\(detailVM.latestMessage?.plainBody ?? email.body)</p>"
                                : rawHTML
                            HTMLEmailView(html: htmlToRender, contentHeight: $emailBodyHeight)
                                .frame(height: emailBodyHeight)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 20)

                            if !displayAttachments.isEmpty {
                                attachmentsSection
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 20)
                            }

                            if !threadMessages.isEmpty {
                                threadSection
                                    .padding(.horizontal, 24)
                            }
                        }
                        .padding(.bottom, 72)
                    }
                }

                // Floating reply bar
                ReplyBarView(email: email, accountID: accountID, fromAddress: fromAddress)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(theme.detailBackground)
        .onAppear { loadThread() }
    }

    // MARK: - Compose helpers

    private var quotedHTML: String {
        let original = detailVM.latestMessage?.htmlBody ?? email.body
        return "<br><br><blockquote style='border-left:2px solid #ccc;margin-left:4px;padding-left:8px;color:#555;'><p><b>\(email.sender.name)</b> wrote:</p>\(original)</blockquote>"
    }

    private func replyMode() -> ComposeMode {
        let sub = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
        return .reply(to: email.sender.email, subject: sub, quotedBody: quotedHTML,
                      replyToMessageID: email.gmailMessageID ?? "", threadID: email.gmailThreadID ?? "")
    }

    private func replyAllMode() -> ComposeMode {
        let sub = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
        let extras = email.recipients.map(\.email).filter { $0 != (detailVM.latestMessage?.to ?? email.recipients.first?.email ?? "") }
        let toField = ([email.sender.email] + extras).joined(separator: ", ")
        return .replyAll(to: toField, cc: email.cc.map(\.email).joined(separator: ", "),
                         subject: sub, quotedBody: quotedHTML,
                         replyToMessageID: email.gmailMessageID ?? "", threadID: email.gmailThreadID ?? "")
    }

    private func forwardMode() -> ComposeMode {
        let sub = email.subject.hasPrefix("Fwd:") ? email.subject : "Fwd: \(email.subject)"
        return .forward(subject: sub, quotedBody: quotedHTML)
    }

    // MARK: - Load

    private func loadThread() {
        guard let threadID = email.gmailThreadID else { return }
        detailVM.attachmentIndexer = attachmentIndexer
        Task { await detailVM.loadThread(id: threadID) }
    }

    // MARK: - Attachment preview & download

    private func loadAndPreview(attachment: Attachment, part: GmailMessagePart) {
        Task {
            guard let msgID = detailVM.latestMessage?.id else { return }
            guard let data = try? await detailVM.downloadAttachment(messageID: msgID, part: part) else { return }
            await MainActor.run {
                onPreviewAttachment?(data, attachment.name, attachment.fileType)
            }
        }
    }

    private func downloadAttachment(attachment: Attachment, part: GmailMessagePart) {
        Task {
            do {
                guard let msgID = detailVM.latestMessage?.id else { return }
                let data = try await detailVM.downloadAttachment(messageID: msgID, part: part)
                await MainActor.run { saveAttachmentData(data, named: attachment.name) }
            } catch { }
        }
    }

    private func saveAttachmentData(_ data: Data, named name: String) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? data.write(to: url)
        }
    }

    // MARK: - Sender Header

    private var senderHeader: some View {
        HStack(spacing: 12) {
            AvatarView(
                initials: email.sender.initials,
                color:    email.sender.avatarColor,
                size:     40,
                avatarURL: email.sender.avatarURL,
                senderDomain: email.sender.domain
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(email.sender.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(theme.textPrimary)

                Text(email.sender.email)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .underline(showSenderInfo, color: theme.textTertiary)
                    .onHover { hovering in
                        showSenderInfo = hovering
                    }
                    .popover(isPresented: $showSenderInfo, arrowEdge: .bottom) {
                        if let msg = detailVM.latestMessage {
                            SenderInfoPopover(message: msg, email: email)
                                .environment(\.theme, theme)
                        }
                    }
            }

            Spacer()

            Text(email.date.formattedFull)
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
        }
    }

    // MARK: - Attachments

    private var attachmentPairs: [(Attachment, GmailMessagePart?)] {
        if let latest = detailVM.latestMessage {
            return latest.attachmentParts.map { part in
                (GmailDataTransformer.makeAttachment(from: part, messageId: latest.id), part)
            }
        }
        return email.attachments.map { ($0, nil) }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 12))
                Text("\(displayAttachments.count) Attachment\(displayAttachments.count > 1 ? "s" : "")")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(theme.textSecondary)

            HStack(spacing: 8) {
                ForEach(attachmentPairs, id: \.0.id) { (attachment, part) in
                    AttachmentChipView(
                        attachment: attachment,
                        onPreview: part.map { p in { loadAndPreview(attachment: attachment, part: p) } },
                        onDownload: part.map { p in { downloadAttachment(attachment: attachment, part: p) } }
                    )
                }
            }
        }
    }

    // MARK: - Thread (previous messages)

    private var threadSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(theme.divider)

            ForEach(threadMessages, id: \.id) { message in
                GmailThreadMessageView(message: message)
            }
        }
    }
}
