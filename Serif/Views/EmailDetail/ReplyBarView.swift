import SwiftUI

struct ReplyBarView: View {
    @State private var replyText = ""
    @State private var isExpanded = false
    @StateObject private var richTextState = RichTextState()
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(theme.isLight ? 0.08 : 0.18), radius: theme.isLight ? 16 : 24, x: 0, y: theme.isLight ? -4 : -8)
        .shadow(color: .black.opacity(theme.isLight ? 0.03 : 0.07), radius: theme.isLight ? 3 : 6,  x: 0, y: -1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Collapsed

    private var collapsedContent: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 10) {
                Text("Write a reply...")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textTertiary)
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundColor(theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            RichTextEditor(
                state: richTextState,
                text: $replyText,
                textColorValue: NSColor(theme.textPrimary),
                placeholder: "Write a reply...",
                autoFocus: true
            )
            .frame(minHeight: 120, maxHeight: 200)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Divider().background(theme.divider)

            FormattingToolbar(state: richTextState)

            Divider().background(theme.divider)

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

                Button { collapse() } label: {
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

                Button { collapse() } label: {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Helpers

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isExpanded = false
            replyText = ""
        }
    }
}
