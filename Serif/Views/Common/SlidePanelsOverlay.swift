import SwiftUI

struct SlidePanelsOverlay: View {
    @ObservedObject var panels: PanelCoordinator

    @ObservedObject var themeManager: ThemeManager
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var selectedAccountID: String?
    @Binding var undoDuration: Int
    @Binding var refreshInterval: Int
    var lastRefreshedAt: Date?
    @Binding var signatureForNew: String
    @Binding var signatureForReply: String
    var sendAsAliases: [GmailSendAs]
    var onAliasesUpdated: (() -> Void)?
    @ObservedObject var attachmentStore: AttachmentStore

    @Environment(\.theme) private var theme

    var body: some View {
        settingsPanel
        helpPanel
        #if DEBUG
        debugPanel
        #endif
        originalPanel
        attachmentPanel
        webBrowserOverlay
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        SlidePanel(isPresented: $panels.showSettings, title: "Settings") {
            VStack(alignment: .leading, spacing: 16) {
                ThemePickerView(themeManager: themeManager)
                AccountsSettingsView(authViewModel: authViewModel, selectedAccountID: $selectedAccountID)
                BehaviorSettingsCard(
                    undoDuration: $undoDuration,
                    refreshInterval: $refreshInterval,
                    lastRefreshedAt: lastRefreshedAt
                )
                ContactsSettingsCard(
                    accountID: selectedAccountID ?? authViewModel.primaryAccount?.id ?? ""
                )
                SignatureSettingsCard(
                    aliases: sendAsAliases,
                    accountID: selectedAccountID ?? authViewModel.primaryAccount?.id ?? "",
                    signatureForNew: $signatureForNew,
                    signatureForReply: $signatureForReply,
                    onAliasesUpdated: { onAliasesUpdated?() }
                )
                StorageSettingsCard(attachmentStore: attachmentStore)
                #if DEBUG
                DeveloperSettingsCard()
                #endif
            }
            .padding(20)
        }
        .environment(\.theme, theme)
        .zIndex(10)
    }

    // MARK: - Help

    private var helpPanel: some View {
        SlidePanel(isPresented: $panels.showHelp, title: "Keyboard Shortcuts") {
            ShortcutsHelpView()
        }
        .environment(\.theme, theme)
        .zIndex(10)
    }

    // MARK: - Debug

    #if DEBUG
    private var debugPanel: some View {
        SlidePanel(isPresented: $panels.showDebug, title: "Debug") {
            DebugMenuView(accountID: selectedAccountID ?? authViewModel.primaryAccount?.id ?? "")
        }
        .environment(\.theme, theme)
        .zIndex(10)
    }
    #endif

    // MARK: - Original Message

    private var originalPanel: some View {
        SlidePanel(isPresented: $panels.showOriginal, title: "Original Message") {
            if let msg = panels.originalMessage {
                OriginalMessageView(
                    message: msg,
                    rawSource: panels.originalRawSource,
                    isLoading: panels.isLoadingOriginal
                )
            } else {
                VStack {
                    Spacer()
                    ProgressView().tint(theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.theme, theme)
        .zIndex(10)
    }

    // MARK: - Attachment Preview

    private var attachmentPanel: some View {
        SlidePanel(isPresented: $panels.showAttachmentPreview, title: panels.attachmentPreviewName, scrollable: false) {
            if let data = panels.attachmentPreviewData {
                AttachmentPreviewView(
                    data: data,
                    fileName: panels.attachmentPreviewName,
                    fileType: panels.attachmentPreviewFileType,
                    onDownload: { saveAttachment(data: data, name: panels.attachmentPreviewName) },
                    onClose: { panels.showAttachmentPreview = false }
                )
            } else {
                VStack {
                    Spacer()
                    ProgressView().tint(theme.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .environment(\.theme, theme)
        .zIndex(10)
    }

    // MARK: - Web Browser

    private var webBrowserOverlay: some View {
        Group {
            if panels.showWebBrowser, let url = panels.webBrowserURL {
                InAppBrowserView(url: url) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        panels.showWebBrowser = false
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .zIndex(20)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: panels.showWebBrowser)
    }

    private func saveAttachment(data: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }
}
