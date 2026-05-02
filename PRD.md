# Skillbox - Product Requirements Document

> A native menu bar app for browsing, opening, and deleting Claude skills.

---

## 1. Overview

Skillbox is a lightweight, native macOS menu bar app for managing Claude skills installed at `~/.claude/skills/`. It provides a scrollable, searchable list of every user-installed skill with one-click actions to open the skill folder in your editor or move it to Trash.

**v1 ships macOS-only, personal-use, ad-hoc signed.** Cross-platform builds (Linux, Windows) are roadmap items captured in §14.

## 2. Problem

Managing Claude skills today means `cd ~/.claude/skills && ls`, then `code <name>` or `rm -rf <name>`. Power users with 30+ skills want a menu bar app that collapses that to one click and stays out of the way otherwise.

## 3. Goals

- **G1** - Single, always-accessible view of every user-installed skill.
- **G2** - One-click open of any skill folder in the user's preferred editor.
- **G3** - One-click delete (move to Trash) with inline confirmation.
- **G4** - Stay out of the way: menu bar app, no Dock icon.
- **G5** - Launch in <200ms, use <20MB RAM at idle.

## 4. Non-Goals

- Skill creation or editing within the app itself (delegate to editor).
- Plugin skill management - those are owned by `claude plugin` commands and live across versioned cache + marketplace dirs; deleting them would break installs. Out of scope for Skillbox.
- Syncing skills across machines.
- Cloud connectivity, accounts, marketplace.
- Modifying Claude's runtime behavior.

## 5. Target User

Developers who maintain user-level Claude skills on their Mac and want a fast menu bar app to browse, open, and prune them.

## 6. Skill Source

**Single root, configurable, default `~/.claude/skills/`.** A skill is any direct child folder containing a `SKILL.md` file with YAML frontmatter.

```
~/.claude/skills/
├── diagnose/
│   └── SKILL.md
├── frontend-ui-engineering/
│   └── SKILL.md
├── grill-me/
│   └── SKILL.md
└── ...
```

No nested categories, no multi-root scanning. The list is flat. Power users with skills elsewhere can change the root in Settings.

### Metadata Extraction

From each `SKILL.md`, Skillbox parses YAML frontmatter via Yams:

| Field         | Source                     | Use                        |
|---------------|----------------------------|----------------------------|
| `name`        | frontmatter `name:`        | Display name in list       |
| `description` | frontmatter `description:` | Subtitle + hover tooltip   |
| `path`        | Absolute folder path       | Open-in-editor target      |

`size` and `file_count` from earlier drafts are dropped from MVP - not displayed in the row layout.

## 7. Architecture

### 7.1 Platform & Toolkit

**v1 (this PRD):** macOS 14 Sonoma+, SwiftUI, Swift 6.

| Component        | Choice                          | Rationale                                    |
|------------------|---------------------------------|----------------------------------------------|
| Menu bar + popover | `MenuBarExtra(.window)`       | 2026-idiomatic, no AppKit shell needed       |
| Keyboard nav     | `.onKeyPress` (macOS 14+)       | Native SwiftUI, no NSEvent monitor           |
| Settings window  | SwiftUI `Settings { ... }` scene| Standard pattern, integrates with @AppStorage|
| Prefs storage    | `UserDefaults` via `@AppStorage`| Native, reactive, zero serialisation code   |
| YAML parsing     | Yams (SwiftPM)                  | Robust, handles quoted/multiline edge cases  |
| File watching    | `DispatchSource` on root FD     | ~15 lines, sufficient (rescan on event)      |
| Trash deletion   | `FileManager.trashItem(at:)`    | Canonical macOS API                          |
| Editor launch    | `Process.run` with detected CLI | code / cursor / zed / subl / nova / bbedit / mate |
| Launch at login  | `SMAppService` (macOS 13+)      | Modern replacement for SMLoginItemSetEnabled |
| Build            | Swift Package Manager + Makefile| No Xcode dependency, ad-hoc codesign         |

**v1.1+ roadmap:** Linux (GTK 4 / Rust), Windows (WinUI 3 or Rust). No cross-platform abstraction layer - separate native builds.

### 7.2 Component Diagram

```
┌─────────────────────────────────────────┐
│              Menu Bar Icon              │
│            (click to toggle)            │
└──────────────┬──────────────────────────┘
               │
┌──────────────▼──────────────────────────┐
│       MenuBarExtra(.window) Popover     │
│  ┌────────────────────────────────────┐ │
│  │  🔍 Search                         │ │
│  ├────────────────────────────────────┤ │
│  │  📦 diagnose                ✏️ 🗑️   │ │
│  │     Disciplined diagnosis...       │ │
│  │  📦 frontend-ui-engineering ✏️ 🗑️  │ │
│  │     Builds production-quality...   │ │
│  │  📦 grill-me                ✏️ 🗑️   │ │
│  │     Interview the user...          │ │
│  │  ... (scrollable)                  │ │
│  ├────────────────────────────────────┤ │
│  │  ⚙️ Settings   🔄 Refresh   38     │ │
│  └────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

### 7.3 Core Modules

| Module              | Responsibility                                                        |
|---------------------|-----------------------------------------------------------------------|
| `SkillScanner`      | Walks the configured root, finds direct children with `SKILL.md`, parses YAML via Yams, returns `[Skill]` |
| `SkillStore`        | `@Observable` cache of scanned skills + filtered view. Triggers rescan on watcher events and on popover open. |
| `DirectoryWatcher`  | `DispatchSource.makeFileSystemObjectSource` on the root dir FD, debounces events 200ms, calls onChange |
| `EditorDetector`    | One-shot probe of `$PATH` for known GUI editor CLIs                   |
| `EditorLauncher`    | Spawns the configured editor with skill folder or SKILL.md path       |
| `SkillDeleter`      | `FileManager.trashItem` wrapper                                       |

No `ConfigManager` - replaced by `@AppStorage`.

## 8. Features (MVP)

### 8.1 Skill List

- Flat, scrollable list (single root, no categorisation).
- Each row: skill name, single-line truncated description, edit icon, delete icon.
- Hover on row shows full description as tooltip (`.help()`).
- Footer shows total count.

Sections, collapsibility, badge counts, and category grouping are removed - they don't add value for a single flat root.

### 8.2 Search / Filter

- Auto-focused TextField at the top of the popover.
- Real-time filter on `localizedCaseInsensitiveContains` against name + description.
- Clears on popover close.
- ⌘F also focuses the search field.

### 8.3 Edit Action (✏️)

- Opens the skill in the configured editor.
- **Editor detection:** probe `$PATH` on first launch for `code`, `cursor`, `zed`, `subl`, `nova`, `bbedit`, `mate`. Default to first found. **`$EDITOR` is intentionally ignored** - it's typically a terminal editor (`vim`, `nano`) that breaks the "open folder" semantic.
- **Open target:** folder by default (full project context). Settings override switches to "SKILL.md only".
- User can supply a custom command in Settings.

### 8.4 Delete Action (🗑️)

- Two-stage inline confirm: clicking 🗑️ replaces the row content with a confirm strip ("Delete *diagnose*? → Trash" + Cancel/Delete buttons).
- Esc or Cancel restores normal row state.
- Confirm → `FileManager.trashItem(at:)` → row disappears (watcher will also fire).
- No system NSAlert (would dismiss the popover on focus loss).

### 8.5 Settings Panel

Native SwiftUI `Settings { ... }` scene. Fields:

- **Skills directory** - text field + "Browse..." button. Default `~/.claude/skills/`.
- **Editor** - dropdown of detected GUI editors + "Custom command" text field.
- **Open target** - radio: Folder / SKILL.md.
- **Launch at login** - toggle (uses `SMAppService`).

Removed from earlier draft: refresh interval (always live-watching), multiple roots.

### 8.6 File Watching

- `DispatchSource.makeFileSystemObjectSource` on the root dir's FD.
- Listens for `.write / .delete / .rename`.
- Debounced 200ms then triggers a full rescan.
- Detects skill add / remove / rename of direct children.
- Description-edit-inside-SKILL.md is *not* watched recursively - picked up at next popover open or manual refresh.

## 9. UX Specifications

### 9.1 Menu Bar Icon

- Custom 4-diamond zig-zag mark, source-of-truth at `Sources/Skillbox/Resources/AppIcon.svg`.
- Rendered programmatically via Core Graphics into an `NSImage` with `isTemplate = true` (see `Views/SkillboxIcon.swift`) so Cocoa auto-tints it for light/dark mode and active-state highlighting.
- 18pt tall, ~10.3pt wide (preserving the SVG's 428:748 portrait aspect).
- Single click toggles the popover (default `MenuBarExtra` behavior).

### 9.2 Popover Window

- Fixed width: 360pt. Max height: 480pt (List handles scroll beyond).
- Anchored below the menu bar icon (default `MenuBarExtra(.window)`).
- Dismisses on click-outside or Esc.
- Respects system dark/light mode automatically.
- No title bar.

### 9.3 Row Layout

```
┌──────────────────────────────────────────────┐
│ 📦  skill-name                    ✏️   🗑️    │
│     Short description text...                │
└──────────────────────────────────────────────┘
```

- Name: system font, semibold, 13pt.
- Description: system font, regular, 11pt, secondary color, single-line truncated.
- Icons: 14pt SF Symbols, secondary color, accent on hover.

## 10. Configuration

Stored in `UserDefaults` (`~/Library/Preferences/com.skillbox.app.plist`) via `@AppStorage`. No hand-editable config file in v1.

| Key                | Type    | Default                               |
|--------------------|---------|---------------------------------------|
| `skillsRootPath`   | String  | `~/.claude/skills`                    |
| `editorCommand`    | String  | first detected of `code,cursor,zed,subl,nova,bbedit,mate` |
| `openTarget`       | String  | `folder` (or `skill_md`)              |
| `launchAtLogin`    | Bool    | `false`                               |

Plain-text TOML at `~/.skillbox/config.toml` from earlier drafts is dropped - fights macOS conventions and adds a parser dep with no benefit.

## 11. Keyboard Shortcuts

All scoped to the open popover. **No global hotkey** (avoids Carbon HotKey complexity / KeyboardShortcuts dep in v1).

| Shortcut      | Action                                          |
|---------------|-------------------------------------------------|
| `↑ / ↓`       | Navigate skill list                             |
| `Return`      | Open selected skill in editor                   |
| `⌫` / `Delete`| Begin delete-confirm on selected (Esc cancels)  |
| `⌘ + F`       | Focus search field                              |
| `Esc`         | Cancel pending delete-confirm or dismiss popover|

## 12. Technical Constraints

- **No runtime dependencies**: no Node, no Python, no Docker. Single compiled binary inside `.app` bundle.
- **One SwiftPM dep**: Yams.
- **Ad-hoc codesigned** (`codesign --sign -`) for v1 personal use. Apple Developer ID / notarization is a v1.1 prerequisite for public distribution.
- **No network access**: fully offline, local filesystem only.
- **Binary size target**: <10MB.
- **Idle memory target**: <20MB.

## 13. Build & Distribution

**v1:** Swift Package Manager + Makefile produces a hand-bundled `Skillbox.app`, ad-hoc signed. Personal use only - no `.dmg`, no Homebrew cask.

```sh
make bundle    # builds and produces ./Skillbox.app
make install   # copies to /Applications
make run       # builds and opens
```

**v1.1+ roadmap:**

| Platform | Build System        | Artifact                  |
|----------|---------------------|---------------------------|
| macOS    | Same + Xcode notarize | `.dmg`, Homebrew cask  |
| Linux    | Cargo / Meson       | `.deb`, `.rpm`, AppImage  |
| Windows  | MSBuild / Cargo     | `.msix`, portable `.exe`  |

## 14. Future Considerations (Post-MVP)

- Linux (GTK 4 / Rust) and Windows (WinUI 3) builds.
- Public distribution: notarization, Homebrew cask.
- Plugin skills view (read-only): `~/.claude/plugins/.../skills/` with versioned cache deduplication. Not deletable from Skillbox.
- Global hotkey (⌘⇧K) via `KeyboardShortcuts` SPM library, with rebinder UI.
- Skill detail panel: expand a row to see full description, file tree, size, last modified.
- Drag-and-drop install: drop a `.skill` zip onto the menu bar icon to install.
- Duplicate-skill action for templating.
- Skill enable/disable toggle without deleting.
- Quick preview: render `SKILL.md` as Markdown.
- Bulk actions: multi-select for batch delete.
- Skill health check: validate frontmatter, flag missing fields.
- CLI companion: `skillbox list / open / rm`.

## 15. Success Metrics

| Metric                        | Target         |
|-------------------------------|----------------|
| Time to view all skills       | < 1 second     |
| Time to open skill in editor  | < 500ms        |
| Idle memory usage             | < 20MB         |
| Cold launch to interactive    | < 200ms        |
| Personal dogfood              | Daily use within 1 week |

