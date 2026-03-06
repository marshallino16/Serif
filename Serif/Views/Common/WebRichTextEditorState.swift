import AppKit
import WebKit
import Combine

@MainActor
final class WebRichTextEditorState: ObservableObject {
    // Formatting state (updated by JS selectionChanged)
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var isStrikethrough = false
    @Published var fontSize: CGFloat = 13
    @Published var textColor: NSColor = .labelColor
    @Published var alignment: NSTextAlignment = .left
    @Published var selectedText: String = ""

    // WKWebView reference (set by Coordinator)
    weak var webView: WKWebView?

    // Inline images pending send
    var pendingInlineImages: [InlineImageAttachment] = []

    // MARK: - Formatting

    func toggleBold()          { eval("execBold()") }
    func toggleItalic()        { eval("execItalic()") }
    func toggleUnderline()     { eval("execUnderline()") }
    func toggleStrikethrough() { eval("execStrikethrough()") }

    func setFontSize(_ size: CGFloat) {
        fontSize = size
        eval("execFontSize(\(Int(size)))")
    }

    func setTextColor(_ color: NSColor) {
        textColor = color
        let hex = colorToHex(color)
        eval("execForeColor('\(hex)')")
    }

    func removeFormat() { eval("execRemoveFormat()") }

    func setAlignment(_ alignment: NSTextAlignment) {
        self.alignment = alignment
        let dir: String
        switch alignment {
        case .center:    dir = "center"
        case .right:     dir = "right"
        case .justified: dir = "justify"
        default:         dir = "left"
        }
        eval("execAlign('\(dir)')")
    }

    func insertNumberedList()  { eval("execInsertOrderedList()") }
    func insertBulletList()    { eval("execInsertUnorderedList()") }
    func increaseIndent()      { eval("execIndent()") }
    func decreaseIndent()      { eval("execOutdent()") }

    func insertLink(url: String, text: String? = nil) {
        let escapedURL = url.replacingOccurrences(of: "'", with: "\\'")
        if let text = text {
            let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
            eval("execInsertLink('\(escapedURL)', '\(escapedText)')")
        } else {
            eval("execInsertLink('\(escapedURL)', null)")
        }
    }

    func removeLink() { eval("execUnlink()") }

    func undo() { webView?.undoManager?.undo() }
    func redo() { webView?.undoManager?.redo() }

    // MARK: - Content

    func setHTML(_ html: String) {
        let escaped = html.jsEscaped
        eval("setHTML(\(escaped))")
    }

    func insertHTML(_ html: String) {
        let escaped = html.jsEscaped
        eval("insertHTML(\(escaped))")
    }

    func getHTMLAsync() async -> String {
        guard let webView else { return "" }
        do {
            let result = try await webView.evaluateJavaScript("getHTML()")
            return result as? String ?? ""
        } catch {
            return ""
        }
    }

    func focus() { eval("focusEditor()") }

    // MARK: - Images

    func insertImage(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }

        // Compress if wider than 480px
        let imageData: Data
        let mimeType: String
        if let image = NSImage(data: data) {
            let maxWidth: CGFloat = 480
            if image.size.width > maxWidth {
                let ratio = maxWidth / image.size.width
                let newSize = NSSize(width: maxWidth, height: image.size.height * ratio)
                let resized = NSImage(size: newSize)
                resized.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: newSize))
                resized.unlockFocus()
                if let tiff = resized.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    imageData = jpeg
                    mimeType = "image/jpeg"
                } else {
                    imageData = data
                    mimeType = detectMimeType(data)
                }
            } else {
                imageData = data
                mimeType = detectMimeType(data)
            }
        } else {
            imageData = data
            mimeType = detectMimeType(data)
        }

        let cid = "img_\(UUID().uuidString.prefix(8))"
        let ext = mimeType == "image/png" ? "png" : "jpg"
        let filename = "\(cid).\(ext)"

        pendingInlineImages.append(InlineImageAttachment(
            contentID: cid, data: imageData, mimeType: mimeType, filename: filename
        ))

        let base64 = imageData.base64EncodedString()
        let dataURL = "data:\(mimeType);base64,\(base64)"
        eval("insertImageBase64('\(dataURL)', '\(cid)')")
    }

    // MARK: - Theme update

    func updateTheme(textColor: String, bgColor: String, accentColor: String, placeholderColor: String) {
        eval("setThemeColors('\(textColor)', '\(bgColor)', '\(accentColor)', '\(placeholderColor)')")
    }

    // MARK: - Selection state update (called by Coordinator)

    func handleSelectionChanged(_ info: [String: Any]) {
        let newBold = info["bold"] as? Bool ?? false
        let newItalic = info["italic"] as? Bool ?? false
        let newUnderline = info["underline"] as? Bool ?? false
        let newStrikethrough = info["strikethrough"] as? Bool ?? false
        let newSelectedText = info["selectedText"] as? String ?? ""
        let newFontSize = (info["fontSize"] as? Int).map { CGFloat($0) }
        let newTextColor = (info["textColor"] as? String).flatMap { nsColorFromHex($0) }
        var newAlignment: NSTextAlignment?
        if let align = info["alignment"] as? String {
            switch align {
            case "center":  newAlignment = .center
            case "right":   newAlignment = .right
            case "justify": newAlignment = .justified
            default:        newAlignment = .left
            }
        }

        // Only publish changes to avoid unnecessary SwiftUI re-renders
        if isBold != newBold { isBold = newBold }
        if isItalic != newItalic { isItalic = newItalic }
        if isUnderline != newUnderline { isUnderline = newUnderline }
        if isStrikethrough != newStrikethrough { isStrikethrough = newStrikethrough }
        if selectedText != newSelectedText { selectedText = newSelectedText }
        if let fs = newFontSize, fontSize != fs { fontSize = fs }
        if let tc = newTextColor, textColor != tc { textColor = tc }
        if let a = newAlignment, alignment != a { alignment = a }
    }

    // MARK: - Private

    func eval(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    private func colorToHex(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(c.redComponent * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func nsColorFromHex(_ hex: String) -> NSColor {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    private func detectMimeType(_ data: Data) -> String {
        guard data.count >= 4 else { return "image/png" }
        let bytes = [UInt8](data.prefix(4))
        if bytes[0] == 0x89 && bytes[1] == 0x50 { return "image/png" }
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return "image/jpeg" }
        if bytes[0] == 0x47 && bytes[1] == 0x49 { return "image/gif" }
        return "image/png"
    }
}

// MARK: - String JS escaping

extension String {
    var jsEscaped: String {
        let escaped = self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "'\(escaped)'"
    }
}
