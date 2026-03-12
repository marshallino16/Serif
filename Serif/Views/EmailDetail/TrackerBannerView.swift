import SwiftUI

struct TrackerBannerView: View {
    let trackerCount: Int
    let trackers: [TrackerInfo]
    let onAllow: () -> Void

    @State private var showDetails = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 13))
                    .foregroundColor(theme.accentPrimary)

                Text("\(trackerCount) tracker\(trackerCount > 1 ? "s" : "") blocked")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.textPrimary)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDetails.toggle()
                    }
                } label: {
                    Text(showDetails ? "Hide details" : "Show details")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onAllow()
                } label: {
                    Text("Load blocked content")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(theme.accentPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(theme.accentPrimary.opacity(0.12))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if showDetails {
                Divider()
                    .padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(groupedTrackers, id: \.name) { group in
                        HStack(spacing: 8) {
                            Image(systemName: group.icon)
                                .font(.system(size: 10))
                                .foregroundColor(theme.textTertiary)
                                .frame(width: 14)
                            Text(group.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.textPrimary)
                            if group.count > 1 {
                                Text("×\(group.count)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(theme.textTertiary)
                            }
                            Spacer()
                            Text(group.kindLabel)
                                .font(.system(size: 10))
                                .foregroundColor(theme.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(theme.cardBackground)
        .cornerRadius(8)
    }

    // MARK: - Grouped trackers

    private struct TrackerGroup: Hashable {
        let name: String
        let kind: TrackerKind
        let count: Int
        var icon: String {
            switch kind {
            case .pixel:        return "circle.fill"
            case .knownTracker: return "antenna.radiowaves.left.and.right"
            case .cssTracker:   return "paintbrush"
            case .trackingLink: return "link"
            }
        }
        var kindLabel: String {
            switch kind {
            case .pixel:        return "Pixel"
            case .knownTracker: return "Tracker"
            case .cssTracker:   return "CSS"
            case .trackingLink: return "Link"
            }
        }
    }

    private var groupedTrackers: [TrackerGroup] {
        var counts: [String: (kind: TrackerKind, count: Int)] = [:]
        for t in trackers {
            let name = t.serviceName ?? t.source
            if let existing = counts[name] {
                counts[name] = (existing.kind, existing.count + 1)
            } else {
                counts[name] = (t.kind, 1)
            }
        }
        return counts.map { TrackerGroup(name: $0.key, kind: $0.value.kind, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
}
