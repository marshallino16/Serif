import Foundation
import Combine

// MARK: - Glob Matching

extension String {
    /// Matches a simple glob pattern (supports `*` as wildcard, case-insensitive).
    func matchesGlob(_ pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
        let regexPattern = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
        return range(of: regexPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - IndexingStats

struct IndexingStats: Equatable {
    var total: Int = 0
    var indexed: Int = 0
    var pending: Int = 0
    var failed: Int = 0
}

// MARK: - AttachmentStore

@MainActor
final class AttachmentStore: ObservableObject {

    // MARK: - Published State

    @Published var searchQuery = ""
    @Published var searchResults: [AttachmentSearchResult] = []
    @Published var allAttachments: [IndexedAttachment] = []
    @Published var stats = IndexingStats()
    @Published var isSearching = false
    @Published var filterFileType: Attachment.FileType?
    @Published var filterDirection: IndexedAttachment.Direction?
    @Published var exclusionRules: [String] = []

    // MARK: - Dependencies

    private let database: AttachmentDatabase
    private let searchService: AttachmentSearchService
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    var accountID: String = ""

    var indexer: AttachmentIndexer?

    // MARK: - Computed

    var displayedAttachments: [AttachmentSearchResult] {
        var results = searchQuery.isEmpty
            ? allAttachments.map {
                AttachmentSearchResult(id: $0.id, attachment: $0, score: 1.0, matchSource: .fts)
            }
            : searchResults

        if let fileType = filterFileType {
            results = results.filter { $0.attachment.fileType == fileType.rawValue }
        }
        if let direction = filterDirection {
            results = results.filter { $0.attachment.direction == direction }
        }

        // Apply exclusion rules
        if !exclusionRules.isEmpty {
            results = results.filter { r in
                !exclusionRules.contains(where: { r.attachment.filename.matchesGlob($0) })
            }
        }

        // Deduplicate by filename + size (same file attached to multiple emails)
        var seen = Set<String>()
        results = results.filter { r in
            let key = "\(r.attachment.filename)_\(r.attachment.size)"
            return seen.insert(key).inserted
        }
        return results
    }

    var isIndexing: Bool { stats.pending > 0 }

    // MARK: - Init

    init(database: AttachmentDatabase = .shared) {
        self.database = database
        self.searchService = AttachmentSearchService(database: database)
        setupSearchDebounce()
    }

    // MARK: - Search Debounce

    private func setupSearchDebounce() {
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    func refresh() {
        loadExclusionRules()
        allAttachments = database.allAttachments(limit: 5000, offset: 0, accountID: accountID)
        let raw = database.stats(accountID: accountID)
        stats = IndexingStats(
            total: raw.total,
            indexed: raw.indexed,
            pending: raw.pending,
            failed: raw.failed
        )
    }

    // MARK: - Exclusion Rules

    func loadExclusionRules() {
        exclusionRules = UserDefaults.standard.stringArray(forKey: UserDefaultsKey.attachmentExclusionRules(accountID)) ?? []
    }

    func saveExclusionRules() {
        UserDefaults.standard.set(exclusionRules, forKey: UserDefaultsKey.attachmentExclusionRules(accountID))
    }

    func addExclusionRule(_ pattern: String) {
        guard !pattern.isEmpty, !exclusionRules.contains(pattern) else { return }
        exclusionRules.append(pattern)
        saveExclusionRules()
    }

    func removeExclusionRule(_ pattern: String) {
        exclusionRules.removeAll { $0 == pattern }
        saveExclusionRules()
    }

    // MARK: - Search

    private func performSearch(query: String) {
        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            defer { isSearching = false }

            guard !Task.isCancelled else { return }
            let results = searchService.search(query: query, accountID: accountID)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }
}
