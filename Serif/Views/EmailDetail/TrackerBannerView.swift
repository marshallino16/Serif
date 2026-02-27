import SwiftUI

struct TrackerBannerView: View {
    let trackerCount: Int
    let onAllow: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 13))
                .foregroundColor(theme.accentPrimary)

            Text("\(trackerCount) tracker\(trackerCount > 1 ? "s" : "") blocked")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.textPrimary)

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
        .background(theme.cardBackground)
        .cornerRadius(8)
    }
}
