import SwiftUI

// MARK: - Flow Layout for chips (wraps to multiple rows)

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, pos) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                                  proposal: .unspecified)
        }
    }

    private func arrange(in maxWidth: CGFloat, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (positions, CGSize(width: maxWidth, height: max(y + rowHeight, 1)))
    }
}

private struct FieldHeightPrefKey: PreferenceKey {
    static var defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct iOSContactAutocompleteField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let contacts: [StoredContact]

    @Environment(\.theme) private var theme
    @State private var chips: [String] = []
    @State private var currentInput = ""
    @State private var lastSyncedText = ""
    @State private var fieldHeight: CGFloat = 44
    @FocusState private var isFocused: Bool

    // MARK: - Sync logic

    private func parseExternalText() {
        let raw = text
        if raw.isEmpty {
            chips = []
            currentInput = ""
            lastSyncedText = raw
            return
        }
        let parts = raw.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let allConfirmed = raw.hasSuffix(",") || raw.hasSuffix(", ") || (parts.last?.contains("@") ?? false)
        if allConfirmed {
            chips = parts
            currentInput = ""
        } else if parts.count <= 1 {
            chips = []
            currentInput = parts.first ?? ""
        } else {
            chips = Array(parts.dropLast())
            currentInput = parts.last ?? ""
        }
        lastSyncedText = raw
    }

    private func updateBinding() {
        var parts = chips
        let trimmed = currentInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { parts.append(trimmed) }
        let newText = parts.joined(separator: ", ")
        lastSyncedText = newText
        if text != newText { text = newText }
    }

    private func confirmInput() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        chips.append(trimmed)
        currentInput = ""
        updateBinding()
    }

    private func removeChip(at index: Int) {
        chips.remove(at: index)
        updateBinding()
    }

    private var inputBinding: Binding<String> {
        Binding(
            get: { currentInput },
            set: { newValue in
                if newValue.contains(",") {
                    let segments = newValue.components(separatedBy: ",")
                    for seg in segments.dropLast() {
                        let trimmed = seg.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty { chips.append(trimmed) }
                    }
                    currentInput = (segments.last ?? "").trimmingCharacters(in: .whitespaces)
                } else {
                    currentInput = newValue
                }
                updateBinding()
            }
        )
    }

    // MARK: - Autocomplete

    private var suggestions: [StoredContact] {
        let query = currentInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2, isFocused else { return [] }
        let existing = Set(chips.map { $0.lowercased() })
        return contacts.filter {
            !existing.contains($0.email.lowercased()) &&
            ($0.name.lowercased().contains(query) || $0.email.lowercased().contains(query))
        }
    }

    private var showDropdown: Bool { isFocused && !suggestions.isEmpty }

    private static let rowHeight: CGFloat = 45

    private func selectContact(_ contact: StoredContact) {
        chips.append(contact.email)
        currentInput = ""
        updateBinding()
    }

    var body: some View {
        ChipFlowLayout(spacing: 6) {
            ForEach(chips.indices, id: \.self) { index in
                chipView(email: chips[index], index: index)
            }
            TextField(chips.isEmpty ? placeholder : "", text: inputBinding)
                .font(.system(size: 15))
                .foregroundColor(theme.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .focused($isFocused)
                .frame(minWidth: 80)
                .onSubmit { confirmInput() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FieldHeightPrefKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(FieldHeightPrefKey.self) { fieldHeight = $0 }
        .overlay(alignment: .topLeading) {
            if showDropdown {
                autocompleteDropdown.offset(x: 16, y: fieldHeight)
            }
        }
        .onAppear { parseExternalText() }
        .onChange(of: text) { _, newValue in
            guard newValue != lastSyncedText else { return }
            parseExternalText()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused && !currentInput.trimmingCharacters(in: .whitespaces).isEmpty {
                confirmInput()
            }
        }
        .zIndex(10)
    }

    // MARK: - Chip view (Gmail-style)

    private func chipView(email: String, index: Int) -> some View {
        let contact = contacts.first(where: { $0.email.lowercased() == email.lowercased() })
        let initials: String = {
            if let contact { return contactInitials(contact) }
            return String(email.prefix(1)).uppercased()
        }()
        let color: String = {
            if let contact { return contactColor(contact) }
            let colors = ["#4285F4", "#EA4335", "#FBBC04", "#34A853", "#FF6D01", "#46BDC6", "#7B1FA2", "#C2185B"]
            return colors[abs(email.hashValue) % colors.count]
        }()
        let name: String = {
            if let contact, !contact.name.isEmpty { return contact.name }
            return email
        }()

        return HStack(spacing: 6) {
            AvatarView(
                initials: initials,
                color: color,
                size: 22,
                avatarURL: contact?.photoURL,
                senderDomain: email.split(separator: "@").last.map(String.init)
            )
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textPrimary)
                .lineLimit(1)
            Button { removeChip(at: index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 3)
        .padding(.trailing, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(theme.cardBackground)
                .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
        )
    }

    // MARK: - Dropdown

    private var autocompleteDropdown: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.prefix(20).enumerated()), id: \.element.id) { index, contact in
                    if index > 0 { Divider().padding(.leading, 44) }
                    contactRow(contact)
                }
            }
            .padding(4)
        }
        .scrollContentBackground(.hidden)
        .frame(width: 300, height: Self.rowHeight * min(CGFloat(suggestions.count), 5) + 8)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.06), radius: 3, y: 2)
    }

    private func contactRow(_ contact: StoredContact) -> some View {
        Button { selectContact(contact) } label: {
            HStack(spacing: 10) {
                AvatarView(
                    initials: contactInitials(contact),
                    color: contactColor(contact),
                    size: 28,
                    avatarURL: contact.photoURL,
                    senderDomain: contact.email.split(separator: "@").last.map(String.init)
                )
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
