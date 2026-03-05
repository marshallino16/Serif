import SwiftUI

struct FormattingToolbar: View {
    @ObservedObject var state: WebRichTextEditorState
    @Environment(\.theme) private var theme
    @State private var showColorPopover = false
    @State private var showLinkPopover = false
    @State private var linkURL = ""
    @State private var linkText = ""

    private let fontSizes: [CGFloat] = [9, 10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 36]

    private let colorGrid: [[NSColor]] = [
        [.white, NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1), NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1), NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1), .black],
        [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemTeal],
        [.systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemBrown],
    ]

    var body: some View {
        HStack(spacing: 0) {
            // Undo / Redo
            Group {
                toolbarButton(icon: "arrow.uturn.backward", tooltip: "Undo") {
                    state.undo()
                }
                toolbarButton(icon: "arrow.uturn.forward", tooltip: "Redo") {
                    state.redo()
                }
            }

            separator

            // Remove formatting
            toolbarButton(icon: "textformat", tooltip: "Remove formatting") {
                state.removeFormat()
            }

            separator

            // Font size
            Menu {
                ForEach(fontSizes, id: \.self) { size in
                    Button {
                        state.setFontSize(size)
                    } label: {
                        HStack {
                            Text("\(Int(size))")
                            if state.fontSize == size {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text("\(Int(state.fontSize))")
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(theme.cardBackground)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            separator

            // Bold, Italic, Underline, Strikethrough
            Group {
                toggleButton(icon: "bold", tooltip: "Bold", isActive: state.isBold) {
                    state.toggleBold()
                }
                toggleButton(icon: "italic", tooltip: "Italic", isActive: state.isItalic) {
                    state.toggleItalic()
                }
                toggleButton(icon: "underline", tooltip: "Underline", isActive: state.isUnderline) {
                    state.toggleUnderline()
                }
                toggleButton(icon: "strikethrough", tooltip: "Strikethrough", isActive: state.isStrikethrough) {
                    state.toggleStrikethrough()
                }
            }

            separator

            // Text color - popover with color grid
            Button {
                showColorPopover.toggle()
            } label: {
                VStack(spacing: 1) {
                    Text("A")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(nsColor: state.textColor))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(nsColor: state.textColor))
                        .frame(width: 12, height: 2)
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Text color")
            .popover(isPresented: $showColorPopover, arrowEdge: .bottom) {
                ColorGridPopover(state: state, showPopover: $showColorPopover, colorGrid: colorGrid)
            }

            separator

            // Alignment - individual icon buttons
            Group {
                alignmentButton(icon: "text.alignleft", alignment: .left, tooltip: "Align left")
                alignmentButton(icon: "text.aligncenter", alignment: .center, tooltip: "Center")
                alignmentButton(icon: "text.alignright", alignment: .right, tooltip: "Align right")
                alignmentButton(icon: "text.justify", alignment: .justified, tooltip: "Justify")
            }

            separator

            // Lists
            Group {
                toolbarButton(icon: "list.number", tooltip: "Numbered list") {
                    state.insertNumberedList()
                }
                toolbarButton(icon: "list.bullet", tooltip: "Bullet list") {
                    state.insertBulletList()
                }
            }

            separator

            // Indentation
            Group {
                toolbarButton(icon: "decrease.indent", tooltip: "Decrease indent") {
                    state.decreaseIndent()
                }
                toolbarButton(icon: "increase.indent", tooltip: "Increase indent") {
                    state.increaseIndent()
                }
            }

            separator

            // Link
            Button {
                linkURL = "https://"
                linkText = state.selectedText
                showLinkPopover.toggle()
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Insert link (Cmd+K)")
            .popover(isPresented: $showLinkPopover, arrowEdge: .bottom) {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Text("URL")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .leading)
                        TextField("https://", text: $linkURL)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    HStack(spacing: 6) {
                        Text("Text")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 30, alignment: .leading)
                        TextField("Display text (optional)", text: $linkText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            showLinkPopover = false
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.plain)

                        Button("Insert") {
                            let text = linkText.isEmpty ? nil : linkText
                            state.insertLink(url: linkURL, text: text)
                            showLinkPopover = false
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  linkURL == "https://")
                    }
                }
                .padding(12)
                .frame(width: 280)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Helpers

    private var separator: some View {
        Divider()
            .frame(height: 16)
            .padding(.horizontal, 6)
    }

    private func toolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(theme.textSecondary)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func toggleButton(icon: String, tooltip: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? theme.accentPrimary : theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? theme.accentPrimary.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func alignmentButton(icon: String, alignment: NSTextAlignment, tooltip: String) -> some View {
        let isActive = state.alignment == alignment
        return Button {
            state.setAlignment(alignment)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: isActive ? .bold : .regular))
                .foregroundColor(isActive ? theme.accentPrimary : theme.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? theme.accentPrimary.opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Color Grid Popover

struct ColorGridPopover: View {
    @ObservedObject var state: WebRichTextEditorState
    @Binding var showPopover: Bool
    let colorGrid: [[NSColor]]
    @State private var customColor: Color = .white
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            // Preset color grid
            VStack(spacing: 6) {
                ForEach(0..<colorGrid.count, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<colorGrid[row].count, id: \.self) { col in
                            let color = colorGrid[row][col]
                            Button {
                                state.setTextColor(color)
                                showPopover = false
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: color))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 3)
                                            .stroke(isSelected(color) ? theme.textInverse : theme.textInverse.opacity(0.15), lineWidth: isSelected(color) ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Divider()

            // Custom color picker
            HStack(spacing: 8) {
                ColorPicker("", selection: $customColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 24, height: 24)

                Text("Custom")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Apply") {
                    state.setTextColor(NSColor(customColor))
                    showPopover = false
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 170)
    }

    private func isSelected(_ color: NSColor) -> Bool {
        let c1 = color.usingColorSpace(.deviceRGB) ?? color
        let c2 = state.textColor.usingColorSpace(.deviceRGB) ?? state.textColor
        return abs(c1.redComponent - c2.redComponent) < 0.05
            && abs(c1.greenComponent - c2.greenComponent) < 0.05
            && abs(c1.blueComponent - c2.blueComponent) < 0.05
    }
}
