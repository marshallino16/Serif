import SwiftUI

#if DEBUG
struct DebugMenuView: View {
    @AppStorage("isSignedIn") private var isSignedIn: Bool = false
    @ObservedObject private var logger = APILogger.shared
    @State private var cacheCount = 0
    @State private var expandedEntryID: UUID?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // MARK: - Onboarding
            debugSection(title: "Onboarding") {
                debugButton(icon: "arrow.counterclockwise", label: "Show Onboarding") {
                    isSignedIn = false
                }
            }

            // MARK: - API Request Log
            debugSection(title: "API Request Log (\(logger.entries.count))") {
                if logger.entries.isEmpty {
                    Text("No requests yet")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(logger.entries.reversed()) { entry in
                            logEntryRow(entry)
                            if entry.id != logger.entries.first?.id {
                                Divider().background(theme.divider)
                            }
                        }
                    }
                    .background(theme.cardBackground)
                    .cornerRadius(8)
                }

                debugButton(icon: "trash", label: "Clear Log") {
                    logger.clear()
                    expandedEntryID = nil
                }
            }

            // MARK: - API Cache
            debugSection(title: "API Cache") {
                HStack {
                    Text("\(cacheCount) response\(cacheCount == 1 ? "" : "s") cached")
                        .font(.system(size: 12))
                        .foregroundColor(theme.textTertiary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { APICache.shared.isEnabled },
                        set: { APICache.shared.isEnabled = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                debugButton(icon: "trash", label: "Clear API Cache") {
                    APICache.shared.clear()
                    cacheCount = APICache.shared.cachedResponseCount
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            cacheCount = APICache.shared.cachedResponseCount
        }
    }

    // MARK: - Log Entry Row

    @ViewBuilder
    private func logEntryRow(_ entry: APILogEntry) -> some View {
        let isExpanded = expandedEntryID == entry.id
        VStack(alignment: .leading, spacing: 0) {

            // ── Collapsed header ──
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedEntryID = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(spacing: 6) {
                    Text(entry.fromCache ? "CACHE" : entry.method)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(entry.fromCache ? Color.gray : (entry.method == "GET" ? Color.blue : Color.orange))
                        .cornerRadius(3)

                    Text(entry.shortPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if !entry.fromCache {
                        Text("\(entry.durationMs)ms")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textTertiary)
                    }

                    Text(entry.statusLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(statusColor(for: entry.statusLevel))
                        .frame(width: 40, alignment: .trailing)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ── Expanded detail ──
            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {

                    // REQUEST block
                    detailSectionLabel("REQUEST")

                    monoBlock {
                        Text("\(entry.method) \(entry.path)")
                            .foregroundColor(theme.textPrimary)
                    }

                    if !entry.requestHeaders.isEmpty {
                        monoBlock {
                            ForEach(entry.requestHeaders.keys.sorted(), id: \.self) { key in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(key + ": ")
                                        .foregroundColor(theme.textTertiary)
                                    Text(entry.requestHeaders[key] ?? "")
                                        .foregroundColor(theme.textSecondary)
                                }
                            }
                        }
                    }

                    if let reqBody = entry.requestBody, !reqBody.isEmpty {
                        detailSectionLabel("REQUEST BODY")
                        scrollableMonoBlock(reqBody, maxHeight: 120)
                    }

                    // RESPONSE block
                    HStack {
                        detailSectionLabel("RESPONSE")
                        if let err = entry.errorMessage {
                            Text(err)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.red)
                        }
                        Spacer()
                        Text("\(entry.responseSize) bytes · \(entry.date.formatted(.dateTime.hour().minute().second()))")
                            .font(.system(size: 10))
                            .foregroundColor(theme.textTertiary)
                    }

                    if !entry.responseHeaders.isEmpty {
                        monoBlock {
                            ForEach(entry.responseHeaders.keys.sorted(), id: \.self) { key in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(key + ": ")
                                        .foregroundColor(theme.textTertiary)
                                    Text(entry.responseHeaders[key] ?? "")
                                        .foregroundColor(theme.textSecondary)
                                }
                            }
                        }
                    }

                    if !entry.responseBody.isEmpty {
                        HStack {
                            if entry.bodyTruncated {
                                Text("Body truncated at 200 KB")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(entry.responseBody, forType: .string)
                            } label: {
                                Label("Copy body", systemImage: "doc.on.doc")
                                    .font(.system(size: 10))
                                    .foregroundColor(theme.accentPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 4)

                        scrollableMonoBlock(entry.responseBody, maxHeight: 360)
                    }
                }
                .padding(.bottom, 8)
                .background(theme.detailBackground.opacity(0.6))
            }
        }
    }

    // MARK: - Sub-components

    private func detailSectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(theme.textTertiary)
            .tracking(1)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func monoBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            content()
        }
        .font(.system(size: 10, design: .monospaced))
        .textSelection(.enabled)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func scrollableMonoBlock(_ text: String, maxHeight: CGFloat) -> some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(maxHeight: maxHeight)
        .background(theme.listBackground)
        .cornerRadius(4)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func debugSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(theme.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }

    private func statusColor(for level: APILogEntry.StatusLevel) -> Color {
        switch level {
        case .success: return theme.accentSecondary
        case .cached:  return theme.textTertiary
        case .warning: return theme.unreadIndicator
        case .error:   return theme.destructive
        }
    }

    private func debugButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(theme.accentPrimary)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(theme.cardBackground)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
#endif
