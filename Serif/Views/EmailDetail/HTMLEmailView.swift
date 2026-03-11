import WebKit
import SwiftUI

// Forwards all scroll events to the parent responder so the SwiftUI
// ScrollView (not the WebView) handles vertical scrolling.
private class PassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    // Prevent this read-only WebView from setting a text cursor,
    // which causes flickering when overlapping with the reply editor.
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }
}

struct HTMLEmailView: NSViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    var onOpenLink: ((URL) -> Void)?
    @Environment(\.theme) private var theme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "imageLog")
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        #if DEBUG
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif
        let webView = PassthroughWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let textHex = theme.textPrimary.hexString
        let cacheKey = "\(html)|\(textHex)"
        guard context.coordinator.lastCacheKey != cacheKey else { return }
        context.coordinator.lastCacheKey = cacheKey
        context.coordinator.isLoadingContent = true
        // Defer height reset so SwiftUI processes it after the current render pass.
        // This shrinks the frame before didFinish measures the new content.
        DispatchQueue.main.async {
            self.contentHeight = 1
        }

        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        let userScript = WKUserScript(
            source: Self.userScriptSource(textHex: textHex),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(userScript)

        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name='viewport' content='width=device-width, initial-scale=1'>
        <meta name='color-scheme' content='light dark'>
        <style>
        html, body {
            margin: 0;
            padding: 0;
            overflow: hidden;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif;
            font-size: 14px;
            line-height: 1.65;
            color: \(textHex);
            background-color: transparent;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        img { max-width: 100% !important; height: auto !important; }
        a { color: #1a73e8; }
        blockquote { border-left: 3px solid #dadce0; margin: 8px 0; padding: 4px 12px; color: #5f6368; }
        pre, code { font-family: 'SF Mono', 'Menlo', monospace; font-size: 12px; background: rgba(0,0,0,0.06); padding: 2px 4px; border-radius: 3px; }
        table { border-collapse: collapse; }
        * { box-sizing: border-box; max-width: 100% !important; cursor: default !important; }

        @media (prefers-color-scheme: dark) {
            a { color: #8ab4f8; }
            blockquote { border-left-color: #5f6368; color: #9aa0a6; }
            pre, code { background: rgba(255,255,255,0.1); color: #e8eaed; }
        }
        </style>
        </head>
        <body><div id="emailContent" style="padding-bottom:16px">\(html)</div></body>
        </html>
        """
        webView.loadHTMLString(fullHTML, baseURL: nil)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "imageLog")
    }

    // MARK: - User Script

    private static func userScriptSource(textHex: String) -> String {
        """
        var THEME_TEXT = '\(textHex)';

        function fixDarkModeColors() {
            if (!window.matchMedia('(prefers-color-scheme: dark)').matches) return;

            var BG_LUM = 0.015;
            var MIN_CR = 4.0;

            function linearize(c) {
                c /= 255;
                return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
            }
            function relativeLum(r, g, b) {
                return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b);
            }
            function contrastWith(lum) {
                var hi = Math.max(lum, BG_LUM), lo = Math.min(lum, BG_LUM);
                return (hi + 0.05) / (lo + 0.05);
            }
            function parseRgb(s) {
                var i = s.indexOf('(');
                if (i < 0) return null;
                var parts = s.slice(i + 1).split(',');
                return parts.length >= 3 ? [parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2])] : null;
            }
            function hue2rgb(p, q, t) {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1/6) return p + (q - p) * 6 * t;
                if (t < 0.5) return q;
                if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                return p;
            }
            function lightenToContrast(r, g, b) {
                r /= 255; g /= 255; b /= 255;
                var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                var h = 0, s = 0, l = (mx + mn) / 2;
                if (mx !== mn) {
                    var d = mx - mn;
                    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
                    if      (mx === r) h = (g - b) / d + (g < b ? 6 : 0);
                    else if (mx === g) h = (b - r) / d + 2;
                    else               h = (r - g) / d + 4;
                    h /= 6;
                }
                for (var tl = Math.max(l + 0.1, 0.55); tl <= 1.0; tl += 0.04) {
                    var q2 = tl < 0.5 ? tl * (1 + s) : tl + s - tl * s;
                    var p2 = 2 * tl - q2;
                    var nr = Math.round(hue2rgb(p2, q2, h + 1/3) * 255);
                    var ng = Math.round(hue2rgb(p2, q2, h)       * 255);
                    var nb = Math.round(hue2rgb(p2, q2, h - 1/3) * 255);
                    if (contrastWith(relativeLum(nr, ng, nb)) >= MIN_CR)
                        return 'rgb(' + nr + ',' + ng + ',' + nb + ')';
                }
                return THEME_TEXT;
            }

            function isAchromatic(r, g, b) {
                var mx = Math.max(r, g, b), mn = Math.min(r, g, b);
                return (mx - mn) < 30 && mx < 80;
            }

            // Walk ancestors to find the nearest explicit background
            function effectiveBgLum(el) {
                var node = el;
                while (node && node !== document.documentElement) {
                    var bg = window.getComputedStyle(node).backgroundColor;
                    var rgba = parseRgb(bg);
                    if (rgba) {
                        // Check alpha — rgba(0,0,0,0) means transparent
                        var parts = bg.slice(bg.indexOf('(') + 1).split(',');
                        var alpha = parts.length >= 4 ? parseFloat(parts[3]) : 1;
                        if (alpha > 0.1) return relativeLum(rgba[0], rgba[1], rgba[2]);
                    }
                    node = node.parentElement;
                }
                return BG_LUM; // no explicit bg → assume dark theme background
            }

            function processEl(el) {
                var c = window.getComputedStyle(el).color;
                var rgb = parseRgb(c);
                if (!rgb) return;
                var bgLum = effectiveBgLum(el);
                // If element sits on a light background (lum > 0.4), skip — text is already readable
                if (bgLum > 0.4) return;
                var textLum = relativeLum(rgb[0], rgb[1], rgb[2]);
                var hi = Math.max(textLum, bgLum), lo = Math.min(textLum, bgLum);
                var cr = (hi + 0.05) / (lo + 0.05);
                if (cr >= MIN_CR) return;
                var replacement = isAchromatic(rgb[0], rgb[1], rgb[2])
                    ? THEME_TEXT
                    : lightenToContrast(rgb[0], rgb[1], rgb[2]);
                el.style.setProperty('color', replacement, 'important');
            }

            document.querySelectorAll(
                'body,p,div,span,td,th,li,a,font,b,strong,em,i,h1,h2,h3,h4,h5,h6,small,label,cite,blockquote'
            ).forEach(processEl);
        }

        fixDarkModeColors();

        var imgs = document.querySelectorAll('img');
        imgs.forEach(function(img) {
            window.webkit.messageHandlers.imageLog.postMessage(
                'img src=' + img.src.substring(0,80) + ' complete=' + img.complete + ' naturalW=' + img.naturalWidth
            );
            if (!img.complete) {
                img.addEventListener('load', function() {
                    window.webkit.messageHandlers.imageLog.postMessage('LOADED: ' + this.src.substring(0,80));
                    window.webkit.messageHandlers.imageLog.postMessage('REMEASURE');
                });
                img.addEventListener('error', function() {
                    window.webkit.messageHandlers.imageLog.postMessage('FAILED: ' + this.src.substring(0,80));
                });
            }
        });
        window.webkit.messageHandlers.imageLog.postMessage(
            'Total imgs: ' + imgs.length + ', already complete: ' + Array.from(imgs).filter(function(i){return i.complete;}).length
        );
        """
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLEmailView
        var lastCacheKey: String = ""
        var isLoadingContent = false

        init(_ parent: HTMLEmailView) { self.parent = parent }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? String else { return }
            if body == "REMEASURE" {
                DispatchQueue.main.async { [weak self] in
                    // Re-measure when any image finishes loading
                    self?.remeasureIfNeeded()
                }
            } else {
                print("[HTMLEmailView] \(body)")
            }
        }

        private func remeasureIfNeeded() {
            // Will be called with the webView on next cycle
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoadingContent = false
            measureHeight(webView)
            // Re-measure after delays to catch lazy/slow images
            for delay in [0.5, 1.5, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                    guard let webView else { return }
                    self?.measureHeight(webView)
                }
            }
        }

        private func measureHeight(_ webView: WKWebView) {
            webView.evaluateJavaScript(
                "document.getElementById('emailContent').offsetHeight"
            ) { [weak self] result, _ in
                DispatchQueue.main.async {
                    if let h = result as? CGFloat, h > 0 {
                        self?.parent.contentHeight = h
                    }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                if let onOpenLink = parent.onOpenLink {
                    onOpenLink(url)
                } else {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            guard isLoadingContent,
                  navigationAction.navigationType == .other,
                  navigationAction.request.url?.scheme == "about"
                      || navigationAction.request.url?.absoluteString == "about:blank"
            else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
