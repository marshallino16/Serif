import SwiftUI
import AppKit

// MARK: - Rich Text State

final class RichTextState: ObservableObject {
    @Published var isBold = false
    @Published var isItalic = false
    @Published var isUnderline = false
    @Published var isStrikethrough = false
    @Published var fontFamily = "System Font"
    @Published var fontSize: CGFloat = 13
    @Published var textColor: NSColor = .white
    @Published var alignment: NSTextAlignment = .left

    weak var textView: NSTextView?

    func toggleBold() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            let storage = tv.textStorage!
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? NSFont {
                    let newFont = isBold ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask) : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                    storage.addAttribute(.font, value: newFont, range: subRange)
                }
            }
            storage.endEditing()
        } else {
            var attrs = tv.typingAttributes
            if let font = attrs[.font] as? NSFont {
                let newFont = isBold ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask) : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                attrs[.font] = newFont
                tv.typingAttributes = attrs
            }
        }
        isBold.toggle()
    }

    func toggleItalic() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length > 0 {
            let storage = tv.textStorage!
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? NSFont {
                    let newFont = isItalic ? NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask) : NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                    storage.addAttribute(.font, value: newFont, range: subRange)
                }
            }
            storage.endEditing()
        } else {
            var attrs = tv.typingAttributes
            if let font = attrs[.font] as? NSFont {
                let newFont = isItalic ? NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask) : NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                attrs[.font] = newFont
                tv.typingAttributes = attrs
            }
        }
        isItalic.toggle()
    }

    func toggleUnderline() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let newValue: NSUnderlineStyle = isUnderline ? [] : .single
        if range.length > 0 {
            tv.textStorage?.addAttribute(.underlineStyle, value: newValue.rawValue, range: range)
        } else {
            var attrs = tv.typingAttributes
            attrs[.underlineStyle] = newValue.rawValue
            tv.typingAttributes = attrs
        }
        isUnderline.toggle()
    }

    func toggleStrikethrough() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let newValue: NSUnderlineStyle = isStrikethrough ? [] : .single
        if range.length > 0 {
            tv.textStorage?.addAttribute(.strikethroughStyle, value: newValue.rawValue, range: range)
        } else {
            var attrs = tv.typingAttributes
            attrs[.strikethroughStyle] = newValue.rawValue
            tv.typingAttributes = attrs
        }
        isStrikethrough.toggle()
    }

    func setFontFamily(_ family: String) {
        guard let tv = textView else { return }
        fontFamily = family
        let range = tv.selectedRange()
        if range.length > 0 {
            let storage = tv.textStorage!
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? NSFont {
                    let newFont = NSFont(name: family, size: font.pointSize) ?? NSFont.systemFont(ofSize: font.pointSize)
                    storage.addAttribute(.font, value: newFont, range: subRange)
                }
            }
            storage.endEditing()
        } else {
            var attrs = tv.typingAttributes
            if let font = attrs[.font] as? NSFont {
                let newFont = NSFont(name: family, size: font.pointSize) ?? NSFont.systemFont(ofSize: font.pointSize)
                attrs[.font] = newFont
                tv.typingAttributes = attrs
            }
        }
    }

    func setFontSize(_ size: CGFloat) {
        guard let tv = textView else { return }
        fontSize = size
        let range = tv.selectedRange()
        if range.length > 0 {
            let storage = tv.textStorage!
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? NSFont {
                    let newFont = NSFontManager.shared.convert(font, toSize: size)
                    storage.addAttribute(.font, value: newFont, range: subRange)
                }
            }
            storage.endEditing()
        } else {
            var attrs = tv.typingAttributes
            if let font = attrs[.font] as? NSFont {
                attrs[.font] = NSFontManager.shared.convert(font, toSize: size)
                tv.typingAttributes = attrs
            }
        }
    }

    func setTextColor(_ color: NSColor) {
        guard let tv = textView else { return }
        textColor = color
        let range = tv.selectedRange()
        if range.length > 0 {
            tv.textStorage?.addAttribute(.foregroundColor, value: color, range: range)
        } else {
            var attrs = tv.typingAttributes
            attrs[.foregroundColor] = color
            tv.typingAttributes = attrs
        }
    }

    func setAlignment(_ alignment: NSTextAlignment) {
        guard let tv = textView else { return }
        self.alignment = alignment
        let range = tv.selectedRange()
        let paraRange = (tv.string as NSString).paragraphRange(for: range)
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        tv.textStorage?.addAttribute(.paragraphStyle, value: style, range: paraRange)
    }

    func insertNumberedList() {
        guard let tv = textView else { return }
        let insertion = "1. "
        tv.insertText(insertion, replacementRange: tv.selectedRange())
    }

    func insertBulletList() {
        guard let tv = textView else { return }
        let insertion = "• "
        tv.insertText(insertion, replacementRange: tv.selectedRange())
    }

    func increaseIndent() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let paraRange = (tv.string as NSString).paragraphRange(for: range)
        let storage = tv.textStorage!
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paraRange) { value, subRange, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent += 28
            style.firstLineHeadIndent += 28
            storage.addAttribute(.paragraphStyle, value: style, range: subRange)
        }
        storage.endEditing()
    }

    func decreaseIndent() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let paraRange = (tv.string as NSString).paragraphRange(for: range)
        let storage = tv.textStorage!
        storage.beginEditing()
        storage.enumerateAttribute(.paragraphStyle, in: paraRange) { value, subRange, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.headIndent = max(0, style.headIndent - 28)
            style.firstLineHeadIndent = max(0, style.firstLineHeadIndent - 28)
            storage.addAttribute(.paragraphStyle, value: style, range: subRange)
        }
        storage.endEditing()
    }

    func undo() {
        textView?.undoManager?.undo()
    }

    func redo() {
        textView?.undoManager?.redo()
    }

    func updateState() {
        guard let tv = textView else { return }
        let attrs: [NSAttributedString.Key: Any]
        if tv.selectedRange().length > 0 {
            attrs = tv.textStorage?.attributes(at: tv.selectedRange().location, effectiveRange: nil) ?? tv.typingAttributes
        } else {
            attrs = tv.typingAttributes
        }

        if let font = attrs[.font] as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            isBold = traits.contains(.boldFontMask)
            isItalic = traits.contains(.italicFontMask)
            fontSize = font.pointSize
            fontFamily = font.familyName ?? "System Font"
        }

        if let underline = attrs[.underlineStyle] as? Int {
            isUnderline = underline != 0
        } else {
            isUnderline = false
        }

        if let strikethrough = attrs[.strikethroughStyle] as? Int {
            isStrikethrough = strikethrough != 0
        } else {
            isStrikethrough = false
        }

        if let color = attrs[.foregroundColor] as? NSColor {
            textColor = color
        }

        if let para = attrs[.paragraphStyle] as? NSParagraphStyle {
            alignment = para.alignment
        }
    }
}

// MARK: - Rich Text Editor (NSTextView wrapper)

struct RichTextEditor: NSViewRepresentable {
    @ObservedObject var state: RichTextState
    @Binding var text: String
    var textColorValue: NSColor
    var placeholder: String = ""
    var autoFocus: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.white,
        ]
        textView.delegate = context.coordinator

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        // Placeholder
        if !placeholder.isEmpty {
            let placeholderView = NSTextField(labelWithString: placeholder)
            placeholderView.font = NSFont.systemFont(ofSize: 13)
            placeholderView.textColor = NSColor.placeholderTextColor
            placeholderView.translatesAutoresizingMaskIntoConstraints = false
            placeholderView.tag = 999
            textView.addSubview(placeholderView)
            NSLayoutConstraint.activate([
                placeholderView.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 9),
                placeholderView.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            ])
            placeholderView.isHidden = !text.isEmpty
        }

        state.textView = textView

        // Auto-focus
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if state.textView !== textView {
            state.textView = textView
        }
        textView.insertionPointColor = .white
        // Update placeholder visibility
        if let placeholderView = textView.viewWithTag(999) {
            placeholderView.isHidden = !textView.string.isEmpty
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor

        init(_ parent: RichTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            // Update placeholder visibility
            if let placeholderView = tv.viewWithTag(999) {
                placeholderView.isHidden = !tv.string.isEmpty
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.state.updateState()
        }
    }
}
