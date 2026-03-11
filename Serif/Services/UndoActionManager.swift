import Foundation

struct PendingUndoAction: Identifiable {
    let id = UUID()
    let label: String
    let onConfirm: () -> Void
    let onUndo: () -> Void
}

@MainActor
final class UndoActionManager: ObservableObject {

    static let shared = UndoActionManager()

    /// Stack of pending actions (most recent = last). Max 5.
    @Published var pendingActions: [PendingUndoAction] = []
    @Published var progress: Double = 1.0
    @Published var timeRemaining: Double = 0

    private let maxStack = 5
    private var countdownTask: Task<Void, Never>?

    private init() {}

    /// The currently displayed action (most recent).
    var currentAction: PendingUndoAction? { pendingActions.last }

    func schedule(label: String, onConfirm: @escaping () -> Void, onUndo: @escaping () -> Void) {
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
        guard let action = pendingActions.popLast() else { return }
        action.onUndo()

        if !pendingActions.isEmpty {
            startCountdown()
        }
    }

    func confirm() {
        countdownTask?.cancel()
        countdownTask = nil
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
        let actions = pendingActions
        pendingActions.removeAll()
        for action in actions { action.onConfirm() }
    }

    private func startCountdown() {
        countdownTask?.cancel()

        let stored = UserDefaults.standard.integer(forKey: UserDefaultsKey.undoDuration)
        let duration = Double([5, 10, 20, 30].contains(stored) ? stored : 5)

        progress = 1.0
        timeRemaining = duration

        countdownTask = Task { [weak self] in
            guard let self else { return }
            let totalSteps = Int(duration * 20) // 50ms intervals
            for step in (0..<totalSteps).reversed() {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                self.progress = Double(step) / Double(totalSteps)
                self.timeRemaining = Double(step) / 20.0
            }
            guard !Task.isCancelled else { return }
            self.confirm()
        }
    }
}
