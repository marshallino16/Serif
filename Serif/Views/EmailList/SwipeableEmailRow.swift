import SwiftUI
import AppKit

// MARK: - View

struct SwipeableEmailRow: View {
    let email: Email
    let isSelected: Bool
    let onTap: () -> Void
    let onArchive: (() -> Void)?
    let onDelete: (() -> Void)?

    @StateObject private var state = SwipeRowState()
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            if state.dragOffset > 0 {
                archiveBg
            } else if state.dragOffset < 0 {
                deleteBg
            }

            EmailRowView(email: email, isSelected: isSelected, action: onTap)
                .offset(x: state.dragOffset)
        }
        .frame(height: state.isCollapsed ? 0 : nil)
        .clipped()
        .onHover { state.isHovered = $0 }
        .onAppear {
            state.onArchive = onArchive
            state.onDelete  = onDelete
            state.attach()
        }
        .onDisappear { state.detach() }
    }

    private var archiveBg: some View {
        theme.accentSecondary
            .overlay(
                HStack(spacing: 6) {
                    Image(systemName: "archivebox.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Archive")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                }
                .foregroundColor(theme.textInverse)
                .padding(.leading, 20)
            )
    }

    private var deleteBg: some View {
        theme.destructive
            .overlay(
                HStack(spacing: 6) {
                    Spacer()
                    Text("Delete")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(theme.textInverse)
                .padding(.trailing, 20)
            )
    }
}

// MARK: - State

@MainActor
final class SwipeRowState: ObservableObject {
    @Published var dragOffset: CGFloat = 0
    @Published var isCollapsed = false

    let threshold: CGFloat = 80

    var isHovered    = false
    var onArchive: (() -> Void)?
    var onDelete:  (() -> Void)?

    private var accumX:           CGFloat = 0
    private var isHoriz:          Bool?   = nil
    private var isDismissing              = false
    private var monitor:          Any?

    // MARK: Lifecycle

    func attach() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            self?.process(event) ?? event
        }
    }

    func detach() {
        if isHoriz == true { SwipeCoordinator.shared.isSwipeActive = false }
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    // MARK: Event processing

    private func process(_ event: NSEvent) -> NSEvent? {
        let tracking = isHoriz == true
        guard (isHovered || tracking), !isDismissing else { return event }

        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 10
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10

        switch event.phase {
        case .began:
            accumX  = 0
            isHoriz = nil

        case .changed:
            if isHoriz == nil {
                if abs(dx) > abs(dy) * 1.3 {
                    isHoriz = true
                    SwipeCoordinator.shared.isSwipeActive = true  // lock scroll
                } else if abs(dy) > abs(dx) * 1.3 {
                    isHoriz = false
                }
            }
            if isHoriz == true {
                accumX += dx
                withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.85)) {
                    dragOffset = rubberbanded(accumX)
                }
                return nil  // consume horizontal swipe
            }
            if isHoriz == nil { return nil }  // consume during disambiguation

        case .ended, .cancelled:
            if isHoriz == true {
                SwipeCoordinator.shared.isSwipeActive = false  // unlock scroll
                finalize()
                accumX  = 0
                isHoriz = nil
                return nil
            }
            accumX  = 0
            isHoriz = nil

        default:
            break
        }

        return event
    }

    // MARK: Helpers

    private func rubberbanded(_ delta: CGFloat) -> CGFloat {
        guard abs(delta) > threshold else { return delta }
        let excess = abs(delta) - threshold
        let sign: CGFloat = delta > 0 ? 1 : -1
        return sign * (threshold + excess * 0.3)
    }

    private func finalize() {
        if dragOffset >= threshold {
            dismiss(right: true)
        } else if dragOffset <= -threshold {
            dismiss(right: false)
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                dragOffset = 0
            }
        }
    }

    private func dismiss(right: Bool) {
        isDismissing = true
        withAnimation(.easeIn(duration: 0.22)) {
            dragOffset = right ? 500 : -500
        }
        let action = right ? onArchive : onDelete

        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeOut(duration: 0.18)) { self.isCollapsed = true }
            action?()
        }
    }

    func undoDismiss() {
        isDismissing = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
            isCollapsed = false
            dragOffset  = 0
        }
    }
}

// MARK: - SwipeCoordinator

@MainActor
final class SwipeCoordinator: ObservableObject {
    static let shared = SwipeCoordinator()
    @Published var isSwipeActive = false
    private init() {}
}
