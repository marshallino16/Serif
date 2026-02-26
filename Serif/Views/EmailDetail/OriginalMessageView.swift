import SwiftUI

struct OriginalMessageView: View {
    let message: GmailMessage
    let rawSource: String?
    let isLoading: Bool

    @State private var copied = false
    @Environment(\.theme) private var theme

    // MARK: - Parsed metadata

    private var messageIDValue: String {
        message.header(named: "Message-ID") ?? message.id
    }

    private var dateValue: String {
        if let d = message.date {
            let fmt = DateFormatter()
            fmt.dateStyle = .long
            fmt.timeStyle = .medium
            return fmt.string(from: d)
        }
        return message.header(named: "Date") ?? "—"
    }

    private var deliveryDelay: String? {
        guard let dateHeader = message.header(named: "Date"),
              let internalMs = message.internalDate,
              let ms = Int64(internalMs) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Try common RFC 2822 formats
        for fmt in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss ZZZZ"] {
            formatter.dateFormat = fmt
            if let sent = formatter.date(from: dateHeader) {
                let received = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
                let diff = Int(received.timeIntervalSince(sent))
                if diff < 0 { return nil }
                if diff < 60 { return "\(diff) seconds" }
                let mins = diff / 60
                let secs = diff % 60
                if mins < 60 { return secs > 0 ? "\(mins) min \(secs) sec" : "\(mins) min" }
                return "\(mins / 60)h \(mins % 60)m"
            }
        }
        return nil
    }

    private var fromValue: String { message.from }
    private var toValue: String { message.to }
    private var subjectValue: String { message.subject }

    private var spfValue: String? { extractAuthResult(for: "spf") }
    private var dkimValue: String? { extractAuthResult(for: "dkim") }
    private var dmarcValue: String? { extractAuthResult(for: "dmarc") }

    private func extractAuthResult(for method: String) -> String? {
        guard let results = message.header(named: "Authentication-Results") else { return nil }
        let parts = results.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix(method) {
                return trimmed
            }
        }
        return nil
    }

    private func authStatusColor(_ value: String?) -> Color {
        guard let v = value?.lowercased() else { return theme.textSecondary }
        if v.contains("=pass") { return .green }
        if v.contains("=fail") || v.contains("=softfail") { return .red }
        return .orange
    }

    private func authStatusLabel(_ value: String?) -> String {
        guard let v = value?.lowercased() else { return "—" }
        if v.contains("=pass") { return "PASS" }
        if v.contains("=fail") { return "FAIL" }
        if v.contains("=softfail") { return "SOFTFAIL" }
        if v.contains("=neutral") { return "NEUTRAL" }
        if v.contains("=none") { return "NONE" }
        return v
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            metadataTable
                .padding(20)

            Divider().background(theme.divider)

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    if let source = rawSource {
                        downloadOriginal(source)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 11))
                        Text("Download Original")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(rawSource == nil)

                Spacer()

                Button {
                    if let source = rawSource {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(copied ? "Copied!" : "Copy to Clipboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.accentPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.accentPrimary.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(rawSource == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider().background(theme.divider)

            // Raw source
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                        .tint(theme.textTertiary)
                    Text("Loading original message…")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else if let source = rawSource {
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(source)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.textSecondary)
                        .textSelection(.enabled)
                        .padding(20)
                }
            } else {
                VStack {
                    Spacer()
                    Text("Could not load original message")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
    }

    // MARK: - Metadata table

    private var metadataTable: some View {
        VStack(spacing: 0) {
            metadataRow(label: "Message ID", value: messageIDValue)
            Divider().background(theme.divider)
            metadataRow(label: "Created at", value: dateValue + (deliveryDelay.map { " (\($0))" } ?? ""))
            Divider().background(theme.divider)
            metadataRow(label: "From", value: fromValue)
            Divider().background(theme.divider)
            metadataRow(label: "To", value: toValue)
            Divider().background(theme.divider)
            metadataRow(label: "Subject", value: subjectValue)
            Divider().background(theme.divider)
            authRow(label: "SPF", value: spfValue)
            Divider().background(theme.divider)
            authRow(label: "DKIM", value: dkimValue)
            Divider().background(theme.divider)
            authRow(label: "DMARC", value: dmarcValue)
        }
        .background(theme.cardBackground)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.divider, lineWidth: 1))
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
                .frame(width: 100, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.leading, 14)

            Text(value)
                .font(.system(size: 12))
                .foregroundColor(theme.textPrimary)
                .textSelection(.enabled)
                .padding(.vertical, 10)
                .padding(.trailing, 14)

            Spacer()
        }
    }

    private func authRow(label: String, value: String?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textTertiary)
                .frame(width: 100, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.leading, 14)

            HStack(spacing: 6) {
                Text(authStatusLabel(value))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(authStatusColor(value))

                if let v = value {
                    Text(v)
                        .font(.system(size: 11))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 10)
            .padding(.trailing, 14)

            Spacer()
        }
    }

    // MARK: - Download

    private func downloadOriginal(_ source: String) {
        DispatchQueue.main.async {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "original_message.eml"
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try? source.data(using: .utf8)?.write(to: url)
        }
    }
}
