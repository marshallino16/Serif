# iOS Port Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure Serif into a multi-platform project with shared code, platform abstractions, and an iOS target that compiles.

**Architecture:** Create `Common/Platform/` abstractions for NSImage/NSColor/NSWorkspace, patch ~10 files to use them, reorganize into `Common/macOS/iOS/` folders, add iOS target with placeholder app. Both targets must build.

**Tech Stack:** Swift, SwiftUI, AppKit (macOS), UIKit (iOS), WKWebView, AppAuth

**Spec:** `docs/superpowers/specs/2026-03-18-ios-port-phase1-design.md`

---

## Chunk 1: Platform Abstractions & File Patches

### Task 1: Create Common/Platform/ abstraction files

**Files:**
- Create: `Serif/Common/Platform/PlatformImage.swift`
- Create: `Serif/Common/Platform/PlatformColor.swift`
- Create: `Serif/Common/Platform/PlatformURL.swift`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p Serif/Common/Platform
```

- [ ] **Step 2: Create PlatformImage.swift**

```swift
// Serif/Common/Platform/PlatformImage.swift
#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif
```

- [ ] **Step 3: Create PlatformColor.swift**

```swift
// Serif/Common/Platform/PlatformColor.swift
import SwiftUI

extension Color {
    /// Compute luminance from resolved color components (cross-platform).
    func luminance(in environment: EnvironmentValues = EnvironmentValues()) -> Double {
        let resolved = self.resolve(in: environment)
        return 0.299 * Double(resolved.red) + 0.587 * Double(resolved.green) + 0.114 * Double(resolved.blue)
    }
}
```

- [ ] **Step 4: Create PlatformURL.swift**

```swift
// Serif/Common/Platform/PlatformURL.swift
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PlatformURL {
    @MainActor
    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add Serif/Common/Platform/
git commit -m "Add cross-platform abstractions for Image, Color, and URL"
```

---

### Task 2: Patch Theme.swift — replace NSColor luminance

**Files:**
- Modify: `Serif/Theme/Theme.swift:44-54` (isLight, sidebarIsDark)
- Modify: `Serif/Theme/Theme.swift:200-204` (hexString)

- [ ] **Step 1: Replace isLight computed property**

Replace `NSColor(detailBackground).usingColorSpace(.sRGB)` luminance with the new cross-platform `Color.luminance()` extension. Lines 44-48:

```swift
var isLight: Bool {
    detailBackground.luminance() > 0.5
}
```

- [ ] **Step 2: Replace sidebarIsDark computed property**

Lines 51-55:

```swift
private var sidebarIsDark: Bool {
    sidebarBackground.luminance() < 0.5
}
```

- [ ] **Step 3: Replace hexString with cross-platform version**

Lines 200-206. Replace NSColor-based conversion with resolved color:

```swift
var hexString: String {
    let resolved = self.resolve(in: EnvironmentValues())
    let r = Int(max(0, min(1, resolved.red)) * 255)
    let g = Int(max(0, min(1, resolved.green)) * 255)
    let b = Int(max(0, min(1, resolved.blue)) * 255)
    return String(format: "#%02X%02X%02X", r, g, b)
}
```

- [ ] **Step 4: Remove any remaining `import AppKit` if present (implicit through NSColor)**

Verify no other NSColor usage remains in the file.

- [ ] **Step 5: Build macOS target to verify**

```bash
xcodebuild -project Serif.xcodeproj -scheme Serif -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 6: Commit**

```bash
git add Serif/Theme/Theme.swift
git commit -m "Replace NSColor with cross-platform Color.resolve in Theme"
```

---

### Task 3: Patch AvatarCache and ThumbnailCache — NSImage → PlatformImage

**Files:**
- Modify: `Serif/Services/AvatarCache.swift`
- Modify: `Serif/Services/ThumbnailCache.swift`

- [ ] **Step 1: Patch AvatarCache.swift**

Replace `import AppKit` with conditional import. Replace all `NSImage` with `PlatformImage`. Keep `NSCache` (available on both platforms via Foundation).

Key changes:
- Line 1: Replace `import AppKit` with `#if os(macOS)\nimport AppKit\n#else\nimport UIKit\n#endif`
- Line 15: `NSCache<NSString, NSImage>()` → `NSCache<NSString, PlatformImage>()`
- Line 23: Return type `NSImage?` → `PlatformImage?`
- Lines 41, 60: `NSImage(contentsOfFile:)` → platform conditional:
  ```swift
  #if os(macOS)
  let img = NSImage(contentsOfFile: fileURL.path)
  #else
  let img = UIImage(contentsOfFile: fileURL.path)
  #endif
  ```

- [ ] **Step 2: Patch ThumbnailCache.swift**

Replace `import AppKit` with conditional import. Replace `NSImage` with `PlatformImage`.

Key changes:
- Line 1: Conditional import
- Line 10: `[String: NSImage]` → `[String: PlatformImage]`
- Line 40: Return type → `PlatformImage?`
- Lines 92+: All `NSImage` references → `PlatformImage`
- Lines 138-159 (image resizing with lockFocus): Wrap in `#if os(macOS)` and provide iOS `UIGraphicsImageRenderer` alternative
- Line 129: `NSImage(contentsOf:)` → conditional

- [ ] **Step 3: Build macOS target to verify**

```bash
xcodebuild -project Serif.xcodeproj -scheme Serif -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Serif/Services/AvatarCache.swift Serif/Services/ThumbnailCache.swift
git commit -m "Replace NSImage with PlatformImage in cache services"
```

---

### Task 4: Patch view files — AvatarView, AccountAvatarBubble

**Files:**
- Modify: `Serif/Views/Common/AvatarView.swift`
- Modify: `Serif/Views/Common/AccountAvatarBubble.swift`

- [ ] **Step 1: Patch AvatarView.swift**

- Line 2: Replace `import AppKit` with conditional import
- Line 11: `NSImage?` → `PlatformImage?`
- Line 17: `Image(nsImage: image)` → conditional:
  ```swift
  #if os(macOS)
  Image(nsImage: image)
  #else
  Image(uiImage: image)
  #endif
  ```

- [ ] **Step 2: Patch AccountAvatarBubble.swift**

Same pattern:
- Line 2: Conditional import
- Line 10: `NSImage?` → `PlatformImage?`
- Line 26: `Image(nsImage:)` → conditional

- [ ] **Step 3: Build macOS and verify**

- [ ] **Step 4: Commit**

```bash
git add Serif/Views/Common/AvatarView.swift Serif/Views/Common/AccountAvatarBubble.swift
git commit -m "Replace NSImage with PlatformImage in avatar views"
```

---

### Task 5: Patch UnsubscribeService — NSWorkspace → PlatformURL

**Files:**
- Modify: `Serif/Services/UnsubscribeService.swift`

- [ ] **Step 1: Replace NSWorkspace.shared.open with PlatformURL.open**

- Line 2: Remove `import AppKit`
- Line 43: `NSWorkspace.shared.open(url)` → `PlatformURL.open(url)`
- NSRegularExpression and NSRange are Foundation, no change needed.

- [ ] **Step 2: Build and verify**

- [ ] **Step 3: Commit**

```bash
git add Serif/Services/UnsubscribeService.swift
git commit -m "Replace NSWorkspace with PlatformURL in UnsubscribeService"
```

---

### Task 6: Patch FormattingToolbar and WebRichTextEditorState

**Files:**
- Modify: `Serif/Views/Common/FormattingToolbar.swift`
- Modify: `Serif/Views/Common/WebRichTextEditorState.swift`

- [ ] **Step 1: Patch FormattingToolbar.swift**

These files are macOS-only views (will live in macOS/ folder). For now, add `#if os(macOS)` guards around the NSColor/NSTextAlignment usage so they compile on macOS but are excluded on iOS.

Wrap the entire file body in `#if os(macOS)`:
```swift
import SwiftUI
#if os(macOS)
import AppKit
// ... existing code unchanged ...
#endif
```

- [ ] **Step 2: Patch WebRichTextEditorState.swift**

Same approach — this file has deep NSColor/NSImage/NSTextAlignment dependencies. Wrap platform-specific parts:

- Add conditional import at top
- Wrap NSColor properties (lines 13-14) in `#if os(macOS) ... #else` with iOS alternatives:
  ```swift
  #if os(macOS)
  @Published var textColor: NSColor = .labelColor
  @Published var alignment: NSTextAlignment = .left
  #else
  @Published var textColor: UIColor = .label
  @Published var alignment: NSTextAlignment = .left
  #endif
  ```
- Wrap setTextColor, setAlignment, colorToHex, nsColorFromHex in `#if os(macOS)` with iOS equivalents using UIColor
- Wrap NSImage resizing (lines 107-118) with `#if os(macOS)` and UIKit alternative

- [ ] **Step 3: Build macOS and verify**

- [ ] **Step 4: Commit**

```bash
git add Serif/Views/Common/FormattingToolbar.swift Serif/Views/Common/WebRichTextEditorState.swift
git commit -m "Add platform conditionals to FormattingToolbar and EditorState"
```

---

### Task 7: Patch remaining files — ContentExtractor, AuthViewModel

**Files:**
- Modify: `Serif/Services/ContentExtractor.swift`
- Modify: `Serif/ViewModels/AuthViewModel.swift`

- [ ] **Step 1: Patch ContentExtractor.swift**

- Line 43: Replace `(filename as NSString).pathExtension.lowercased()` with:
  ```swift
  (filename as NSString).pathExtension.lowercased()
  // NSString is Foundation, works on iOS — no change needed
  ```
  Actually NSString is Foundation, cross-platform. Just replace `import AppKit` with `import Foundation`. Line 118 `NSAttributedString` is also Foundation.

- [ ] **Step 2: Patch AuthViewModel.swift**

- Line 22: `NSApplication.shared.windows.first` → conditional:
  ```swift
  #if os(macOS)
  let window = NSApplication.shared.windows.first
  #else
  let window: UIWindow? = nil // iOS uses different auth flow
  #endif
  ```

- Add `UpdaterViewModel` reference behind `#if os(macOS)` since Sparkle is macOS-only.

- [ ] **Step 3: Build macOS and verify**

- [ ] **Step 4: Commit**

```bash
git add Serif/Services/ContentExtractor.swift Serif/ViewModels/AuthViewModel.swift
git commit -m "Add platform conditionals to ContentExtractor and AuthViewModel"
```

---

## Chunk 2: Folder Restructure & iOS Target

### Task 8: Create folder structure and move files

**Files:**
- Move ~100 files from `Serif/` to `Serif/Common/` and `Serif/macOS/`

- [ ] **Step 1: Create target directories**

```bash
mkdir -p Serif/Common/{Models,Services/{Auth,Gmail,Protocols},ViewModels,Utilities,Theme}
mkdir -p Serif/macOS/{Views/{Sidebar,EmailList,EmailDetail,Compose,Common,Attachments,Settings,Templates,Onboarding,Components},Support}
mkdir -p Serif/iOS/Views
mkdir -p Serif/Resources/{macOS,iOS}
```

- [ ] **Step 2: Move Common files**

```bash
# Models
git mv Serif/Models/*.swift Serif/Common/Models/

# Services (top-level)
for f in APICache AttachmentDatabase AttachmentIndexer AttachmentSearchService AvatarCache BIMIService CalendarInviteParser ContentExtractor CPUMonitor EmailPrintService HistorySyncService LabelSuggestionService LabelSyncService MailCacheStore MessageFetchService NetworkMonitor QuickReplyService SignatureResolver SubscriptionsStore SummaryService TemplateStore ThumbnailCache ToastManager TrackerBlockerService UndoActionManager UnsubscribeService; do
  git mv "Serif/Services/${f}.swift" Serif/Common/Services/
done

# Services subdirs
git mv Serif/Services/Auth/*.swift Serif/Common/Services/Auth/
git mv Serif/Services/Gmail/*.swift Serif/Common/Services/Gmail/
git mv Serif/Services/Protocols/*.swift Serif/Common/Services/Protocols/

# ViewModels
for f in AppCoordinator AttachmentStore AuthViewModel ComposeModeInitializer ComposeViewModel EmailActionCoordinator EmailDetailViewModel MailboxViewModel PanelCoordinator; do
  git mv "Serif/ViewModels/${f}.swift" Serif/Common/ViewModels/
done

# Utilities
git mv Serif/Utilities/*.swift Serif/Common/Utilities/

# Theme
git mv Serif/Theme/*.swift Serif/Common/Theme/

# Platform (already created in Task 1)
# Already in Serif/Common/Platform/
```

- [ ] **Step 3: Move macOS-specific files**

```bash
# Entry points
git mv Serif/SerifApp.swift Serif/macOS/
git mv Serif/ContentView.swift Serif/macOS/

# Views (all subdirectories)
git mv Serif/Views/Sidebar/*.swift Serif/macOS/Views/Sidebar/
git mv Serif/Views/EmailList/*.swift Serif/macOS/Views/EmailList/
git mv Serif/Views/EmailDetail/*.swift Serif/macOS/Views/EmailDetail/
git mv Serif/Views/Compose/*.swift Serif/macOS/Views/Compose/
git mv Serif/Views/Common/*.swift Serif/macOS/Views/Common/
git mv Serif/Views/Attachments/*.swift Serif/macOS/Views/Attachments/
git mv Serif/Views/Settings/*.swift Serif/macOS/Views/Settings/
git mv Serif/Views/Templates/*.swift Serif/macOS/Views/Templates/
git mv Serif/Views/Onboarding/*.swift Serif/macOS/Views/Onboarding/
git mv Serif/Views/Components/*.swift Serif/macOS/Views/Components/

# macOS-only support
git mv Serif/ViewModels/UpdaterViewModel.swift Serif/macOS/Support/

# Configuration
git mv Serif/Configuration/*.swift Serif/macOS/
```

- [ ] **Step 4: Move resources**

```bash
git mv Serif/Serif.entitlements Serif/Resources/macOS/
# Info.plist stays or moves depending on Xcode config
```

- [ ] **Step 5: Clean up empty directories**

```bash
rmdir Serif/Models Serif/Services/Auth Serif/Services/Gmail Serif/Services/Protocols Serif/Services Serif/ViewModels Serif/Utilities Serif/Theme Serif/Views/Sidebar Serif/Views/EmailList Serif/Views/EmailDetail Serif/Views/Compose Serif/Views/Common Serif/Views/Attachments Serif/Views/Settings Serif/Views/Templates Serif/Views/Onboarding Serif/Views/Components Serif/Views Serif/Configuration 2>/dev/null || true
```

- [ ] **Step 6: Commit the restructure**

```bash
git add -A
git commit -m "Restructure into Common/macOS/iOS folder layout"
```

---

### Task 9: Update Xcode project references

**Files:**
- Modify: `Serif.xcodeproj/project.pbxproj`

- [ ] **Step 1: Update all PBXFileReference paths**

Every file that moved needs its path updated in pbxproj. Since the project has ~130 file references, use a script:

```bash
# Script to update file paths in pbxproj
cd /Users/marshalino16/Documents/GitHub/Serif
python3 -c "
import re

with open('Serif.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# Map old paths to new paths
moves = {
    'Serif/Models/': 'Serif/Common/Models/',
    'Serif/Services/Auth/': 'Serif/Common/Services/Auth/',
    'Serif/Services/Gmail/': 'Serif/Common/Services/Gmail/',
    'Serif/Services/Protocols/': 'Serif/Common/Services/Protocols/',
    'Serif/Services/': 'Serif/Common/Services/',
    'Serif/Utilities/': 'Serif/Common/Utilities/',
    'Serif/Theme/': 'Serif/Common/Theme/',
    'Serif/ViewModels/UpdaterViewModel': 'Serif/macOS/Support/UpdaterViewModel',
    'Serif/ViewModels/': 'Serif/Common/ViewModels/',
    'Serif/SerifApp.swift': 'Serif/macOS/SerifApp.swift',
    'Serif/ContentView.swift': 'Serif/macOS/ContentView.swift',
    'Serif/Views/': 'Serif/macOS/Views/',
    'Serif/Configuration/': 'Serif/macOS/',
}

for old, new in moves.items():
    content = content.replace(old, new)

with open('Serif.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print('Done')
"
```

- [ ] **Step 2: Add new files to pbxproj (Platform/ files)**

Add PBXFileReference and PBXBuildFile entries for PlatformImage.swift, PlatformColor.swift, PlatformURL.swift.

- [ ] **Step 3: Build macOS to verify all references resolve**

```bash
xcodebuild -project Serif.xcodeproj -scheme Serif -configuration Debug build 2>&1 | tail -5
```

- [ ] **Step 4: Commit**

```bash
git add Serif.xcodeproj/project.pbxproj
git commit -m "Update Xcode project references for new folder structure"
```

---

### Task 10: Add iOS target and placeholder app

**Files:**
- Modify: `Serif.xcodeproj/project.pbxproj`
- Create: `Serif/iOS/SerifApp.swift`
- Create: `Serif/iOS/ContentView.swift`
- Create: `Serif/Resources/iOS/Info.plist`

- [ ] **Step 1: Create iOS entry point files**

```swift
// Serif/iOS/SerifApp.swift
import SwiftUI

@main
struct SerifiOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

```swift
// Serif/iOS/ContentView.swift
import SwiftUI

struct ContentView: View {
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 48))
                .foregroundColor(themeManager.currentTheme.accentPrimary)
            Text("Serif")
                .font(.system(size: 24, weight: .bold))
            Text("iOS — Coming Soon")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.detailBackground)
        .environment(\.theme, themeManager.currentTheme)
    }
}
```

- [ ] **Step 2: Create iOS Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Serif</string>
    <key>CFBundleIdentifier</key>
    <string>com.genyus.serif.ios</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>UILaunchScreen</key>
    <dict/>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Add iOS target to Xcode project**

Add a new native target "Serif iOS" in the pbxproj:
- Product type: `com.apple.product-type.application`
- Platform: iOS
- Deployment target: 17.0
- Bundle ID: `com.genyus.serif.ios`
- Dependencies: AppAuth, BlossomColorPicker
- Exclude: Sparkle

- [ ] **Step 4: Set file membership**

All files in `Serif/Common/` → both targets (Serif + Serif iOS).
All files in `Serif/macOS/` → Serif target only.
All files in `Serif/iOS/` → Serif iOS target only.

Exclude from iOS target:
- EmailPrintService.swift
- CPUMonitor.swift
- AttachmentIndexer.swift
- AttachmentDatabase.swift
- AttachmentSearchService.swift
- ContentExtractor.swift
- UpdaterViewModel.swift
- KeyboardShortcutsModifier.swift
- SerifCommands.swift
- ShortcutsHelpView.swift

- [ ] **Step 5: Build macOS target**

```bash
xcodebuild -project Serif.xcodeproj -scheme Serif -configuration Debug build 2>&1 | tail -5
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 6: Build iOS target**

```bash
xcodebuild -project Serif.xcodeproj -scheme "Serif iOS" -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10
```

Expected: **BUILD SUCCEEDED**

- [ ] **Step 7: Run existing tests**

```bash
xcodebuild -project Serif.xcodeproj -scheme Serif test 2>&1 | tail -10
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Add iOS target with placeholder app, both targets build"
```
