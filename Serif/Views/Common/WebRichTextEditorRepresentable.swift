import SwiftUI
import WebKit

struct WebRichTextEditorRepresentable: NSViewRepresentable {
    @ObservedObject var state: WebRichTextEditorState
    @Binding var htmlContent: String
    var theme: Theme
    var placeholder: String
    var autoFocus: Bool
    var onFileDrop: ((URL) -> Void)?
    var onOpenLink: ((URL) -> Void)?

    func makeCoordinator() -> WebRichTextEditorCoordinator {
        WebRichTextEditorCoordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "editor")
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        let html = HTMLTemplate.editorHTML(
            textColor: theme.textPrimary.hexString,
            backgroundColor: "transparent",
            accentColor: theme.accentPrimary.hexString,
            placeholderColor: theme.textTertiary.hexString,
            placeholderText: placeholder,
            initialHTML: htmlContent
        )
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        // Update theme colors dynamically
        state.updateTheme(
            textColor: theme.textPrimary.hexString,
            bgColor: "transparent",
            accentColor: theme.accentPrimary.hexString,
            placeholderColor: theme.textTertiary.hexString
        )
    }
}
