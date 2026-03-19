import SwiftUI

struct SearchTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var query = ""
    @State private var selectedEmail: Email?
    @State private var isSearching = false
    @State private var searchResults: [Email] = []
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched && searchResults.isEmpty && !isSearching {
                    // Initial state — no search performed yet
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
                    // Search performed but no results
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
                        onRefresh: { await performSearch() }
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
                }
            }
        }
    }

    private func performSearch() async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        do {
            let listResponse = try await GmailMessageService.shared.listMessages(
                accountID: coordinator.accountID,
                labelIDs: [],
                query: query,
                maxResults: 50
            )
            let refs = listResponse.messages ?? []
            guard !refs.isEmpty else {
                searchResults = []
                hasSearched = true
                isSearching = false
                return
            }
            let fullMessages = try await GmailMessageService.shared.getMessages(
                ids: refs.map(\.id),
                accountID: coordinator.accountID,
                format: "metadata"
            )
            searchResults = fullMessages.map { coordinator.mailboxViewModel.makeEmail(from: $0) }
        } catch {
            print("[SearchTab] Search failed: \(error)")
            searchResults = []
        }
        hasSearched = true
        isSearching = false
    }
}
