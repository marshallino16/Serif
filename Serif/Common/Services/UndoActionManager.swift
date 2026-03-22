import SwiftUI

struct PendingUndoAction: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    private let confirmCallbacks: [() -> Void]
    private let undoCallbacks: [() -> Void]

    init(label: String, count: Int = 1, onConfirm: @escaping () -> Void, onUndo: @escaping () -> Void) {
        self.label = label
        self.count = count
        self.confirmCallbacks = [onConfirm]
        self.undoCallbacks = [onUndo]
    }

    private init(label: String, count: Int, confirmCallbacks: [() -> Void], undoCallbacks: [() -> Void]) {
        self.label = label
        self.count = count
        self.confirmCallbacks = confirmCallbacks
        self.undoCallbacks = undoCallbacks
    }

    func merged(onConfirm: @escaping () -> Void, onUndo: @escaping () -> Void) -> PendingUndoAction {
        PendingUndoAction(
            label: label,
            count: count + 1,
            confirmCallbacks: confirmCallbacks + [onConfirm],
            undoCallbacks: undoCallbacks + [onUndo]
        )
    }

    var displayLabel: String {
        count > 1 ? "\(label) (\(count))" : label
    }

    func onConfirm() { for cb in confirmCallbacks { cb() } }
    func onUndo()    { for cb in undoCallbacks { cb() } }
}

@MainActor
final class UndoActionManager: ObservableObject {

    static let shared = UndoActionManager()

    /// Stack of pending actions (most recent = last). Max 20.
    @Published var pendingActions: [PendingUndoAction] = []
    @Published var progress: Double = 1.0
    @Published var timeRemaining: Double = 0

    private let maxStack = 20
    private var countdownTask: Task<Void, Never>?

    private init() {}

    /// The currently displayed action (most recent).
    var currentAction: PendingUndoAction? { pendingActions.last }

    func schedule(label: String, onConfirm: @escaping () -> Void, onUndo: @escaping () -> Void) {
        // Group with current action if same label and timer is running
        if let last = pendingActions.last, last.label == label, countdownTask != nil {
            pendingActions[pendingActions.count - 1] = last.merged(onConfirm: onConfirm, onUndo: onUndo)
            startCountdown()
            return
        }

        // If stack is full, confirm the oldest action to make room
        if pendingActions.count >= maxStack {
            let oldest = pendingActions.removeFirst()
            oldest.onConfirm()
        }

        let action = PendingUndoAction(label: label, onConfirm: onConfirm, onUndo: onUndo)
        pendingActions.append(action)
        startCountdown()
    }

    func undo() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation(.none) { progress = 0 }
        guard let action = pendingActions.popLast() else { return }
        action.onUndo()

        if !pendingActions.isEmpty {
            startCountdown()
        }
    }

    func confirm() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation(.none) { progress = 0 }
        guard let action = pendingActions.popLast() else { return }
        action.onConfirm()

        if !pendingActions.isEmpty {
            startCountdown()
        }
    }

    /// Confirms all remaining actions in the stack immediately.
    func confirmAll() {
        countdownTask?.cancel()
        countdownTask = nil
        withAnimation(.none) { progress = 0 }
        let actions = pendingActions
        pendingActions.removeAll()
        for action in actions { action.onConfirm() }
    }

    private func startCountdown() {
        countdownTask?.cancel()

        let stored = UserDefaults.standard.integer(forKey: "undoDuration")
        let duration = Double([5, 10, 20, 30].contains(stored) ? stored : 5)

        // Reset progress without animation, then animate to 0 (GPU-driven)
        withAnimation(.none) { progress = 1.0 }
        timeRemaining = duration

        // Kick off the smooth animation on the next frame
        Task { @MainActor in
            withAnimation(.linear(duration: duration)) {
                self.progress = 0.0
            }
        }

        countdownTask = Task { [weak self] in
            guard let self else { return }
            // Update timeRemaining once per second (label only)
            let seconds = Int(duration)
            for i in 1...seconds {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self.timeRemaining = duration - Double(i)
            }
            guard !Task.isCancelled else { return }
            self.confirm()
        }
    }
}
