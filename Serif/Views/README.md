# Views

SwiftUI views. UI presentation only — no business logic.

## Guidelines

- **No business logic in views.** Views read state from ViewModels and call callbacks. They do not:
  - Call Services or APIs directly
  - Perform data transformations beyond simple formatting
  - Contain persistence logic
- **No hardcoded colors.** Always use `@Environment(\.theme)` for theming.
- **Callbacks over direct ViewModel access.** Views receive `onDelete`, `onArchive`, etc. as closures. Only top-level views (ContentView) wire these to ViewModels.
- **Small, composable views.** Extract reusable components into `Common/`. One concern per file.
- **Animations belong in views**, not in ViewModels or Services.

## Subfolders

### `Sidebar/`
Left column — folder navigation, account switcher, labels.

### `EmailList/`
Middle column — email rows, swipe actions, search. `SwipeableEmailRow` handles gesture state locally via `SwipeRowState`.

### `EmailDetail/`
Right column — thread view, HTML rendering (`HTMLEmailView` via WKWebView), attachments, reply bar.

### `Compose/`
Email composer — `ComposeView` for the form, `AutocompleteTextField` for contact suggestions in To/Cc/Bcc.

### `Attachments/`
Attachment gallery view.

### `Onboarding/`
Sign-in / welcome screen.

### `Common/`
Shared reusable components:
| File | Role |
|------|------|
| `AvatarView` | Circular avatar with initials fallback |
| `SearchBarView` | Search input |
| `LabelChipView` | Colored label pill |
| `ThemePickerView` | Theme grid + color customization |
| `SlidePanel` | Animated side panel |
| `FormattingToolbar` | Rich text toolbar for compose |
| `RichTextEditor` | NSTextView wrapper for compose |
| `UndoToastView` | Undo toast + offline toast |
| `DebugMenuView` | API logs, cache controls |
| `ShortcutsHelpView` | Keyboard shortcuts reference |
| `AccountsSettingsView` | Account management settings |
