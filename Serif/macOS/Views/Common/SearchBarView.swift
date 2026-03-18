import SwiftUI

struct SearchBarView: View {
    @Binding var text: String
    @Binding var focusTrigger: Bool
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

            NonAutoFocusTextField(text: $text, placeholder: "Search", focusTrigger: $focusTrigger)
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
    }
}

// MARK: - NSTextField wrapper that refuses initial first responder

struct NonAutoFocusTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var focusTrigger: Bool

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
        if focusTrigger {
            DispatchQueue.main.async {
                nsView.programmaticFocus = true
                nsView.window?.makeFirstResponder(nsView)
                nsView.programmaticFocus = false
                focusTrigger = false
            }
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
    }
}

class NoAutoFocusNSTextField: NSTextField {
    var programmaticFocus = false

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        if programmaticFocus {
            return super.becomeFirstResponder()
        }
        if let event = NSApp.currentEvent,
           event.type == .leftMouseDown || event.type == .keyDown {
            return super.becomeFirstResponder()
        }
        return false
    }
}
