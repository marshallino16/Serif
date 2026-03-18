import SwiftUI

struct SignatureEditorView: View {
    let alias: GmailSendAs
    let accountID: String
    var onSave: ((GmailSendAs) -> Void)?

    @StateObject private var editorState = WebRichTextEditorState()
    @State private var htmlContent: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.divider)
            ScrollView(.horizontal, showsIndicators: false) {
                FormattingToolbar(state: editorState)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider().background(theme.divider)
            editorArea
            if let error = errorMessage {
                errorBanner(error)
            }
        }
        .frame(width: 560, height: 420)
        .background(theme.detailBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear {
            htmlContent = alias.signature ?? ""
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Signature")
                    .font(.serifTitle)
                    .foregroundColor(theme.textPrimary)
                Text(alias.sendAsEmail)
                    .font(.serifSmall)
                    .foregroundColor(theme.textTertiary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(theme.textSecondary)
                .font(.serifLabel)
            saveButton
        }
        .padding(16)
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            save()
        } label: {
            HStack(spacing: 5) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
                Text(isSaving ? "Saving…" : "Save")
                    .font(.serifLabel)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.accentPrimary))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
    }

    // MARK: - Editor

    private var editorArea: some View {
        WebRichTextEditor(
            state: editorState,
            htmlContent: $htmlContent,
            placeholder: "Enter your signature…"
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.serifSmall)
            Text(message)
                .font(.serifSmall)
                .foregroundColor(.red)
            Spacer()
            Button {
                errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.serifBadge)
                    .foregroundColor(theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }

    // MARK: - Save Action

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await GmailProfileService.shared.updateSignature(
                    sendAsEmail: alias.sendAsEmail,
                    signature: htmlContent,
                    accountID: accountID
                )
                onSave?(updated)
                dismiss()
            } catch {
                errorMessage = "Failed to save: \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}
