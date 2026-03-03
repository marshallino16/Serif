import SwiftUI
import UniformTypeIdentifiers

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

    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var subject = ""
    @State private var bodyText = ""
    @State private var showCc = false
    @State private var showBcc = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var attachments: [URL] = []
    @State private var isDragTargeted = false
    @State private var didApplyMode = false
    @State private var selectedAliasEmail: String
    @State private var currentSignature: String = ""
    @StateObject private var richTextState = RichTextState()
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
        onDiscard: @escaping () -> Void
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
        self._selectedAliasEmail = State(initialValue: fromAddress)
        self._composeVM        = StateObject(wrappedValue: ComposeViewModel(
            accountID: accountID,
            fromAddress: fromAddress
        ))
    }

    private var draft: Email? {
        mailStore.emails.first { $0.id == draftId }
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

            RichTextEditor(
                state: richTextState,
                text: $bodyText,
                textColorValue: NSColor(theme.textPrimary),
                placeholder: "Write your message...",
                autoFocus: true
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

            FormattingToolbar(state: richTextState)
                .background(theme.detailBackground)

            Divider()
                .background(theme.divider)

            composeActions
        }
        .background(theme.detailBackground)
        .overlay(
            Group {
                if isDragTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(theme.accentPrimary, lineWidth: 2)
                        .padding(4)
                }
            }
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            providers.forEach { provider in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async { attachments.append(url) }
                    }
                }
            }
            return true
        }
        .onAppear { loadDraft() }
        .onChange(of: to)       { _ in scheduleAutoSave() }
        .onChange(of: cc)       { _ in scheduleAutoSave() }
        .onChange(of: bcc)      { _ in scheduleAutoSave() }
        .onChange(of: subject)  { _ in scheduleAutoSave() }
        .onChange(of: bodyText) { _ in scheduleAutoSave() }
        .onChange(of: selectedAliasEmail) { newEmail in
            composeVM.fromAddress = newEmail
            replaceSignature(for: newEmail)
        }
    }

    // MARK: - Draft

    private func loadDraft() {
        if let draft = draft {
            to       = draft.recipients.map(\.email).joined(separator: ", ")
            cc       = draft.cc.map(\.email).joined(separator: ", ")
            subject  = draft.subject == "(No subject)" ? "" : draft.subject
            bodyText = draft.body
        }

        guard !didApplyMode else { return }
        didApplyMode = true

        let fields = ComposeModeInitializer.apply(
            mode: mode,
            signatureForNew: signatureForNew,
            signatureForReply: signatureForReply,
            aliases: sendAsAliases
        )

        to               = fields.to.isEmpty ? to : fields.to
        cc               = fields.cc.isEmpty ? cc : fields.cc
        showCc           = fields.showCc || showCc
        subject          = fields.subject.isEmpty ? subject : fields.subject
        bodyText         = fields.bodyText.isEmpty ? bodyText : fields.bodyText
        currentSignature = fields.currentSignature
        if let tid = fields.threadID          { composeVM.threadID = tid }
        if let mid = fields.replyToMessageID  { composeVM.replyToMessageID = mid }
    }

    private func scheduleAutoSave() {
        mailStore.updateDraft(id: draftId, subject: subject, body: bodyText, to: to, cc: cc)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            composeVM.to      = to
            composeVM.cc      = cc
            composeVM.bcc     = bcc
            composeVM.subject = subject
            composeVM.body    = bodyText
            await composeVM.saveDraft()
        }
    }

    // MARK: - Send

    private func sendEmail() async {
        guard !to.isEmpty, !subject.isEmpty else { return }
        isSending      = true
        sendError      = nil
        composeVM.to             = to
        composeVM.cc             = cc
        composeVM.bcc            = bcc
        composeVM.subject        = subject
        composeVM.body           = bodyText
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
                saveTask?.cancel()
                Task { await composeVM.discardDraft() }
                onDiscard()
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
                saveTask?.cancel()
                Task { await composeVM.discardDraft() }
                onDiscard()
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
        let newSig = SignatureResolver.signatureForAlias(
            aliasEmail,
            aliases: sendAsAliases,
            fallbackPreferredEmail: preferredEmail
        )
        let result = SignatureResolver.replaceSignature(
            in: bodyText,
            currentSignature: currentSignature,
            newSignature: newSig
        )
        bodyText = result.body
        currentSignature = result.signature
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
