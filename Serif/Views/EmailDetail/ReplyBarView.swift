import SwiftUI

struct ReplyBarView: View {
    @State private var replyText = ""
    @State private var isExpanded = false
    @StateObject private var richTextState = RichTextState()
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                // Expanded reply editor
                Divider().background(theme.divider)

                // Rich text editor
                RichTextEditor(
                    state: richTextState,
                    text: $replyText,
                    textColorValue: .white,
                    placeholder: "Write a reply...",
                    autoFocus: true
                )
                .frame(minHeight: 120, maxHeight: 200)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Divider().background(theme.divider)

                // Formatting toolbar
                FormattingToolbar(state: richTextState)

                Divider().background(theme.divider)

                // Actions
                HStack(spacing: 12) {
                    Button {
                        // Attach
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 12))
                            .foregroundColor(theme.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help("Attach file")

                    Spacer()

                    Button {
                        collapse()
                    } label: {
                        Text("Discard")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.buttonSecondary)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])

                    Button {
                        collapse()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11))
                            Text("Send")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(theme.textInverse)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(theme.accentPrimary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            } else {
                // Collapsed quick-reply bar
                HStack(spacing: 12) {
                    Button {
                        isExpanded = true
                    } label: {
                        HStack {
                            Text("Write a reply...")
                                .font(.system(size: 12))
                                .foregroundColor(theme.textTertiary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(theme.inputBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .background(theme.detailBackground)
    }

    private func collapse() {
        isExpanded = false
        replyText = ""
    }
}
