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
- Auto-updates: powered by [Sparkle](https://sparkle-project.org). Skillbox checks `https://mmurakaru.github.io/skillbox/appcast.xml` every 24 hours and prompts when a new signed release is available. Manual check via Settings → Updates → "Check for Updates…".

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

Releases are driven by [Changesets](https://github.com/changesets/changesets) + two GitHub Actions workflows. Day-to-day, the only thing a contributor does is **add a changeset to their PR**.

### Contributor flow

```sh
npm install   # one-time, pulls @changesets/cli into node_modules
npx changeset # interactive: pick patch/minor/major + write a summary
git add .changeset
```

Commit the resulting `.changeset/<random>.md` file alongside your PR.

### What happens after merge

1. PR merges to `main` with a changeset.
2. `.github/workflows/changesets.yml` opens a **"Version Packages"** PR that:
   - Bumps `package.json#version` according to the highest pending bump.
   - Propagates the new version into `Info.plist.template`'s `CFBundleShortVersionString` and increments `CFBundleVersion` via `scripts/sync-version.mjs`.
   - Regenerates `CHANGELOG.md` from the changeset summaries.
3. The maintainer merges the Version PR. Changesets tags the commit `vX.Y.Z`.
4. The tag push triggers `.github/workflows/release.yml`:
   - `make bundle` → `Skillbox.app`.
   - Sparkle-signs the zip with the `SPARKLE_ED_PRIVATE_KEY` repo secret.
   - `gh release create` uploads the signed zip.
   - `scripts/append-appcast.mjs` adds a new `<item>` to `docs/appcast.xml`.
   - Commits the updated appcast back to `main`.
5. GitHub Pages publishes the new appcast within ~30s.
6. Installed apps detect the new version on their next daily check.

Tags with a pre-release suffix (e.g. `v0.3.0-beta.1`) ship as GitHub pre-releases. Plain `vX.Y.Z` ships as stable.

### Local-only release (escape hatch)

`make bundle` still works for local one-off builds. See `SETUP.md` for the one-time keys-and-Pages setup before the automated flow can run.
