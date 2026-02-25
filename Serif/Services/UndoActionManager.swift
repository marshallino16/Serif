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

    @Published var pendingAction: PendingUndoAction?
    @Published var progress: Double = 1.0
    @Published var timeRemaining: Double = 0

    private var countdownTask: Task<Void, Never>?

    private init() {}

    func schedule(label: String, onConfirm: @escaping () -> Void, onUndo: @escaping () -> Void) {
        // Confirm any existing pending action immediately
        if let existing = pendingAction {
            countdownTask?.cancel()
            countdownTask = nil
            pendingAction = nil
            existing.onConfirm()
        }

        let stored = UserDefaults.standard.integer(forKey: "undoDuration")
        let duration = Double([5, 10, 20, 30].contains(stored) ? stored : 5)

        pendingAction = PendingUndoAction(label: label, onConfirm: onConfirm, onUndo: onUndo)
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

    func undo() {
        countdownTask?.cancel()
        countdownTask = nil
        let action = pendingAction
        pendingAction = nil
        action?.onUndo()
    }

    func confirm() {
        countdownTask?.cancel()
        countdownTask = nil
        let action = pendingAction
        pendingAction = nil
        action?.onConfirm()
    }
}
