# macOS Development Patterns

## Contents

- [Liquid Glass and macOS 26](#liquid-glass-and-macos-26) — design system, opt-out, accessibility
- [Window management](#window-management) — scene types, restoration, data-driven windows
- [Menu system](#menu-system) — required menus, shortcuts, MenuBarExtra
- [SwiftUI for macOS](#swiftui-for-macos) — NavigationSplitView, Table, Form differences
- [AppKit-SwiftUI interop](#appkit-swiftui-interop) — NSViewRepresentable rules, NSHostingView
- [File system](#file-system) — NSFileCoordinator, security-scoped bookmarks
- [Sandboxing and entitlements](#sandboxing-and-entitlements) — hardened runtime, privacy manifests
- [HIG conventions](#hig-conventions) — button placement, sheet vs modal, iOS port anti-patterns

---

## Liquid Glass and macOS 26

Recompiling with Xcode 26 gives SwiftUI apps the new Liquid Glass design automatically.
`NavigationSplitView` becomes a glass sidebar, `TabView` gets liquid tab bar, toolbars get glass
appearance. One-year grace period to adapt. Temporary opt-out:

```swift
defaults write com.apple.YourApp com.apple.SwiftUI.DisableSolarium -bool YES
```

**App icons must be squircles** — non-compliant icons get placed inside a grey squircle. Always test
with **Reduced Transparency**, **Increased Contrast**, and **Reduced Motion** accessibility
settings.

Glass effects in SwiftUI:

```swift
MyView()
    .glassEffect(.regular, in: .rect(cornerRadius: 12))
```

## Window management

### Scene types

| Scene Type      | Purpose                 | Instance Count               |
| --------------- | ----------------------- | ---------------------------- |
| `WindowGroup`   | Main app windows        | Multiple (Cmd+N creates new) |
| `Window(id:)`   | Single-instance utility | One per ID                   |
| `DocumentGroup` | Document-based apps     | One per document             |
| `Settings`      | Preferences window      | Singleton                    |
| `MenuBarExtra`  | Menu bar item           | Singleton                    |

**Most common mistake:** Using `WindowGroup` when you want a singleton. Use `Window(id:)` instead.

### Window restoration

SwiftUI persists position of only a single window per group. Position lost when closing with Cmd+W
(vs quitting with Cmd+Q). Disable automatic window tabbing unless specifically wanted:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}
```

**Data-driven windows enforce single-instance-per-value** — opening the same item ID again brings
the existing window to front.

## Menu system

### Required menus

Every Mac app MUST include at minimum: App, File, Edit, View, Window, Help. Omit File only if not
document-based. App-specific menus go between Edit and View, or between View and Window.

### Keyboard shortcuts that must work

| Shortcut            | Action              | Notes                           |
| ------------------- | ------------------- | ------------------------------- |
| Cmd+Q               | Quit                | Never override                  |
| Cmd+W               | Close Window        | Never override                  |
| Cmd+N               | New Window/Document | Required for multi-window apps  |
| Cmd+,               | Settings            | Auto-wired by Settings scene    |
| Cmd+Z / Shift+Cmd+Z | Undo/Redo           | Responder chain handles routing |

### MenuBarExtra for status bar apps

For menu-bar-only apps (with `LSUIElement` set), provide a Quit button somewhere in the UI. `NSMenu`
in `NSStatusItem` outperforms `NSPopover` — instant display, native click-away dismissal.

## SwiftUI for macOS

### NavigationSplitView gotchas

- `.prominentDetail` does NOT work on macOS — only iPadOS/iOS
- Safe area insets bug can add mysterious vertical spacing. Workaround: `.ignoresSafeArea(.all)` on
  content column
- Column visibility survives app restart — provide menu item to toggle sidebar
- Programmatic sidebar toggle requires fragile workaround:

```swift
NSApp.keyWindow?.firstResponder?.tryToPerform(
    #selector(NSSplitViewController.toggleSidebar(_:)), with: nil
)
```

### Table sorting is NOT automatic

Table only updates sort indicators — you must re-sort data yourself:

```swift
Table(users, selection: $selectedUsers, sortOrder: $sortOrder) {
    TableColumn("Name", value: \.name)
    TableColumn("Score", value: \.score) { Text(String($0.score)) }
}
.onChange(of: sortOrder) { _, newOrder in
    users.sort(using: newOrder)
}
```

Sortable key paths only support `String` and `Int`. For other types, provide custom
`SortComparator`.

### Form styling

macOS defaults to `ColumnsFormStyle` (two-column grid). For Settings, use `.formStyle(.grouped)` but
add `.padding(.top, -20)` to fix unwanted top padding.

## AppKit-SwiftUI interop

### NSViewRepresentable golden rules

**Rule 1 — When updating NSView from SwiftUI state**: Check EVERY property, but ONLY update the
NSView property if it actually changed.

**Rule 2 — When updating SwiftUI state from NSView changes**: Updates MUST happen asynchronously via
`DispatchQueue.main.async`.

```swift
// ❌ Causes infinite loops
func textViewDidChangeSelection(_ notification: Notification) {
    parent.selection = textView.selectedRange()  // Synchronous!
}

// ✅ Async state changes
func textViewDidChangeSelection(_ notification: Notification) {
    let range = textView.selectedRange()
    DispatchQueue.main.async {
        self.parent.selection = range
    }
}
```

### NSHostingView sizing

Remove `.intrinsicContentSize` from `sizingOptions` to allow `Spacer()` to expand:

```swift
let hostingView = NSHostingView(rootView: MySwiftUIView())
hostingView.sizingOptions = [.minSize, .maxSize]  // Omit .intrinsicContentSize
```

### When to use which

| SwiftUI                        | AppKit                          |
| ------------------------------ | ------------------------------- |
| Settings windows, simple forms | NSOutlineView with complex drag |
| Charts, new features           | NSTableView with 100k+ rows     |
| Most views and state           | Fine-grained window control     |

Practical consensus: **70% SwiftUI, 30% AppKit**. Mixing has negligible overhead (<1%).

## File system

### NSFileCoordinator self-coordination trap

When initialized with `NSFileCoordinator(filePresenter: self)`, coordination will NOT block against
other claims made by coordinators with the same presenter. Pass `nil` for mutual exclusion:

```swift
// ❌ Won't coordinate writes between threads using same presenter
let coordinator = NSFileCoordinator(filePresenter: self)

// ✅ Pass nil for mutual exclusion within same process
let coordinator = NSFileCoordinator(filePresenter: nil)
```

Don't hold coordinator instances — instantiate per-operation.

### Security-scoped bookmarks

MUST use the **resolved URL**, not original. Failing to call `stopAccessingSecurityScopedResource()`
leaks kernel resources. Calls are NOT nested — one stop cancels all starts:

```swift
var isStale = false
let resolvedURL = try URL(
    resolvingBookmarkData: bookmarkData,
    options: .withSecurityScope,
    relativeTo: nil,
    bookmarkDataIsStale: &isStale
)
guard resolvedURL.startAccessingSecurityScopedResource() else { return }
defer { resolvedURL.stopAccessingSecurityScopedResource() }
```

Bookmarks cannot be shared between app and extension via app groups (by design).

## Sandboxing and entitlements

### Never use --deep when code signing

```bash
# ❌ Strips entitlements, signs everything identically
codesign --force --deep --options runtime --sign "Dev ID..." MyApp.app

# ✅ Sign components individually from inside out
codesign --force --options runtime --entitlements helper.entitlements \
    --sign "Dev ID..." MyApp.app/Contents/Library/LoginItems/Helper.app
codesign --force --options runtime --entitlements app.entitlements \
    --sign "Dev ID..." MyApp.app
```

### Privacy manifests — now mandatory

Apps without privacy manifests for required-reason APIs are rejected. Common rejection cause:
`UserDefaults`, `FileManager` timestamp APIs, or `ProcessInfo.systemUptime` without declaring
required reason in `PrivacyInfo.xcprivacy`.

## HIG conventions

### Button placement

Rightmost button is the action (Save, Delete, Send). Second from right is Cancel. Escape triggers
Cancel. Buttons should be **verbs**, never "Yes"/"No":

```text
[Don't Save]          [Cancel]      [Save]
 leftmost              always         rightmost
 (optional)            second         (action)
                       from right
```

### iOS port anti-patterns

| ❌ iOS Pattern            | ✅ macOS Pattern                  |
| ------------------------- | --------------------------------- |
| Hamburger menu            | Menu bar                          |
| Bottom tab bar            | Sidebar + toolbar                 |
| Large 44pt+ touch targets | Compact 22-28pt controls          |
| Floating action buttons   | Toolbar or inline buttons         |
| Custom window chrome      | Standard title bar/traffic lights |
| Single-window only        | Support Cmd+N                     |

### Settings window rules

- Use `Form` with `.formStyle(.grouped)` and `Section`
- Not translucent — opaque backgrounds
- Minimize/maximize buttons disabled but not removed
- "General" tab uses `gearshape`, "Advanced" uses `gearshape.2`
- Should NOT close on Escape (Escape is for transient UI)
