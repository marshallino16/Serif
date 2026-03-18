import WebKit
import AppKit

final class EmailPrintService {
    static let shared = EmailPrintService()
    private init() {}

    private var printWindow: NSWindow?
    private var printWebView: WKWebView?

    func printEmail(message: GmailMessage, email: Email) {
        let html = buildPrintHTML(message: message, email: email)

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 720, height: 960), configuration: config)

        // WKWebView must live inside a window to support printing
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 720, height: 960),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderBack(nil)         // off-screen, behind everything

        self.printWindow = window
        self.printWebView = webView

        let delegate = PrintNavigationDelegate { [weak self] wv in
            self?.showPrintDialog(webView: wv)
        }
        objc_setAssociatedObject(webView, "printDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        webView.navigationDelegate = delegate

        webView.loadHTMLString(html, baseURL: URL(string: "https://mail.google.com/"))
    }

    private func showPrintDialog(webView: WKWebView) {
        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false

        let printOp = webView.printOperation(with: printInfo)
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true

        if let mainWindow = NSApp.keyWindow ?? NSApp.mainWindow {
            printOp.runModal(for: mainWindow, delegate: self, didRun: #selector(printDidFinish(_:success:contextInfo:)), contextInfo: nil)
        } else {
            printOp.run()
            cleanup()
        }
    }

    @objc private func printDidFinish(_ op: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        cleanup()
    }

    private func cleanup() {
        printWindow?.orderOut(nil)
        printWindow = nil
        printWebView = nil
    }

    // MARK: - HTML Generation

    private func buildPrintHTML(message: GmailMessage, email: Email) -> String {
        let subject = escapeHTML(message.subject)
        let senderName = escapeHTML(email.sender.name)
        let senderEmail = escapeHTML(email.sender.email)
        let toValue = escapeHTML(message.to)
        let ccValue = escapeHTML(message.cc)
        let replyTo = escapeHTML(message.replyTo)

        let dateFormatted: String = {
            if let d = message.date {
                let fmt = DateFormatter()
                fmt.dateStyle = .long
                fmt.timeStyle = .short
                return fmt.string(from: d)
            }
            return ""
        }()

        let bodyHTML = message.htmlBody ?? "<p>\(escapeHTML(message.plainBody ?? email.body))</p>"

        var headerRows = """
        <tr><td class="label">From:</td><td><strong>\(senderName)</strong> &lt;\(senderEmail)&gt;</td></tr>
        """
        if replyTo != senderEmail && !message.replyTo.isEmpty {
            headerRows += """
            <tr><td class="label">Reply to:</td><td>\(escapeHTML(message.replyTo))</td></tr>
            """
        }
        headerRows += """
        <tr><td class="label">To:</td><td>\(toValue)</td></tr>
        """
        if !ccValue.isEmpty {
            headerRows += """
            <tr><td class="label">Cc:</td><td>\(ccValue)</td></tr>
            """
        }
        headerRows += """
        <tr><td class="label">Date:</td><td>\(dateFormatted)</td></tr>
        """

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            @page { margin: 0; }
            * { box-sizing: border-box; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, Arial, sans-serif;
                font-size: 13px;
                color: #202124;
                margin: 0;
                padding: 0;
                background: white;
            }
            .print-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                padding: 8px 0;
                border-bottom: 1px solid #dadce0;
                margin-bottom: 16px;
            }
            .print-header .app-name {
                font-size: 20px;
                font-weight: normal;
                color: #5f6368;
            }
            .print-header .sender-email {
                font-size: 12px;
                color: #5f6368;
            }
            .subject {
                font-size: 22px;
                font-weight: normal;
                color: #202124;
                margin: 0 0 4px 0;
            }
            .msg-count {
                font-size: 12px;
                color: #5f6368;
                margin-bottom: 16px;
            }
            .message-block {
                border-top: 1px solid #dadce0;
                padding-top: 12px;
                margin-bottom: 24px;
            }
            .meta-table {
                font-size: 12px;
                color: #5f6368;
                margin-bottom: 16px;
                border-collapse: collapse;
            }
            .meta-table td {
                padding: 1px 0;
                vertical-align: top;
            }
            .meta-table .label {
                padding-right: 8px;
                white-space: nowrap;
                color: #5f6368;
            }
            .meta-table td:last-child {
                color: #202124;
            }
            .sender-line {
                display: flex;
                justify-content: space-between;
                align-items: baseline;
            }
            .email-body {
                font-size: 14px;
                line-height: 1.6;
                color: #202124;
                word-wrap: break-word;
                overflow-wrap: break-word;
            }
            .email-body img { max-width: 100% !important; height: auto !important; }
            .email-body a { color: #1a73e8; }
            .email-body blockquote {
                border-left: 3px solid #dadce0;
                margin: 8px 0;
                padding: 4px 12px;
                color: #5f6368;
            }
            .email-body table { border-collapse: collapse; }
        </style>
        </head>
        <body>
            <div class="print-header">
                <span class="app-name">Serif</span>
                <span class="sender-email">\(senderEmail)</span>
            </div>

            <h1 class="subject">\(subject)</h1>
            <div class="msg-count">1 message</div>

            <div class="message-block">
                <table class="meta-table" width="100%">
                    <tr>
                        <td colspan="2">
                            <div class="sender-line">
                                <span><strong>\(senderName)</strong> &lt;\(senderEmail)&gt;</span>
                                <span>\(dateFormatted)</span>
                            </div>
                        </td>
                    </tr>
                    \(headerRows)
                </table>

                <div class="email-body">
                    \(bodyHTML)
                </div>
            </div>
        </body>
        </html>
        """
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Navigation delegate for print

private class PrintNavigationDelegate: NSObject, WKNavigationDelegate {
    let onFinish: (WKWebView) -> Void

    init(onFinish: @escaping (WKWebView) -> Void) {
        self.onFinish = onFinish
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onFinish(webView)
        }
    }
}
