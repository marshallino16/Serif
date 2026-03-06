import SwiftUI

@MainActor
class PanelCoordinator: ObservableObject {
    // MARK: - Panel visibility

    @Published var showSettings = false
    @Published var showHelp = false
    @Published var showDebug = false
    @Published var showOriginal = false
    @Published var showAttachmentPreview = false
    @Published var showWebBrowser = false

    // MARK: - Web browser data

    @Published var webBrowserURL: URL?

    // MARK: - Original message data

    @Published var originalMessage: GmailMessage?
    @Published var originalRawSource: String?
    @Published var isLoadingOriginal = false

    // MARK: - Email preview data

    @Published var showEmailPreview = false
    @Published var previewEmail: Email?
    @Published var previewAccountID = ""

    // MARK: - Attachment preview data

    @Published var attachmentPreviewData: Data?
    @Published var attachmentPreviewName = ""
    @Published var attachmentPreviewFileType: Attachment.FileType = .document

    var isAnyOpen: Bool {
        showSettings || showHelp || showDebug || showAttachmentPreview || showOriginal || showWebBrowser || showEmailPreview
    }

    func closeAll() {
        showSettings = false
        showHelp = false
        showDebug = false
        showAttachmentPreview = false
        showOriginal = false
        showWebBrowser = false
        showEmailPreview = false
    }

    func openSettings() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showSettings = true
        }
    }

    func previewAttachment(data: Data?, name: String, fileType: Attachment.FileType) {
        attachmentPreviewData = data
        attachmentPreviewName = name
        attachmentPreviewFileType = fileType
        if !showAttachmentPreview {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                showAttachmentPreview = true
            }
        }
    }

    func showOriginalMessage(from vm: EmailDetailViewModel) {
        guard let msg = vm.latestMessage else { return }
        originalMessage = msg
        originalRawSource = nil
        isLoadingOriginal = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showOriginal = true
        }
        Task {
            do {
                let raw = try await GmailMessageService.shared.getRawMessage(id: msg.id, accountID: vm.accountID)
                self.originalRawSource = raw.rawSource
            } catch {
                self.originalRawSource = nil
            }
            self.isLoadingOriginal = false
        }
    }

    func showEmail(_ email: Email, accountID: String) {
        previewEmail = email
        previewAccountID = accountID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showEmailPreview = true
        }
    }

    func openInAppBrowser(url: URL) {
        webBrowserURL = url
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showWebBrowser = true
        }
    }

    func downloadMessage(from vm: EmailDetailViewModel) {
        guard let msg = vm.latestMessage else { return }
        Task {
            do {
                let raw = try await GmailMessageService.shared.getRawMessage(id: msg.id, accountID: vm.accountID)
                if let source = raw.rawSource {
                    await MainActor.run {
                        let panel = NSSavePanel()
                        panel.nameFieldStringValue = "\(msg.subject).eml"
                        panel.canCreateDirectories = true
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        try? source.data(using: .utf8)?.write(to: url)
                    }
                }
            } catch { }
        }
    }
}
