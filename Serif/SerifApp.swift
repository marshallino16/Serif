import SwiftUI

@main
struct SerifApp: App {
    @AppStorage("isSignedIn") private var isSignedIn: Bool = false

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
    }
}
