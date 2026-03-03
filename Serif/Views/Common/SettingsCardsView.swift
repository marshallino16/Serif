import SwiftUI

// MARK: - Behavior Settings Card

struct BehaviorSettingsCard: View {
    @Binding var undoDuration: Int
    @Binding var refreshInterval: Int
    let lastRefreshedAt: Date?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Behavior")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            HStack {
                Text("Undo duration")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                Spacer()
                Picker("", selection: $undoDuration) {
                    Text("5s").tag(5)
                    Text("10s").tag(10)
                    Text("20s").tag(20)
                    Text("30s").tag(30)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            Divider().background(theme.divider)

            HStack {
                Text("Refresh interval")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)
                Spacer()
                Picker("", selection: $refreshInterval) {
                    Text("2 min").tag(120)
                    Text("5 min").tag(300)
                    Text("10 min").tag(600)
                    Text("1 hour").tag(3600)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
            }

            RefreshStatusView(lastRefreshedAt: lastRefreshedAt, refreshInterval: refreshInterval)
        }
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}

// MARK: - Contacts Settings Card

struct ContactsSettingsCard: View {
    let accountID: String
    @State private var isRefreshingContacts = false
    @Environment(\.theme) private var theme

    var body: some View {
        let count = ContactStore.shared.contacts(for: accountID).count

        VStack(alignment: .leading, spacing: 12) {
            Text("Contacts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            HStack {
                Text("\(count) contacts cached")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textSecondary)

                Spacer()

                Button {
                    guard !isRefreshingContacts else { return }
                    isRefreshingContacts = true
                    Task {
                        await GmailProfileService.shared.refreshContacts(accountID: accountID)
                        isRefreshingContacts = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        if isRefreshingContacts {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        Text(isRefreshingContacts ? "Refreshing…" : "Refresh")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.accentPrimary)
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingContacts)
            }
        }
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}

// MARK: - Signature Settings Card

struct SignatureSettingsCard: View {
    let aliases: [GmailSendAs]
    @Binding var signatureForNew: String
    @Binding var signatureForReply: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signatures")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            if aliases.isEmpty {
                Text("No aliases found")
                    .font(.system(size: 12))
                    .foregroundColor(theme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(aliases, id: \.sendAsEmail) { alias in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(alias.displayName ?? alias.sendAsEmail)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.textPrimary)
                                if alias.isPrimary == true {
                                    Text("Primary")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(theme.accentPrimary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(theme.accentPrimary.opacity(0.15)))
                                }
                            }
                            Text(alias.sendAsEmail)
                                .font(.system(size: 11))
                                .foregroundColor(theme.textTertiary)
                            if let sig = alias.signature, !sig.isEmpty {
                                Text(sig.strippingHTML.prefix(80) + (sig.strippingHTML.count > 80 ? "…" : ""))
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.textTertiary)
                                    .lineLimit(2)
                            } else {
                                Text("No signature")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.textTertiary)
                                    .italic()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider().background(theme.divider)

                HStack {
                    Text("New emails")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                    Spacer()
                    Picker("", selection: $signatureForNew) {
                        Text("Default").tag("")
                        ForEach(aliases, id: \.sendAsEmail) { alias in
                            Text(alias.displayName ?? alias.sendAsEmail).tag(alias.sendAsEmail)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                HStack {
                    Text("Replies & forwards")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                    Spacer()
                    Picker("", selection: $signatureForReply) {
                        Text("Default").tag("")
                        ForEach(aliases, id: \.sendAsEmail) { alias in
                            Text(alias.displayName ?? alias.sendAsEmail).tag(alias.sendAsEmail)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            }
        }
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
    }
}

// MARK: - Storage Settings Card

struct StorageSettingsCard: View {
    @ObservedObject var attachmentStore: AttachmentStore
    @State private var dbSize: Int64 = 0
    @State private var showClearConfirm = false
    @State private var isClearing = false
    @Environment(\.theme) private var theme

    private var formattedSize: String {
        let bytes = dbSize
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(theme.textPrimary)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Attachment index")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                    HStack(spacing: 8) {
                        Text(formattedSize)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(theme.textPrimary)
                        Text("\(attachmentStore.stats.total) attachments")
                            .font(.system(size: 11))
                            .foregroundColor(theme.textTertiary)
                    }
                }

                Spacer()

                Button {
                    showClearConfirm = true
                } label: {
                    HStack(spacing: 5) {
                        if isClearing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        Text(isClearing ? "Clearing..." : "Clear")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .disabled(isClearing || attachmentStore.stats.total == 0)
            }
        }
        .padding(20)
        .background(theme.cardBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        .onAppear { dbSize = AttachmentDatabase.shared.databaseSizeBytes() }
        .onChange(of: attachmentStore.stats.total) { _ in
            dbSize = AttachmentDatabase.shared.databaseSizeBytes()
        }
        .alert("Clear attachment index?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                isClearing = true
                AttachmentDatabase.shared.clearAll()
                attachmentStore.refresh()
                dbSize = AttachmentDatabase.shared.databaseSizeBytes()
                isClearing = false
            }
        } message: {
            Text("This will delete all \(attachmentStore.stats.total) indexed attachments (\(formattedSize)). Attachments will be re-indexed as you browse your emails.")
        }
    }
}

// MARK: - Refresh Status

struct RefreshStatusView: View {
    let lastRefreshedAt: Date?
    let refreshInterval: Int
    @State private var now: Date = Date()
    @Environment(\.theme) private var theme

    private var timer: Timer.TimerPublisher {
        Timer.publish(every: 1, on: .main, in: .common)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "clock.arrow.2.circlepath")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                Text(lastRefreshLabel)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
            HStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                Text(nextRefreshLabel)
                    .font(.system(size: 11))
                    .foregroundColor(theme.textTertiary)
                Spacer()
            }
        }
        .onReceive(timer.autoconnect()) { date in now = date }
    }

    private var lastRefreshLabel: String {
        guard let last = lastRefreshedAt else { return "Last refresh: never" }
        let elapsed = Int(now.timeIntervalSince(last))
        if elapsed < 60 { return "Last refresh: \(elapsed)s ago" }
        let mins = elapsed / 60
        return "Last refresh: \(mins) min ago"
    }

    private var nextRefreshLabel: String {
        guard let last = lastRefreshedAt else { return "Next refresh: soon" }
        let elapsed = now.timeIntervalSince(last)
        let remaining = max(0, Double(refreshInterval) - elapsed)
        let secs = Int(remaining)
        if secs < 60 { return "Next refresh: in \(secs)s" }
        let mins = secs / 60
        let rem  = secs % 60
        return rem > 0 ? "Next refresh: in \(mins)m \(rem)s" : "Next refresh: in \(mins)m"
    }
}
