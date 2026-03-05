import SwiftUI

@main
struct SerifApp: App {
    @AppStorage("isSignedIn") private var isSignedIn: Bool = false
    @StateObject private var updaterVM = UpdaterViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if isSignedIn {
                    ContentView()
                        .transition(.opacity)
                } else {
                    OnboardingView(isSignedIn: $isSignedIn)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: isSignedIn)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            // Remove system Edit menu handlers so our hidden buttons can intercept ⌘Z and ⌘A
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterVM.checkForUpdates()
                }
                .disabled(!updaterVM.canCheckForUpdates)
            }
        }
    }
}
