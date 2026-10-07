# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar app for Claude Code: skills, auto-memory, hooks, and env vars.

See [PRD.md](PRD.md) for the spec.

## Skill storage model

Skillbox treats `~/.agents/skills` as the canonical skill source of truth. Claude Code still reads `~/.claude/skills`, so Skillbox maintains that directory as a compatibility mount of symlinks:

```txt
~/.agents/skills/<skill>/...      # real files
~/.claude/skills/<skill>          # symlink -> ~/.agents/skills/<skill>
```

Installs, deletes, remote sync, and backup tooling operate on `.agents`; `.claude/skills` is the Claude-facing mount.

## Install

Grab the latest `Skillbox-vX.Y.Z.zip` from [Releases](https://github.com/mmurakaru/skillbox/releases), unzip, and drag `Skillbox.app` to `/Applications`.

The app is ad-hoc signed, not notarized. On first launch macOS Gatekeeper will refuse to open it. Either right-click → Open and confirm, or strip the quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/Skillbox.app
```

## Build & run

Requires macOS 26+, Swift 6.2 toolchain (Command Line Tools is enough).

```sh
make bundle    # produces ./Skillbox.app, ad-hoc signed
make run       # builds and opens
make install   # copies to /Applications
make clean
```

Run tests with `swift test`.

Render the installation progress UI for inspection with `SKILLBOX_RENDER_DIR=/tmp/skillbox-render swift test --filter SkillInstallTests/renderInstallProgressHarness`. This creates PNGs for downloading, installing, and completion states using the production SwiftUI view.

## Release

Releases are driven by [Changesets](https://github.com/changesets/changesets) + two GitHub Actions workflows.

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
3. The maintainer merges the Version PR and pushes a `vX.Y.Z` tag at that merged commit.
4. The tag push triggers `.github/workflows/release.yml`:
   - `make bundle` → `Skillbox.app`.
   - Sparkle-signs the zip when the `SPARKLE_ED_PRIVATE_KEY` repo secret is configured. Without it, publishes the ad-hoc signed zip for manual installation.
   - `gh release create` uploads the signed zip.
   - For Sparkle-signed updates, `scripts/append-appcast.mjs` adds a new `<item>` to `docs/appcast.xml`.
   - Commits the updated appcast back to `main`.
5. GitHub Pages publishes the new appcast within ~30s.
6. Installed apps detect the new version on their next daily check.

Tags with a pre-release suffix (e.g. `v0.3.0-beta.1`) ship as GitHub pre-releases. Plain `vX.Y.Z` ships as stable.

### Local-only release (escape hatch)

`make bundle` still works for local one-off builds. See `SETUP.md` for the one-time keys-and-Pages setup before the automated flow can run.
