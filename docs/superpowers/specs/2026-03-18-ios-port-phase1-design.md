# iOS Port — Phase 1: Restructuration & Target iOS

## Overview

Reorganize the Serif macOS project into a multi-platform structure with shared code in `Common/`, macOS-specific code in `macOS/`, and a new iOS target with placeholder views. This phase does NOT implement iOS UI — it sets up the foundation so Phase 2-3 can build iOS screens incrementally.

## Scope

**In scope:**
- New folder structure: `Common/`, `macOS/`, `iOS/`
- Platform abstraction layer (`Common/Platform/`)
- Patch files with minor AppKit dependencies to use abstractions
- New iOS target in same Xcode project (iPhone + iPad)
- iOS placeholder app that compiles and launches

**Out of scope:**
- iOS navigation, views, or screens (Phase 2-3)
- AttachmentIndexer, AttachmentDatabase, CPUMonitor (excluded from iOS)
- Template feature (excluded from iOS MVP)
- Push notifications

## Folder Structure

```
Serif/
├── Common/
│   ├── Models/
│   ├── Services/
│   │   ├── Auth/
│   │   ├── Gmail/
│   │   └── Protocols/
│   ├── ViewModels/
│   ├── Utilities/
│   ├── Theme/
│   └── Platform/
│       ├── PlatformImage.swift
│       ├── PlatformColor.swift
│       └── PlatformURL.swift
├── macOS/
│   ├── SerifApp.swift
│   ├── ContentView.swift
│   ├── Views/ (all current views)
│   └── Support/ (KeyboardShortcutsModifier, SerifCommands, UpdaterViewModel)
├── iOS/
│   ├── SerifApp.swift
│   ├── ContentView.swift
│   └── Views/
│       └── Placeholder.swift
└── Resources/
    ├── macOS/ (Info.plist, Serif.entitlements)
    └── iOS/ (Info.plist, SerifiOS.entitlements)
```

## Platform Abstractions (`Common/Platform/`)

### PlatformImage.swift

```swift
#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif
```

Used by: AvatarCache, ThumbnailCache, AvatarView, AccountAvatarBubble.

### PlatformColor.swift

Replace `NSColor` usage in `Theme.swift` for luminance calculation. Use `Color.resolve(in: EnvironmentValues())` which returns resolved RGBA components on both platforms (available macOS 14+ / iOS 17+).

### PlatformURL.swift

```swift
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PlatformURL {
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
```

Used by: UnsubscribeService, any service opening external URLs.

## Files That Need Patching Before Move

| File | Current Dependency | Fix |
|------|--------------------|-----|
| Theme.swift | `NSColor` for `isLight`/`sidebarIsDark` | Use `Color.resolve(in:)` for luminance |
| AvatarCache.swift | `NSImage`, `NSCache` | Use `PlatformImage` typealias |
| ThumbnailCache.swift | `NSImage` | Use `PlatformImage` typealias |
| AvatarView.swift | `NSImage` | Use `PlatformImage` typealias |
| AccountAvatarBubble.swift | `NSImage` | Use `PlatformImage` typealias |
| UnsubscribeService.swift | `NSWorkspace.shared.open` | Use `PlatformURL.open` |
| FormattingToolbar.swift | `NSColor` array | Use `Color` initializers |
| WebRichTextEditorState.swift | `NSColor`, `NSTextAlignment` | `#if os()` conditional |
| ContentExtractor.swift | `NSString` for pathExtension | Use Swift String API |
| EmailPrintService.swift | NSPrintOperation | Keep macOS-only, exclude from iOS target |

## File Movement Map

### → Common/Models/
Email.swift, ComposeMode.swift, GmailAccount.swift, EmailTemplate.swift, IndexedAttachment.swift, MailStore.swift

### → Common/Services/
All services except EmailPrintService.swift and CPUMonitor.swift.
Subdirectories preserved: Auth/, Gmail/, Protocols/.

### → Common/ViewModels/
AppCoordinator.swift, MailboxViewModel.swift, ComposeViewModel.swift, AuthViewModel.swift, EmailActionCoordinator.swift, EmailDetailViewModel.swift, ComposeModeInitializer.swift, AttachmentStore.swift, PanelCoordinator.swift.

Excluded from Common (macOS only): UpdaterViewModel.swift.

### → Common/Utilities/
StringExtensions.swift, DateFormatting.swift, HTMLTemplate.swift, FileUtils.swift, GmailDataTransformer.swift, InlineImageProcessor.swift.

### → Common/Theme/
Theme.swift, DefaultThemes.swift, DesignSystem.swift, ThemeManager.swift.

### → macOS/
SerifApp.swift, ContentView.swift.

### → macOS/Views/
All current Views/ subdirectories as-is.

### → macOS/Support/
KeyboardShortcutsModifier.swift, SerifCommands.swift, UpdaterViewModel.swift.

### macOS-only services (excluded from iOS target via file membership)
EmailPrintService.swift, CPUMonitor.swift, AttachmentIndexer.swift, AttachmentDatabase.swift, AttachmentSearchService.swift, ContentExtractor.swift.

## iOS Target Configuration

- **Target name:** Serif iOS
- **Bundle ID:** com.genyus.serif.ios
- **Deployment target:** iOS 17.0
- **Devices:** iPhone + iPad
- **Shared dependencies:** AppAuth, BlossomColorPicker
- **macOS-only dependencies:** Sparkle
- **File membership:** Common/ → both targets. macOS/ → macOS target. iOS/ → iOS target.

## iOS Placeholder App

Minimal app that compiles and shows a "Serif iOS — Coming Soon" screen. Verifies the target builds and shared code compiles on iOS.

```swift
// iOS/SerifApp.swift
@main
struct SerifApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// iOS/ContentView.swift
struct ContentView: View {
    var body: some View {
        Text("Serif iOS")
    }
}
```

## Migration Strategy

1. Create `Common/Platform/` abstractions first
2. Patch files with AppKit dependencies to use abstractions
3. Move files to new folder structure
4. Update Xcode project (file references, groups)
5. Add iOS target
6. Set file membership (Common → both, macOS → macOS only, iOS → iOS only)
7. Build macOS target — verify no regression
8. Build iOS target — verify it compiles
9. Run existing tests — verify they pass

## Risks

- **Xcode project file conflicts:** Moving 100+ files changes many pbxproj references. Use careful sequential moves.
- **Import breakage:** Moving files changes module paths. Swift doesn't use explicit module paths for files in the same target, so this should be transparent.
- **Sparkle conditional:** AuthViewModel references UpdaterViewModel. Need `#if os(macOS)` guard or move the Sparkle reference out.
