import SwiftUI
import UniformTypeIdentifiers

struct iOSQuickReplyView: View {
    let email: Email
    let accountID: String
    let fromAddress: String
    let mailStore: MailStore
    @ObservedObject var coordinator: AppCoordinator
    @Binding var expandTrigger: Bool
    @Binding var isFullscreen: Bool

    @State private var replyText = ""
    @State private var replyHTML = ""
    @State private var isExpanded = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var attachments: [URL] = []
    @State private var saveTask: Task<Void, Never>?
    @State private var isInitialLoad = true
    @State private var isLoadingDraft = false
    @State private var showDiscardAlert = false
    @State private var showAttachmentPicker = false
    @State private var showTemplatePicker = false
    @State private var quickReplies: [String] = []
    @State private var isLoadingReplies = false
    @State private var visibleChipCount = 0
    @State private var gradientRotation: Double = 0
    @State private var isReplyAll = true
    @State private var showRecipients = false
    @StateObject private var composeVM: ComposeViewModel
    @StateObject private var editorState = WebRichTextEditorState()
    @Environment(\.theme) private var theme

    init(email: Email, accountID: String, fromAddress: String, mailStore: MailStore, coordinator: AppCoordinator, expandTrigger: Binding<Bool>, isFullscreen: Binding<Bool>) {
        self.email = email
        self.accountID = accountID
        self.fromAddress = fromAddress
        self.mailStore = mailStore
        self._coordinator = ObservedObject(wrappedValue: coordinator)
        self._expandTrigger = expandTrigger
        self._isFullscreen = isFullscreen
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
        .frame(maxHeight: isFullscreen ? .infinity : nil)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: isFullscreen ? 0 : 16))
        .animation(.easeInOut(duration: 0.35), value: isFullscreen)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -2)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: -1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isExpanded
                        ? AnyShapeStyle(theme.border)
                        : AnyShapeStyle(
                            AngularGradient(
                                colors: [
                                    theme.accentPrimary.opacity(0.5),
                                    theme.border,
                                    theme.accentPrimary.opacity(0.2),
                                    theme.border,
                                    theme.accentPrimary.opacity(0.5),
                                ],
                                center: .center,
                                angle: .degrees(gradientRotation)
                            )
                        ),
                    lineWidth: 1
                )
        )
        .onAppear { startGradientAnimation() }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { startGradientAnimation() }
        }
        .onChange(of: replyHTML) { _, _ in
            scheduleAutoSave()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInitialLoad = false
            }
        }
        .task(id: email.id) {
            isLoadingReplies = true
            quickReplies = await QuickReplyService.shared.generateReplies(for: email)
            isLoadingReplies = false
        }
        .onChange(of: expandTrigger) { _, shouldExpand in
            if shouldExpand {
                expandTrigger = false
                if !isExpanded {
                    expand()
                }
            }
        }
        .alert("Discard reply?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) { collapse() }
        } message: {
            Text("Your reply draft will be permanently deleted.")
        }
        .sheet(isPresented: $showAttachmentPicker) {
            iOSDocumentPicker { urls in
                let compatible = urls.filter { $0.isEmailCompatible }
                attachments += compatible
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            NavigationStack {
                iOSTemplatePickerSheet(templates: TemplateStore.shared.templates) { template in
                    replyText = template.bodyHTML.strippingHTML
                    replyHTML = template.bodyHTML
                    editorState.setHTML(template.bodyHTML)
                    showTemplatePicker = false
                }
                .environment(\.theme, theme)
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Derived State

    private var replyBodyIsEmpty: Bool {
        replyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasSavedDraft: Bool {
        guard let threadID = email.gmailThreadID else { return false }
        return mailStore.replyDrafts[threadID] != nil
    }

    private var collapsedPlaceholder: String {
        let currentText = replyHTML.isEmpty
            ? replyText.trimmingCharacters(in: .whitespacesAndNewlines)
            : replyHTML.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentText.isEmpty {
            let preview = String(currentText.prefix(50))
            return "\(preview)\(currentText.count > 50 ? "..." : "")"
        }
        if let threadID = email.gmailThreadID,
           let saved = mailStore.replyDrafts[threadID] {
            let preview = saved.preview
            return "\(preview)\(preview.count >= 50 ? "..." : "")"
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
                if !quickReplies.isEmpty {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 13))
                        .foregroundStyle(appleIntelligenceGradient)
                }
                Text(collapsedPlaceholder)
                    .font(.system(size: 14))
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

    private var replyToAddress: String {
        if isReplyAll {
            let extras = email.recipients.map(\.email).filter { $0 != fromAddress }
            return ([email.sender.email] + extras).joined(separator: ", ")
        }
        return email.sender.email
    }

    private var replyCcAddress: String {
        isReplyAll ? email.cc.map(\.email).joined(separator: ", ") : ""
    }

    private var expandedContent: some View {
        VStack(spacing: 0) {
            // Reply mode toggle + recipients
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isReplyAll.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isReplyAll ? "arrowshape.turn.up.left.2.fill" : "arrowshape.turn.up.left.fill")
                            .font(.system(size: 11))
                        Text(isReplyAll ? "Reply All" : "Reply")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.accentPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accentPrimary.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showRecipients.toggle() }
                } label: {
                    Text("To: \(email.sender.name.isEmpty ? email.sender.email : email.sender.name)\(isReplyAll && !email.cc.isEmpty ? " +\(email.cc.count)" : "")")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if showRecipients {
                VStack(alignment: .leading, spacing: 4) {
                    Text("To: \(replyToAddress)")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                    if isReplyAll && !replyCcAddress.isEmpty {
                        Text("Cc: \(replyCcAddress)")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider().background(theme.divider)

            // Quick reply chips
            if !quickReplies.isEmpty {
                quickReplyChips
            }

            // Formatting toolbar
            iOSFormattingToolbar(state: editorState)

            Divider().background(theme.divider)

            // Rich text editor
            iOSWebRichTextEditor(
                state: editorState,
                htmlContent: $replyHTML,
                placeholder: "Write a reply..."
            )
            .frame(minHeight: 100, maxHeight: isFullscreen ? .infinity : 180)

            // Attachments
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
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(theme.cardBackground))
                            .foregroundColor(theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }

            Divider().background(theme.divider)

            // Action bar
            HStack(spacing: 14) {
                // Minimize
                Button {
                    minimize()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 32, height: 32)
                }

                // Fullscreen toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { isFullscreen.toggle() }
                } label: {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Attach
                Button { showAttachmentPicker = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 32, height: 32)
                }

                // Template
                Button { showTemplatePicker = true } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 32, height: 32)
                }

                if let err = sendError {
                    Text(err)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                Spacer()

                if !replyBodyIsEmpty {
                    // Discard
                    Button { discardAction() } label: {
                        Text("Discard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.hoverBackground)
                            .cornerRadius(6)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))

                    // Send
                    Button { Task { await sendReply() } } label: {
                        HStack(spacing: 4) {
                            Group {
                                if isSending {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                }
                            }
                            .font(.system(size: 11))
                            .frame(width: 12, height: 12)
                            Text("Send")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(theme.textInverse)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(theme.accentPrimary.opacity(isSending ? 0.6 : 1))
                        .cornerRadius(6)
                    }
                    .disabled(isSending)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.2), value: replyBodyIsEmpty)
        }
    }

    // MARK: - Quick Reply Chips

    private var appleIntelligenceGradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "#6E6CE8"), Color(hex: "#54C0F0"), Color(hex: "#E8754A")],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var quickReplyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 12))
                    .foregroundStyle(appleIntelligenceGradient)
                    .opacity(visibleChipCount > 0 ? 1 : 0)
                    .scaleEffect(visibleChipCount > 0 ? 1 : 0.5)

                ForEach(Array(quickReplies.enumerated()), id: \.element) { index, suggestion in
                    Button {
                        replyText = suggestion
                        replyHTML = "<p>\(suggestion)</p>"
                        editorState.setHTML("<p>\(suggestion)</p>")
                    } label: {
                        Text(suggestion)
                            .font(.system(size: 13))
                            .foregroundColor(theme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(theme.cardBackground)
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(appleIntelligenceGradient, lineWidth: 1.5)
                            )
                    }
                    .opacity(index < visibleChipCount ? 1 : 0)
                    .offset(x: index < visibleChipCount ? 0 : 15)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .onAppear { animateChips() }
        .onChange(of: quickReplies) { _, _ in animateChips() }
    }

    private func animateChips() {
        visibleChipCount = 0
        guard !quickReplies.isEmpty else { return }
        for i in 0..<quickReplies.count {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(i) * 0.1)) {
                visibleChipCount = i + 1
            }
        }
    }

    // MARK: - Actions

    func expand() {
        loadExistingDraft()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded = true
        }
    }

    private func discardAction() {
        if hasSavedDraft || composeVM.gmailDraftID != nil {
            showDiscardAlert = true
        } else {
            collapse()
        }
    }

    private func sendReply() async {
        saveTask?.cancel()

        // Recover draft ID so we can delete it after sending
        if composeVM.gmailDraftID == nil,
           let threadID = email.gmailThreadID,
           let saved = mailStore.replyDrafts[threadID] {
            composeVM.gmailDraftID = saved.gmailDraftID
        }

        let sub = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
        let replyBody = replyHTML.isEmpty ? replyText : replyHTML
        let aliases = coordinator.mailboxViewModel.sendAsAliases
        let sig = SignatureResolver.resolveHTML(
            preferredEmail: coordinator.signatureForReply,
            aliases: aliases
        )
        let quotedOriginal = QuoteFormatter.formatReplyQuote(
            senderName: email.sender.name,
            senderEmail: email.sender.email,
            date: email.date,
            originalHTML: email.body
        )
        let fullBody = sig.isEmpty
            ? replyBody + quotedOriginal
            : replyBody + "<br>" + sig + quotedOriginal
        let sanitized = HTMLSanitizer.sanitizeForSend(
            fullBody,
            themeTextColor: ThemeManager.shared.currentTheme.textPrimary.hexString
        )

        let pending = PendingSend(
            from: fromAddress, to: replyToAddress, cc: replyCcAddress, bcc: "",
            subject: sub, bodyHTML: fullBody, attachmentURLs: attachments,
            sanitizedBody: sanitized, isHTML: true,
            threadID: email.gmailThreadID, replyToMessageID: email.gmailMessageID,
            inlineImages: composeVM.inlineImages, gmailDraftID: composeVM.gmailDraftID,
            accountID: accountID
        )

        // Clean up draft references
        if let threadID = email.gmailThreadID {
            mailStore.replyDrafts.removeValue(forKey: threadID)
            mailStore.saveReplyDrafts()
        }
        if let gid = composeVM.gmailDraftID {
            mailStore.gmailDrafts.removeAll { $0.gmailDraftID == gid }
        }

        collapse()

        UndoActionManager.shared.schedule(
            label: "Reply sent",
            onConfirm: { Task { await pending.performSend() } },
            onUndo: { [weak coordinator] in coordinator?.reopenSendUndo(pending) }
        )
    }

    private func loadExistingDraft() {
        guard let threadID = email.gmailThreadID,
              let saved = mailStore.replyDrafts[threadID] else { return }
        isLoadingDraft = true
        Task {
            do {
                let draft = try await GmailDraftService.shared.getDraft(
                    id: saved.gmailDraftID, accountID: accountID, format: "full"
                )
                if let body = draft.message?.body, !body.isEmpty {
                    composeVM.gmailDraftID = saved.gmailDraftID
                    isInitialLoad = true
                    replyText = body.strippingHTML
                    replyHTML = body
                    editorState.setHTML(body)
                    isLoadingDraft = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isInitialLoad = false
                    }
                } else {
                    composeVM.gmailDraftID = saved.gmailDraftID
                    isLoadingDraft = false
                }
            } catch {
                mailStore.replyDrafts.removeValue(forKey: threadID)
                mailStore.saveReplyDrafts()
                isLoadingDraft = false
            }
        }
    }

    private func scheduleAutoSave() {
        guard !isInitialLoad, !isLoadingDraft else { return }
        if replyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
            if composeVM.gmailDraftID == nil,
               let threadID = email.gmailThreadID,
               let saved = mailStore.replyDrafts[threadID] {
                composeVM.gmailDraftID = saved.gmailDraftID
            }
            let sub = email.subject.hasPrefix("Re:") ? email.subject : "Re: \(email.subject)"
            composeVM.to = replyToAddress
            composeVM.cc = replyCcAddress
            composeVM.subject = sub
            composeVM.body = replyHTML.isEmpty ? replyText : replyHTML
            composeVM.isHTML = !replyHTML.isEmpty
            composeVM.replyToMessageID = email.gmailMessageID
            await composeVM.saveDraft()
            if let threadID = email.gmailThreadID, let draftID = composeVM.gmailDraftID {
                let plain = replyHTML.isEmpty ? replyText.trimmingCharacters(in: .whitespacesAndNewlines) : replyHTML.strippingHTML
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
            isFullscreen = false
        }
    }

    private func startGradientAnimation() {
        gradientRotation = 0
        withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
            gradientRotation = 360
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
            replyText = ""
            replyHTML = ""
            attachments = []
            sendError = nil
        }
    }
}
