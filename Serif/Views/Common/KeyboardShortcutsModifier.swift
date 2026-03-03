import SwiftUI

/// Invisible view that captures global keyboard shortcuts.
struct KeyboardShortcutsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Group {
            Button("") { coordinator.panelCoordinator.openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("") { coordinator.panelCoordinator.closeAll() }
                .keyboardShortcut(.escape, modifiers: []).disabled(!coordinator.panelCoordinator.isAnyOpen)
            Button("") { UndoActionManager.shared.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("") { coordinator.searchFocusTrigger = true }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { coordinator.selectAllEmails() }
                .keyboardShortcut("a", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }
}
