import SwiftUI
import AppKit
import WebKit

/// Invisible view that captures global keyboard shortcuts.
/// Cmd+A, Cmd+Z, and Cmd+F are handled via NSEvent monitor to respect the responder chain
/// (text fields/editors get priority over global app shortcuts).
struct KeyboardShortcutsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            Button("") { coordinator.panelCoordinator.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("") { coordinator.panelCoordinator.closeAll() }
                .keyboardShortcut(.escape, modifiers: []).disabled(!coordinator.panelCoordinator.isAnyOpen)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .background(KeyboardEventMonitor(coordinator: coordinator))
    }
}

// MARK: - Responder-aware keyboard monitor

/// Uses NSEvent.addLocalMonitorForEvents to intercept key events
/// while respecting the first responder chain (text fields get native Cmd+A/Z/F).
private struct KeyboardEventMonitor: NSViewRepresentable {
    let coordinator: AppCoordinator

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.install()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.coordinator = coordinator
    }

    func makeCoordinator() -> Coordinator { Coordinator(coordinator: coordinator) }

    class Coordinator {
        var coordinator: AppCoordinator
        private var monitor: Any?

        init(coordinator: AppCoordinator) {
            self.coordinator = coordinator
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handleKeyDown(event)
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private var isTextInputFocused: Bool {
            guard let responder = NSApp.keyWindow?.firstResponder else { return false }
            if responder is NSTextView || responder is NSTextField { return true }
            // WKWebView uses an internal NSView subclass as first responder;
            // walk up the view hierarchy to detect it.
            var view = responder as? NSView
            while let v = view {
                if v is WKWebView { return true }
                view = v.superview
            }
            return false
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            // Escape — close any open panel (takes priority over everything)
            if event.keyCode == 53 {
                let panels = coordinator.panelCoordinator
                if MainActor.assumeIsolated({ panels.isAnyOpen }) {
                    DispatchQueue.main.async { panels.closeAll() }
                    return nil
                }
            }

            guard event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift) else { return event }

            switch event.charactersIgnoringModifiers {
            case "a":
                if isTextInputFocused { return event } // let native select-all handle it
                DispatchQueue.main.async { self.coordinator.selectAllEmails() }
                return nil

            case "z":
                if isTextInputFocused { return event } // let native undo handle it
                DispatchQueue.main.async { UndoActionManager.shared.undo() }
                return nil

            case "f":
                if isTextInputFocused { return event } // let native find handle it
                DispatchQueue.main.async { self.coordinator.searchFocusTrigger = true }
                return nil

            default:
                return event
            }
        }
    }
}
