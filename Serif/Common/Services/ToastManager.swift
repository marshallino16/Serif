import Foundation

enum ToastType {
    case success, error, info
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let type: ToastType

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()
    private init() {}

    @Published var currentToast: ToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(message: String, type: ToastType = .info, duration: Double = 3.5) {
        dismissTask?.cancel()
        currentToast = ToastMessage(message: message, type: type)
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            currentToast = nil
        }
    }
}
