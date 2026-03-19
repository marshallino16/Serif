import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Picker (UIDocumentPickerViewController wrapper)

struct iOSDocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        init(onPick: @escaping ([URL]) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

// MARK: - Compose View

struct iOSComposeView: View {
    let accountID: String
    let fromAddress: String
    let mode: ComposeMode
    let draftEmail: Email?
    let onDismiss: () -> Void
    @Environment(\.theme) private var theme

    private var contacts: [StoredContact] { ContactStore.shared.contacts(for: accountID) }

    @State private var to = ""
    @State private var cc = ""
    @State private var bcc = ""
    @State private var subject = ""
    @State private var bodyHTML = ""
    @State private var showCc = false
    @State private var showBcc = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var attachments: [URL] = []
    @State private var showAttachmentPicker = false
    @State private var showTemplatePicker = false
    @State private var showSaveTemplateAlert = false
    @State private var templateName = ""
    @State private var showDiscardAlert = false
    @State private var saveTask: Task<Void, Never>?
    @State private var isInitialLoad = true
    @State private var isSavingDraft = false
    @StateObject private var composeVM: ComposeViewModel
    @StateObject private var editorState = WebRichTextEditorState()

    init(accountID: String, fromAddress: String, mode: ComposeMode = .new, draftEmail: Email? = nil, onDismiss: @escaping () -> Void) {
        self.accountID = accountID
        self.fromAddress = fromAddress
        self.mode = mode
        self.draftEmail = draftEmail
        self.onDismiss = onDismiss
        self._composeVM = StateObject(wrappedValue: ComposeViewModel(
            accountID: accountID,
            fromAddress: fromAddress
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // To
                        iOSContactAutocompleteField(
                            label: "To", placeholder: "Recipients",
                            text: $to, contacts: contacts
                        )
                        Divider().padding(.horizontal, 16)

                        // Cc
                        if showCc {
                            iOSContactAutocompleteField(
                                label: "Cc", placeholder: "Cc recipients",
                                text: $cc, contacts: contacts
                            )
                            Divider().padding(.horizontal, 16)
                        }

                        // Bcc
                        if showBcc {
                            iOSContactAutocompleteField(
                                label: "Bcc", placeholder: "Bcc recipients",
                                text: $bcc, contacts: contacts
                            )
                            Divider().padding(.horizontal, 16)
                        }

                        // Subject
                        composeField(label: "Subject", text: $subject, placeholder: "Subject")
                        Divider().padding(.horizontal, 16)

                        // Formatting toolbar
                        iOSFormattingToolbar(state: editorState)

                        Divider().padding(.horizontal, 16)

                        // Body (rich text editor)
                        iOSWebRichTextEditor(
                            state: editorState,
                            htmlContent: $bodyHTML,
                            placeholder: "Compose email...",
                            autoFocus: true
                        )
                        .frame(minHeight: 250)
                    }
                }

                // Attachments bar
                if !attachments.isEmpty {
                    Divider()
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
                                .padding(.vertical, 5)
                                .background(Capsule().fill(theme.cardBackground))
                                .foregroundColor(theme.textSecondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }

                // Send error
                if let err = sendError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                }
            }
            .background(theme.detailBackground)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Menu {
                        Button("Save Draft") {
                            Task { await saveDraftAndDismiss() }
                        }
                        Button("Discard", role: .destructive) {
                            saveTask?.cancel()
                            Task { await composeVM.discardDraft() }
                            onDismiss()
                        }
                    } label: {
                        Text("Cancel")
                    } primaryAction: {
                        if hasContent {
                            showDiscardAlert = true
                        } else {
                            onDismiss()
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await sendEmail() }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .disabled(isSending || to.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            // Cc toggle
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showCc.toggle() }
                            } label: {
                                Text("Cc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(showCc ? theme.accentPrimary : theme.textSecondary)
                            }

                            // Bcc toggle
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showBcc.toggle() }
                            } label: {
                                Text("Bcc")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(showBcc ? theme.accentPrimary : theme.textSecondary)
                            }

                            // Attach
                            Button { showAttachmentPicker = true } label: {
                                Image(systemName: "paperclip")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                            }

                            // Template
                            Button { showTemplatePicker = true } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                            }

                            // Save draft
                            Button {
                                Task { await saveDraftAndDismiss() }
                            } label: {
                                Image(systemName: "square.and.arrow.down.on.square")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                            }

                            // Save as template
                            Button {
                                templateName = ""
                                showSaveTemplateAlert = true
                            } label: {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 14))
                                    .foregroundColor(theme.textSecondary)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .onAppear {
            if let draft = draftEmail {
                loadDraftEmail(draft)
            } else {
                applyMode()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInitialLoad = false
            }
        }
        .onChange(of: to)      { _, _ in scheduleAutoSave() }
        .onChange(of: cc)      { _, _ in scheduleAutoSave() }
        .onChange(of: bcc)     { _, _ in scheduleAutoSave() }
        .onChange(of: subject) { _, _ in scheduleAutoSave() }
        .onChange(of: bodyHTML) { _, _ in scheduleAutoSave() }
        .onDisappear { saveTask?.cancel() }
        .sheet(isPresented: $showAttachmentPicker) {
            iOSDocumentPicker { urls in
                let compatible = urls.filter { $0.isEmailCompatible }
                attachments += compatible
                let rejected = urls.count - compatible.count
                if rejected > 0 {
                    ToastManager.shared.show(message: "\(rejected) unsupported file(s) skipped", type: .error)
                }
            }
        }
        .sheet(isPresented: $showTemplatePicker) {
            NavigationStack {
                iOSTemplatePickerSheet(templates: TemplateStore.shared.templates) { template in
                    subject = template.subject
                    bodyHTML = template.bodyHTML
                    editorState.setHTML(template.bodyHTML)
                    showTemplatePicker = false
                }
                .environment(\.theme, theme)
            }
            .presentationDetents([.medium])
        }
        .alert("Save as Template", isPresented: $showSaveTemplateAlert) {
            TextField("Template name", text: $templateName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard !templateName.isEmpty else { return }
                let template = EmailTemplate(name: templateName, subject: subject, bodyHTML: bodyHTML)
                TemplateStore.shared.save(template, accountID: accountID)
                ToastManager.shared.show(message: "Template saved", type: .success)
            }
        } message: {
            Text("Enter a name for this template.")
        }
        .alert("Save or discard?", isPresented: $showDiscardAlert) {
            Button("Save Draft") {
                Task { await saveDraftAndDismiss() }
            }
            Button("Discard", role: .destructive) {
                saveTask?.cancel()
                Task { await composeVM.discardDraft() }
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Do you want to save this message as a draft?")
        }
    }

    // MARK: - Fields

    private func composeField(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textTertiary)
                .frame(width: 55, alignment: .leading)
            TextField(placeholder, text: text)
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(label != "Subject")
                .keyboardType(label == "Subject" ? .default : .emailAddress)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Mode

    private var navigationTitle: String {
        if draftEmail != nil { return "Edit Draft" }
        switch mode {
        case .new: return "New Message"
        case .reply: return "Reply"
        case .replyAll: return "Reply All"
        case .forward: return "Forward"
        }
    }

    private var hasContent: Bool {
        !to.isEmpty || !cc.isEmpty || !bcc.isEmpty || !subject.isEmpty
            || !bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func applyMode() {
        let fields = ComposeModeInitializer.apply(
            mode: mode,
            signatureForNew: SignatureResolver.resolve(preferredEmail: fromAddress, aliases: []),
            signatureForReply: SignatureResolver.resolve(preferredEmail: fromAddress, aliases: []),
            aliases: []
        )
        if !fields.to.isEmpty { to = fields.to }
        if !fields.cc.isEmpty { cc = fields.cc; showCc = true }
        if !fields.subject.isEmpty { subject = fields.subject }
        if !fields.bodyHTML.isEmpty {
            bodyHTML = fields.bodyHTML
            editorState.setHTML(fields.bodyHTML)
        }
        if let tid = fields.threadID { composeVM.threadID = tid }
        if let mid = fields.replyToMessageID { composeVM.replyToMessageID = mid }

        // For replyAll, the mode already provides Cc — just make sure the field is visible
        switch mode {
        case .replyAll:
            showCc = true
        default:
            break
        }
    }

    // MARK: - Draft Loading

    private func loadDraftEmail(_ draft: Email) {
        to = draft.recipients.map(\.email).joined(separator: ", ")
        cc = draft.cc.map(\.email).joined(separator: ", ")
        subject = draft.subject == "(No subject)" ? "" : draft.subject
        bodyHTML = draft.body
        editorState.setHTML(draft.body)
        if let gid = draft.gmailDraftID {
            composeVM.gmailDraftID = gid
        }
        if let tid = draft.gmailThreadID {
            composeVM.threadID = tid
        }
        if !draft.cc.isEmpty { showCc = true }
    }

    // MARK: - Drafts

    private func syncToVM() {
        composeVM.to      = to
        composeVM.cc      = cc
        composeVM.bcc     = bcc
        composeVM.subject = subject
        composeVM.body    = bodyHTML
        composeVM.isHTML  = true
    }

    private func scheduleAutoSave() {
        guard !isInitialLoad else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            syncToVM()
            await composeVM.saveDraft()
        }
    }

    private func saveDraftAndDismiss() async {
        isSavingDraft = true
        saveTask?.cancel()
        syncToVM()
        await composeVM.saveDraft()
        isSavingDraft = false
        onDismiss()
    }

    // MARK: - Send

    private func sendEmail() async {
        guard !to.isEmpty else { return }
        isSending = true
        sendError = nil
        composeVM.to = to
        composeVM.cc = cc
        composeVM.bcc = bcc
        composeVM.subject = subject
        composeVM.body = bodyHTML
        composeVM.isHTML = true
        composeVM.attachmentURLs = attachments
        await composeVM.send()
        isSending = false
        if composeVM.isSent {
            onDismiss()
        } else {
            sendError = composeVM.error
        }
    }
}

// MARK: - iOS Template Picker Sheet

struct iOSTemplatePickerSheet: View {
    let templates: [EmailTemplate]
    let onSelect: (EmailTemplate) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [EmailTemplate] {
        if search.isEmpty { return templates }
        let q = search.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(q) || $0.subject.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(theme.textTertiary)
                TextField("Search templates...", text: $search)
                    .font(.system(size: 15))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if filtered.isEmpty {
                Spacer()
                Text(templates.isEmpty ? "No templates yet" : "No results")
                    .font(.system(size: 15))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            } else {
                List(filtered) { template in
                    Button { onSelect(template) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name.isEmpty ? "Untitled" : template.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                                .lineLimit(1)
                            if !template.subject.isEmpty {
                                Text(template.subject)
                                    .font(.system(size: 13))
                                    .foregroundColor(theme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(theme.detailBackground)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
