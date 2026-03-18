import SwiftUI

struct TemplateEditorView: View {
    let templateID: UUID
    let accountID: String
    @ObservedObject var store: TemplateStore
    let onDelete: () -> Void
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var subject = ""
    @State private var bodyHTML = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isInitialLoad = true
    @StateObject private var editorState = WebRichTextEditorState()

    private var template: EmailTemplate? {
        store.templates.first { $0.id == templateID }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(theme.divider)

            // Name
            composeField(label: "Name", text: $name, placeholder: "Template name")
            Divider().background(theme.divider).padding(.horizontal, 24)

            // Subject
            composeField(label: "Subject", text: $subject, placeholder: "Subject")
            Divider().background(theme.divider).padding(.horizontal, 24)

            // Body
            WebRichTextEditor(
                state: editorState,
                htmlContent: $bodyHTML,
                placeholder: "Template body...",
                autoFocus: false
            )
            .padding(.horizontal, 20)
            .padding(.top, 4)

            Divider().background(theme.divider)
            FormattingToolbar(state: editorState)
        }
        .background(theme.detailBackground)
        .onAppear { loadTemplate() }
        .onChange(of: templateID) { _ in loadTemplate() }
        .onChange(of: name)     { _ in scheduleSave() }
        .onChange(of: subject)  { _ in scheduleSave() }
        .onChange(of: bodyHTML) { _ in scheduleSave() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text(name.isEmpty ? "Untitled" : name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Button {
                store.delete(id: templateID, accountID: accountID)
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete template")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Fields

    private func composeField(label: String, text: Binding<String>, placeholder: String) -> some View {
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

    // MARK: - Load / Save

    private func loadTemplate() {
        guard let t = template else { return }
        isInitialLoad = true
        name = t.name
        subject = t.subject
        bodyHTML = t.bodyHTML
        editorState.setHTML(t.bodyHTML)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isInitialLoad = false
        }
    }

    private func scheduleSave() {
        guard !isInitialLoad else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            guard var t = template else { return }
            t.name = name
            t.subject = subject
            t.bodyHTML = bodyHTML
            store.save(t, accountID: accountID)
        }
    }
}
