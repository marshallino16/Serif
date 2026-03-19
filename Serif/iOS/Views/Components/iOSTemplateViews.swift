import SwiftUI

// MARK: - Template List

struct iOSTemplateListView: View {
    @ObservedObject var coordinator: AppCoordinator
    @StateObject private var store = TemplateStore.shared
    @Environment(\.theme) private var theme

    private var accountID: String { coordinator.accountID }

    var body: some View {
        Group {
            if store.templates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 36))
                        .foregroundColor(theme.textTertiary)
                    Text("No templates yet")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                    Button {
                        createTemplate()
                    } label: {
                        Text("Create Template")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.textInverse)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(theme.accentPrimary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sortedTemplates) { template in
                        NavigationLink {
                            iOSTemplateEditorView(template: template, accountID: accountID, store: store)
                        } label: {
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
                                Text(template.updatedAt, style: .relative)
                                    .font(.system(size: 12))
                                    .foregroundColor(theme.textTertiary)
                            }
                            .padding(.vertical, 2)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(id: template.id, accountID: accountID)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(theme.listBackground)
            }
        }
        .background(theme.listBackground)
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { createTemplate() } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { store.load(accountID: accountID) }
    }

    private var sortedTemplates: [EmailTemplate] {
        store.templates.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func createTemplate() {
        let template = EmailTemplate()
        store.save(template, accountID: accountID)
    }
}

// MARK: - Template Editor

struct iOSTemplateEditorView: View {
    let template: EmailTemplate
    let accountID: String
    @ObservedObject var store: TemplateStore
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var subject: String
    @State private var bodyHTML: String
    @State private var saveTask: Task<Void, Never>?
    @State private var isInitialLoad = true
    @State private var showDeleteConfirm = false
    @StateObject private var editorState = WebRichTextEditorState()

    init(template: EmailTemplate, accountID: String, store: TemplateStore) {
        self.template = template
        self.accountID = accountID
        self.store = store
        self._name = State(initialValue: template.name)
        self._subject = State(initialValue: template.subject)
        self._bodyHTML = State(initialValue: template.bodyHTML)
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    TextField("Template name", text: $name)
                        .font(.system(size: 16, weight: .medium))
                    TextField("Subject", text: $subject)
                        .font(.system(size: 15))
                }

                Section("Body") {
                    iOSWebRichTextEditor(
                        state: editorState,
                        htmlContent: $bodyHTML,
                        placeholder: "Template body..."
                    )
                    .frame(minHeight: 250)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.listBackground)

            iOSFormattingToolbar(state: editorState)
        }
        .background(theme.detailBackground)
        .navigationTitle(name.isEmpty ? "Untitled" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(theme.destructive)
                }
            }
        }
        .alert("Delete Template?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                store.delete(id: template.id, accountID: accountID)
                dismiss()
            }
        }
        .onAppear {
            editorState.setHTML(template.bodyHTML)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isInitialLoad = false
            }
        }
        .onChange(of: name) { _, _ in scheduleSave() }
        .onChange(of: subject) { _, _ in scheduleSave() }
        .onChange(of: bodyHTML) { _, _ in scheduleSave() }
    }

    private func scheduleSave() {
        guard !isInitialLoad else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            var t = template
            t.name = name
            t.subject = subject
            t.bodyHTML = bodyHTML
            store.save(t, accountID: accountID)
        }
    }
}
