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
    var backgroundColor: String = "transparent"
    @Environment(\.theme) private var theme

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "imageLog")
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
        let cacheKey = "\(html)|\(textHex)|\(backgroundColor)"
        guard context.coordinator.lastCacheKey != cacheKey else { return }
        context.coordinator.lastCacheKey = cacheKey
        // Defer height reset so SwiftUI processes it after the current render pass.
        // This shrinks the frame before didFinish measures the new content.
        DispatchQueue.main.async {
            self.contentHeight = 1
        }
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
            background-color: \(backgroundColor);
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        img { max-width: 100% !important; height: auto !important; }
        a { color: #1a73e8; }
        blockquote { border-left: 3px solid #dadce0; margin: 8px 0; padding: 4px 12px; color: #5f6368; }
        pre, code { font-family: 'SF Mono', 'Menlo', monospace; font-size: 12px; background: rgba(0,0,0,0.06); padding: 2px 4px; border-radius: 3px; }
        /* Do NOT force border-collapse:collapse — that nukes `border-spacing`,
           which designed emails (Doctolib, transactional emails…) rely on for
           vertical spacing between rows/buttons. */
        * { box-sizing: border-box; max-width: 100% !important; cursor: default !important; }

        @media (prefers-color-scheme: dark) {
            a { color: #8ab4f8; }
            blockquote { border-left-color: #5f6368; color: #9aa0a6; }
            pre, code { background: rgba(255,255,255,0.1); color: #e8eaed; }
        }
        </style>
        <script>
        // ── Dark-mode readability fix ────────────────────────────────────────
        // Walks common text elements, computes WCAG contrast ratio against the
        // dark background, and lightens only colours that fall below the threshold
        // while preserving hue and saturation as much as possible.
        var THEME_TEXT = '\(textHex)';
        var THEME_BG = '\(backgroundColor)';

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
            function parseRgb(s) {
                var i = s.indexOf('(');
                if (i < 0) return null;
                var parts = s.slice(i + 1).split(',');
                return parts.length >= 3 ? [parseInt(parts[0]), parseInt(parts[1]), parseInt(parts[2])] : null;
            }
            function parseHex(h) {
                h = h.replace('#', '');
                return [parseInt(h.substr(0,2),16), parseInt(h.substr(2,2),16), parseInt(h.substr(4,2),16)];
            }
            function hue2rgb(p, q, t) {
                if (t < 0) t += 1;
                if (t > 1) t -= 1;
                if (t < 1/6) return p + (q - p) * 6 * t;
                if (t < 0.5) return q;
                if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
                return p;
            }
            function rgbToHsl(r, g, b) {
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
                return [h, s, l];
            }
            function hslToRgb(h, s, l) {
                if (s === 0) { var v = Math.round(l * 255); return [v, v, v]; }
                var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
                var p = 2 * l - q;
                return [
                    Math.round(hue2rgb(p, q, h + 1/3) * 255),
                    Math.round(hue2rgb(p, q, h)       * 255),
                    Math.round(hue2rgb(p, q, h - 1/3) * 255)
                ];
            }

            function emailSupportsDarkMode() {
                var el = document.getElementById('emailContent');
                if (!el) return false;
                var styles = el.querySelectorAll('style');
                for (var i = 0; i < styles.length; i++) {
                    var text = styles[i].textContent || '';
                    if (text.indexOf('prefers-color-scheme') !== -1) return true;
                }
                var metas = el.querySelectorAll('meta[name="color-scheme"], meta[name="supported-color-schemes"]');
                for (var j = 0; j < metas.length; j++) {
                    var content = metas[j].getAttribute('content') || '';
                    if (content.indexOf('dark') !== -1) return true;
                }
                var html = el.innerHTML;
                if (html.indexOf('prefers-color-scheme') !== -1) return true;
                return false;
            }

            var emailHasDarkMode = emailSupportsDarkMode();

            if (!emailHasDarkMode && THEME_BG !== 'transparent') {
                var themeBgRgb = parseHex(THEME_BG);
                var themeBgCss = 'rgb(' + themeBgRgb[0] + ',' + themeBgRgb[1] + ',' + themeBgRgb[2] + ')';
                document.querySelectorAll(
                    'table,td,th,div,body,section,article,header,footer,main,aside,tr'
                ).forEach(function(el) {
                    var cs = window.getComputedStyle(el);
                    var bg = cs.backgroundColor;
                    var rgb = parseRgb(bg);
                    if (!rgb) return;
                    var parts = bg.slice(bg.indexOf('(') + 1).split(',');
                    var alpha = parts.length >= 4 ? parseFloat(parts[3]) : 1;
                    if (alpha < 0.1) return;
                    var lum = relativeLum(rgb[0], rgb[1], rgb[2]);
                    if (lum < 0.5) return;
                    el.style.setProperty('background-color', themeBgCss, 'important');
                    if (el.hasAttribute('bgcolor')) el.removeAttribute('bgcolor');
                    ['border', 'borderTop', 'borderBottom', 'borderLeft', 'borderRight'].forEach(function(prop) {
                        var bColor = cs[prop + 'Color'];
                        var bRgb = parseRgb(bColor);
                        if (bRgb && relativeLum(bRgb[0], bRgb[1], bRgb[2]) > 0.4) {
                            el.style.setProperty(prop.replace(/([A-Z])/g, '-$1').toLowerCase() + '-color',
                                'rgba(' + themeBgRgb[0] + ',' + themeBgRgb[1] + ',' + themeBgRgb[2] + ',0.3)', 'important');
                        }
                    });
                });
            }

            function lightenToContrast(r, g, b) {
                var hsl = rgbToHsl(r, g, b);
                for (var tl = Math.max(hsl[2] + 0.1, 0.55); tl <= 1.0; tl += 0.04) {
                    var c = hslToRgb(hsl[0], hsl[1], tl);
                    if (((relativeLum(c[0], c[1], c[2]) + 0.05) / (BG_LUM + 0.05)) >= MIN_CR)
                        return 'rgb(' + c[0] + ',' + c[1] + ',' + c[2] + ')';
                }
                return THEME_TEXT;
            }

            function isAchromatic(r, g, b) {
                return (Math.max(r, g, b) - Math.min(r, g, b)) < 30 && Math.max(r, g, b) < 80;
            }

            function effectiveBgLum(el) {
                var node = el;
                while (node && node !== document.documentElement) {
                    var bg = window.getComputedStyle(node).backgroundColor;
                    var rgba = parseRgb(bg);
                    if (rgba) {
                        var parts = bg.slice(bg.indexOf('(') + 1).split(',');
                        var a = parts.length >= 4 ? parseFloat(parts[3]) : 1;
                        if (a > 0.1) return relativeLum(rgba[0], rgba[1], rgba[2]);
                    }
                    node = node.parentElement;
                }
                return BG_LUM;
            }

            function processEl(el) {
                var c = window.getComputedStyle(el).color;
                var rgb = parseRgb(c);
                if (!rgb) return;
                var bgLum = effectiveBgLum(el);
                if (emailHasDarkMode && bgLum > 0.4) return;
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

        // Auto-link bare URLs in text nodes (macOS WKWebView has no dataDetectorTypes)
        function autoLinkURLs() {
            var urlRegex = /(https?:\\/\\/[^\\s<>"']+)/g;
            var walker = document.createTreeWalker(
                document.getElementById('emailContent') || document.body,
                NodeFilter.SHOW_TEXT, null, false
            );
            var nodes = [];
            while (walker.nextNode()) nodes.push(walker.currentNode);
            nodes.forEach(function(node) {
                if (node.parentElement && node.parentElement.tagName === 'A') return;
                var text = node.textContent;
                if (!urlRegex.test(text)) return;
                urlRegex.lastIndex = 0;
                var frag = document.createDocumentFragment();
                var lastIdx = 0;
                var match;
                while ((match = urlRegex.exec(text)) !== null) {
                    if (match.index > lastIdx) {
                        frag.appendChild(document.createTextNode(text.slice(lastIdx, match.index)));
                    }
                    var a = document.createElement('a');
                    a.href = match[1];
                    a.textContent = match[1];
                    frag.appendChild(a);
                    lastIdx = urlRegex.lastIndex;
                }
                if (lastIdx < text.length) {
                    frag.appendChild(document.createTextNode(text.slice(lastIdx)));
                }
                node.parentNode.replaceChild(frag, node);
            });
        }

        // ── Image monitoring + trigger colour fix on load ────────────────────
        window.addEventListener('load', function() {
            autoLinkURLs();
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
        });
        </script>
        </head>
        <body><div id="emailContent" style="padding-bottom:16px">\(html)</div></body>
        </html>
        """
        webView.loadHTMLString(fullHTML, baseURL: URL(string: "https://mail.google.com/"))
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLEmailView
        var lastCacheKey: String = ""

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
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
