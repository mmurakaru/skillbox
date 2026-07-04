# Changesets

This directory holds [Changesets](https://github.com/changesets/changesets) - markdown files describing what changed in each release.

## How to add a changeset

```sh
npx changeset
```

The CLI will ask:

1. **Which packages are bumped?** Just `skillbox` (one virtual package).
2. **What kind of bump?** `patch` / `minor` / `major`.
3. **Summary** - a short user-facing sentence. This lands in `CHANGELOG.md` verbatim.

The command writes a randomly-named `.md` file in this directory. Commit it as part of your PR.

## What happens after merge

The `changesets` GitHub Action sees the new `.changeset/*.md` files on `main` and opens a "Version Packages" PR that:

- Bumps `package.json#version` according to the highest pending bump type
- Runs `scripts/sync-version.mjs` to propagate the new version into `Sources/Skillbox/Resources/Info.plist.template` (`CFBundleShortVersionString`) and increment `CFBundleVersion`
- Regenerates `CHANGELOG.md` from the changeset summaries
- Deletes the consumed `.changeset/*.md` files

When that PR is merged, the same action tags the new commit `vX.Y.Z`, which triggers `.github/workflows/release.yml` to build, Sparkle-sign, and publish the release + appcast.

## Why we have a `package.json` for a Swift app

Changesets is npm-native, and the official `changesets/action` GitHub Action expects a `package.json`. We don't publish to npm (`"access": "restricted"`). The Node devDependency lets us reuse the canonical changesets workflow rather than reinvent it in Swift.
