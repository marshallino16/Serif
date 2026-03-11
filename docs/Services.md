# Services

Business logic, networking, and side effects. This is the **only** layer that talks to external APIs.

## Guidelines

- Services are **singletons** (`static let shared`) — stateless request handlers, not state containers.
- All API calls go through `GmailAPIClient` which handles auth tokens, rate limiting, and logging.
- Services return raw API models (`GmailMessage`, `GmailLabel`, etc.). They do NOT return UI models.
- Error handling: throw errors up to the ViewModel. Services don't show UI or set `@Published` state.
- Services must be **account-aware**: every method takes `accountID` as parameter.
- No SwiftUI imports. No `@Published`, no `ObservableObject` (except `UndoActionManager` and `NetworkMonitor` which are UI singletons by design).

## Subfolders

### `Auth/`
OAuth flow, token storage (Keychain), token refresh. `OAuthService` handles the Google OAuth PKCE flow. `TokenStore` persists tokens securely.

### `Gmail/`
Gmail REST API wrappers. One service per domain:
- `GmailAPIClient` — HTTP layer (auth headers, base URL, per-account token refresh coalescing)
- `GmailMessageService` — Messages, threads, mutations (trash, archive, star, labels), History API. Label modifications delegate to a single `modifyLabels` method.
- `GmailLabelService` — Label CRUD
- `GmailProfileService` — Profile info, contacts, send-as aliases, photos
- `GmailSendService` — Compose, send, draft CRUD (RFC 2822 MIME encoding with RFC 2047 header encoding)
- `GmailDraftService` — Draft fetch (single + batch), used for quick reply draft loading
- `GmailModels` — All API response/request types (`Codable` structs)

### Root-level files
| File | Role |
|------|------|
| `APICache.swift` | Generic ETag-based HTTP response caching |
| `AttachmentDatabase.swift` | SQLite FTS5 index for attachment search |
| `AttachmentIndexer.swift` | Async indexing with CPU throttling |
| `AttachmentSearchService.swift` | Hybrid FTS + semantic embedding search |
| `AvatarCache.swift` | Avatar image caching (uses shared `stableHash` for cache keys) |
| `BIMIService.swift` | BIMI logo resolution via DNS-over-HTTPS |
| `CalendarInviteParser.swift` | iCalendar (.ics) parsing for calendar invite cards |
| `ContentExtractor.swift` | PDF/OCR/Word/text extraction + embedding generation |
| `CPUMonitor.swift` | Adaptive CPU throttling for background tasks |
| `EmailPrintService.swift` | Print formatting via WKWebView |
| `HistorySyncService.swift` | Delta sync via Gmail History API with label-aware filtering |
| `LabelSyncService.swift` | Label + category unread count syncing |
| `MailCacheStore.swift` | File-based JSON cache for messages/threads, keyed by accountID |
| `MessageFetchService.swift` | Pagination, cache management, generation tracking for stale detection |
| `NetworkMonitor.swift` | `@MainActor` online/offline detection via NWPathMonitor |
| `QuickReplyService.swift` | AI-powered quick reply suggestions with bounded cache |
| `SignatureResolver.swift` | Signature HTML lookup per alias, signature replacement in body |
| `SubscriptionsStore.swift` | Detects newsletter/subscription emails, manages unsubscribe state |
| `SummaryService.swift` | AI-powered email summaries (delegates to `String.cleanedForAI` for preprocessing) |
| `ThumbnailCache.swift` | Thumbnail generation + LRU caching with concurrency limiting |
| `ToastManager.swift` | Toast notification state (show/dismiss, typed messages) |
| `TrackerBlockerService.swift` | HTML sanitization, tracking pixel/domain blocking (O(1) domain lookup) |
| `UndoActionManager.swift` | Undo toast state machine (schedule -> countdown -> confirm/undo) |
| `UnsubscribeService.swift` | Parses List-Unsubscribe headers, RFC 8058 one-click POST |
