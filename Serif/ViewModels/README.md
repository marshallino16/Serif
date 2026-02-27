# ViewModels

State management layer between Services and Views. Each ViewModel is an `@MainActor ObservableObject`.

## Guidelines

- ViewModels own `@Published` state and call Services to fetch/mutate data.
- ViewModels do **not** import SwiftUI views. They may import `SwiftUI` for `@Published` and animations.
- One ViewModel per major screen/domain:
  - `AuthViewModel` — sign-in state, account list
  - `MailboxViewModel` — email list, labels, folder navigation, mutations
  - `EmailDetailViewModel` — thread loading, attachments, raw source
  - `ComposeViewModel` — draft state, send, auto-save
- **Cache-first pattern**: load from disk → show instantly → refresh from API → persist.
  - Disk cache: `MailCacheStore` (file-based JSON in `~/Library/Application Support/`)
  - In-memory cache: `messageCache: [String: GmailMessage]` avoids redundant API fetches
- **Optimistic UI**: update `@Published` state before the API call. Revert on failure.
- ViewModels are **account-aware**: `accountID` is always a parameter or stored property.
- Conversion from API models to UI models happens here (e.g. `GmailMessage` → `Email`).

## Files

| File | Role |
|------|------|
| `AuthViewModel.swift` | OAuth flow, account switching, sign-in/out state |
| `MailboxViewModel.swift` | Email list + `MailCacheStore` (disk persistence for mails, labels, threads) |
| `EmailDetailViewModel.swift` | Thread loading with disk cache, attachment download |
| `ComposeViewModel.swift` | Draft management, send, auto-save, Bcc |
