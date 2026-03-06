import SwiftUI

struct ReplyBarView: View {
    let email: Email
    let accountID: String
    let fromAddress: String
    let mailStore: MailStore
    var onOpenLink: ((URL) -> Void)?

    @State private var replyHTML = ""
    @State private var isExpanded = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var attachments: [URL] = []
    @State private var saveTask: Task<Void, Never>?
    @State private var isInitialLoad = true
    @State private var isLoadingDraft = false
    @State private var showDiscardAlert = false
    @StateObject private var editorState = WebRichTextEditorState()
    @StateObject private var composeVM: ComposeViewModel
    @Environment(\.theme) private var theme

    init(email: Email, accountID: String, fromAddress: String, mailStore: MailStore, onOpenLink: ((URL) -> Void)? = nil) {
        self.email = email
        self.accountID = accountID
        self.fromAddress = fromAddress
        self.mailStore = mailStore
        self.onOpenLink = onOpenLink
        self._composeVM = StateObject(wrappedValue: ComposeViewModel(
            accountID: accountID,
            fromAddress: fromAddress,
            threadID: email.gmailThreadID
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -2)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: -1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .background(ClickOutsideDetector(isExpanded: isExpanded, onClickOutside: { minimize() }))
        .onChange(of: replyHTML) { _ in
            scheduleAutoSave()
        }
        .animation(.easeInOut(duration: 0.2), value: replyBodyIsEmpty)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInitialLoad = false
            }
        }
        .alert("Discard reply?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { collapse() }
        } message: {
            Text("Your reply draft will be permanently deleted.")
        }
    }

    private var replyBodyIsEmpty: Bool {
        replyHTML.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSavedDraft: Bool {
        guard let threadID = email.gmailThreadID else { return false }
        return mailStore.replyDrafts[threadID] != nil
    }

    private var collapsedPlaceholder: String {
        let currentText = replyHTML.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentText.isEmpty {
            let preview = String(currentText.prefix(50))
            return "\(preview)\(currentText.count > 50 ? "…" : "")"
        }
        if let threadID = email.gmailThreadID,
           let saved = mailStore.replyDrafts[threadID] {
            let preview = saved.preview
            return "\(preview)\(preview.count >= 50 ? "…" : "")"
        }
        return "Write a reply..."
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        Button {
            loadExistingDraft()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                Text(collapsedPlaceholder)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textTertiary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: hasSavedDraft ? "arrow.uturn.forward" : "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            WebRichTextEditor(
                state: editorState,
                htmlContent: $replyHTML,
                placeholder: "Write a reply...",
                autoFocus: true,
                onFileDrop: { url in handleFileDrop(url) },
                onOpenLink: onOpenLink
            )
            .frame(minHeight: 120, maxHeight: 200)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if !attachments.isEmpty {
                Divider().background(theme.divider)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachments, id: \.self) { url in
                            HStack(spacing: 4) {
                                Image(systemName: url.sfSymbolIcon)
                                    .font(.system(size: 11))
                                Text(url.lastPathComponent)
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                Button { attachments.removeAll { $0 == url } } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(theme.cardBackground))
                            .foregroundColor(theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                }
            }

            Divider().background(theme.divider)

            FormattingToolbar(state: editorState)

            Divider().background(theme.divider)

            HStack(spacing: 12) {
                Button { minimize() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Minimize")
                .keyboardShortcut(.escape, modifiers: [])

                Button { attachFiles() } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("Attach file")

                if let err = sendError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Spacer()

                if !replyBodyIsEmpty {
                    Button { discardAction() } label: {
                        Text("Discard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.buttonSecondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

                    Button { Task { await sendReply() } } label: {
                        HStack(spacing: 4) {
                            if isSending {
                                ProgressView().scaleEffect(0.6).tint(.white)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 11))
                            }
                            Text(isSending ? "Sending..." : "Send")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(theme.textInverse)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(theme.accentPrimary.opacity(isSending ? 0.6 : 1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isSending)
                    .keyboardShortcut(.return, modifiers: .command)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Actions

    private func discardAction() {
        if hasSavedDraft || composeVM.gmailDraftID != nil {
            showDiscardAlert = true
        } else {
            collapse()
        }
    }

    private func sendReply() async {
        isSending = true
        sendError = nil

        let (processedHTML, images) = InlineImageProcessor.extractInlineImages(from: replyHTML)
        let sub = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"

        composeVM.to = email.sender.email
        composeVM.subject = sub
        composeVM.body = processedHTML
        composeVM.isHTML = true
        composeVM.inlineImages = images + editorState.pendingInlineImages
        composeVM.replyToMessageID = email.gmailMessageID
        composeVM.attachmentURLs = attachments

        await composeVM.send()
        isSending = false

        if composeVM.isSent {
            if let threadID = email.gmailThreadID {
                mailStore.replyDrafts.removeValue(forKey: threadID)
                mailStore.saveReplyDrafts()
            }
            ToastManager.shared.show(message: "Reply sent", type: .success)
            collapse()
        } else {
            sendError = composeVM.error
        }
    }

    private func handleFileDrop(_ url: URL) {
        if !url.isEmailCompatible {
            ToastManager.shared.show(message: "Format non support\u{00E9}: .\(url.pathExtension)", type: .error)
        } else if url.isImage {
            editorState.insertImage(from: url)
        } else {
            attachments.append(url)
        }
    }

    private func attachFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { response in
            if response == .OK {
                attachments += panel.urls
            }
        }
    }

    private func loadExistingDraft() {
        guard let threadID = email.gmailThreadID,
              let saved = mailStore.replyDrafts[threadID] else { return }
        // Block all auto-saves until the draft content is loaded
        isLoadingDraft = true
        Task {
            do {
                let draft = try await GmailDraftService.shared.getDraft(
                    id: saved.gmailDraftID, accountID: accountID, format: "full"
                )
                if let body = draft.message?.body, !body.isEmpty {
                    composeVM.gmailDraftID = saved.gmailDraftID
                    isInitialLoad = true
                    replyHTML = body
                    editorState.setHTML(body)
                    isLoadingDraft = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isInitialLoad = false
                    }
                } else {
                    // Draft exists but body is empty — treat as valid, let user type
                    composeVM.gmailDraftID = saved.gmailDraftID
                    isLoadingDraft = false
                }
            } catch {
                // Draft no longer exists on Gmail — clean up the link
                mailStore.replyDrafts.removeValue(forKey: threadID)
                mailStore.saveReplyDrafts()
                isLoadingDraft = false
            }
        }
    }

    private func scheduleAutoSave() {
        guard !isInitialLoad, !isLoadingDraft else { return }
        if replyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Content was cleared — discard any existing draft
            saveTask?.cancel()
            if let threadID = email.gmailThreadID, mailStore.replyDrafts[threadID] != nil {
                mailStore.replyDrafts.removeValue(forKey: threadID)
                mailStore.saveReplyDrafts()
                if composeVM.gmailDraftID != nil {
                    Task { await composeVM.discardDraft() }
                }
            }
            return
        }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            // Recover draft ID if view was recreated but draft exists on Gmail
            if composeVM.gmailDraftID == nil,
               let threadID = email.gmailThreadID,
               let saved = mailStore.replyDrafts[threadID] {
                composeVM.gmailDraftID = saved.gmailDraftID
            }
            let sub = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
            composeVM.to = email.sender.email
            composeVM.subject = sub
            composeVM.body = replyHTML
            composeVM.isHTML = true
            composeVM.replyToMessageID = email.gmailMessageID
            await composeVM.saveDraft()
            // Store the link so the draft can be restored when coming back
            if let threadID = email.gmailThreadID, let draftID = composeVM.gmailDraftID {
                let plain = replyHTML.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                mailStore.replyDrafts[threadID] = .init(
                    gmailDraftID: draftID,
                    preview: String(plain.prefix(50))
                )
                mailStore.saveReplyDrafts()
            }
        }
    }

    private func minimize() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = false
        }
    }

    private func collapse() {
        saveTask?.cancel()
        if let threadID = email.gmailThreadID {
            mailStore.replyDrafts.removeValue(forKey: threadID)
            mailStore.saveReplyDrafts()
        }
        if composeVM.gmailDraftID != nil {
            Task { await composeVM.discardDraft() }
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = false
            replyHTML = ""
            attachments = []
            sendError = nil
        }
    }
}

// MARK: - Click Outside Detector

/// NSViewRepresentable that monitors mouse clicks and fires a callback
/// when the click lands outside of its own parent view hierarchy.
private struct ClickOutsideDetector: NSViewRepresentable {
    let isExpanded: Bool
    let onClickOutside: () -> Void

    private class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func cursorUpdate(with event: NSEvent) {}
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        context.coordinator.anchorView = view
        context.coordinator.onClickOutside = onClickOutside
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isExpanded = isExpanded
        context.coordinator.onClickOutside = onClickOutside
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        weak var anchorView: NSView?
        var isExpanded = false
        var onClickOutside: (() -> Void)?
        private var monitor: Any?

        func install() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.handleClick(event)
                return event
            }
        }

        private func handleClick(_ event: NSEvent) {
            guard isExpanded, let anchor = anchorView, let anchorWindow = anchor.window else { return }
            // Ignore clicks in popover windows (color picker, link popover, alerts, etc.)
            if let eventWindow = event.window, eventWindow !== anchorWindow {
                return
            }
            let clickInAnchor = anchor.convert(event.locationInWindow, from: nil)
            if !anchor.bounds.contains(clickInAnchor) {
                DispatchQueue.main.async { [weak self] in
                    self?.onClickOutside?()
                }
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}
