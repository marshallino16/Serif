# Serif — Architecture Overview

macOS Gmail client built with Swift/SwiftUI. 3-column layout (sidebar, email list, email detail).

## Folder Structure

| Folder | Role |
|--------|------|
| `Configuration/` | App-level config (API keys, scopes) |
| `Models/` | Data models and local stores |
| `Services/` | Network, auth, business logic |
| `Theme/` | Theming system (colors, persistence) |
| `Utilities/` | Pure helper functions (no state, no side effects) |
| `ViewModels/` | State management layer between Services and Views |
| `Views/` | SwiftUI views (UI only) |
| `Resources/` | Assets, fonts, static files |

## Core Principles

1. **Unidirectional data flow**: Services → ViewModels → Views. Views never call Services directly.
2. **Cache-first**: Contacts, labels, mails, and threads are loaded from disk cache first, then refreshed from API.
3. **Multi-account**: All persistence is keyed by `accountID`. Never assume a single account.
4. **Optimistic UI**: Mutations (archive, trash, star) update the UI immediately, then call the API.
5. **Theme via Environment**: `@Environment(\.theme)` is the single source of truth for colors in all Views.

## Entry Point

`SerifApp.swift` → routes to `OnboardingView` or `ContentView` based on `@AppStorage("isSignedIn")`.
`ContentView.swift` is the main orchestrator: owns ViewModels, wires callbacks, manages navigation state.
