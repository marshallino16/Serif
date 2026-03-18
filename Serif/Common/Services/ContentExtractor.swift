import Foundation
import AppKit
import PDFKit
import Vision
import NaturalLanguage

// MARK: - Content Extractor

/// Utility for extracting searchable text from attachment data and generating embeddings.
/// Used by AttachmentIndexer to populate FTS5 and embedding columns.
enum ContentExtractor {

    // MARK: - Extraction Result

    enum ExtractionResult {
        case text(String)
        case unsupported
    }

    // MARK: - Supported Extensions

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "tiff", "heic", "bmp", "gif"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "csv", "json", "xml", "html", "md", "rtf", "log",
        "swift", "py", "js", "ts", "css", "yaml", "yml", "toml", "ini", "cfg"
    ]

    private static let wordMimeTypes: Set<String> = [
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "application/msword",
        "application/vnd.oasis.opendocument.text"
    ]

    private static let wordExtensions: Set<String> = ["doc", "docx", "odt"]

    // MARK: - Public API

    /// Route extraction based on file extension and MIME type.
    static func extract(from data: Data, mimeType: String?, filename: String) -> ExtractionResult {
        let ext = (filename as NSString).pathExtension.lowercased()

        // PDF
        if ext == "pdf" || mimeType == "application/pdf" {
            return extractPDF(data: data)
        }

        // Word documents (.doc, .docx, .odt)
        if wordExtensions.contains(ext) || wordMimeTypes.contains(mimeType ?? "") {
            return extractWordDocument(data: data, ext: ext.isEmpty ? "docx" : ext)
        }

        // Images
        if imageExtensions.contains(ext) || (mimeType?.hasPrefix("image/") == true) {
            return extractOCR(data: data)
        }

        // Plain-text family
        if textExtensions.contains(ext) || mimeType?.hasPrefix("text/") == true {
            return extractText(data: data)
        }

        return .unsupported
    }

    // MARK: - PDF

    private static func extractPDF(data: Data) -> ExtractionResult {
        guard let document = PDFDocument(data: data) else { return .unsupported }

        var pages: [String] = []
        for i in 0..<document.pageCount {
            if let page = document.page(at: i), let text = page.string, !text.isEmpty {
                pages.append(text)
            }
        }

        let combined = pages.joined(separator: "\n")
        return combined.isEmpty ? .unsupported : .text(combined)
    }

    // MARK: - OCR (Vision)

    private static func extractOCR(data: Data) -> ExtractionResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: data, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .unsupported
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .unsupported
        }

        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        return text.isEmpty ? .unsupported : .text(text)
    }

    // MARK: - Word Documents

    private static func extractWordDocument(data: Data, ext: String) -> ExtractionResult {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try data.write(to: tempFile)
            defer { try? FileManager.default.removeItem(at: tempFile) }
            let attributed = try NSAttributedString(url: tempFile, options: [:], documentAttributes: nil)
            let text = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? .unsupported : .text(text)
        } catch {
            return .unsupported
        }
    }

    // MARK: - Plain Text

    private static func extractText(data: Data) -> ExtractionResult {
        guard let string = String(data: data, encoding: .utf8), !string.isEmpty else {
            return .unsupported
        }
        return .text(string)
    }

    // MARK: - Embedding Generation

    /// Generate an averaged sentence embedding using NaturalLanguage.framework.
    /// Splits the input into sentences, embeds each (capped at 100), and averages the vectors.
    static func generateEmbedding(for text: String) -> [Float]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return sentences.count < 100
        }

        guard !sentences.isEmpty else { return nil }

        let dimension = embedding.dimension
        var sum = [Double](repeating: 0.0, count: dimension)
        var count = 0

        for sentence in sentences {
            if let vector = embedding.vector(for: sentence) {
                for i in 0..<dimension {
                    sum[i] += vector[i]
                }
                count += 1
            }
        }

        guard count > 0 else { return nil }

        let scale = 1.0 / Double(count)
        return sum.map { Float($0 * scale) }
    }

    // MARK: - Cosine Similarity

    /// Compute cosine similarity between two vectors of equal length.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrtf(normA) * sqrtf(normB)
        guard denominator > 0 else { return 0 }

        return dot / denominator
    }
}
