import SwiftUI

struct EmailHoverSummaryView: View {
    let email: Email
    @Environment(\.theme) private var theme
    @State private var displayedText = ""
    @State private var streamTask: Task<Void, Never>?
    @State private var isStreaming = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                AvatarView(
                    initials: email.sender.initials,
                    color: email.sender.avatarColor,
                    size: 28,
                    avatarURL: email.sender.avatarURL,
                    senderDomain: email.sender.domain
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(email.sender.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.textPrimary)
                        .lineLimit(1)
                    Text(email.subject)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(email.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
            }

            // Metadata pills
            if !email.recipients.isEmpty || email.hasAttachments {
                HStack(spacing: 6) {
                    if !email.recipients.isEmpty {
                        metadataPill(
                            icon: "person.2",
                            text: recipientsSummary
                        )
                    }
                    if email.hasAttachments {
                        metadataPill(
                            icon: "paperclip",
                            text: attachmentsSummary
                        )
                    }
                    if email.isFromMailingList {
                        metadataPill(icon: "newspaper", text: "Mailing list")
                    }
                }
            }

            Divider()
                .background(theme.divider)

            // Summary body
            if displayedText.isEmpty && isStreaming {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Summarizing...")
                        .font(.system(size: 11))
                        .foregroundColor(theme.textTertiary)
                }
            } else {
                Text(displayedText)
                    .font(.system(size: 12))
                    .foregroundColor(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeIn(duration: 0.05), value: displayedText)
            }

            // Footer
            if !isStreaming {
                footerView
            }
        }
        .padding(14)
        .onAppear { startStreaming() }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: - Metadata

    private var recipientsSummary: String {
        let names = email.recipients.prefix(3).map { $0.name.components(separatedBy: " ").first ?? $0.name }
        let count = email.recipients.count + email.cc.count
        if count <= 3 {
            return names.joined(separator: ", ")
        }
        return "\(names.prefix(2).joined(separator: ", ")) +\(count - 2)"
    }

    private var attachmentsSummary: String {
        let count = email.attachments.count
        if count == 0 { return "Attachments" }
        if count == 1, let first = email.attachments.first {
            return first.name
        }
        return "\(count) files"
    }

    private func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 10))
                .lineLimit(1)
        }
        .foregroundColor(theme.textTertiary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(theme.hoverBackground))
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerView: some View {
        HStack {
            Spacer()
            if #available(macOS 26.0, *) {
                #if canImport(FoundationModels)
                Label("Apple Intelligence", systemImage: "apple.intelligence")
                    .font(.system(size: 9))
                    .foregroundColor(theme.textTertiary)
                #else
                previewLabel
                #endif
            } else {
                previewLabel
            }
        }
    }

    private var previewLabel: some View {
        Text("Preview")
            .font(.system(size: 9))
            .foregroundColor(theme.textTertiary)
    }

    // MARK: - Streaming

    private func startStreaming() {
        streamTask = Task { @MainActor in
            let stream = SummaryService.shared.summary(for: email)
            for await text in stream {
                guard !Task.isCancelled else { return }
                displayedText = text
            }
            isStreaming = false
        }
    }
}
