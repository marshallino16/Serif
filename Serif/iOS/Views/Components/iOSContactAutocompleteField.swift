import SwiftUI

struct iOSContactAutocompleteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let contacts: [StoredContact]
    @Environment(\.theme) private var theme
    @FocusState private var isFocused: Bool
    @State private var fieldHeight: CGFloat = 44

    private var currentSegment: String {
        let parts = text.components(separatedBy: ",")
        return (parts.last ?? "").trimmingCharacters(in: .whitespaces)
    }

    private var suggestions: [StoredContact] {
        let query = currentSegment.lowercased()
        guard query.count >= 2, isFocused else { return [] }
        let existing = Set(
            text.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
        )
        return contacts.filter {
            !existing.contains($0.email.lowercased()) &&
            ($0.name.lowercased().contains(query) || $0.email.lowercased().contains(query))
        }
    }

    private var showDropdown: Bool {
        isFocused && !suggestions.isEmpty
    }

    private static let rowHeight: CGFloat = 45

    var body: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 15))
            .foregroundColor(theme.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
            .focused($isFocused)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FieldHeightPrefKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(FieldHeightPrefKey.self) { fieldHeight = $0 }
        .overlay(alignment: .topLeading) {
            if showDropdown {
                autocompleteDropdown
                    .offset(x: 16, y: fieldHeight)
            }
        }
        .zIndex(10)
    }

    // MARK: - Dropdown

    private var autocompleteDropdown: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.prefix(20).enumerated()), id: \.element.id) { index, contact in
                    if index > 0 {
                        Divider().padding(.leading, 44)
                    }
                    contactRow(contact)
                }
            }
            .padding(4)
        }
        .scrollContentBackground(.hidden)
        .frame(
            width: 300,
            height: Self.rowHeight * min(CGFloat(suggestions.count), 5) + 8
        )
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
    }

    private func contactRow(_ contact: StoredContact) -> some View {
        Button {
            selectContact(contact)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: contactColor(contact)))
                        .frame(width: 28, height: 28)
                    Text(contactInitials(contact))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    if !contact.name.isEmpty {
                        Text(contact.name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textPrimary)
                            .lineLimit(1)
                    }
                    Text(contact.email)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func selectContact(_ contact: StoredContact) {
        var parts = text.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let last = parts.last, !last.contains("@") {
            parts.removeLast()
        }
        parts.append(contact.email)
        text = parts.joined(separator: ", ") + ", "
    }

    // MARK: - Helpers

    private func contactInitials(_ contact: StoredContact) -> String {
        if !contact.name.isEmpty {
            let parts = contact.name.split(separator: " ")
            let first = parts.first?.prefix(1) ?? ""
            let last = parts.count > 1 ? parts.last!.prefix(1) : ""
            return "\(first)\(last)".uppercased()
        }
        return String(contact.email.prefix(1)).uppercased()
    }

    private func contactColor(_ contact: StoredContact) -> String {
        let colors = ["#4285F4", "#EA4335", "#FBBC04", "#34A853", "#FF6D01", "#46BDC6", "#7B1FA2", "#C2185B"]
        return colors[abs(contact.email.hashValue) % colors.count]
    }
}

private struct FieldHeightPrefKey: PreferenceKey {
    static var defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
