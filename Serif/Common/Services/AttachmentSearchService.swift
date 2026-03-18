import Foundation

// MARK: - AttachmentSearchService

/// Hybrid search: FTS5 keyword search first, semantic embedding fallback if sparse results.
struct AttachmentSearchService {

    private let database: AttachmentDatabase
    private let semanticThreshold: Int = 5

    init(database: AttachmentDatabase = .shared) {
        self.database = database
    }

    // MARK: - Search

    func search(query: String, accountID: String) -> [AttachmentSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return database.allAttachments(limit: 200, accountID: accountID).map {
                AttachmentSearchResult(id: $0.id, attachment: $0, score: 1.0, matchSource: .fts)
            }
        }

        // Step 1: FTS keyword search
        let ftsResults = database.searchFTS(query: trimmed, accountID: accountID)
        let maxBM25 = ftsResults.map(\.1).max() ?? 1.0

        var resultMap: [String: AttachmentSearchResult] = [:]
        for (att, rawScore) in ftsResults {
            let normalizedScore = maxBM25 > 0 ? rawScore / maxBM25 : 1.0
            resultMap[att.id] = AttachmentSearchResult(
                id: att.id,
                attachment: att,
                score: normalizedScore,
                matchSource: .fts
            )
        }

        // Step 2: Semantic fallback if fewer than threshold results
        if ftsResults.count < semanticThreshold {
            if let queryEmbedding = ContentExtractor.generateEmbedding(for: trimmed) {
                let allEmbeddings = database.allEmbeddings(accountID: accountID)
                var semanticScores: [(String, Float)] = []

                for (id, emb) in allEmbeddings {
                    let sim = ContentExtractor.cosineSimilarity(queryEmbedding, emb)
                    if sim > 0.3 {
                        semanticScores.append((id, sim))
                    }
                }
                semanticScores.sort { $0.1 > $1.1 }

                for (id, sim) in semanticScores.prefix(20) {
                    if let existing = resultMap[id] {
                        // Merge FTS + semantic scores
                        resultMap[id] = AttachmentSearchResult(
                            id: id,
                            attachment: existing.attachment,
                            score: (existing.score + Double(sim)) / 2.0,
                            matchSource: .combined
                        )
                    } else if let att = database.attachment(byId: id) {
                        resultMap[id] = AttachmentSearchResult(
                            id: id,
                            attachment: att,
                            score: Double(sim),
                            matchSource: .semantic
                        )
                    }
                }
            }
        }

        return resultMap.values.sorted { $0.score > $1.score }
    }
}
