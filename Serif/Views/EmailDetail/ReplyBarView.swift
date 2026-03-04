import SwiftUI

struct ReplyBarView: View {
    let email: Email
    let accountID: String
    let fromAddress: String

    @State private var replyHTML = ""
    @State private var isExpanded = false
    @State private var isSending = false
    @State private var sendError: String?
    @State private var attachments: [URL] = []
    @StateObject private var editorState = WebRichTextEditorState()
    @StateObject private var composeVM: ComposeViewModel
    @Environment(\.theme) private var theme

    init(email: Email, accountID: String, fromAddress: String) {
        self.email = email
        self.accountID = accountID
        self.fromAddress = fromAddress
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
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                Text("Write a reply...")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Image(systemName: "square.and.pencil")
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
                onFileDrop: { url in handleFileDrop(url) }
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

                Button { collapse() } label: {
                    Text("Discard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.buttonSecondary)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

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
                .disabled(isSending || replyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Actions

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

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isExpanded = false
            replyHTML = ""
            attachments = []
            sendError = nil
        }
    }
}
