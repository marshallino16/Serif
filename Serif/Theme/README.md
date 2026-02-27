# Theme

Color theming system with customization and persistence.

## Guidelines

- `Theme` is a **value type** (`struct`). It holds all color properties. No logic beyond color lookup.
- Themes are accessed in Views exclusively via `@Environment(\.theme)`. Never instantiate or hardcode colors.
- `ThemeManager` is the single `ObservableObject` that owns the current theme. It handles:
  - Base theme selection (persisted to UserDefaults)
  - Per-theme color overrides (persisted to UserDefaults as `[themeID: [colorKey: hex]]`)
  - `currentTheme` = base theme + overrides applied
- `Theme.==` must compare actual colors (not just `id`), otherwise SwiftUI won't propagate environment changes when overrides change.
- When adding a new color property:
  1. Add the `let` to `Theme`
  2. Add it to `colorGroups`, `color(for:)`, `label(for:)`, and `applying(overrides:)`
  3. Add it to every theme in `DefaultThemes.swift`

## Files

| File | Role |
|------|------|
| `Theme.swift` | `Theme` struct, `Color` extensions (hex init/export), color lookup helpers |
| `DefaultThemes.swift` | All 12 built-in theme definitions |
| `ThemeManager.swift` | Theme selection, overrides, persistence, `EnvironmentKey` |
