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

    @ViewBuilder
    private func logEntryRow(_ entry: APILogEntry) -> some View {
        let isExpanded = expandedEntryID == entry.id
        VStack(alignment: .leading, spacing: 0) {
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
                        .foregroundColor(entry.statusColor)
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

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.textTertiary)
                        .textSelection(.enabled)

                    if let err = entry.errorMessage {
                        Text(err)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                    }

                    if !entry.responseBody.isEmpty {
                        ScrollView(.vertical) {
                            Text(entry.responseBody)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(theme.textSecondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
                    }

                    HStack {
                        Text("\(entry.responseSize) bytes")
                        Spacer()
                        Text(entry.date.formatted(.dateTime.hour().minute().second()))
                    }
                    .font(.system(size: 10))
                    .foregroundColor(theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .background(theme.detailBackground.opacity(0.5))
            }
        }
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
