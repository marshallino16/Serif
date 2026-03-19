import WebKit

class iOSWebRichTextEditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var parent: iOSWebRichTextEditorRepresentable

    init(_ parent: iOSWebRichTextEditorRepresentable) {
        self.parent = parent
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else { return }

        Task { @MainActor in
            switch type {
            case "contentChanged":
                let isEmpty = dict["isEmpty"] as? Bool ?? false
                if isEmpty {
                    parent.htmlContent = ""
                } else if let html = dict["html"] as? String {
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
                    _ = filename
                }

            case "openLink":
                if let urlString = dict["url"] as? String, let url = URL(string: urlString) {
                    parent.onOpenLink?(url)
                }

            default:
                break
            }
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated {
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            parent.state.webView = webView
            if !parent.htmlContent.isEmpty {
                parent.state.setHTML(parent.htmlContent)
            }
            if parent.autoFocus {
                parent.state.focus()
            }
        }
    }

    // MARK: - Private

    private func handleDroppedImage(dataURL: String, mimeType: String, filename: String) {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return }
        let base64 = String(dataURL[dataURL.index(after: commaIndex)...])
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return }

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
