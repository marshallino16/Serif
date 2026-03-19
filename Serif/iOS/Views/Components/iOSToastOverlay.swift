import SwiftUI

/// Positions undo and offline toasts just above the iOS tab bar.
struct iOSToastOverlay: View {
    @ObservedObject private var network = NetworkMonitor.shared
    @ObservedObject private var undoMgr = UndoActionManager.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 8) {
                // Offline toast
                if !network.isConnected {
                    offlineCard
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Undo toast
                if let action = undoMgr.currentAction {
                    undoCard(action)
                        .id(action.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 60) // above tab bar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(!network.isConnected || undoMgr.currentAction != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: network.isConnected)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: undoMgr.currentAction?.id)
    }

    // MARK: - Offline Card

    private var offlineCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
            Text("No internet connection")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardBackground)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Undo Card

    private func undoCard(_ action: PendingUndoAction) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(action.displayLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button("Undo") { undoMgr.undo() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.accentPrimary)
                    .buttonStyle(.plain)

                Text("\(max(1, Int(ceil(undoMgr.timeRemaining))))s")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(theme.textTertiary)
                    .frame(width: 26, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.divider)
                    Rectangle()
                        .fill(theme.accentPrimary.opacity(0.7))
                        .frame(width: geo.size.width * undoMgr.progress)
                        .animation(.linear(duration: 0.06), value: undoMgr.progress)
                }
            }
            .frame(height: 3)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.cardBackground)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
