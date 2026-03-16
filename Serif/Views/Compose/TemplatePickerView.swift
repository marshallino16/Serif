import SwiftUI

struct TemplatePickerView: View {
    let templates: [EmailTemplate]
    let onSelect: (EmailTemplate) -> Void
    @Environment(\.theme) private var theme
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
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                TextField("Search templates...", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().background(theme.divider)

            if filtered.isEmpty {
                Text(templates.isEmpty ? "No templates" : "No results")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(filtered) { template in
                            Button { onSelect(template) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(template.name.isEmpty ? "Untitled" : template.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(theme.textPrimary)
                                        .lineLimit(1)
                                    if !template.subject.isEmpty {
                                        Text(template.subject)
                                            .font(.system(size: 11))
                                            .foregroundColor(theme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if template.id != filtered.last?.id {
                                Divider().background(theme.divider).padding(.leading, 10)
                            }
                        }
                    }
                }
                .frame(maxHeight: 250)
            }
        }
        .frame(width: 260)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
    }
}
