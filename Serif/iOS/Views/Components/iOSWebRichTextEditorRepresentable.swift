import SwiftUI
import WebKit

struct iOSWebRichTextEditorRepresentable: UIViewRepresentable {
    @ObservedObject var state: WebRichTextEditorState
    @Binding var htmlContent: String
    var theme: Theme
    var placeholder: String
    var autoFocus: Bool
    var onFileDrop: ((URL) -> Void)?
    var onOpenLink: ((URL) -> Void)?

    func makeCoordinator() -> iOSWebRichTextEditorCoordinator {
        iOSWebRichTextEditorCoordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "editor")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Fix: WKWebView keeps bottom inset after keyboard dismissal
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil, queue: .main
        ) { _ in
            // Delay to let the keyboard animation finish
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                webView.scrollView.contentInset.bottom = 0
                webView.scrollView.verticalScrollIndicatorInsets.bottom = 0
            }
        }

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

    func updateUIView(_ webView: WKWebView, context: Context) {
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
