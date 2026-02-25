import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    @Binding var focusTrigger: Bool
    @FocusState private var fieldFocused: Bool
    @Environment(\.theme) private var theme

    init(text: Binding<String>, focusTrigger: Binding<Bool> = .constant(false)) {
        self._text = text
        self._focusTrigger = focusTrigger
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textTertiary)

            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)
                .focused($fieldFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(theme.searchBarBackground)
        .cornerRadius(8)
        .onChange(of: focusTrigger) { triggered in
            if triggered {
                fieldFocused = true
                focusTrigger = false
            }
        }
    }
}
