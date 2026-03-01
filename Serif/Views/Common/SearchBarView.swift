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

            NonAutoFocusTextField(text: $text, placeholder: "Search", isFocused: $fieldFocused)
                .font(.system(size: 13))
                .foregroundColor(theme.textPrimary)

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

// MARK: - NSTextField wrapper that refuses initial first responder

struct NonAutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isFocused: FocusState<Bool>.Binding

    func makeNSView(context: Context) -> NoAutoFocusNSTextField {
        let field = NoAutoFocusNSTextField()
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.delegate = context.coordinator
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = true
        return field
    }

    func updateNSView(_ nsView: NoAutoFocusNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        // Handle programmatic focus (⌘F)
        if isFocused.wrappedValue && nsView.window?.firstResponder != nsView.currentEditor() {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: NonAutoFocusTextField
        init(_ parent: NonAutoFocusTextField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused.wrappedValue = false
        }
    }
}

class NoAutoFocusNSTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        // Refuse automatic first responder on window setup
        // Accept if triggered by user click or programmatic focus
        if let event = NSApp.currentEvent {
            if event.type == .leftMouseDown || event.type == .keyDown {
                return super.becomeFirstResponder()
            }
        }
        // Check if this is a programmatic focus request (⌘F)
        let trace = Thread.callStackSymbols.joined()
        if trace.contains("makeFirstResponder") {
            return super.becomeFirstResponder()
        }
        return false
    }
}
