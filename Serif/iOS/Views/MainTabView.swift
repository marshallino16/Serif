import SwiftUI

struct MainTabView: View {
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.theme) private var theme

    var body: some View {
        TabView {
            Tab("Inbox", systemImage: "tray.fill") {
                InboxTab(coordinator: coordinator)
            }

            Tab("Attachments", systemImage: "paperclip") {
                iOSAttachmentExplorerView(coordinator: coordinator, store: coordinator.attachmentStore)
            }

            Tab("Account", systemImage: "person.crop.circle") {
                AccountTab(coordinator: coordinator)
            }

            Tab(role: .search) {
                SearchTab(coordinator: coordinator)
            }
        }
        .modifier(TabBarMinimizeOnScrollModifier())
        .tint(theme.textPrimary)
    }
}

// MARK: - Tab Bar Minimize on Scroll (iOS 26+)

private struct TabBarMinimizeOnScrollModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}
