import SwiftUI

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: Theme

    let availableThemes: [Theme] = [
        .midnight,
        .ocean,
        .serif,
        .nord,
        .rose,
        .xcodeDark,
        .emerald,
        .solarizedDark,
        .dracula,
        .oneDark,
        .sunset,
        .light,
    ]

    /// The currently selected base theme ID.
    private(set) var selectedBaseID: String

    /// Custom color overrides per theme ID. Key: "themeID", Value: [colorKey: hexString].
    private var allOverrides: [String: [String: String]]

    private init() {
        let savedId = UserDefaults.standard.string(forKey: "selectedThemeId") ?? "midnight"
        let base = Self.theme(byId: savedId)
        self.selectedBaseID = savedId

        // Load overrides
        if let data = UserDefaults.standard.data(forKey: "themeOverrides"),
           let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            self.allOverrides = decoded
        } else {
            self.allOverrides = [:]
        }

        let overrides = self.allOverrides[savedId] ?? [:]
        self.currentTheme = overrides.isEmpty ? base : base.applying(overrides: overrides)
    }

    func selectTheme(_ theme: Theme) {
        selectedBaseID = theme.id
        UserDefaults.standard.set(theme.id, forKey: "selectedThemeId")
        let overrides = allOverrides[theme.id] ?? [:]
        currentTheme = overrides.isEmpty ? theme : theme.applying(overrides: overrides)
    }

    // MARK: - Overrides

    var currentOverrides: [String: String] {
        allOverrides[selectedBaseID] ?? [:]
    }

    func setOverride(key: String, hex: String) {
        var overrides = allOverrides[selectedBaseID] ?? [:]
        overrides[key] = hex
        allOverrides[selectedBaseID] = overrides
        persistOverrides()
        let base = Self.theme(byId: selectedBaseID)
        currentTheme = base.applying(overrides: overrides)
    }

    func removeOverride(key: String) {
        var overrides = allOverrides[selectedBaseID] ?? [:]
        overrides.removeValue(forKey: key)
        allOverrides[selectedBaseID] = overrides.isEmpty ? nil : overrides
        persistOverrides()
        let base = Self.theme(byId: selectedBaseID)
        currentTheme = overrides.isEmpty ? base : base.applying(overrides: overrides)
    }

    func resetOverrides() {
        allOverrides[selectedBaseID] = nil
        persistOverrides()
        currentTheme = Self.theme(byId: selectedBaseID)
    }

    var hasOverrides: Bool {
        !(allOverrides[selectedBaseID] ?? [:]).isEmpty
    }

    private func persistOverrides() {
        let data = try? JSONEncoder().encode(allOverrides)
        UserDefaults.standard.set(data, forKey: "themeOverrides")
    }

    private static func theme(byId id: String) -> Theme {
        let all: [Theme] = [.midnight, .ocean, .serif, .nord, .rose, .xcodeDark, .emerald, .solarizedDark, .dracula, .oneDark, .sunset, .light]
        return all.first { $0.id == id } ?? .midnight
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
