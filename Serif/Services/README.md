# Services

Business logic, networking, and side effects. This is the **only** layer that talks to external APIs.

## Guidelines

- Services are **singletons** (`static let shared`) — stateless request handlers, not state containers.
- All API calls go through `GmailAPIClient` which handles auth tokens, rate limiting, and logging.
- Services return raw API models (`GmailMessage`, `GmailLabel`, etc.). They do NOT return UI models.
- Error handling: throw errors up to the ViewModel. Services don't show UI or set `@Published` state.
- Services must be **account-aware**: every method takes `accountID` as parameter.
- No SwiftUI imports. No `@Published`, no `ObservableObject` (except `UndoActionManager` which is a UI singleton by design).

## Subfolders

### `Auth/`
OAuth flow, token storage (Keychain), token refresh. `OAuthService` handles the Google OAuth PKCE flow. `TokenStore` persists tokens securely.

### `Gmail/`
Gmail REST API wrappers. One service per domain:
- `GmailAPIClient` — HTTP layer (auth headers, base URL, logging)
- `GmailMessageService` — messages, threads, mutations (trash, archive, star, labels)
- `GmailLabelService` — label CRUD
- `GmailProfileService` — profile info, contacts, send-as aliases, photos
- `GmailSendService` — compose and send (RFC 2822 encoding)
- `GmailModels` — all API response/request types (`Codable` structs)

### Root-level files
| File | Role |
|------|------|
| `APICache.swift` | Debug-only response cache |
| `UndoActionManager.swift` | Undo toast state machine (schedule → countdown → confirm/undo) |
| `UnsubscribeService.swift` | Parses List-Unsubscribe headers |
| `SubscriptionsStore.swift` | Detects newsletter/subscription emails |
| `EmailPrintService.swift` | Print formatting |
