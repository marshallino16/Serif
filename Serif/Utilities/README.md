# Utilities

Pure helper functions and extensions. Zero state, zero side effects.

## Guidelines

- **Pure functions only**: input → output. No singletons, no persistence, no network.
- No SwiftUI view code. No `@Published`, no `ObservableObject`.
- If a utility grows to need state or persistence, move it to `Services/` or `Models/`.
- Keep utilities small and focused. One file per concern.

## Files

| File | Role |
|------|------|
| `DateFormatting.swift` | Date display helpers (relative time, formatted dates) |
| `FileUtils.swift` | File system helpers (temp dirs, file size formatting) |
| `GmailDataTransformer.swift` | Transforms raw Gmail data (MIME parsing, header extraction) |
