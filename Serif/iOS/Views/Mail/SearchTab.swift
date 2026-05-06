import SwiftUI

struct SearchTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var selectedEmail: Email?
    @State private var isSearching = false
    @State private var searchResults: [Email] = []
    @State private var hasSearched = false
    @State private var nextPageToken: String?
    @State private var isLoadingMore = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched && searchResults.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(theme.textTertiary)
                        Text("Search emails")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasSearched && searchResults.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(theme.textTertiary)
                        Text("No results for \"\(query)\"")
                            .font(.system(size: 15))
                            .foregroundColor(theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    iOSEmailListView(
                        emails: searchResults,
                        isLoading: isSearching,
                        selectedEmail: $selectedEmail,
                        onRefresh: { await performSearch() },
                        onLoadMore: nextPageToken != nil ? { Task { await loadMore() } } : nil,
                        isLoadingMore: isLoadingMore
                    )
                    .navigationDestination(item: $selectedEmail) { email in
                        iOSEmailDetailView(email: email, coordinator: coordinator)
                    }
                }
            }
            .background(theme.detailBackground)
            .scrollContentBackground(.hidden)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Search emails...")
            .onSubmit(of: .search) {
                Task { await performSearch() }
            }
            .onChange(of: query) { _, newValue in
                if newValue.isEmpty {
                    hasSearched = false
                    searchResults = []
                    nextPageToken = nil
                }
            }
        }
    }

    private func performSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        searchResults = []
        nextPageToken = nil
        do {
            let results = try await fetchPage(pageToken: nil)
            searchResults = results
        } catch {
            print("[SearchTab] Search failed: \(error)")
            searchResults = []
        }
        hasSearched = true
        isSearching = false
    }

    private func loadMore() async {
        guard let token = nextPageToken, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let results = try await fetchPage(pageToken: token)
            searchResults.append(contentsOf: results)
        } catch {
            print("[SearchTab] Load more failed: \(error)")
        }
        isLoadingMore = false
    }

    private func fetchPage(pageToken: String?) async throws -> [Email] {
        let result = try await GmailMessageService.shared.searchByThreads(
            accountID: coordinator.accountID,
            query: query,
            pageToken: pageToken,
            maxResults: 50
        )
        nextPageToken = result.nextPageToken
        return result.messages.map { coordinator.mailboxViewModel.makeEmail(from: $0) }
    }
}
