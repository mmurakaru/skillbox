# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar app for Claude Code: skills, auto-memory, hooks, and env vars.

See [PRD.md](PRD.md) for the spec.

## Features

- Skills tab: browse, search, open, and trash skills under `~/.claude/skills/`.
- Memory tab: browse Claude auto-memory entries (`~/.claude/projects/<project>/memory/*.md`) per project, with type badges and edit/delete.
- Hooks tab: browse hooks across `~/.claude/settings.json` and per-project `.claude/settings.json` / `settings.local.json`, with scope filter and edit/delete.
- Env tab: toggle individual env vars on/off without losing values (disabled vars stash in `~/.claude/skillbox-env-stash.json`); add new vars with autocomplete from a built-in catalog of well-known Claude Code env vars.
- Insights button (⌘I): runs `claude -p "/insights"` headlessly in the background, footer shows a spinner during the run, then opens the resulting HTML report (the skill's own `~/.claude/usage-data/report.html` if it produced one, otherwise a markdown-rendered fallback at `~/Library/Caches/Skillbox/`) in your default browser.
- Toggle tabs with ⌘1 / ⌘2 / ⌘3 / ⌘4.

## Install

Grab the latest `Skillbox-vX.Y.Z.zip` from [Releases](https://github.com/mmurakaru/skillbox/releases), unzip, and drag `Skillbox.app` to `/Applications`.

The app is ad-hoc signed, not notarized. On first launch macOS Gatekeeper will refuse to open it. Either right-click → Open and confirm, or strip the quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/Skillbox.app
```

## Build & run

Requires macOS 14+, Swift 6 toolchain (Command Line Tools is enough).

```sh
make bundle    # produces ./Skillbox.app, ad-hoc signed
make run       # builds and opens
make install   # copies to /Applications
make clean
```

Run tests with `swift test`.

## Architecture

The app has three layers under `Sources/Skillbox/`:

- **Models** - `Skill`, `Memory`, `Hook`, `EnvVar`. `FileBackedItemStore<Item>` is the generic single-root store powering `SkillStore` and `MemoryStore`; `HookStore` and `EnvVarStore` are bespoke because they aggregate from multiple `settings.json` files across scopes (and `EnvVarStore` also manages a private stash file for disabled values).
- **Services** - leaf utilities (`SkillScanner`, `SkillsCLI`, `SkillRegistry`, `EditorLauncher`, `DirectoryWatcher`) and one deep module: `RemoteSkillService` owns the install / update / check-for-updates lifecycle behind a small interface. `Ports.swift` defines the protocols views talk to so tests can substitute in-memory adapters.
- **Views** - SwiftUI views. `PopoverView` is the menu-bar entry point; sheets like `InstallFromURLSheet` and `RegistryView` route through a `SkillsTabRoute` enum.

For the quickest tour of what the app does, read `Tests/SkillboxTests/AppTourTest.swift`.

## Release

Bump `CFBundleShortVersionString` in `Sources/Skillbox/Resources/Info.plist.template`, then:

```sh
VERSION=v0.1.0-beta.2     # adjust
make clean bundle
ditto -c -k --keepParent Skillbox.app Skillbox-$VERSION.zip
git tag -a $VERSION -m "$VERSION"
git push origin $VERSION
gh release create $VERSION --prerelease --title "$VERSION" --notes "..." Skillbox-$VERSION.zip
rm -f Skillbox-$VERSION.zip
```

Drop `--prerelease` once you tag a stable `vX.Y.Z` (no `-beta`/`-rc` suffix).
