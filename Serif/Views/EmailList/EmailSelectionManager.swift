import SwiftUI
import AppKit

/// Handles multi-select logic: Cmd+click toggle, Shift+click range, single click, and arrow key navigation.
enum EmailSelectionManager {

    /// Process a tap on an email row, respecting Cmd and Shift modifiers.
    static func handleTap(
        email: Email,
        sortedEmails: [Email],
        selectedEmailIDs: inout Set<String>,
        selectedEmail: inout Email?,
        selectionAnchorID: inout String?
    ) {
        let id = email.id.uuidString
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            // Cmd+click: toggle in set
            if selectedEmailIDs.contains(id) {
                selectedEmailIDs.remove(id)
            } else {
                selectedEmailIDs.insert(id)
            }
            selectionAnchorID = id
            selectedEmail = selectedEmailIDs.count == 1
                ? sortedEmails.first { selectedEmailIDs.contains($0.id.uuidString) }
                : nil
        } else if modifiers.contains(.shift), let anchorID = selectionAnchorID {
            // Shift+click: range select
            let ids = sortedEmails.map { $0.id.uuidString }
            if let anchorIdx = ids.firstIndex(of: anchorID),
               let clickIdx = ids.firstIndex(of: id) {
                let range = min(anchorIdx, clickIdx)...max(anchorIdx, clickIdx)
                selectedEmailIDs = Set(ids[range])
                selectedEmail = nil
            }
        } else {
            // Normal click: single select
            selectedEmailIDs = [id]
            selectedEmail = email
            selectionAnchorID = id
        }
    }

    /// Navigate to the previous email in the sorted list.
    static func navigateToPrevious(
        sortedEmails: [Email],
        selectedEmailIDs: inout Set<String>,
        selectedEmail: inout Email?,
        selectionAnchorID: inout String?
    ) {
        guard let current = selectedEmail,
              let index = sortedEmails.firstIndex(where: { $0.id == current.id }),
              index > 0 else { return }
        let email = sortedEmails[index - 1]
        selectedEmailIDs = [email.id.uuidString]
        selectedEmail = email
        selectionAnchorID = email.id.uuidString
    }

    /// Navigate to the next email in the sorted list.
    static func navigateToNext(
        sortedEmails: [Email],
        selectedEmailIDs: inout Set<String>,
        selectedEmail: inout Email?,
        selectionAnchorID: inout String?
    ) {
        guard let current = selectedEmail,
              let index = sortedEmails.firstIndex(where: { $0.id == current.id }),
              index < sortedEmails.count - 1 else { return }
        let email = sortedEmails[index + 1]
        selectedEmailIDs = [email.id.uuidString]
        selectedEmail = email
        selectionAnchorID = email.id.uuidString
    }

    /// Select all emails in the sorted list.
    static func selectAll(
        sortedEmails: [Email],
        selectedEmailIDs: inout Set<String>,
        selectedEmail: inout Email?,
        selectionAnchorID: inout String?
    ) {
        selectedEmailIDs = Set(sortedEmails.map { $0.id.uuidString })
        selectedEmail = nil
        selectionAnchorID = sortedEmails.first?.id.uuidString
    }
}
