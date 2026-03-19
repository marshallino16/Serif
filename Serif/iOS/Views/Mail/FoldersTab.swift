import SwiftUI

struct FoldersTab: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var showEmptyTrashAlert = false
    @State private var showEmptySpamAlert = false

    private let folders: [Folder] = [.starred, .sent, .drafts, .subscriptions, .archive, .spam, .trash]

    private var userLabels: [GmailLabel] {
        coordinator.mailboxViewModel.labels.filter { !$0.isSystemLabel }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Folders") {
                    ForEach(folders) { folder in
                        NavigationLink {
                            FolderEmailListView(folder: folder, coordinator: coordinator)
                        } label: {
                            Label(folder.rawValue, systemImage: folder.icon)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if folder == .trash {
                                Button(role: .destructive) {
                                    showEmptyTrashAlert = true
                                } label: {
                                    Label("Empty", systemImage: "trash.slash")
                                }
                            }
                            if folder == .spam {
                                Button(role: .destructive) {
                                    showEmptySpamAlert = true
                                } label: {
                                    Label("Empty", systemImage: "xmark.bin")
                                }
                            }
                        }
                    }
                }

                Section("Templates") {
                    NavigationLink {
                        iOSTemplateListView(coordinator: coordinator)
                    } label: {
                        Label("Templates", systemImage: "doc.on.doc.fill")
                    }
                }

                if !userLabels.isEmpty {
                    Section("Labels") {
                        ForEach(userLabels) { label in
                            NavigationLink {
                                LabelEmailListView(label: label, coordinator: coordinator)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: label.color?.backgroundColor ?? "#888888"))
                                        .frame(width: 10, height: 10)
                                    Text(label.name)
                                    Spacer()
                                    if let unread = label.messagesUnread, unread > 0 {
                                        Text("\(unread)")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(theme.accentPrimary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.listBackground)
            .navigationTitle("Mail")
            .navigationBarTitleDisplayMode(.large)
            .alert("Empty Trash", isPresented: $showEmptyTrashAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Empty Trash", role: .destructive) {
                    Task { await coordinator.mailboxViewModel.emptyTrash() }
                }
            } message: {
                Text("All messages in Trash will be permanently deleted. This action cannot be undone.")
            }
            .alert("Empty Spam", isPresented: $showEmptySpamAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Empty Spam", role: .destructive) {
                    Task { await coordinator.mailboxViewModel.emptySpam() }
                }
            } message: {
                Text("All messages in Spam will be permanently deleted. This action cannot be undone.")
            }
        }
    }
}

// MARK: - Folder Email List

struct FolderEmailListView: View {
    let folder: Folder
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var selectedEmail: Email?
    @State private var showEmptyConfirm = false

    var body: some View {
        iOSEmailListView(
            emails: coordinator.mailboxViewModel.emails,
            isLoading: coordinator.mailboxViewModel.isLoading,
            selectedEmail: $selectedEmail,
            onRefresh: {
                if let labelID = folder.gmailLabelID {
                    await coordinator.mailboxViewModel.refreshCurrentFolder(labelIDs: [labelID])
                } else if let query = folder.gmailQuery {
                    await coordinator.mailboxViewModel.loadFolder(labelIDs: [], query: query)
                }
            },
            onArchive: { email in
                coordinator.actionCoordinator.archiveEmail(email) { next in
                    coordinator.selectNext(next)
                }
            },
            onTrash: { email in
                coordinator.actionCoordinator.deleteEmail(email) { next in
                    coordinator.selectNext(next)
                }
            },
            onLoadMore: {
                Task { await coordinator.mailboxViewModel.loadMore() }
            },
            isLoadingMore: coordinator.mailboxViewModel.isLoadingMore
        )
        .navigationTitle(folder.rawValue)
        .toolbar {
            if folder == .trash || folder == .spam {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive) {
                        showEmptyConfirm = true
                    } label: {
                        Text(folder == .trash ? "Empty Trash" : "Empty Spam")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .disabled(coordinator.mailboxViewModel.emails.isEmpty)
                }
            }
        }
        .alert(
            folder == .trash ? "Empty Trash" : "Empty Spam",
            isPresented: $showEmptyConfirm
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                Task {
                    if folder == .trash {
                        await coordinator.mailboxViewModel.emptyTrash()
                    } else {
                        await coordinator.mailboxViewModel.emptySpam()
                    }
                }
            }
        } message: {
            Text("All messages will be permanently deleted. This cannot be undone.")
        }
        .navigationDestination(item: $selectedEmail) { email in
            iOSEmailDetailView(email: email, coordinator: coordinator)
        }
        .task(id: folder) {
            if let labelID = folder.gmailLabelID {
                await coordinator.mailboxViewModel.refreshCurrentFolder(labelIDs: [labelID])
            } else if let query = folder.gmailQuery {
                await coordinator.mailboxViewModel.loadFolder(labelIDs: [], query: query)
            }
        }
    }
}

// MARK: - Label Email List

struct LabelEmailListView: View {
    let label: GmailLabel
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme
    @State private var selectedEmail: Email?

    var body: some View {
        iOSEmailListView(
            emails: coordinator.mailboxViewModel.emails,
            isLoading: coordinator.mailboxViewModel.isLoading,
            selectedEmail: $selectedEmail,
            onRefresh: {
                await coordinator.mailboxViewModel.refreshCurrentFolder(labelIDs: [label.id])
            },
            onArchive: { email in
                coordinator.actionCoordinator.archiveEmail(email) { next in
                    coordinator.selectNext(next)
                }
            },
            onTrash: { email in
                coordinator.actionCoordinator.deleteEmail(email) { next in
                    coordinator.selectNext(next)
                }
            },
            onLoadMore: {
                Task { await coordinator.mailboxViewModel.loadMore() }
            },
            isLoadingMore: coordinator.mailboxViewModel.isLoadingMore
        )
        .navigationTitle(label.name)
        .navigationDestination(item: $selectedEmail) { email in
            iOSEmailDetailView(email: email, coordinator: coordinator)
        }
        .task(id: label.id) {
            await coordinator.mailboxViewModel.refreshCurrentFolder(labelIDs: [label.id])
        }
    }
}
