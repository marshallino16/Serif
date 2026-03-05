import SwiftUI

struct ComposeView: View {
    @ObservedObject var mailStore: MailStore
    let draftId: UUID
    let accountID: String
    let fromAddress: String
    let mode: ComposeMode
    let sendAsAliases: [GmailSendAs]
    let signatureForNew: String
    let signatureForReply: String
    let contacts: [StoredContact]
    let onDiscard: () -> Void
    var onOpenLink: ((URL) -> Void)?

    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var subject = ""
    @State private var bodyHTML = ""
    @State private var showCc = false
    @State private var showBcc = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var attachments: [URL] = []
    @State private var didApplyMode = false
    @State private var isInitialLoad = true
    @State private var selectedAliasEmail: String
    @State private var currentSignatureHTML: String = ""
    @State private var showDiscardAlert = false
    @StateObject private var editorState = WebRichTextEditorState()
    @StateObject private var composeVM: ComposeViewModel
    @Environment(\.theme) private var theme

    init(
        mailStore: MailStore,
        draftId: UUID,
        accountID: String,
        fromAddress: String,
        mode: ComposeMode = .new,
        sendAsAliases: [GmailSendAs] = [],
        signatureForNew: String = "",
        signatureForReply: String = "",
        contacts: [StoredContact] = [],
        onDiscard: @escaping () -> Void,
        onOpenLink: ((URL) -> Void)? = nil
    ) {
        self._mailStore        = ObservedObject(wrappedValue: mailStore)
        self.draftId           = draftId
        self.accountID         = accountID
        self.fromAddress       = fromAddress
        self.mode              = mode
        self.sendAsAliases     = sendAsAliases
        self.signatureForNew   = signatureForNew
        self.signatureForReply = signatureForReply
        self.contacts          = contacts
        self.onDiscard         = onDiscard
        self.onOpenLink        = onOpenLink
        self._selectedAliasEmail = State(initialValue: fromAddress)
        self._composeVM        = StateObject(wrappedValue: ComposeViewModel(
            accountID: accountID,
            fromAddress: fromAddress
        ))
    }

    private var draft: Email? {
        mailStore.emails.first { $0.id == draftId }
            ?? mailStore.gmailDrafts.first { $0.id == draftId }
    }

    var body: some View {
        VStack(spacing: 0) {
            composeToolbar

            Divider()
                .background(theme.divider)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if sendAsAliases.count > 1 {
                        fromField
                        Divider().background(theme.divider).padding(.horizontal, 24)
                    }

                    AutocompleteTextField(label: "To", placeholder: "Recipients", text: $to, contacts: contacts)
                    Divider().background(theme.divider).padding(.horizontal, 24)

                    if showCc {
                        AutocompleteTextField(label: "Cc", placeholder: "Cc recipients", text: $cc, contacts: contacts)
                        Divider().background(theme.divider).padding(.horizontal, 24)
                    }

                    if showBcc {
                        AutocompleteTextField(label: "Bcc", placeholder: "Bcc recipients", text: $bcc, contacts: contacts)
                        Divider().background(theme.divider).padding(.horizontal, 24)
                    }

                    composeField(label: "Subject", text: $subject, placeholder: "Subject")
                    Divider().background(theme.divider).padding(.horizontal, 24)
                }
            }
            .zIndex(10)

            WebRichTextEditor(
                state: editorState,
                htmlContent: $bodyHTML,
                placeholder: "Write your message...",
                autoFocus: true,
                onFileDrop: { url in handleFileDrop(url) },
                onOpenLink: onOpenLink
            )
            .padding(.horizontal, 20)
            .padding(.top, 4)

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
                    .padding(.horizontal, 20).padding(.vertical, 8)
                }
            }

            Divider()
                .background(theme.divider)

            FormattingToolbar(state: editorState)
                .background(theme.detailBackground)

            Divider()
                .background(theme.divider)

            composeActions
        }
        .background(theme.detailBackground)
        .onAppear { loadDraft() }
        .onChange(of: to)       { _ in scheduleAutoSave() }
        .onChange(of: cc)       { _ in scheduleAutoSave() }
        .onChange(of: bcc)      { _ in scheduleAutoSave() }
        .onChange(of: subject)  { _ in scheduleAutoSave() }
        .onChange(of: bodyHTML) { _ in scheduleAutoSave() }
        .onChange(of: selectedAliasEmail) { newEmail in
            composeVM.fromAddress = newEmail
            replaceSignature(for: newEmail)
        }
        .alert("Discard draft?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                saveTask?.cancel()
                Task { await composeVM.discardDraft() }
                onDiscard()
            }
        } message: {
            Text("This draft will be permanently deleted.")
        }
    }

    // MARK: - Draft

    private func loadDraft() {
        let existingDraft = draft
        let hasExistingContent = !(existingDraft?.body.isEmpty ?? true)

        if let draft = existingDraft {
            to      = draft.recipients.map(\.email).joined(separator: ", ")
            cc      = draft.cc.map(\.email).joined(separator: ", ")
            subject = draft.subject == "(No subject)" ? "" : draft.subject
            bodyHTML = draft.body
            if let gid = draft.gmailDraftID {
                composeVM.gmailDraftID = gid
            }
            if !draft.cc.isEmpty { showCc = true }
        }

        // Don't apply mode initializer on existing drafts — it would overwrite body with signature
        if !hasExistingContent {
            guard !didApplyMode else { isInitialLoad = false; return }
            didApplyMode = true

            let fields = ComposeModeInitializer.apply(
                mode: mode,
                signatureForNew: signatureForNew,
                signatureForReply: signatureForReply,
                aliases: sendAsAliases
            )

            to                   = fields.to.isEmpty ? to : fields.to
            cc                   = fields.cc.isEmpty ? cc : fields.cc
            showCc               = fields.showCc || showCc
            subject              = fields.subject.isEmpty ? subject : fields.subject
            bodyHTML              = fields.bodyHTML.isEmpty ? bodyHTML : fields.bodyHTML
            currentSignatureHTML = fields.currentSignatureHTML
            if let tid = fields.threadID          { composeVM.threadID = tid }
            if let mid = fields.replyToMessageID  { composeVM.replyToMessageID = mid }
        }

        // Delay clearing isInitialLoad so the WebView's didFinish → setHTML → contentChanged
        // cycle doesn't trigger a spurious auto-save that could corrupt inline images.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isInitialLoad = false
        }
    }

    private func scheduleAutoSave() {
        guard !isInitialLoad else { return }
        mailStore.updateDraft(id: draftId, subject: subject, body: bodyHTML, to: to, cc: cc)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            composeVM.to      = to
            composeVM.cc      = cc
            composeVM.bcc     = bcc
            composeVM.subject = subject
            composeVM.body    = bodyHTML
            composeVM.isHTML  = true
            await composeVM.saveDraft()
            // Persist gmailDraftID back to the Email in mailStore so it survives view destruction
            if let gid = composeVM.gmailDraftID {
                mailStore.setGmailDraftID(gid, for: draftId)
                // Update reply draft preview if this draft is linked to a quick reply
                if let threadID = composeVM.threadID,
                   mailStore.replyDrafts[threadID] != nil {
                    let plain = bodyHTML.strippingHTML.trimmingCharacters(in: .whitespacesAndNewlines)
                    mailStore.replyDrafts[threadID] = .init(
                        gmailDraftID: gid,
                        preview: String(plain.prefix(50))
                    )
                    mailStore.saveReplyDrafts()
                }
            }
        }
    }

    // MARK: - Send

    private func sendEmail() async {
        guard !to.isEmpty, !subject.isEmpty else { return }
        isSending = true
        sendError = nil

        // Extract inline images from HTML (data: → cid:)
        let (processedHTML, images) = InlineImageProcessor.extractInlineImages(from: bodyHTML)
        composeVM.to             = to
        composeVM.cc             = cc
        composeVM.bcc            = bcc
        composeVM.subject        = subject
        composeVM.body           = processedHTML
        composeVM.isHTML         = true
        composeVM.inlineImages   = images + editorState.pendingInlineImages
        composeVM.attachmentURLs = attachments
        await composeVM.send()
        isSending = false
        if composeVM.isSent {
            saveTask?.cancel()
            onDiscard()
        } else {
            sendError = composeVM.error
        }
    }

    // MARK: - File Drop

    private func handleFileDrop(_ url: URL) {
        if !url.isEmailCompatible {
            ToastManager.shared.show(message: "Format non support\u{00E9}: .\(url.pathExtension)", type: .error)
        } else if url.isImage {
            editorState.insertImage(from: url)
        } else {
            attachments.append(url)
        }
    }

    // MARK: - Attachments

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

    // MARK: - Toolbar

    private var composeToolbar: some View {
        HStack(spacing: 12) {
            Spacer()

            toolbarButton(icon: "paperclip", label: "Attach") { attachFiles() }

            Button {
                showCc.toggle()
            } label: {
                Text("Cc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(showCc ? theme.accentPrimary : theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Cc")

            Button {
                showBcc.toggle()
            } label: {
                Text("Bcc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(showBcc ? theme.accentPrimary : theme.textSecondary)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show Bcc")

            Divider().frame(height: 16)

            toolbarButton(icon: "trash", label: "Discard") {
                showDiscardAlert = true
            }
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

    // MARK: - Bottom actions

    private var composeActions: some View {
        HStack(spacing: 12) {
            Button {
                showDiscardAlert = true
            } label: {
                Text("Discard")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(theme.buttonSecondary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if let err = sendError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await sendEmail() }
            } label: {
                HStack(spacing: 6) {
                    if isSending {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 11))
                    }
                    Text(isSending ? "Sending…" : "Send")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(theme.textInverse)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(theme.accentPrimary.opacity(isSending ? 0.6 : 1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isSending || to.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - From field

    private var fromField: some View {
        HStack(spacing: 10) {
            Text("From")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
                .frame(width: 50, alignment: .leading)

            Picker("", selection: $selectedAliasEmail) {
                ForEach(sendAsAliases, id: \.sendAsEmail) { alias in
                    Text(aliasLabel(alias)).tag(alias.sendAsEmail)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .font(.system(size: 13))
            .fixedSize()

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private func aliasLabel(_ alias: GmailSendAs) -> String {
        if let name = alias.displayName, !name.isEmpty {
            return "\(name) <\(alias.sendAsEmail)>"
        }
        return alias.sendAsEmail
    }

    // MARK: - Signature helpers

    private func replaceSignature(for aliasEmail: String) {
        let isReplyOrForward: Bool
        switch mode {
        case .new: isReplyOrForward = false
        default:   isReplyOrForward = true
        }
        let preferredEmail = isReplyOrForward ? signatureForReply : signatureForNew
        let newSig = SignatureResolver.signatureHTMLForAlias(
            aliasEmail,
            aliases: sendAsAliases,
            fallbackPreferredEmail: preferredEmail
        )
        let result = SignatureResolver.replaceHTMLSignature(
            in: bodyHTML,
            currentSignature: currentSignatureHTML,
            newSignature: newSig
        )
        bodyHTML = result.body
        currentSignatureHTML = result.signature
        // Update the editor content
        editorState.setHTML(bodyHTML)
    }

    // MARK: - Fields

    private func composeField(label: String, text: Binding<String>, placeholder: String = "") -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
                .frame(width: 50, alignment: .leading)

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}
