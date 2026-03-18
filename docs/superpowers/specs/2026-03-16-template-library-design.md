# Template Library — Design Spec

## Overview

Reusable email template library, per-account, integrated into the sidebar, compose view, and quick reply. Templates contain a name, subject, and HTML body.

## Data Model

```swift
struct EmailTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var subject: String
    var bodyHTML: String
    var createdAt: Date
    var updatedAt: Date
}
```

## Storage — TemplateStore

Singleton `TemplateStore: ObservableObject`. Per-account storage in UserDefaults, key `"com.serif.templates.{accountID}"`, JSON-encoded `[EmailTemplate]`.

### Interface

```swift
@MainActor
final class TemplateStore: ObservableObject {
    static let shared = TemplateStore()

    @Published var templates: [EmailTemplate] = []

    func load(accountID: String)
    func save(_ template: EmailTemplate, accountID: String)
    func delete(id: UUID, accountID: String)
    func deleteAccount(_ accountID: String)
}
```

- `load(accountID:)` — reads from UserDefaults, populates `templates`.
- `save(_:accountID:)` — upserts (insert or update by id), persists, updates `templates`.
- `delete(id:accountID:)` — removes by id, persists, updates `templates`.
- `deleteAccount(_:)` — removes UserDefaults key (called on account deletion).

Account switch calls `load(accountID:)` in `AppCoordinator.handleAccountChange`.

## Folder Enum

Add `case templates = "Templates"` to `Folder` in `Email.swift`, positioned after `.drafts`. Properties:

- `icon` → `"doc.text.fill"`
- `gmailLabelID` → `nil`
- `gmailQuery` → `nil`

## Sidebar

`.templates` renders as a standard `SidebarItemView` in `SidebarView.folderList`. No expand/collapse, no children. Positioned between Drafts and Attachments in the folder list iteration.

## Template List (Middle Column)

### TemplateListView

Displayed when `selectedFolder == .templates`. Receives `@ObservedObject templateStore: TemplateStore` and a `selectedTemplateID: Binding<UUID?>`.

Layout:
- Toolbar: title "Templates" + "+" button to create a new template.
- List of templates sorted by `updatedAt` descending.
- Each row: name (primary text), subject (secondary text), relative date.
- Selected state via `selectedTemplateID` binding.
- Empty state: illustration + "No templates yet" + create button.

### ContentView Integration

```swift
if coordinator.selectedFolder == .templates {
    TemplateListView(...)
} else {
    // existing email list
}
```

## Template Editor (Right Column)

### TemplateEditorView

Displayed when `selectedFolder == .templates && selectedTemplateID != nil`.

Layout:
- Name field (TextField, prominent).
- Subject field (TextField).
- Divider.
- `WebRichTextEditor` for bodyHTML.
- `FormattingToolbar` at the bottom.
- Toolbar: delete button.

Auto-save: debounced 1-second save via `TemplateStore.save()` on any field change.

### ContentView Integration

```swift
if coordinator.selectedFolder == .templates {
    if let templateID = coordinator.selectedTemplateID {
        TemplateEditorView(...)
    } else {
        // empty state placeholder
    }
} else {
    // existing detail pane
}
```

## Template Picker (Compose & Reply)

### TemplatePickerView

A popover view listing templates for the current account. Used in both ComposeView and ReplyBarView.

Layout:
- Search field to filter by name.
- Scrollable list of templates (name + subject preview).
- Click selects and dismisses.

### ComposeView Integration

Two new toolbar buttons:
1. **"Use Template"** — opens TemplatePickerView popover. On selection: replaces `subject` and `bodyHTML`, calls `editorState.setHTML()`.
2. **"Save as Template"** — alert with name field. On confirm: creates `EmailTemplate` from current `subject` + `bodyHTML`, saves via `TemplateStore`.

### ReplyBarView Integration

One button in the reply toolbar area:
- **Template icon** — opens TemplatePickerView popover. On selection: replaces `replyHTML`, calls `editorState.setHTML()`.

## AppCoordinator Changes

New state:
```swift
@Published var selectedTemplateID: UUID?
```

In `handleFolderChange(_:)`:
- If folder is `.templates`: call `templateStore.load(accountID:)`, clear `selectedTemplateID`.
- If folder is not `.templates`: clear `selectedTemplateID`.

In `handleAccountChange(_:)`:
- Call `templateStore.load(accountID: id)` alongside existing parallel loads.

## Files

| Action | Path | Purpose |
|--------|------|---------|
| Create | `Serif/Models/EmailTemplate.swift` | Data model |
| Create | `Serif/Services/TemplateStore.swift` | Persistence singleton |
| Create | `Serif/Views/Templates/TemplateListView.swift` | List view (middle column) |
| Create | `Serif/Views/Templates/TemplateEditorView.swift` | Editor view (right column) |
| Create | `Serif/Views/Compose/TemplatePickerView.swift` | Popover for selecting templates |
| Modify | `Serif/Models/Email.swift` | Add `.templates` to Folder enum |
| Modify | `Serif/Views/Sidebar/SidebarView.swift` | Render templates folder |
| Modify | `Serif/ViewModels/AppCoordinator.swift` | Selection state + account switch |
| Modify | `Serif/ContentView.swift` | Route to template list/editor |
| Modify | `Serif/Views/Compose/ComposeView.swift` | Template picker + save-as buttons |
| Modify | `Serif/Views/EmailDetail/ReplyBarView.swift` | Template picker button |

## Out of Scope

- Template categories/folders.
- Template sharing across accounts.
- Template variables/placeholders.
- Import/export.
