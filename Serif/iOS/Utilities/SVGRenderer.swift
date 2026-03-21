#if os(iOS)
import UIKit
import WebKit

/// Rasterizes SVG data to UIImage using an offscreen WKWebView + canvas.
/// UIImage doesn't support SVG natively — this is needed for BIMI brand logos.
@MainActor
enum SVGRenderer {
    static func render(svgData: Data, size: CGFloat = 128) async -> UIImage? {
        let helper = RenderHelper()
        return await helper.render(svgData: svgData, size: size)
    }
}

@MainActor
private final class RenderHelper: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var webView: WKWebView?
    private var size: CGFloat = 128
    private var timeoutTask: Task<Void, Never>?

    func render(svgData: Data, size: CGFloat) async -> UIImage? {
        self.size = size
        let frame = CGRect(x: 0, y: 0, width: size, height: size)
        let wv = WKWebView(frame: frame)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.navigationDelegate = self
        self.webView = wv

        let base64 = svgData.base64EncodedString()
        let s = Int(size)
        let html = """
        <html><head><meta name="viewport" content="width=\(s),initial-scale=1">
        <style>*{margin:0;padding:0}html,body{width:\(s)px;height:\(s)px;overflow:hidden;background:transparent}
        img{width:100%;height:100%;object-fit:contain}</style></head>
        <body><img id="svg" src="data:image/svg+xml;base64,\(base64)"></body></html>
        """

        return await withCheckedContinuation { cont in
            self.continuation = cont
            // Timeout after 5 seconds
            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                self.finish(with: nil)
            }
            wv.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let s = Int(size)
        let js = """
        (function() {
            var img = document.getElementById('svg');
            if (!img || !img.complete || img.naturalWidth === 0) return '';
            var c = document.createElement('canvas');
            c.width = \(s); c.height = \(s);
            var ctx = c.getContext('2d');
            ctx.drawImage(img, 0, 0, \(s), \(s));
            return c.toDataURL('image/png');
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            var image: UIImage?
            if let dataURL = result as? String,
               let range = dataURL.range(of: "base64,"),
               let data = Data(base64Encoded: String(dataURL[range.upperBound...])) {
                image = UIImage(data: data)
            }
            self.finish(with: image)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: nil)
    }

    private func finish(with image: UIImage?) {
        guard let cont = continuation else { return }
        continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        webView?.navigationDelegate = nil
        webView = nil
        cont.resume(returning: image)
    }
}
#endif
