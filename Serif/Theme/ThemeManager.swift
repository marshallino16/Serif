import SwiftUI

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: Theme {
        didSet {
            UserDefaults.standard.set(currentTheme.id, forKey: "selectedThemeId")
        }
    }

    let availableThemes: [Theme] = [
        .midnight,
        .ocean,
        .charcoal,
        .nord,
        .rose,
        .light,
    ]

    private init() {
        let savedId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "midnight"
        self.currentTheme = availableThemes.first { $0.id == savedId } ?? .midnight
    }
}

// MARK: - Environment Key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .midnight
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
