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
    var onPreviewAttachment: ((Data?, String, Attachment.FileType) -> Void)?
    var onShowOriginal: ((EmailDetailViewModel) -> Void)?
    var onDownloadMessage: ((EmailDetailViewModel) -> Void)?
    var onUnsubscribe: ((URL, Bool, String?) async -> Bool)?
    var onPrint: ((GmailMessage, Email) -> Void)?
    var checkUnsubscribed: ((String) -> Bool)?
    var extractBodyUnsubscribeURL: ((String) -> URL?)?
    var onOpenLink: ((URL) -> Void)?
    var fromAddress: String = ""
    var mailStore: MailStore?
    var coordinator: AppCoordinator?

    @StateObject private var detailVM: EmailDetailViewModel
    @State private var emailBodyHeight: CGFloat = 100
    @State private var didUnsubscribe = false
    @State private var showSenderInfo = false
    @State private var showOriginalInviteEmail = false
    @State private var showQuotedMain = false
    @State private var labelSuggestions: [LabelSuggestion] = []
    @State private var showForwardAttachmentAlert = false
    @AppStorage("aiLabelSuggestions") private var aiLabelSuggestionsEnabled = true
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
        onPreviewAttachment:   ((Data?, String, Attachment.FileType) -> Void)? = nil,
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

    /// Reply messages in the thread (everything after the original). Empty for single messages.
    private var olderThreadMessages: [GmailMessage] {
        let all = detailVM.messages
        guard all.count > 1 else { return [] }
        return Array(all.dropFirst())
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
                onForward: { mode in
                    if email.hasAttachments {
                        showForwardAttachmentAlert = true
                    } else {
                        onForward?(mode)
                    }
                },
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
                            .padding(.bottom, labelSuggestions.isEmpty ? 20 : 6)
                            .zIndex(1)

                            if !labelSuggestions.isEmpty {
                                HStack(spacing: 4) {
                                    ForEach(labelSuggestions, id: \.name) { suggestion in
                                        Button {
                                            applyLabelSuggestion(suggestion)
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: suggestion.isNew ? "plus.circle" : "plus")
                                                    .font(.system(size: 7, weight: .semibold))
                                                Text(suggestion.name)
                                                    .font(.system(size: 10))
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(theme.accentPrimary.opacity(0.08))
                                            .foregroundColor(theme.accentPrimary.opacity(0.7))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.bottom, 16)
                                .animation(.easeOut(duration: 0.25), value: labelSuggestions.map(\.name))
                            }

                            if detailVM.hasBlockedTrackers {
                                TrackerBannerView(
                                    trackerCount: detailVM.blockedTrackerCount,
                                    trackers: detailVM.trackerResult?.trackers ?? [],
                                    onAllow: { detailVM.allowBlockedContent() }
                                )
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                            }

                            if let invite = detailVM.calendarInvite {
                                CalendarInviteCardView(
                                    invite: invite,
                                    isLoading: detailVM.rsvpInProgress,
                                    showOriginalEmail: $showOriginalInviteEmail,
                                    onAccept:  { Task { await detailVM.sendRSVP(.accepted) } },
                                    onDecline: { Task { await detailVM.sendRSVP(.declined) } },
                                    onMaybe:   { Task { await detailVM.sendRSVP(.maybe) } }
                                )
                                .padding(.horizontal, 24)
                                .padding(.bottom, 12)
                            }

                            // Original message: full HTML rendering with quote stripping
                            if detailVM.calendarInvite == nil || showOriginalInviteEmail {
                                let rawHTML = detailVM.resolvedHTML ?? detailVM.displayHTML ?? detailVM.latestMessage?.htmlBody ?? ""
                                let fullHTML = rawHTML.isEmpty
                                    ? "<p>\(GmailThreadMessageView.escapeAndBreak(detailVM.latestMessage?.plainBody ?? email.body))</p>"
                                    : rawHTML
                                let parts = GmailThreadMessageView.stripQuotedHTML(fullHTML)
                                let htmlToRender = (showQuotedMain || parts.quoted == nil) ? fullHTML : parts.original

                                HTMLEmailView(html: htmlToRender, contentHeight: $emailBodyHeight, onOpenLink: onOpenLink, backgroundColor: theme.detailBackground.hexString)
                                    .frame(height: emailBodyHeight)
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, parts.quoted != nil ? 4 : 20)

                                if parts.quoted != nil {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            showQuotedMain.toggle()
                                        }
                                    } label: {
                                        Text(showQuotedMain ? "Hide quoted" : "···")
                                            .font(.system(size: showQuotedMain ? 11 : 14, weight: showQuotedMain ? .medium : .bold))
                                            .foregroundColor(theme.textTertiary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Capsule().fill(theme.hoverBackground))
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 20)
                                }
                            }

                            if !displayAttachments.isEmpty {
                                attachmentsSection
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 20)
                            }

                            // Thread replies as chat bubbles (chronological order)
                            if !olderThreadMessages.isEmpty {
                                conversationSection
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 12)
                            }
                        }
                        .padding(.bottom, 72)
                    }
                    .task(id: email.id) {
                        labelSuggestions = []
                        guard aiLabelSuggestionsEnabled else { return }
                        let suggestions = await LabelSuggestionService.shared.generateSuggestions(
                            for: email,
                            existingLabels: allLabels
                        )
                        withAnimation { labelSuggestions = suggestions }
                    }
                }

                // Floating reply bar
                ReplyBarView(email: email, accountID: accountID, fromAddress: fromAddress, mailStore: mailStore ?? MailStore(), coordinator: coordinator ?? AppCoordinator(), onOpenLink: onOpenLink)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(theme.detailBackground)
        .alert("Forward Attachments?", isPresented: $showForwardAttachmentAlert) {
            Button("Include Attachments") {
                // TODO: Download and attach — for now forward without
                onForward?(forwardMode())
            }
            Button("Without Attachments") {
                onForward?(forwardMode())
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This email has attachments. Would you like to include them in the forward?")
        }
        .onAppear { loadThread() }
    }

    // MARK: - Compose helpers

    private var quotedHTML: String {
        let original = detailVM.resolvedHTML ?? detailVM.latestMessage?.htmlBody ?? email.body
        return QuoteFormatter.formatReplyQuote(
            senderName: email.sender.name,
            senderEmail: email.sender.email,
            date: email.date,
            originalHTML: original
        )
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
        let original = detailVM.resolvedHTML ?? detailVM.latestMessage?.htmlBody ?? email.body
        let forwardQuote = QuoteFormatter.formatForwardQuote(
            senderName: email.sender.name,
            senderEmail: email.sender.email,
            date: email.date,
            to: email.recipients.map(\.email).joined(separator: ", "),
            subject: email.subject,
            originalHTML: original
        )
        return .forward(subject: sub, quotedBody: forwardQuote)
    }

    // Per-message compose modes (for thread bubble actions)
    private func replyMode(for message: GmailMessage) -> ComposeMode {
        let sender = GmailDataTransformer.parseContact(message.from)
        let subj = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        let quote = QuoteFormatter.formatReplyQuote(
            senderName: sender.name,
            senderEmail: sender.email,
            date: message.date ?? Date(),
            originalHTML: message.htmlBody ?? message.plainBody ?? ""
        )
        return .reply(to: sender.email, subject: subj, quotedBody: quote,
                      replyToMessageID: message.id, threadID: message.threadId)
    }

    private func replyAllMode(for message: GmailMessage) -> ComposeMode {
        let sender = GmailDataTransformer.parseContact(message.from)
        let subj = message.subject.hasPrefix("Re:") ? message.subject : "Re: \(message.subject)"
        let toContacts = GmailDataTransformer.parseContacts(message.to)
        let ccContacts = GmailDataTransformer.parseContacts(message.cc)
        let extras = toContacts.map(\.email).filter { $0.lowercased() != fromAddress.lowercased() }
        let toField = ([sender.email] + extras).joined(separator: ", ")
        let quote = QuoteFormatter.formatReplyQuote(
            senderName: sender.name,
            senderEmail: sender.email,
            date: message.date ?? Date(),
            originalHTML: message.htmlBody ?? message.plainBody ?? ""
        )
        return .replyAll(to: toField, cc: ccContacts.map(\.email).joined(separator: ", "),
                         subject: subj, quotedBody: quote,
                         replyToMessageID: message.id, threadID: message.threadId)
    }

    private func forwardMode(for message: GmailMessage) -> ComposeMode {
        let sender = GmailDataTransformer.parseContact(message.from)
        let toContacts = GmailDataTransformer.parseContacts(message.to)
        let subj = message.subject.hasPrefix("Fwd:") ? message.subject : "Fwd: \(message.subject)"
        let quote = QuoteFormatter.formatForwardQuote(
            senderName: sender.name,
            senderEmail: sender.email,
            date: message.date ?? Date(),
            to: toContacts.map(\.email).joined(separator: ", "),
            subject: message.subject,
            originalHTML: message.htmlBody ?? message.plainBody ?? ""
        )
        return .forward(subject: subj, quotedBody: quote)
    }

    // MARK: - Load

    private func loadThread() {
        guard let threadID = email.gmailThreadID else { return }
        detailVM.attachmentIndexer = attachmentIndexer
        Task { await detailVM.loadThread(id: threadID) }
    }

    private func applyLabelSuggestion(_ suggestion: LabelSuggestion) {
        withAnimation { labelSuggestions.removeAll { $0.name == suggestion.name } }
        if suggestion.isNew {
            onCreateAndAddLabel?(suggestion.name) { _ in }
        } else if let label = allLabels.first(where: { $0.displayName == suggestion.name }) {
            var newIDs = currentLabelIDs
            newIDs.append(label.id)
            detailVM.updateLabelIDs(newIDs)
            onAddLabel?(label.id)
        }
    }

    // MARK: - Attachment preview & download

    private func loadAndPreview(attachment: Attachment, part: GmailMessagePart) {
        onPreviewAttachment?(nil, attachment.name, attachment.fileType)
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
            } catch {
                ToastManager.shared.show(message: "Download failed: \(error.localizedDescription)", type: .error)
            }
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

    // MARK: - Conversation (older thread messages as chat bubbles)

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(theme.divider)

            VStack(spacing: 12) {
                ForEach(olderThreadMessages, id: \.id) { message in
                    GmailThreadMessageView(
                        message: message,
                        fromAddress: fromAddress,
                        resolvedHTML: detailVM.resolvedMessageHTML[message.id],
                        onOpenLink: onOpenLink,
                        onReply: { onReply?(replyMode(for: message)) },
                        onReplyAll: { onReplyAll?(replyAllMode(for: message)) },
                        onForward: { onForward?(forwardMode(for: message)) },
                        onToggleStar: {
                            guard let coordinator else { return }
                            let isStarred = message.labelIds?.contains("STARRED") ?? false
                            Task { await coordinator.mailboxViewModel.toggleStar(message.id, isStarred: isStarred) }
                        },
                        onMarkUnread: {
                            guard let coordinator else { return }
                            Task { await coordinator.mailboxViewModel.markAsUnread(message.id) }
                        },
                        onArchive: {
                            guard let coordinator else { return }
                            Task {
                                await coordinator.mailboxViewModel.archive(message.id)
                                if let threadID = email.gmailThreadID { await detailVM.loadThread(id: threadID) }
                            }
                        },
                        onTrash: {
                            guard let coordinator else { return }
                            Task {
                                await coordinator.mailboxViewModel.trash(message.id, threadID: nil)
                                if let threadID = email.gmailThreadID { await detailVM.loadThread(id: threadID) }
                            }
                        },
                        onSpam: {
                            guard let coordinator else { return }
                            Task {
                                await coordinator.mailboxViewModel.spam(message.id)
                                if let threadID = email.gmailThreadID { await detailVM.loadThread(id: threadID) }
                            }
                        }
                    )
                }
            }
        }
    }
}
