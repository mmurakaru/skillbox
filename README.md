# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar app for managing claude skills (`~/.claude/skills/`) and auto-memory (`~/.claude/projects/*/memory/`).

See [PRD.md](PRD.md) for the spec.

## Features

- Skills tab: browse, search, open, and trash skills under `~/.claude/skills/`.
- Memory tab: browse Claude auto-memory entries (`~/.claude/projects/<project>/memory/*.md`) per project, with type badges and edit/delete.
- Toggle tabs with ⌘1 / ⌘2.

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

- **Models** - `Skill`, `Memory`, and `FileBackedItemStore<Item>` (the generic store that powers both `SkillStore` and `MemoryStore`).
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
