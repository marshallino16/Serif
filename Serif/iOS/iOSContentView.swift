import SwiftUI

struct iOSContentView: View {
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var coordinator = AppCoordinator()
    @AppStorage("isSignedIn") private var isSignedIn = false

    var body: some View {
        ZStack {
            Group {
                if isSignedIn {
                    MainTabView(coordinator: coordinator)
                        .onChange(of: coordinator.selectedAccountID) { _, newID in
                            coordinator.handleAccountChange(newID)
                        }
                        .transition(.opacity)
                } else {
                    iOSOnboardingView(isSignedIn: $isSignedIn)
                        .transition(.opacity)
                }
            }

            // Toasts pinned just above tab bar
            iOSToastOverlay()
                .environment(\.theme, themeManager.currentTheme)
                .zIndex(100)
        }
        .environment(\.theme, themeManager.currentTheme)
        .preferredColorScheme(themeManager.currentTheme.isLight ? .light : .dark)
        .animation(.easeInOut(duration: 0.5), value: isSignedIn)
        .onChange(of: isSignedIn) { _, signedIn in
            if signedIn { initializeAfterSignIn() }
        }
        .onAppear {
            if isSignedIn { initializeCoordinator() }
        }
    }

    private func initializeCoordinator() {
        coordinator.handleAppear()
        Task {
            async let folder: Void = coordinator.loadCurrentFolder()
            async let labels: Void = coordinator.mailboxViewModel.loadLabels()
            async let counts: Void = coordinator.mailboxViewModel.loadCategoryUnreadCounts()
            _ = await (folder, labels, counts)
        }
    }

    private func initializeAfterSignIn() {
        // The onboarding view uses its own AuthViewModel instance which persisted the
        // account to AccountStore. The coordinator's AuthViewModel still has a stale
        // (empty) cache from init time. Reload it so handleAppear() finds the account.
        coordinator.authViewModel.reloadAccounts()
        coordinator.handleAppear()
    }
}
