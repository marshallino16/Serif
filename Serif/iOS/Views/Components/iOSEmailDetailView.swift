import SwiftUI
import WebKit

// MARK: - Quoted HTML Stripping (shared logic with macOS GmailThreadMessageView)

private enum HTMLQuoteStripper {
    /// Removes quoted/replied content from HTML, returning (original, quoted?).
    /// Detects Gmail, Outlook, Apple Mail, and generic patterns.
    static func stripQuotedHTML(_ html: String) -> (original: String, quoted: String?) {
        // 1. Gmail: <div class="gmail_quote"> or <div class="gmail_quote_container">
        if let range = html.range(of: #"<div\s+class\s*=\s*"[^"]*gmail_quote[^"]*""#,
                                  options: .regularExpression) {
            let before = String(html[html.startIndex..<range.lowerBound])
            let after = String(html[range.lowerBound...])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (before, after)
            }
        }

        // 2. Outlook: <div id="divRplyFwdMsg"> or <div id="appendonsend">
        for pattern in [
            #"<div\s+id\s*=\s*"divRplyFwdMsg""#,
            #"<div\s+id\s*=\s*"appendonsend""#,
        ] {
            if let range = html.range(of: pattern, options: .regularExpression) {
                let before = String(html[html.startIndex..<range.lowerBound])
                let after = String(html[range.lowerBound...])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, after)
                }
            }
        }

        // 2b. Outlook border-top separator
        if let range = html.range(of: #"<div\s+style\s*=\s*"[^"]*border-top\s*:\s*solid[^"]*"[^>]*>"#,
                                  options: .regularExpression) {
            let afterStart = range.lowerBound
            let lookAhead = String(html[afterStart..<html.index(afterStart, offsetBy: min(500, html.distance(from: afterStart, to: html.endIndex)))])
            if lookAhead.range(of: #"(De|From)(\s|&nbsp;|;)*\s*:"#, options: .regularExpression) != nil {
                let before = String(html[html.startIndex..<range.lowerBound])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, String(html[range.lowerBound...]))
                }
            }
        }

        // 3. "On ... wrote:" / "Le ... a ecrit" patterns
        let attrPatterns = [
            #"<div[^>]*class\s*=\s*"[^"]*gmail_attr[^"]*"[^>]*>.*?</div>\s*<blockquote"#,
            #"On\s.+wrote\s*:"#,
            #"Le\s.+a\s+(é|e)crit\s*:"#,
        ]
        for pattern in attrPatterns {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let before = String(html[html.startIndex..<range.lowerBound])
                let after = String(html[range.lowerBound...])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, after)
                }
            }
        }

        // 4. Outlook FR/EN header block
        let headerPatterns = [
            #"<b>De(\s|&nbsp;)*:</\s*b>"#,
            #"<b>From(\s|&nbsp;)*:</\s*b>"#,
            #"-----\s*Original Message\s*-----"#,
            #"-----\s*Message d['']origine\s*-----"#,
            #"---------- Forwarded message ----------"#,
        ]
        for pattern in headerPatterns {
            if let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let before = String(html[html.startIndex..<range.lowerBound])
                let after = String(html[range.lowerBound...])
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (before, after)
                }
            }
        }

        // 5. Generic <blockquote> as last resort
        if let range = html.range(of: #"<blockquote[\s>]"#, options: [.regularExpression, .backwards]) {
            let before = String(html[html.startIndex..<range.lowerBound])
            let afterLen = html[range.lowerBound...].count
            if afterLen > html.count * 3 / 10 &&
               !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (before, String(html[range.lowerBound...]))
            }
        }

        return (html, nil)
    }
}

// MARK: - Main Detail View

struct iOSEmailDetailView: View {
    let email: Email
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @StateObject private var detailVM: EmailDetailViewModel
    @State private var emailBodyHeight: CGFloat = 100
    @State private var showSenderInfoSheet = false
    @State private var showOriginalInviteEmail = false
    @State private var showQuotedMain = false
    @State private var avatarImage: PlatformImage?
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var composeModeToPresent: ComposeMode?
    @State private var showForwardAttachmentAlert = false
    @State private var forwardAttachmentURLs: [URL] = []
    @State private var showLabelSheet = false
    @State private var expandQuickReply = false
    @State private var labelSuggestions: [LabelSuggestion] = []
    @State private var previewAttachmentData: Data?
    @State private var previewAttachmentName: String = ""
    @State private var previewAttachmentType: Attachment.FileType = .document
    @State private var showAttachmentPreview = false
    @AppStorage("aiLabelSuggestions") private var aiLabelSuggestionsEnabled = true

    init(email: Email, coordinator: AppCoordinator) {
        self.email = email
        self.coordinator = coordinator
        self._detailVM = StateObject(wrappedValue: EmailDetailViewModel(accountID: coordinator.accountID))
    }

    /// Live version of the email from the coordinator (reflects star/read/label changes).
    private var liveEmail: Email {
        if let msgID = email.gmailMessageID {
            return coordinator.mailboxViewModel.emails.first(where: { $0.gmailMessageID == msgID }) ?? email
        }
        return email
    }

    // MARK: - Derived content

    private var hasMultipleRecipients: Bool {
        email.recipients.count > 1 || !email.cc.isEmpty
    }

    private var isMailingList: Bool {
        detailVM.latestMessage?.isFromMailingList ?? email.isFromMailingList
            || detailVM.latestMessage?.unsubscribeURL != nil
            || email.unsubscribeURL != nil
    }

    private var displayAttachments: [Attachment] {
        if let latest = detailVM.latestMessage {
            return latest.attachmentParts.map { GmailDataTransformer.makeAttachment(from: $0, messageId: latest.id) }
        }
        return email.attachments
    }

    private var olderThreadMessages: [GmailMessage] {
        let all = detailVM.messages
        guard all.count > 1 else { return [] }
        return Array(all.dropLast())
    }

    private var attachmentPairs: [(Attachment, GmailMessagePart?)] {
        if let latest = detailVM.latestMessage {
            return latest.attachmentParts.map { part in
                (GmailDataTransformer.makeAttachment(from: part, messageId: latest.id), part)
            }
        }
        return email.attachments.map { ($0, nil) }
    }

    private var currentUserLabels: [GmailLabel] {
        let ids = Set(email.gmailLabelIDs)
        return coordinator.mailboxViewModel.labels.filter { !$0.isSystemLabel && ids.contains($0.id) }
    }

    private func emailLabel(from gmailLabel: GmailLabel) -> EmailLabel {
        EmailLabel(
            id: UUID(),
            name: gmailLabel.displayName,
            color: gmailLabel.resolvedBgColor,
            textColor: gmailLabel.resolvedTextColor
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if detailVM.isLoading && detailVM.thread == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Sender header
                        senderHeader
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 12)

                        // Subject
                        Text(detailVM.latestMessage?.subject ?? email.subject)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(theme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, currentUserLabels.isEmpty ? 16 : 8)

                        // Labels
                        if !currentUserLabels.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(currentUserLabels) { label in
                                        LabelChipView(
                                            label: emailLabel(from: label),
                                            isRemovable: true
                                        ) {
                                            let newIDs = email.gmailLabelIDs.filter { $0 != label.id }
                                            detailVM.updateLabelIDs(newIDs)
                                            if let msgID = email.gmailMessageID {
                                                Task {
                                                    await coordinator.mailboxViewModel.removeLabel(label.id, from: msgID)
                                                }
                                            }
                                        }
                                    }

                                    Button {
                                        showLabelSheet = true
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 9, weight: .bold))
                                            Text("Add")
                                                .font(.system(size: 10, weight: .medium))
                                        }
                                        .foregroundColor(theme.textTertiary)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().strokeBorder(theme.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, labelSuggestions.isEmpty ? 12 : 4)
                        }

                        // AI Label Suggestions
                        if !labelSuggestions.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(labelSuggestions, id: \.name) { suggestion in
                                        Button {
                                            applyLabelSuggestion(suggestion)
                                        } label: {
                                            HStack(spacing: 3) {
                                                Image(systemName: suggestion.isNew ? "plus.circle" : "plus")
                                                    .font(.system(size: 9, weight: .semibold))
                                                Text(suggestion.name)
                                                    .font(.system(size: 11, weight: .medium))
                                            }
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(theme.accentPrimary.opacity(0.08))
                                            .foregroundColor(theme.accentPrimary.opacity(0.7))
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                            .animation(.easeOut(duration: 0.25), value: labelSuggestions.map(\.name))
                        }

                        // Tracker banner
                        if detailVM.hasBlockedTrackers {
                            iOSTrackerBannerView(
                                trackerCount: detailVM.blockedTrackerCount,
                                trackers: detailVM.trackerResult?.trackers ?? [],
                                onAllow: { detailVM.allowBlockedContent() }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }

                        // Calendar invite card
                        if let invite = detailVM.calendarInvite {
                            iOSCalendarInviteCardView(
                                invite: invite,
                                isLoading: detailVM.rsvpInProgress,
                                showOriginalEmail: $showOriginalInviteEmail,
                                onAccept:  { Task { await detailVM.sendRSVP(.accepted) } },
                                onDecline: { Task { await detailVM.sendRSVP(.declined) } },
                                onMaybe:   { Task { await detailVM.sendRSVP(.maybe) } }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }

                        // HTML body
                        if detailVM.calendarInvite == nil || showOriginalInviteEmail {
                            let rawHTML = detailVM.resolvedHTML ?? detailVM.displayHTML ?? detailVM.latestMessage?.htmlBody ?? ""
                            let fullHTML = rawHTML.isEmpty
                                ? "<p>\(Self.plainToHTML(detailVM.latestMessage?.plainBody ?? email.preview))</p>"
                                : rawHTML
                            let parts = HTMLQuoteStripper.stripQuotedHTML(fullHTML)
                            let htmlToRender = (showQuotedMain || parts.quoted == nil) ? fullHTML : parts.original

                            iOSHTMLEmailView(html: htmlToRender, contentHeight: $emailBodyHeight, theme: theme)
                                .frame(height: emailBodyHeight)
                                .padding(.horizontal, 16)
                                .padding(.bottom, parts.quoted != nil ? 4 : 16)

                            if parts.quoted != nil {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showQuotedMain.toggle()
                                    }
                                } label: {
                                    Text(showQuotedMain ? "Hide quoted" : "\u{2026}")
                                        .font(.system(size: showQuotedMain ? 12 : 16, weight: showQuotedMain ? .medium : .bold))
                                        .foregroundColor(theme.textTertiary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Capsule().fill(theme.hoverBackground))
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                            }
                        }

                        // Attachments
                        if !displayAttachments.isEmpty {
                            attachmentsSection
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        }

                        // Older thread messages
                        if !olderThreadMessages.isEmpty {
                            conversationSection
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                    }
                    .padding(.bottom, 80) // space for quick reply bar
                }
            }

            // Quick reply bar (pinned at bottom)
            VStack(spacing: 0) {
                iOSQuickReplyView(
                    email: email,
                    accountID: coordinator.accountID,
                    fromAddress: coordinator.fromAddress,
                    mailStore: coordinator.mailStore,
                    expandTrigger: $expandQuickReply
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
        }
        .background(theme.detailBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if isMailingList {
                    Button {
                        coordinator.actionCoordinator.unsubscribeEmail(email)
                    } label: {
                        Text("Unsubscribe")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(theme.destructive)
                    }
                }

                Menu {
                    Button {
                        expandQuickReply = true
                    } label: {
                        Label(hasMultipleRecipients ? "Reply All" : "Reply",
                              systemImage: hasMultipleRecipients ? "arrowshape.turn.up.left.2" : "arrowshape.turn.up.left")
                    }
                    if hasMultipleRecipients {
                        Button {
                            composeModeToPresent = replyMode()
                        } label: {
                            Label("Reply", systemImage: "arrowshape.turn.up.left")
                        }
                    } else {
                        Button {
                            composeModeToPresent = replyAllMode()
                        } label: {
                            Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                        }
                    }
                    Button {
                        if email.hasAttachments {
                            showForwardAttachmentAlert = true
                        } else {
                            composeModeToPresent = forwardMode()
                        }
                    } label: {
                        Label("Forward", systemImage: "arrowshape.turn.up.right")
                    }
                } label: {
                    Image(systemName: hasMultipleRecipients ? "arrowshape.turn.up.left.2" : "arrowshape.turn.up.left")
                }

                Menu {
                    Button {
                        coordinator.actionCoordinator.archiveEmail(email) { next in
                            coordinator.selectNext(next)
                        }
                        dismiss()
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }

                    Button(role: .destructive) {
                        coordinator.actionCoordinator.deleteEmail(email) { next in
                            coordinator.selectNext(next)
                        }
                        dismiss()
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }

                    Divider()

                    Button {
                        coordinator.actionCoordinator.toggleStarEmail(liveEmail)
                    } label: {
                        Label(
                            liveEmail.isStarred ? "Remove Star" : "Add Star",
                            systemImage: liveEmail.isStarred ? "star.slash" : "star"
                        )
                    }

                    Button {
                        if email.isRead {
                            coordinator.actionCoordinator.markUnreadEmail(email)
                        }
                    } label: {
                        Label("Mark as Unread", systemImage: "envelope.badge")
                    }

                    Divider()

                    Button {
                        showLabelSheet = true
                    } label: {
                        Label("Labels", systemImage: "tag")
                    }

                    Button {
                        printEmail()
                    } label: {
                        Label("Print", systemImage: "printer")
                    }

                    Button {
                        showSenderInfoSheet = true
                    } label: {
                        Label("Message Details", systemImage: "info.circle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        coordinator.actionCoordinator.markSpamEmail(email) { next in
                            coordinator.selectNext(next)
                        }
                        dismiss()
                    } label: {
                        Label("Report as Spam", systemImage: "exclamationmark.shield")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSenderInfoSheet) {
            if let msg = detailVM.latestMessage {
                NavigationStack {
                    iOSSenderInfoSheet(message: msg, email: email)
                        .environment(\.theme, theme)
                        .navigationTitle("Message Details")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showSenderInfoSheet = false }
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showShareSheet) {
            iOSShareSheet(items: shareItems)
        }
        .sheet(isPresented: Binding(
            get: { composeModeToPresent != nil },
            set: { if !$0 { composeModeToPresent = nil } }
        )) {
            if let mode = composeModeToPresent {
                iOSComposeView(
                    accountID: coordinator.accountID,
                    fromAddress: coordinator.fromAddress,
                    mode: mode,
                    initialAttachmentURLs: forwardAttachmentURLs,
                    onDismiss: {
                        composeModeToPresent = nil
                        forwardAttachmentURLs = []
                    }
                )
            }
        }
        .sheet(isPresented: $showLabelSheet) {
            iOSLabelManagementSheet(
                email: email,
                detailVM: detailVM,
                coordinator: coordinator
            )
            .environment(\.theme, theme)
        }
        .sheet(isPresented: $showAttachmentPreview) {
            if let data = previewAttachmentData {
                iOSAttachmentPreviewView(
                    data: data,
                    fileName: previewAttachmentName,
                    fileType: previewAttachmentType,
                    onShare: {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(previewAttachmentName)
                        try? data.write(to: tempURL)
                        shareItems = [tempURL]
                        showAttachmentPreview = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showShareSheet = true
                        }
                    }
                )
                .environment(\.theme, theme)
            }
        }
        .alert("Forward Attachments?", isPresented: $showForwardAttachmentAlert) {
            Button("Include Attachments") {
                Task { await forwardWithAttachments() }
            }
            Button("Without Attachments") {
                forwardAttachmentURLs = []
                composeModeToPresent = forwardMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This email has attachments. Would you like to include them in the forward?")
        }
        .onAppear { loadThread() }
        .task(id: email.id) {
            // Auto-mark as read
            if !email.isRead, let msgID = email.gmailMessageID,
               let msg = coordinator.mailboxViewModel.messages.first(where: { $0.id == msgID }) {
                await coordinator.mailboxViewModel.markAsRead(msg)
            }

            // AI label suggestions
            labelSuggestions = []
            if aiLabelSuggestionsEnabled {
                let suggestions = await LabelSuggestionService.shared.generateSuggestions(
                    for: email,
                    existingLabels: coordinator.mailboxViewModel.labels
                )
                withAnimation { labelSuggestions = suggestions }
            }
        }
        .task(id: email.sender.email) {
            await loadAvatar()
        }
    }

    // MARK: - Load

    private func loadThread() {
        guard let threadID = email.gmailThreadID else { return }
        Task { await detailVM.loadThread(id: threadID) }
    }

    private func applyLabelSuggestion(_ suggestion: LabelSuggestion) {
        withAnimation { labelSuggestions.removeAll { $0.name == suggestion.name } }
        if suggestion.isNew {
            if let msgID = email.gmailMessageID {
                Task {
                    await coordinator.mailboxViewModel.createAndAddLabel(name: suggestion.name, to: msgID)
                }
            }
        } else if let label = coordinator.mailboxViewModel.labels.first(where: { $0.displayName == suggestion.name }),
                  let msgID = email.gmailMessageID {
            Task {
                await coordinator.mailboxViewModel.addLabel(label.id, to: msgID)
            }
        }
    }

    // MARK: - Avatar Loading

    private func loadAvatar() async {
        if let url = email.sender.avatarURL, let img = await AvatarCache.shared.image(for: url) {
            avatarImage = img
            return
        }
        if let domain = email.sender.domain {
            if let bimiURL = await BIMIService.shared.logoURL(for: domain),
               let img = await AvatarCache.shared.image(for: bimiURL) {
                avatarImage = img
            }
        }
    }

    // MARK: - Compose Helpers

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

    private func forwardWithAttachments() async {
        var urls: [URL] = []
        if let msgID = detailVM.latestMessage?.id {
            for (att, part) in attachmentPairs {
                guard let part else { continue }
                do {
                    let data = try await detailVM.downloadAttachment(messageID: msgID, part: part)
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(att.name)
                    try data.write(to: tempURL)
                    urls.append(tempURL)
                } catch {}
            }
        }
        await MainActor.run {
            forwardAttachmentURLs = urls
            composeModeToPresent = forwardMode()
        }
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

    // MARK: - Print

    private func printEmail() {
        let htmlContent = detailVM.resolvedHTML ?? detailVM.displayHTML ?? detailVM.latestMessage?.htmlBody ?? email.body
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = email.subject
        printInfo.outputType = .general
        let formatter = UIMarkupTextPrintFormatter(markupText: htmlContent)
        formatter.perPageContentInsets = UIEdgeInsets(top: 72, left: 72, bottom: 72, right: 72)
        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printFormatter = formatter
        controller.present(animated: true)
    }

    // MARK: - Sender Header

    private var senderHeader: some View {
        Button {
            showSenderInfoSheet = true
        } label: {
            HStack(spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color(hex: email.sender.avatarColor))
                        .frame(width: 44, height: 44)

                    if let img = avatarImage {
                        platformImage(img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        Text(email.sender.initials)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(email.sender.name.isEmpty ? email.sender.email : email.sender.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)

                        if liveEmail.isStarred {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.yellow)
                        }

                        Spacer()

                        Text(email.date.formattedFull)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textTertiary)
                            .layoutPriority(1)
                    }

                    Text(email.sender.email)
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                        .lineLimit(1)
                }
                .foregroundColor(theme.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Attachments

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 13))
                Text("\(displayAttachments.count) Attachment\(displayAttachments.count > 1 ? "s" : "")")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachmentPairs, id: \.0.id) { (attachment, part) in
                        iOSAttachmentChipView(
                            attachment: attachment,
                            onTap: {
                                if let part = part {
                                    if attachment.fileType.isPreviewable {
                                        downloadAndPreview(attachment: attachment, part: part)
                                    } else {
                                        downloadAndShare(attachment: attachment, part: part)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Conversation

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .background(theme.divider)

            Text("Earlier messages")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textTertiary)

            VStack(spacing: 12) {
                ForEach(olderThreadMessages, id: \.id) { message in
                    iOSThreadMessageView(
                        message: message,
                        fromAddress: coordinator.fromAddress,
                        resolvedHTML: detailVM.resolvedMessageHTML[message.id],
                        theme: theme
                    )
                }
            }
        }
    }

    // MARK: - Attachment download & share

    private func downloadAndPreview(attachment: Attachment, part: GmailMessagePart) {
        Task {
            do {
                guard let msgID = detailVM.latestMessage?.id else { return }
                let data = try await detailVM.downloadAttachment(messageID: msgID, part: part)
                await MainActor.run {
                    previewAttachmentData = data
                    previewAttachmentName = attachment.name
                    previewAttachmentType = attachment.fileType
                    showAttachmentPreview = true
                }
            } catch {}
        }
    }

    private func downloadAndShare(attachment: Attachment, part: GmailMessagePart) {
        Task {
            do {
                guard let msgID = detailVM.latestMessage?.id else { return }
                let data = try await detailVM.downloadAttachment(messageID: msgID, part: part)
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(attachment.name)
                try data.write(to: tempURL)
                await MainActor.run {
                    shareItems = [tempURL]
                    showShareSheet = true
                }
            } catch {
                // Download failed silently — could add toast here
            }
        }
    }

    // MARK: - Helpers

    private static func plainToHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func platformImage(_ img: PlatformImage) -> Image {
        #if os(macOS)
        Image(nsImage: img)
        #else
        Image(uiImage: img)
        #endif
    }
}

// MARK: - iOS HTML Email View (WKWebView)

struct iOSHTMLEmailView: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    let theme: Theme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "imageLog")
        config.dataDetectorTypes = [.phoneNumber, .link, .address, .calendarEvent]
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let textHex = theme.textPrimary.hexString
        let cacheKey = "\(html)|\(textHex)"
        guard context.coordinator.lastCacheKey != cacheKey else { return }
        context.coordinator.lastCacheKey = cacheKey

        let preferredSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let baseFontSize = max(14, min(Int(preferredSize), 28))

        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name='viewport' content='width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover'>
        <meta name='color-scheme' content='light dark'>
        <style>
        html, body {
            margin: 0;
            padding: 0;
            overflow: hidden;
        }
        html {
            touch-action: manipulation;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: \(baseFontSize)px;
            line-height: 1.6;
            color: \(textHex);
            background-color: transparent;
            word-wrap: break-word;
            overflow-wrap: break-word;
            -webkit-text-size-adjust: 100%;
            -webkit-font-smoothing: antialiased;
            text-rendering: optimizeLegibility;
            padding: 0 4px;
        }
        /* Force all elements to fit mobile width */
        * { box-sizing: border-box; max-width: 100% !important; }
        img { max-width: 100% !important; height: auto !important; content-visibility: auto; }
        /* Tables: fit within viewport without breaking layout */
        table { border-collapse: collapse; max-width: 100% !important; }
        td, th { word-wrap: break-word; overflow-wrap: break-word; }
        /* Links: larger touch target */
        a { color: #1a73e8; padding: 2px 0; -webkit-tap-highlight-color: rgba(0,0,0,0.1); }
        /* Minimum font size for readability */
        p, div, span, td, li { font-size: inherit; min-height: 0; }
        small, .small { font-size: 13px !important; }
        blockquote { border-left: 3px solid #dadce0; margin: 8px 0; padding: 4px 12px; color: #5f6368; }
        pre, code { font-family: 'SF Mono', 'Menlo', monospace; font-size: 13px; background: rgba(0,0,0,0.06); padding: 2px 4px; border-radius: 3px; overflow-x: auto; white-space: pre-wrap; word-wrap: break-word; -webkit-overflow-scrolling: touch; }
        /* Prevent horizontal scroll from embedded content */
        iframe, video, embed, object { max-width: 100% !important; }
        hr { border: none; border-top: 1px solid #dadce0; margin: 12px 0; }

        @supports (padding: env(safe-area-inset-left)) {
            body {
                padding-left: max(4px, env(safe-area-inset-left));
                padding-right: max(4px, env(safe-area-inset-right));
            }
        }

        @media (prefers-reduced-motion: reduce) {
            *, *::before, *::after {
                animation-duration: 0.001ms !important;
                transition-duration: 0.001ms !important;
            }
        }

        @media (prefers-color-scheme: dark) {
            a { color: #8ab4f8; }
            blockquote { border-left-color: #5f6368; color: #9aa0a6; }
            pre, code { background: rgba(255,255,255,0.1); color: #e8eaed; }
            hr { border-top-color: #5f6368; }
        }
        </style>
        <script>
        var THEME_TEXT = '\(textHex)';

        function fixDarkModeColors() {
            if (!window.matchMedia('(prefers-color-scheme: dark)').matches) return;

            var BG_LUM = 0.015;
            var MIN_CR = 4.0;

            function linearize(c) {
                c /= 255;
                return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
            }
            function relativeLum(r, g, b) {
                return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b);
            }
            function contrastWith(lum) {
                var hi = Math.max(lum, BG_LUM), lo = Math.min(lum, BG_LUM);
                return (hi + 0.05) / (lo + 0.05);
            }
            function parseRgb(s) {
                var i = s.indexOf('(');
                if (i < 0) return null;
                var parts = s.slice(i + 1).split(',');
                return parts.length >= 3 ? [parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2])] : null;
            }
            function hue2rgb(p, q, t) {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1/6) return p + (q - p) * 6 * t;
                if (t < 0.5) return q;
                if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                return p;
            }
            function lightenToContrast(r, g, b) {
                r /= 255; g /= 255; b /= 255;
                var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                var h = 0, s = 0, l = (mx + mn) / 2;
                if (mx !== mn) {
                    var d = mx - mn;
                    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
                    if      (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
                    else if (mx === g) h = (b - r) / d + 2;
                    else               h = (r - g) / d + 4;
                    h /= 6;
                }
                for (var tl = Math.max(l + 0.1, 0.55); tl <= 1.0; tl += 0.04) {
                    var q2 = tl < 0.5 ? tl * (1 + s) : tl + s - tl * s;
                    var p2 = 2 * tl - q2;
                    var nr = Math.round(hue2rgb(p2, q2, h + 1/3) * 255);
                    var ng = Math.round(hue2rgb(p2, q2, h)       * 255);
                    var nb = Math.round(hue2rgb(p2, q2, h - 1/3) * 255);
                    if (contrastWith(relativeLum(nr, ng, nb)) >= MIN_CR)
                        return 'rgb(' + nr + ',' + ng + ',' + nb + ')';
                }
                return THEME_TEXT;
            }

            function isAchromatic(r, g, b) {
                var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                return (mx - mn) < 30 && mx < 80;
            }

            function effectiveBgLum(el) {
                var node = el;
                while (node && node !== document.documentElement) {
                    var bg = window.getComputedStyle(node).backgroundColor;
                    var rgba = parseRgb(bg);
                    if (rgba) {
                        var parts = bg.slice(bg.indexOf('(') + 1).split(',');
                        var alpha = parts.length >= 4 ? parseFloat(parts[3]) : 1;
                        if (alpha > 0.1) return relativeLum(rgba[0], rgba[1], rgba[2]);
                    }
                    node = node.parentElement;
                }
                return BG_LUM;
            }

            function processEl(el) {
                var c = window.getComputedStyle(el).color;
                var rgb = parseRgb(c);
                if (!rgb) return;
                var bgLum = effectiveBgLum(el);
                if (bgLum > 0.4) return;
                var textLum = relativeLum(rgb[0], rgb[1], rgb[2]);
                var hi = Math.max(textLum, bgLum), lo = Math.min(textLum, bgLum);
                var cr = (hi + 0.05) / (lo + 0.05);
                if (cr >= MIN_CR) return;
                var replacement = isAchromatic(rgb[0], rgb[1], rgb[2])
                    ? THEME_TEXT
                    : lightenToContrast(rgb[0], rgb[1], rgb[2]);
                el.style.setProperty('color', replacement, 'important');
            }

            document.querySelectorAll(
                'body,p,div,span,td,th,li,a,font,b,strong,em,i,h1,h2,h3,h4,h5,h6,small,label,cite,blockquote'
            ).forEach(processEl);
        }

        // Force mobile-friendly layout on inline-styled elements
        function fixMobileLayout() {
            var vw = document.documentElement.clientWidth || window.innerWidth;
            // Shrink elements wider than viewport
            document.querySelectorAll('table, td, th, div').forEach(function(el) {
                var w = el.getAttribute('width');
                if (w && parseInt(w) > vw) {
                    el.removeAttribute('width');
                    el.style.maxWidth = '100%';
                }
                if (el.style.width && parseInt(el.style.width) > vw) {
                    el.style.width = '100%';
                }
                if (el.style.minWidth && parseInt(el.style.minWidth) > vw) {
                    el.style.minWidth = '0';
                }
            });
            // Ensure images respect viewport
            document.querySelectorAll('img').forEach(function(img) {
                var w = img.getAttribute('width');
                if (w && parseInt(w) > vw) {
                    img.removeAttribute('width');
                    img.removeAttribute('height');
                }
                img.style.maxWidth = '100%';
                img.style.height = 'auto';
            });
        }

        document.addEventListener('DOMContentLoaded', function() {
            fixMobileLayout();
        });

        window.addEventListener('load', function() {
            fixMobileLayout();
            fixDarkModeColors();

            var imgs = document.querySelectorAll('img');
            imgs.forEach(function(img) {
                if (!img.complete) {
                    img.addEventListener('load', function() {
                        window.webkit.messageHandlers.imageLog.postMessage('REMEASURE');
                    });
                }
                img.addEventListener('error', function() {
                    this.style.display = 'none';
                    window.webkit.messageHandlers.imageLog.postMessage('REMEASURE');
                });
            });
        });
        </script>
        </head>
        <body><div id="emailContent" style="padding-bottom:16px">\(html)</div></body>
        </html>
        """
        webView.loadHTMLString(fullHTML, baseURL: URL(string: "https://mail.google.com/"))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: iOSHTMLEmailView
        var lastCacheKey: String = ""
        var remeasureWorkItem: DispatchWorkItem?

        init(_ parent: iOSHTMLEmailView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            if body == "REMEASURE" || body.hasPrefix("FAILED:") {
                remeasureWorkItem?.cancel()
                let item = DispatchWorkItem { [weak self] in
                    self?.remeasureHeight()
                }
                remeasureWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
            }
        }

        private var webViewRef: WKWebView?

        private func remeasureHeight() {
            guard let webView = webViewRef else { return }
            measureHeight(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webViewRef = webView
            measureHeight(webView)
            for delay in [0.5, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let webView else { return }
                    self?.measureHeight(webView)
                }
            }
        }

        private func measureHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript(
                "(function() { var el = document.getElementById('emailContent'); if (!el) return 0; return Math.ceil(Math.max(el.offsetHeight, el.scrollHeight, el.getBoundingClientRect().height)); })()"
            ) { [weak self] result, _ in
                DispatchQueue.main.async {
                    if let h = result as? CGFloat, h > 0 {
                        self?.parent.contentHeight = h
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Thread Message View

struct iOSThreadMessageView: View {
    let message: GmailMessage
    let fromAddress: String
    var resolvedHTML: String?
    let theme: Theme

    @State private var showQuoted = false
    @State private var contentHeight: CGFloat = 60

    private var sender: Contact { GmailDataTransformer.parseContact(message.from) }

    private var isSentByMe: Bool {
        guard !fromAddress.isEmpty else { return false }
        return sender.email.lowercased() == fromAddress.lowercased()
    }

    private var fullHTML: String {
        if let resolved = resolvedHTML, !resolved.isEmpty { return resolved }
        if let html = message.htmlBody, !html.isEmpty { return html }
        if let plain = message.plainBody, !plain.isEmpty { return "<p>\(plain)</p>" }
        let body = message.body
        return body.isEmpty ? "" : "<p>\(body)</p>"
    }

    private var htmlParts: (original: String, quoted: String?) {
        HTMLQuoteStripper.stripQuotedHTML(fullHTML)
    }

    private var renderedHTML: String {
        if showQuoted || htmlParts.quoted == nil {
            return fullHTML
        }
        return htmlParts.original
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isSentByMe { Spacer(minLength: 40) }

            if !isSentByMe {
                ZStack {
                    Circle()
                        .fill(Color(hex: sender.avatarColor))
                        .frame(width: 28, height: 28)
                    Text(sender.initials)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 28, height: 28)
            }

            VStack(alignment: isSentByMe ? .trailing : .leading, spacing: 4) {
                if !isSentByMe {
                    Text(sender.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                }

                // Bubble
                VStack(alignment: .leading, spacing: 0) {
                    iOSHTMLEmailView(html: renderedHTML, contentHeight: $contentHeight, theme: theme)
                        .frame(height: contentHeight)

                    if htmlParts.quoted != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showQuoted.toggle()
                            }
                        } label: {
                            Text(showQuoted ? "Hide" : "\u{2026}")
                                .font(.system(size: showQuoted ? 11 : 14, weight: showQuoted ? .medium : .bold))
                                .foregroundColor(theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(theme.hoverBackground))
                        }
                        .padding(.top, 4)
                        .padding(.bottom, 4)
                        .padding(.leading, 4)
                    }
                }
                .padding(10)
                .background(
                    isSentByMe
                        ? theme.accentPrimary.opacity(0.12)
                        : theme.cardBackground
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))

                if let date = message.date {
                    Text(date.formattedRelative)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
            }

            if !isSentByMe { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Tracker Banner View

private struct iOSTrackerBannerView: View {
    let trackerCount: Int
    let trackers: [TrackerInfo]
    let onAllow: () -> Void

    @State private var showDetails = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showDetails.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(theme.accentPrimary)

                    Text("\(trackerCount) tracker\(trackerCount > 1 ? "s" : "") blocked")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)

                    Spacer()

                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showDetails {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(groupedTrackers, id: \.name) { group in
                        HStack(spacing: 8) {
                            Image(systemName: group.icon)
                                .font(.system(size: 11))
                                .foregroundColor(theme.textTertiary)
                                .frame(width: 16)
                            Text(group.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                            if group.count > 1 {
                                Text("\u{00D7}\(group.count)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(theme.textTertiary)
                            }
                            Spacer()
                            Text(group.kindLabel)
                                .font(.system(size: 11))
                                .foregroundColor(theme.textTertiary)
                        }
                    }

                    Button {
                        onAllow()
                    } label: {
                        Text("Load blocked content")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.accentPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(theme.accentPrimary.opacity(0.12))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(theme.cardBackground)
        .cornerRadius(10)
    }

    // MARK: - Grouped trackers

    private struct TrackerGroup: Hashable {
        let name: String
        let kind: TrackerKind
        let count: Int
        var icon: String {
            switch kind {
            case .pixel:        return "circle.fill"
            case .knownTracker: return "antenna.radiowaves.left.and.right"
            case .cssTracker:   return "paintbrush"
            case .trackingLink: return "link"
            }
        }
        var kindLabel: String {
            switch kind {
            case .pixel:        return "Pixel"
            case .knownTracker: return "Tracker"
            case .cssTracker:   return "CSS"
            case .trackingLink: return "Link"
            }
        }
    }

    private var groupedTrackers: [TrackerGroup] {
        var counts: [String: (kind: TrackerKind, count: Int)] = [:]
        for t in trackers {
            let name = t.serviceName ?? t.source
            if let existing = counts[name] {
                counts[name] = (existing.kind, existing.count + 1)
            } else {
                counts[name] = (t.kind, 1)
            }
        }
        return counts.map { TrackerGroup(name: $0.key, kind: $0.value.kind, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}

// MARK: - Calendar Invite Card View

private struct iOSCalendarInviteCardView: View {
    let invite: CalendarInvite
    let isLoading: Bool
    @Binding var showOriginalEmail: Bool
    var onAccept:  () -> Void
    var onDecline: () -> Void
    var onMaybe:   () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.accentPrimary)
                Text(invite.summary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2)
            }

            // Date & time
            if !invite.dateText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 18)
                    Text(invite.dateText)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                }
            }

            // Location
            if let location = invite.location, !location.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 18)
                    Text(location)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }
            }

            // Organizer
            if let organizer = invite.organizer, !organizer.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textTertiary)
                        .frame(width: 18)
                    Text(organizer)
                        .font(.system(size: 14))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Divider().background(theme.divider)

            // RSVP buttons
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(spacing: 10) {
                    rsvpButton("Accept", icon: "checkmark", status: .accepted, action: onAccept)
                    rsvpButton("Decline", icon: "xmark", status: .declined, action: onDecline)
                    rsvpButton("Maybe", icon: "questionmark", status: .maybe, action: onMaybe)
                }
            }

            // Show original
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showOriginalEmail.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showOriginalEmail ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                    Text(showOriginalEmail ? "Hide original" : "Show original")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(theme.textTertiary)
            }
        }
        .padding(16)
        .background(theme.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.divider, lineWidth: 1)
        )
    }

    private var hasResponded: Bool {
        invite.rsvpStatus != .pending
    }

    @ViewBuilder
    private func rsvpButton(_ label: String, icon: String, status: CalendarInvite.RSVPStatus, action: @escaping () -> Void) -> some View {
        let isSelected = invite.rsvpStatus == status

        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: isSelected ? "checkmark" : icon)
                    .font(.system(size: 12, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? theme.accentPrimary
                    : theme.accentPrimary.opacity(0.12)
            )
            .foregroundColor(
                isSelected ? .white : theme.accentPrimary
            )
            .cornerRadius(8)
        }
        .opacity(hasResponded && !isSelected ? 0.5 : 1)
    }
}

// MARK: - Sender Info Sheet

struct iOSSenderInfoSheet: View {
    let message: GmailMessage
    let email: Email
    @Environment(\.theme) private var theme

    private var fromDisplay: String {
        let name = email.sender.name
        let addr = email.sender.email
        if name.isEmpty || name == addr { return addr }
        return "\(name) <\(addr)>"
    }

    private var dateFormatted: String {
        if let d = message.date {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .short
            return fmt.string(from: d)
        }
        return "\u{2014}"
    }

    var body: some View {
        List {
            Section {
                infoRow(label: "From", value: fromDisplay, suspicious: message.isSuspiciousSender)
                if let domain = message.fromDomain {
                    infoRow(label: "Sent by", value: domain)
                }
                infoRow(label: "To", value: message.to)
                if !message.cc.isEmpty {
                    infoRow(label: "CC", value: message.cc)
                }
                infoRow(label: "Date", value: dateFormatted)
                infoRow(label: "Subject", value: message.subject)
            }

            if message.mailedBy != nil || message.signedBy != nil || message.encryptionInfo != nil {
                Section("Security") {
                    if let mailed = message.mailedBy {
                        infoRow(label: "Mailed by", value: mailed, suspicious: message.isSuspiciousSender)
                    }
                    if let signed = message.signedBy {
                        infoRow(label: "Signed by", value: signed)
                    }
                    if let encryption = message.encryptionInfo {
                        HStack(spacing: 0) {
                            Text("Security")
                                .font(.system(size: 13))
                                .foregroundColor(theme.textSecondary)
                                .frame(width: 80, alignment: .leading)
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                Text(encryption)
                                    .font(.system(size: 13))
                                    .foregroundColor(theme.textPrimary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func infoRow(label: String, value: String, suspicious: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(theme.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 13, weight: suspicious ? .semibold : .regular))
                .foregroundColor(suspicious ? .red : theme.textPrimary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Attachment Chip View

struct iOSAttachmentChipView: View {
    let attachment: Attachment
    var onTap: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: attachment.fileType.rawValue)
                    .font(.system(size: 14))
                    .foregroundColor(theme.accentPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)

                    if !attachment.size.isEmpty {
                        Text(attachment.size)
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                    }
                }

                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(theme.attachmentBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Share Sheet (UIActivityViewController)

struct iOSShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
