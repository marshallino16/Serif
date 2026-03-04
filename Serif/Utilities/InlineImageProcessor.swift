import Foundation

struct InlineImageAttachment {
    let contentID: String
    let data: Data
    let mimeType: String
    let filename: String
}

enum InlineImageProcessor {

    /// Scans HTML for `<img src="data:..." data-cid="...">` tags,
    /// extracts the base64 data, replaces with `<img src="cid:...">`.
    static func extractInlineImages(from html: String) -> (html: String, images: [InlineImageAttachment]) {
        var images: [InlineImageAttachment] = []
        var result = html

        // Match <img ... src="data:mime;base64,..." ... data-cid="..." ...>
        let pattern = #"<img\s[^>]*src="data:([^;]+);base64,([^"]+)"[^>]*data-cid="([^"]+)"[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (html, [])
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        // Process in reverse to keep string indices stable
        for match in matches.reversed() {
            guard match.numberOfRanges >= 4,
                  let fullRange = Range(match.range, in: html),
                  let mimeRange = Range(match.range(at: 1), in: html),
                  let base64Range = Range(match.range(at: 2), in: html),
                  let cidRange = Range(match.range(at: 3), in: html) else { continue }

            let mimeType = String(html[mimeRange])
            let base64Str = String(html[base64Range])
            let cid = String(html[cidRange])

            guard let data = Data(base64Encoded: base64Str, options: .ignoreUnknownCharacters) else { continue }

            let ext = mimeType.contains("png") ? "png" : "jpg"
            images.insert(InlineImageAttachment(
                contentID: cid,
                data: data,
                mimeType: mimeType,
                filename: "\(cid).\(ext)"
            ), at: 0)

            let replacement = "<img src=\"cid:\(cid)\">"
            result = result.replacingCharacters(in: fullRange, with: replacement)
        }

        return (result, images)
    }
}

private extension String {
    func replacingCharacters(in range: Range<String.Index>, with replacement: String) -> String {
        var copy = self
        copy.replaceSubrange(range, with: replacement)
        return copy
    }
}
