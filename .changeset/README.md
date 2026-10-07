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

## Automatic releases

On pushes to `main`, `.github/workflows/release.yml` consumes pending changesets, updates the version and changelog, commits those changes, and publishes a tagged source release. No version PR or manual tag is required. Pushes without a version bump reuse the current release. Rerun the workflow to recover a failed release.

Binary releases are opt-in. See [SETUP.md](../SETUP.md) for signing and update configuration.

## Why a Swift app has package.json

Changesets uses `package.json` for versioning. Skillbox is private and never published to npm.
