<p align="center">
  <img src="assets/icon.png" width="128" alt="Serif icon" />
</p>

<h1 align="center">Serif</h1>

<p align="center">
  <em>The email client Gmail deserves.</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20iOS%2018%2B-blue?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/swift-5.9-orange?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-purple?logo=swift&logoColor=white" />
  <img src="https://img.shields.io/github/v/release/marshallino16/Serif?color=green" />
  <img src="https://img.shields.io/github/license/marshallino16/Serif" />
</p>

<p align="center">
  <img src="preview.png" alt="App Preview" />
</p>

---

A native Gmail client for macOS and iOS. No Electron. No web wrapper. Just Swift, SwiftUI, and speed.

**Cache-first.** Your inbox loads before you blink.

**Privacy-first.** Tracking pixels blocked. No telemetry. Ever.

**Native-first.** Feels like it shipped with your Mac — and your iPhone.

## Platforms

| | macOS | iOS |
|---|---|---|
| **Min version** | macOS 14 Sonoma | iOS 18 |
| **Devices** | Mac | iPhone + iPad |
| **Distribution** | DMG + Sparkle auto-update | TestFlight |
| **OAuth** | Desktop app (loopback) | ASWebAuthenticationSession + PKCE |

Shared codebase with platform-specific UI. 67% of code is cross-platform.

## Features

| | |
|---|---|
| **Chat-style threads** | Conversations with bubbles, quote collapsing, and thread grouping |
| **Tracker blocking** | Spy pixels, tracking links, and CSS trackers — all stripped automatically |
| **Smart search** | Gmail query syntax + semantic attachment search (FTS5 + NLEmbedding) |
| **Calendar invites** | Event cards with one-click RSVP — accept, decline, maybe |
| **One-click unsubscribe** | RFC 8058 compliant. See all your subscriptions in one view |
| **Apple Intelligence** | On-device email summaries, quick replies, and label suggestions (macOS/iOS 26+) |
| **Label management** | Create, rename, delete, and sync Gmail labels |
| **Attachment explorer** | Browse, search, filter, and preview all attachments with thumbnails |
| **Rich compose** | Rich text editor, contact autocomplete, Bcc, attachments, templates |
| **Draft sync** | Auto-save drafts to Gmail, restore on reopen |
| **Signatures** | Per-account signature management synced with Gmail |
| **Templates** | Reusable email templates with rich text body |
| **16 themes** | 11 dark + 5 light, with per-color customization |
| **Multi-account** | Switch accounts seamlessly, each with its own settings |
| **Contact avatars** | Google Contacts, Gravatar, and BIMI brand logos |
| **Undo send** | Timed undo with visual countdown |
| **Keyboard-first** | `⌘F` search · `⌘↩` send · `⌘Z` undo (macOS) |
| **Auto-update** | Sparkle updates with appcast (macOS) |

### iOS-specific

- Tab bar: Inbox, Attachments, Account, Search
- Swipe actions with undo toast
- Pull-to-refresh with skeleton loading
- Quick reply bar with gradient animation
- Context menus on email rows
- Dynamic Type support
- Mobile-optimized HTML rendering (viewport, tables, safe areas)

## Architecture

```
Serif/
├── Common/          # Shared code (67% — models, services, view models, theme)
│   ├── Models/
│   ├── Services/    # Gmail API, OAuth, cache, indexer, tracker blocker
│   ├── ViewModels/  # AppCoordinator, MailboxViewModel, ComposeViewModel
│   ├── Theme/       # 16 themes with color customization
│   ├── Utilities/
│   └── Platform/    # PlatformImage, PlatformColor, PlatformURL
├── macOS/           # macOS app + views
│   ├── Views/       # 3-column layout, sidebar, keyboard shortcuts
│   └── Support/     # Sparkle updater, menu commands
├── iOS/             # iOS app + views
│   ├── Views/       # Tab bar, navigation, cards
│   └── Views/Attachments/  # Attachment explorer
└── Resources/       # Assets, entitlements
```

## Getting Started

```bash
git clone https://github.com/marshallino16/Serif.git
```

1. Open `Serif.xcodeproj` in Xcode 16+
2. Copy credential templates and fill in your OAuth values:
   - macOS: `Serif/macOS/GoogleCredentials.swift.example` → `GoogleCredentials.swift`
   - iOS: `Serif/iOS/GoogleCredentialsiOS.swift.example` → `GoogleCredentialsiOS.swift`
3. Select the `Serif` scheme (macOS) or `Serif iOS` scheme (iOS)
4. Build and run

> Requires a Google Cloud project with Gmail API enabled.
> macOS uses a Desktop OAuth client. iOS uses an iOS OAuth client with PKCE.

## License

Private project. All rights reserved.
