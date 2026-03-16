import SwiftUI

struct TemplateListView: View {
    @ObservedObject var store: TemplateStore
    @Binding var selectedTemplateID: UUID?
    let accountID: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.divider)

            if store.templates.isEmpty {
                emptyState
            } else {
                templateList
            }
        }
        .frame(width: 320)
        .background(theme.listBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Templates")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)
            Spacer()
            Button { createTemplate() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New template")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - List

    private var templateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedTemplates) { template in
                    templateRow(template)
                    Divider().background(theme.divider).padding(.leading, 16)
                }
            }
        }
    }

    private var sortedTemplates: [EmailTemplate] {
        store.templates.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func templateRow(_ template: EmailTemplate) -> some View {
        Button {
            selectedTemplateID = template.id
        } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(template.name.isEmpty ? "Untitled" : template.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    if !template.subject.isEmpty {
                        Text(template.subject)
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                            .lineLimit(1)
                    }
                    Text(template.updatedAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                selectedTemplateID == template.id
                    ? theme.selectedCardBackground
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.on.doc")
                .font(.system(size: 32))
                .foregroundColor(theme.textTertiary)
            Text("No templates yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(theme.textSecondary)
            Button { createTemplate() } label: {
                Text("Create Template")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textInverse)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(theme.accentPrimary)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: - Actions

    private func createTemplate() {
        let template = EmailTemplate()
        store.save(template, accountID: accountID)
        selectedTemplateID = template.id
    }
}
