import WebKit

class WebRichTextEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var parent: WebRichTextEditorRepresentable

    init(_ parent: WebRichTextEditorRepresentable) {
        self.parent = parent
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "contentChanged":
                if let html = dict["html"] as? String {
                    parent.htmlContent = html
                }

            case "selectionChanged":
                parent.state.handleSelectionChanged(dict)

            case "imageDropped":
                if let dataURL = dict["data"] as? String,
                   let mimeType = dict["mimeType"] as? String {
                    handleDroppedImage(dataURL: dataURL, mimeType: mimeType, filename: dict["filename"] as? String ?? "image")
                }

            case "fileDropped":
                if let filename = dict["filename"] as? String {
                    // Non-image files dropped in editor — notify via onFileDrop with a temp path
                    // For now, just post a toast since we can't get the actual file URL from JS
                    _ = filename
                }

            default:
                break
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            parent.state.webView = webView
            if parent.autoFocus {
                parent.state.focus()
            }
        }
    }

    // MARK: - Private

    private func handleDroppedImage(dataURL: String, mimeType: String, filename: String) {
        // Extract base64 data from data URL
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return }

        // Write to temp file and use insertImage
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(filename)
        do {
            try data.write(to: tempURL)
            Task { @MainActor in
                parent.state.insertImage(from: tempURL)
            }
        } catch {}
    }
}
