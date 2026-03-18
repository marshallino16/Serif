import SwiftUI
import WebKit

struct InAppBrowserView: View {
    let url: URL
    let onClose: () -> Void
    @Environment(\.theme) private var theme
    @State private var currentURL: URL?
    @State private var pageTitle: String = ""
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @StateObject private var webViewStore = WebViewStore()

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Close button
                Button { onClose() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(theme.cardBackground)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Close")
                .keyboardShortcut(.escape, modifiers: [])

                // Navigation
                Button { webViewStore.webView.goBack() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(canGoBack ? theme.textSecondary : theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .help("Back")

                Button { webViewStore.webView.goForward() } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(canGoForward ? theme.textSecondary : theme.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .help("Forward")

                // URL bar
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(theme.textTertiary)
                    }
                    Text(displayURL)
                        .font(.system(size: 12))
                        .foregroundColor(theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.cardBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(theme.border, lineWidth: 1)
                )

                // Open in browser
                Button {
                    NSWorkspace.shared.open(currentURL ?? url)
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 12))
                        Text("Open in Browser")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.cardBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Open in default browser")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(theme.divider)

            // WebView
            BrowserWebView(
                url: url,
                webView: webViewStore.webView,
                onURLChange: { newURL in currentURL = newURL },
                onTitleChange: { title in pageTitle = title },
                onLoadingChange: { loading in isLoading = loading },
                onNavigationChange: { back, forward in
                    canGoBack = back
                    canGoForward = forward
                }
            )
        }
        .background(theme.detailBackground)
    }

    private var displayURL: String {
        let displayedURL = currentURL ?? url
        if let host = displayedURL.host {
            return host + displayedURL.path
        }
        return displayedURL.absoluteString
    }
}

// MARK: - WebView Store

private class WebViewStore: ObservableObject {
    let webView = WKWebView()
}

// MARK: - Browser WebView

private struct BrowserWebView: NSViewRepresentable {
    let url: URL
    let webView: WKWebView
    let onURLChange: (URL) -> Void
    let onTitleChange: (String) -> Void
    let onLoadingChange: (Bool) -> Void
    let onNavigationChange: (Bool, Bool) -> Void

    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BrowserWebView
        private var observation: NSKeyValueObservation?

        init(parent: BrowserWebView) {
            self.parent = parent
            super.init()

            observation = parent.webView.observe(\.isLoading) { [weak self] webView, _ in
                DispatchQueue.main.async {
                    self?.parent.onLoadingChange(webView.isLoading)
                    self?.parent.onNavigationChange(webView.canGoBack, webView.canGoForward)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                parent.onURLChange(url)
            }
            parent.onTitleChange(webView.title ?? "")
            parent.onLoadingChange(false)
            parent.onNavigationChange(webView.canGoBack, webView.canGoForward)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.onLoadingChange(true)
            if let url = webView.url {
                parent.onURLChange(url)
            }
        }
    }
}
