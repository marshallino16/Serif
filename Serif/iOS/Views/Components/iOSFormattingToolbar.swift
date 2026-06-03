import SwiftUI

struct iOSFormattingToolbar: View {
    @ObservedObject var state: WebRichTextEditorState
    /// Optional callbacks — when provided, the toolbar shows the attach/template
    /// buttons inline (e.g. quick reply where the action bar lacks space).
    var onAttachPhoto: (() -> Void)? = nil
    var onAttachFile: (() -> Void)? = nil
    var onPickTemplate: (() -> Void)? = nil
    @Environment(\.theme) private var theme
    @State private var showLinkSheet = false
    @State private var linkURL = ""
    @State private var linkText = ""
    @State private var showColorPicker = false

    private let textColors: [Color] = [
        .black, .white,
        Color(red: 0.8, green: 0.0, blue: 0.0),  // Red
        Color(red: 0.0, green: 0.6, blue: 0.0),  // Green
        Color(red: 0.0, green: 0.4, blue: 0.9),  // Blue
        Color(red: 0.9, green: 0.6, blue: 0.0),  // Orange
        Color(red: 0.6, green: 0.0, blue: 0.8),  // Purple
        Color(red: 0.0, green: 0.7, blue: 0.7),  // Teal
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                // Bold, Italic, Underline, Strikethrough
                Group {
                    toggleButton(icon: "bold", isActive: state.isBold) {
                        state.toggleBold()
                    }
                    toggleButton(icon: "italic", isActive: state.isItalic) {
                        state.toggleItalic()
                    }
                    toggleButton(icon: "underline", isActive: state.isUnderline) {
                        state.toggleUnderline()
                    }
                    toggleButton(icon: "strikethrough", isActive: state.isStrikethrough) {
                        state.toggleStrikethrough()
                    }
                }

                separator

                // Alignment
                Group {
                    alignmentButton(icon: "text.alignleft", alignment: .left)
                    alignmentButton(icon: "text.aligncenter", alignment: .center)
                    alignmentButton(icon: "text.alignright", alignment: .right)
                }

                separator

                // Lists
                Group {
                    toolbarButton(icon: "list.number") {
                        state.insertNumberedList()
                    }
                    toolbarButton(icon: "list.bullet") {
                        state.insertBulletList()
                    }
                }

                separator

                // Link
                Button {
                    linkURL = "https://"
                    linkText = state.selectedText
                    showLinkSheet = true
                } label: {
                    Image(systemName: "link")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                separator

                // Text color
                Menu {
                    ForEach(Array(textColors.enumerated()), id: \.offset) { _, color in
                        Button {
                            let uiColor = UIColor(color)
                            state.setTextColor(uiColor)
                        } label: {
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(color)
                                Text(colorName(color))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "paintbrush.pointed")
                        .font(.system(size: 15))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }

                separator

                // Font size
                Group {
                    toolbarButton(icon: "textformat.size.smaller") {
                        let newSize = max(10, state.fontSize - 2)
                        state.setFontSize(newSize)
                    }
                    Text("\(Int(state.fontSize))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(theme.textSecondary)
                        .frame(minWidth: 24)
                    toolbarButton(icon: "textformat.size.larger") {
                        let newSize = min(48, state.fontSize + 2)
                        state.setFontSize(newSize)
                    }
                }

                separator

                // Indentation
                Group {
                    toolbarButton(icon: "decrease.indent") {
                        state.decreaseIndent()
                    }
                    toolbarButton(icon: "increase.indent") {
                        state.increaseIndent()
                    }
                }

                separator

                // Remove formatting
                toolbarButton(icon: "textformat") {
                    state.removeFormat()
                }

                // Optional attach/template entries (used by quick reply where
                // the action bar doesn't have room).
                if onAttachPhoto != nil || onAttachFile != nil || onPickTemplate != nil {
                    separator

                    if onAttachPhoto != nil || onAttachFile != nil {
                        Menu {
                            if let onAttachPhoto {
                                Button {
                                    onAttachPhoto()
                                } label: {
                                    Label("Photo Library", systemImage: "photo.on.rectangle")
                                }
                            }
                            if let onAttachFile {
                                Button {
                                    onAttachFile()
                                } label: {
                                    Label("Choose File", systemImage: "doc")
                                }
                            }
                        } label: {
                            Image(systemName: "paperclip")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textSecondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                    }

                    if let onPickTemplate {
                        Button(action: onPickTemplate) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15))
                                .foregroundColor(theme.textSecondary)
                                .frame(width: 36, height: 36)
                                .contentShape(Rectangle())
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 44)
        .background(theme.cardBackground)
        .alert("Insert Link", isPresented: $showLinkSheet) {
            TextField("URL", text: $linkURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            TextField("Display text (optional)", text: $linkText)
            Button("Cancel", role: .cancel) {}
            Button("Insert") {
                guard !linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      linkURL != "https://" else { return }
                let text = linkText.isEmpty ? nil : linkText
                state.insertLink(url: linkURL, text: text)
            }
        }
    }

    // MARK: - Helpers

    private var separator: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }

    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(theme.textSecondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
    }

    private func toggleButton(icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? theme.accentPrimary : theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? theme.accentPrimary.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
    }

    private func colorName(_ color: Color) -> String {
        if color == .black { return "Black" }
        if color == .white { return "White" }
        let resolved = color.resolve(in: EnvironmentValues())
        if resolved.red > 0.7 && resolved.green < 0.2 { return "Red" }
        if resolved.green > 0.5 && resolved.red < 0.2 { return "Green" }
        if resolved.blue > 0.7 && resolved.red < 0.2 { return "Blue" }
        if resolved.red > 0.7 && resolved.green > 0.4 { return "Orange" }
        if resolved.red > 0.4 && resolved.blue > 0.6 { return "Purple" }
        return "Teal"
    }

    private func alignmentButton(icon: String, alignment: NSTextAlignment) -> some View {
        let isActive = state.alignment == alignment
        return Button {
            state.setAlignment(alignment)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? theme.accentPrimary : theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? theme.accentPrimary.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
    }
}
