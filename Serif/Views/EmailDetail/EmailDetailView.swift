import SwiftUI

struct EmailDetailView: View {
    let email: Email
    let accountID: String
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

    @StateObject private var detailVM: EmailDetailViewModel
    @State private var labelSearchText = ""
    @State private var isLabelFieldFocused = false
    @State private var highlightedIndex: Int = 0
    @State private var emailBodyHeight: CGFloat = 100
    @State private var isUnsubscribing = false
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
        extractBodyUnsubscribeURL: ((String) -> URL?)? = nil
    ) {
        self.email              = email
        self.accountID          = accountID
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
        self._detailVM             = StateObject(wrappedValue: EmailDetailViewModel(accountID: accountID))
    }

    // MARK: - Derived content

    private var displayAttachments: [Attachment] {
        if let latest = detailVM.latestMessage {
            return latest.attachmentParts.map(GmailDataTransformer.makeAttachment)
        }
        return email.attachments
    }

    private var threadMessages: [GmailMessage] {
        let all = detailVM.messages
        guard all.count > 1 else { return [] }
        return Array(all.dropLast())
    }

    var body: some View {
        VStack(spacing: 0) {
            detailToolbar

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

                            labelsSection
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

                            let rawHTML = detailVM.displayHTML ?? detailVM.latestMessage?.htmlBody ?? ""
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
                        // Extra bottom padding so content doesn't hide behind the floating bar
                        .padding(.bottom, 72)
                    }
                }

                // Floating reply bar
                ReplyBarView()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(theme.detailBackground)
        .onAppear { loadThread() }
    }

    // MARK: - Label helpers

    private var currentLabelIDs: [String] {
        detailVM.latestMessage?.labelIds ?? email.gmailLabelIDs
    }

    private var currentUserLabels: [GmailLabel] {
        let ids = Set(currentLabelIDs)
        return allLabels.filter { !$0.isSystemLabel && ids.contains($0.id) }
    }

    private var availableUserLabels: [GmailLabel] {
        allLabels.filter { !$0.isSystemLabel }
    }

    private func emailLabel(from gmailLabel: GmailLabel) -> EmailLabel {
        EmailLabel(
            id: GmailDataTransformer.deterministicUUID(from: gmailLabel.id),
            name: gmailLabel.displayName,
            color: gmailLabel.resolvedBgColor,
            textColor: gmailLabel.resolvedTextColor
        )
    }

    private var showDropdown: Bool {
        isLabelFieldFocused && !labelSearchText.trimmingCharacters(in: .whitespaces).isEmpty
            && (!filteredLabels.isEmpty || showCreateOption)
    }

    private var labelsSection: some View {
        HStack(spacing: 6) {
            ForEach(currentUserLabels) { label in
                LabelChipView(label: emailLabel(from: label), isRemovable: true) {
                    let newIDs = currentLabelIDs.filter { $0 != label.id }
                    detailVM.updateLabelIDs(newIDs)
                    onRemoveLabel?(label.id)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                TextField("Add label…", text: $labelSearchText, onEditingChanged: { editing in
                    isLabelFieldFocused = editing
                    if editing { highlightedIndex = 0 }
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(theme.textPrimary)
                .onChange(of: labelSearchText) { _ in highlightedIndex = 0 }
                .onSubmit { confirmHighlighted() }
                .onKeyPress(.downArrow) {
                    highlightedIndex = min(highlightedIndex + 1, dropdownItems.count - 1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlightedIndex = max(highlightedIndex - 1, 0)
                    return .handled
                }
            }
            .frame(minWidth: 80, maxWidth: 160)
            .overlay(alignment: .topLeading) {
                if showDropdown {
                    autocompleteDropdown
                        .offset(y: 24)
                }
            }

            Spacer()
        }
    }

    private var dropdownItems: [DropdownItem] {
        var items: [DropdownItem] = filteredLabels.map { .existing($0) }
        if showCreateOption { items.append(.create(labelSearchText.trimmingCharacters(in: .whitespaces))) }
        return items
    }

    private var autocompleteDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            let items = dropdownItems
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let isHighlighted = index == highlightedIndex
                Button {
                    switch item {
                    case .existing(let label): addLabel(label)
                    case .create: createNewLabel()
                    }
                } label: {
                    Group {
                        switch item {
                        case .existing(let label):
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: label.resolvedBgColor))
                                    .frame(width: 8, height: 8)
                                Text(label.displayName)
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textPrimary)
                                if currentLabelIDs.contains(label.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(theme.accentPrimary)
                                }
                            }
                        case .create(let name):
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.accentPrimary)
                                Text("Create \"\(name)\"")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.accentPrimary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isHighlighted ? theme.hoverBackground : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .background(theme.cardBackground.opacity(0.95))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private func confirmHighlighted() {
        let items = dropdownItems
        guard !items.isEmpty, highlightedIndex < items.count else {
            if showCreateOption { createNewLabel() }
            return
        }
        switch items[highlightedIndex] {
        case .existing(let label): addLabel(label)
        case .create: createNewLabel()
        }
    }

    private var filteredLabels: [GmailLabel] {
        let query = labelSearchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return [] }
        return availableUserLabels.filter { $0.displayName.lowercased().contains(query) }
    }

    private var showCreateOption: Bool {
        let query = labelSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return false }
        return !availableUserLabels.contains { $0.displayName.caseInsensitiveCompare(query) == .orderedSame }
    }

    private func addLabel(_ label: GmailLabel) {
        guard !currentLabelIDs.contains(label.id) else {
            labelSearchText = ""
            return
        }
        var newIDs = currentLabelIDs
        newIDs.append(label.id)
        detailVM.updateLabelIDs(newIDs)
        onAddLabel?(label.id)
        labelSearchText = ""
    }

    private func createNewLabel() {
        let name = labelSearchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        labelSearchText = ""
        onCreateAndAddLabel?(name) { [self] labelID in
            if let labelID {
                var newIDs = currentLabelIDs
                newIDs.append(labelID)
                detailVM.updateLabelIDs(newIDs)
            }
        }
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
            } catch {
                // Silently ignore download errors for now
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

    // MARK: - Toolbar

    private var detailToolbar: some View {
        HStack(spacing: 12) {
            Spacer()

            // Unsubscribe button — only shown for mailing lists
            if isMailingList, let url = resolvedUnsubscribeURL {
                if alreadyUnsubscribed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Unsubscribed")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.hoverBackground)
                    .cornerRadius(6)
                } else {
                    Button {
                        isUnsubscribing = true
                        Task {
                            let msgID = email.gmailMessageID
                            let success = await onUnsubscribe?(url, oneClick, msgID) ?? false
                            isUnsubscribing = false
                            if success { didUnsubscribe = true }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isUnsubscribing {
                                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                            }
                            Text("Unsubscribe")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(theme.destructive)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.destructive.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUnsubscribing)
                    .help(oneClick ? "One-click unsubscribe" : "Open unsubscribe page")
                }

                Divider().frame(height: 16)
            }

            if let onArchive {
                toolbarButton(icon: "archivebox", label: "Archive") { onArchive() }
            }
            if let onDelete {
                toolbarButton(icon: "trash", label: "Delete") { onDelete() }
            }
            if let onMoveToInbox {
                toolbarButton(icon: "tray.and.arrow.down", label: "Move to Inbox") { onMoveToInbox() }
            }

            Divider().frame(height: 16)

            Menu {
                Section {
                    Button { onReply?(replyMode()) }    label: { Label("Reply",     systemImage: "arrowshape.turn.up.left") }
                    Button { onReplyAll?(replyAllMode()) } label: { Label("Reply All", systemImage: "arrowshape.turn.up.left.2") }
                    Button { onForward?(forwardMode()) }  label: { Label("Forward",   systemImage: "arrowshape.turn.up.right") }
                }
                Divider()
                Section {
                    Button { onMarkUnread?() } label: { Label("Mark as Unread",     systemImage: "envelope.badge") }
                    Button {
                        let starred = detailVM.latestMessage?.isStarred ?? email.isStarred
                        detailVM.toggleStar()
                        onToggleStar?(starred)
                    } label: {
                        let starred = detailVM.latestMessage?.isStarred ?? email.isStarred
                        Label(starred ? "Remove from Favorites" : "Add to Favorites", systemImage: starred ? "star.slash" : "star")
                    }
                }
                Divider()
                Section {
                    Button {
                        if let msg = detailVM.latestMessage {
                            onPrint?(msg, email)
                        }
                    } label: { Label("Print", systemImage: "printer") }
                    Button { onDownloadMessage?(detailVM) } label: { Label("Download Message", systemImage: "arrow.down.circle") }
                    Button { onShowOriginal?(detailVM) } label: { Label("Show Original",    systemImage: "doc.text") }
                }
                Divider()
                Section {
                    Button { } label: { Label("Mute Thread",    systemImage: "bell.slash") }
                    Button { } label: { Label("Block Sender",   systemImage: "hand.raised") }
                    if let onMarkNotSpam {
                        Button { onMarkNotSpam() } label: { Label("Not Spam", systemImage: "tray.and.arrow.down") }
                    } else {
                        Button(role: .destructive) { onDelete?() } label: { Label("Report as Spam", systemImage: "exclamationmark.shield") }
                    }
                    if let onDeletePermanently {
                        Button(role: .destructive) { onDeletePermanently() } label: { Label("Delete Permanently", systemImage: "trash.slash") }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("More")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func toolbarButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
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

            Text(email.date.formattedRelative)
                .font(.system(size: 12))
                .foregroundColor(theme.textTertiary)
        }
    }

    // MARK: - Attachments

    /// Pairs each Attachment with its source GmailMessagePart (nil for sample-data attachments).
    private var attachmentPairs: [(Attachment, GmailMessagePart?)] {
        if let latest = detailVM.latestMessage {
            return latest.attachmentParts.map { part in
                (GmailDataTransformer.makeAttachment(from: part), part)
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

    private enum DropdownItem {
        case existing(GmailLabel)
        case create(String)
    }

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

// MARK: - Thread message card (GmailMessage)

private struct GmailThreadMessageView: View {
    let message: GmailMessage
    @Environment(\.theme) private var theme

    private var sender: Contact { GmailDataTransformer.parseContact(message.from) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                AvatarView(initials: sender.initials, color: sender.avatarColor, size: 32,
                           avatarURL: sender.avatarURL, senderDomain: sender.domain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(sender.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.textPrimary)

                    if let date = message.date {
                        Text(date.formattedRelative)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                    }
                }
            }

            Text(message.body.strippingHTML)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
                .lineSpacing(4)
                .padding(.leading, 42)
        }
        .padding(16)
        .background(theme.cardBackground)
        .cornerRadius(10)
    }
}


// MARK: - Sender Info Popover

private struct SenderInfoPopover: View {
    let message: GmailMessage
    let email: Email
    @Environment(\.theme) private var theme

    private var fromDisplay: String {
        let name = email.sender.name
        let addr = email.sender.email
        if name.isEmpty || name == addr { return addr }
        return "\(name) <\(addr)>"
    }

    private var sentByDomain: String? {
        // Display domain from From header (the domain claimed in the "From")
        message.fromDomain
    }

    private var dateFormatted: String {
        if let d = message.date {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            return fmt.string(from: d)
        }
        return "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Message info section
            VStack(spacing: 0) {
                infoRow(label: "From:", value: fromDisplay, suspicious: message.isSuspiciousSender)
                if let domain = sentByDomain {
                    infoRow(label: "sent by:", value: domain)
                }
                infoRow(label: "to:", value: message.to)
                if !message.cc.isEmpty {
                    infoRow(label: "cc:", value: message.cc)
                }
                infoRow(label: "Date:", value: dateFormatted)
                infoRow(label: "Subject:", value: message.subject, multiline: true)
            }

            // Security section
            if message.mailedBy != nil || message.signedBy != nil || message.encryptionInfo != nil {
                Divider()
                    .background(theme.divider)
                    .padding(.vertical, 6)

                VStack(spacing: 0) {
                    if let mailed = message.mailedBy {
                        infoRow(label: "Mailed by:", value: mailed, suspicious: message.isSuspiciousSender)
                    }
                    if let signed = message.signedBy {
                        infoRow(label: "Signed by:", value: signed)
                    }
                    if let encryption = message.encryptionInfo {
                        securityRow(label: "Security:", value: encryption)
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 320, maxWidth: 440)
    }

    private func infoRow(label: String, value: String, suspicious: Bool = false, multiline: Bool = false) -> some View {
        HStack(alignment: multiline ? .top : .center, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(theme.textSecondary)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 8)

            Text(value)
                .font(.system(size: 11, weight: suspicious ? .semibold : .regular))
                .foregroundColor(suspicious ? .red : theme.textPrimary)
                .lineLimit(multiline ? 3 : 1)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    private func securityRow(label: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(theme.textSecondary)
                .frame(width: 72, alignment: .trailing)
                .padding(.trailing, 8)

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.green)
                Text(value)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textPrimary)
            }

            Spacer()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - HTML stripping

extension String {
    var strippingHTML: String {
        var result = self
        // Remove style/script blocks first
        result = result.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>",  with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        // Replace block tags with newlines
        result = result.replacingOccurrences(of: "<br\\s*/?>",  with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "<p[^>]*>",    with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</p>",         with: "")
        result = result.replacingOccurrences(of: "<div[^>]*>",  with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: "</div>",       with: "")
        // Strip remaining tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&nbsp;",  with: " ")
        result = result.replacingOccurrences(of: "&lt;",    with: "<")
        result = result.replacingOccurrences(of: "&gt;",    with: ">")
        result = result.replacingOccurrences(of: "&amp;",   with: "&")
        result = result.replacingOccurrences(of: "&quot;",  with: "\"")
        result = result.replacingOccurrences(of: "&#39;",   with: "'")
        // Collapse multiple blank lines
        result = result.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Detail Skeleton

private struct EmailDetailSkeletonView: View {
    @Environment(\.theme) private var theme
    @State private var animate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Sender header
                HStack(spacing: 12) {
                    Circle()
                        .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 6) {
                        bar(width: 140, height: 11)
                        bar(width: 190, height: 9)
                    }
                    Spacer()
                    bar(width: 55, height: 9)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)

                // Subject
                bar(width: 260, height: 16)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                // Body lines
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in bar(height: 11) }
                    bar(width: 220, height: 11)
                    Spacer().frame(height: 6)
                    ForEach(0..<4, id: \.self) { _ in bar(height: 11) }
                    bar(width: 160, height: 11)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }

    private func bar(width: CGFloat? = nil, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(theme.textTertiary.opacity(animate ? 0.1 : 0.2))
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}
