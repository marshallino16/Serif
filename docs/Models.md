# Models

Pure data structures and local persistence stores.

## Guidelines

- Models are **value types** (`struct`) and conform to `Codable` + `Identifiable`.
- No networking logic. No UI imports (`SwiftUI` only if needed for `Color` or similar).
- Local stores (e.g. `MailStore`, `AccountStore`) handle disk persistence via `UserDefaults` or file-based JSON. They do NOT call APIs.
- `Email` is the UI-facing model derived from `GmailMessage`. Conversion happens in `MailboxViewModel`, not here.
- `GmailAccount` holds account metadata + `AccountStore` for multi-account persistence.

## Files

| File | Role |
|------|------|
| `Email.swift` | UI-facing email model (computed from GmailMessage) |
| `ComposeMode.swift` | Compose mode enum (new, reply, replyAll, forward) |
| `GmailAccount.swift` | Account model + `AccountStore` (UserDefaults persistence) |
| `IndexedAttachment.swift` | Indexed attachment model for the attachment vault |
| `MailStore.swift` | `@MainActor` local draft store, Gmail draft sync, reply draft persistence (`ReplyDraftInfo`) |
