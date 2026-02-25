import SwiftUI

struct UndoToastView: View {
    @ObservedObject private var undoMgr = UndoActionManager.shared
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()
            if let action = undoMgr.pendingAction {
                toastCard(action)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 28)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: undoMgr.pendingAction == nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(undoMgr.pendingAction != nil)
    }

    private func toastCard(_ action: PendingUndoAction) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(action.label)
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
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 320)
    }
}
