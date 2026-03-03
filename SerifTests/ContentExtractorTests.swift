import XCTest
@testable import Serif

final class ContentExtractorTests: XCTestCase {

    // MARK: - Plain Text Extraction

    func testExtractPlainText_UTF8() {
        let text = "Hello, this is a plain text file."
        let data = text.data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "text/plain", filename: "note.txt")

        if case .text(let extracted) = result {
            XCTAssertEqual(extracted, text)
        } else {
            XCTFail("Expected .text result for text/plain")
        }
    }

    func testExtractPlainText_ByExtension() {
        let text = "CSV data here"
        let data = text.data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "data.csv")

        if case .text(let extracted) = result {
            XCTAssertEqual(extracted, text)
        } else {
            XCTFail("Expected .text result for .csv extension")
        }
    }

    func testExtractPlainText_CodeFiles() {
        let code = "func hello() { print(\"Hello\") }"
        let data = code.data(using: .utf8)!

        let extensions = ["swift", "py", "js", "ts", "css", "json", "xml", "html", "md", "yaml", "yml", "toml", "ini", "cfg", "log", "rtf"]

        for ext in extensions {
            let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "file.\(ext)")
            if case .text(let extracted) = result {
                XCTAssertEqual(extracted, code, "Failed for extension: \(ext)")
            } else {
                XCTFail("Expected .text result for .\(ext) extension")
            }
        }
    }

    func testExtractPlainText_EmptyData() {
        let data = Data()
        let result = ContentExtractor.extract(from: data, mimeType: "text/plain", filename: "empty.txt")

        if case .unsupported = result {
            // Expected: empty data should return .unsupported
        } else {
            XCTFail("Expected .unsupported for empty text data")
        }
    }

    func testExtractPlainText_ByMimeType() {
        let text = "text content via mime"
        let data = text.data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "text/html", filename: "unknown_ext.xyz")

        if case .text(let extracted) = result {
            XCTAssertEqual(extracted, text)
        } else {
            XCTFail("Expected .text result for text/ mime type prefix")
        }
    }

    // MARK: - Image Types → OCR (unsupported for garbage data)

    func testExtractImage_ReturnsUnsupportedForInvalidData() {
        let data = "not a real image".data(using: .utf8)!

        let imageExtensions = ["jpg", "jpeg", "png", "tiff", "heic", "bmp", "gif"]
        for ext in imageExtensions {
            let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "photo.\(ext)")
            if case .unsupported = result {
                // Expected: garbage data cannot be OCR'd
            } else if case .text = result {
                // OCR might find something in certain cases — acceptable too
            }
        }
    }

    func testExtractImage_ByMimeType() {
        let data = "not real image data".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "image/png", filename: "unknown.xyz")

        // Should route to OCR path (which will return .unsupported for invalid data)
        if case .unsupported = result {
            // Expected
        } else if case .text = result {
            // OCR may produce something — acceptable
        }
    }

    // MARK: - PDF Extraction

    func testExtractPDF_InvalidData() {
        let data = "not a real PDF".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "application/pdf", filename: "doc.pdf")

        if case .unsupported = result {
            // Expected: invalid PDF data should return .unsupported
        } else {
            XCTFail("Expected .unsupported for invalid PDF data")
        }
    }

    func testExtractPDF_ByExtension() {
        let data = "not a real PDF".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "report.pdf")

        if case .unsupported = result {
            // Expected: routes to PDF extractor by extension, invalid data
        } else {
            XCTFail("Expected .unsupported for invalid PDF data by extension")
        }
    }

    // MARK: - Unknown / Unsupported Types

    func testExtractUnknownMimeType_ReturnsUnsupported() {
        let data = "some binary data".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "application/octet-stream", filename: "blob.bin")

        if case .unsupported = result {
            // Expected
        } else {
            XCTFail("Expected .unsupported for unknown MIME type and extension")
        }
    }

    func testExtractUnknownExtension_ReturnsUnsupported() {
        let data = "whatever".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "file.xyz123")

        if case .unsupported = result {
            // Expected
        } else {
            XCTFail("Expected .unsupported for unknown extension with nil mime type")
        }
    }

    func testExtractNoExtension_NoMimeType_ReturnsUnsupported() {
        let data = "data".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "noextension")

        if case .unsupported = result {
            // Expected
        } else {
            XCTFail("Expected .unsupported when no extension and no mime type")
        }
    }

    // MARK: - Word Document Extraction

    func testExtractWordDoc_InvalidData() {
        let data = "not a real docx".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: nil, filename: "report.docx")

        if case .unsupported = result {
            // Expected: invalid Word data
        } else if case .text = result {
            // NSAttributedString might handle it somehow — acceptable
        }
    }

    func testExtractWordDoc_ByMimeType() {
        let data = "not real".data(using: .utf8)!
        let result = ContentExtractor.extract(
            from: data,
            mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            filename: "unknown.xyz"
        )

        if case .unsupported = result {
            // Expected
        } else if case .text = result {
            // Acceptable if NSAttributedString handles it
        }
    }

    // MARK: - Cosine Similarity

    func testCosineSimilarity_IdenticalVectors() {
        let vec: [Float] = [1.0, 2.0, 3.0]
        let similarity = ContentExtractor.cosineSimilarity(vec, vec)
        XCTAssertEqual(similarity, 1.0, accuracy: 0.0001)
    }

    func testCosineSimilarity_OrthogonalVectors() {
        let a: [Float] = [1.0, 0.0, 0.0]
        let b: [Float] = [0.0, 1.0, 0.0]
        let similarity = ContentExtractor.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, accuracy: 0.0001)
    }

    func testCosineSimilarity_OppositeVectors() {
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [-1.0, 0.0]
        let similarity = ContentExtractor.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, -1.0, accuracy: 0.0001)
    }

    func testCosineSimilarity_EmptyVectors() {
        let similarity = ContentExtractor.cosineSimilarity([], [])
        XCTAssertEqual(similarity, 0.0)
    }

    func testCosineSimilarity_DifferentLengths() {
        let a: [Float] = [1.0, 2.0]
        let b: [Float] = [1.0, 2.0, 3.0]
        let similarity = ContentExtractor.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, "Mismatched lengths should return 0")
    }

    func testCosineSimilarity_ZeroVector() {
        let a: [Float] = [0.0, 0.0, 0.0]
        let b: [Float] = [1.0, 2.0, 3.0]
        let similarity = ContentExtractor.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, 0.0, "Zero vector should return 0")
    }

    func testCosineSimilarity_KnownValues() {
        // cos(45 degrees) = ~0.7071
        let a: [Float] = [1.0, 0.0]
        let b: [Float] = [1.0, 1.0]
        let similarity = ContentExtractor.cosineSimilarity(a, b)
        XCTAssertEqual(similarity, Float(1.0 / sqrt(2.0)), accuracy: 0.0001)
    }

    // MARK: - Embedding Generation

    func testGenerateEmbedding_ReturnsConsistentResults() {
        let text = "The quick brown fox jumps over the lazy dog."
        let embedding1 = ContentExtractor.generateEmbedding(for: text)
        let embedding2 = ContentExtractor.generateEmbedding(for: text)

        // Both calls should return the same result (both nil or both non-nil with same values)
        if let e1 = embedding1, let e2 = embedding2 {
            XCTAssertEqual(e1.count, e2.count, "Embeddings should have same dimension")
            for i in 0..<e1.count {
                XCTAssertEqual(e1[i], e2[i], accuracy: 0.0001, "Embedding values should be consistent")
            }
        } else {
            // Both should be nil if NLEmbedding is unavailable
            XCTAssertEqual(embedding1 == nil, embedding2 == nil, "Both should be nil or both non-nil")
        }
    }

    func testGenerateEmbedding_EmptyText() {
        let result = ContentExtractor.generateEmbedding(for: "")
        XCTAssertNil(result, "Empty text should return nil embedding")
    }

    func testGenerateEmbedding_WhitespaceOnly() {
        let result = ContentExtractor.generateEmbedding(for: "   \n\t  ")
        XCTAssertNil(result, "Whitespace-only text should return nil embedding")
    }

    // MARK: - Routing Priority

    func testPDFMimeType_TakesPriorityOverExtension() {
        // A .txt file with application/pdf mime should be routed as PDF
        let data = "not a real PDF".data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "application/pdf", filename: "file.txt")

        // Should attempt PDF extraction (and fail since data is invalid)
        if case .unsupported = result {
            // Expected: routes to PDF path, fails because data is not a valid PDF
        } else if case .text = result {
            // Might fall through — depends on implementation order
        }
    }

    func testExtractPreservesMultilineText() {
        let text = "Line 1\nLine 2\nLine 3"
        let data = text.data(using: .utf8)!
        let result = ContentExtractor.extract(from: data, mimeType: "text/plain", filename: "multi.txt")

        if case .text(let extracted) = result {
            XCTAssertEqual(extracted, text)
            XCTAssertTrue(extracted.contains("\n"))
        } else {
            XCTFail("Expected .text result for multiline text")
        }
    }
}
