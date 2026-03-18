import SwiftUI

// MARK: - Flow Layout for Recipient Chips

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, pos) in result.positions.enumerated() where index < subviews.count {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: .unspecified
            )
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

// MARK: - Height Preference Key

private struct FieldHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 30
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - AutocompleteTextField (Chip-based)

struct AutocompleteTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    let contacts: [StoredContact]

    @State private var chips: [String] = []
    @State private var currentInput = ""
    @State private var lastSyncedText = ""
    @State private var highlightedIndex = 0
    @State private var fieldHeight: CGFloat = 30
    @FocusState private var fieldFocused: Bool
    @Environment(\.theme) private var theme

    // MARK: - Sync Logic

    /// Parse text binding into chips (called on appear and external changes only).
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

        // If text ends with comma or last part has @, all parts are confirmed chips
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

    /// Write chips + currentInput back to the text binding.
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

    // MARK: - Custom Binding (intercepts commas)

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
                highlightedIndex = 0
            }
        )
    }

    // MARK: - Autocomplete

    private var suggestions: [StoredContact] {
        let query = currentInput.trimmingCharacters(in: .whitespaces).lowercased()
        guard query.count >= 2 else { return [] }
        let existing = Set(chips.map { $0.lowercased() })
        return contacts.filter {
            !existing.contains($0.email.lowercased()) &&
            ($0.name.lowercased().contains(query) || $0.email.lowercased().contains(query))
        }
    }

    private var showDropdown: Bool {
        fieldFocused && !suggestions.isEmpty
    }

    private func displayName(for email: String) -> String {
        if let contact = contacts.first(where: { $0.email.lowercased() == email.lowercased() }),
           !contact.name.isEmpty {
            return contact.name
        }
        return email
    }

    private func selectContact(_ contact: StoredContact) {
        chips.append(contact.email)
        currentInput = ""
        updateBinding()
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
                .frame(width: 50, alignment: .leading)
                .padding(.top, 4)

            ChipFlowLayout(spacing: 4) {
                ForEach(chips.indices, id: \.self) { index in
                    chipView(email: chips[index], index: index)
                }

                TextField(chips.isEmpty ? placeholder : "", text: inputBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textPrimary)
                    .focused($fieldFocused)
                    .frame(minWidth: 80)
                    .onKeyPress(.return) {
                        if showDropdown && highlightedIndex < suggestions.count {
                            selectContact(suggestions[highlightedIndex])
                        } else {
                            confirmInput()
                        }
                        return .handled
                    }
                    .onKeyPress(.tab) {
                        guard showDropdown && highlightedIndex < suggestions.count else { return .ignored }
                        selectContact(suggestions[highlightedIndex])
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        if currentInput.isEmpty && !chips.isEmpty {
                            chips.removeLast()
                            updateBinding()
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(.downArrow) {
                        guard showDropdown else { return .ignored }
                        highlightedIndex = min(highlightedIndex + 1, suggestions.count - 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        guard showDropdown else { return .ignored }
                        highlightedIndex = max(highlightedIndex - 1, 0)
                        return .handled
                    }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
        .onAppear { parseExternalText() }
        .onChange(of: text) { _ in
            guard text != lastSyncedText else { return }
            parseExternalText()
        }
        .onChange(of: fieldFocused) { focused in
            if !focused && !currentInput.trimmingCharacters(in: .whitespaces).isEmpty {
                confirmInput()
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FieldHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(FieldHeightKey.self) { fieldHeight = $0 }
        .overlay(alignment: .topLeading) {
            if showDropdown {
                autocompleteDropdown
                    .offset(x: 64, y: fieldHeight + 4)
            }
        }
        .zIndex(10)
    }

    // MARK: - Chip View

    private func chipView(email: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Text(displayName(for: email))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)

            Button { removeChip(at: index) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.accentPrimary)
        .foregroundColor(theme.textInverse)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Autocomplete Dropdown

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
        let hash = abs(contact.email.hashValue)
        return colors[hash % colors.count]
    }

    private func contactRow(_ contact: StoredContact, isHighlighted: Bool) -> some View {
        Button {
            selectContact(contact)
        } label: {
            HStack(spacing: 10) {
                AvatarView(
                    initials: contactInitials(contact),
                    color: contactColor(contact),
                    size: 28
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
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHighlighted ? theme.accentPrimary.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let rowHeight: CGFloat = 45

    private var autocompleteDropdown: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, contact in
                        if index > 0 {
                            Divider()
                                .background(theme.divider)
                                .padding(.leading, 44)
                        }

                        contactRow(contact, isHighlighted: index == highlightedIndex)
                            .id(contact.id)
                    }
                }
                .padding(4)
            }
            .scrollContentBackground(.hidden)
            .frame(width: 300, height: Self.rowHeight * min(CGFloat(suggestions.count), 5) + 8)
            .onChange(of: highlightedIndex) { _ in
                if highlightedIndex < suggestions.count {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(suggestions[highlightedIndex].id, anchor: .center)
                    }
                }
            }
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
        .shadow(color: .black.opacity(0.04), radius: 3, y: 2)
    }
}
