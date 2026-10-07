# skillbox

## 0.4.1

### Patch Changes

- [`121abd8`](https://github.com/mmurakaru/skillbox/commit/121abd82dfb49998d23c63cab68af95f7a1ab79f) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Publish source releases automatically on main, without a manual version PR or tag. Keep binary releases optional and simplify source installation instructions.

## 0.4.0

### Minor Changes

- [#10](https://github.com/mmurakaru/skillbox/pull/10) [`a5b2ba1`](https://github.com/mmurakaru/skillbox/commit/a5b2ba1dca40f1e9f6dec64a91525a11e54cfd54) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Add automatic Jev skill classification with a TypeSafe API key in Settings, cached category and activity filters, and an icon sidebar for navigation. Update app and release-tool dependencies to their latest stable versions.
  
  Simplify remote installation with stable progress indicators, fix GUI subprocess launching, and publish ad-hoc signed releases when update signing is not configured.

## 0.3.2

### Patch Changes

- [#8](https://github.com/mmurakaru/skillbox/pull/8) [`047c35d`](https://github.com/mmurakaru/skillbox/commit/047c35d273561a414cea57bb0d82b529506d1082) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Prefer Zed when opening AGENTS.md and skill folders.

## 0.3.1

### Patch Changes

- [#6](https://github.com/mmurakaru/skillbox/pull/6) [`a3ebc07`](https://github.com/mmurakaru/skillbox/commit/a3ebc07a8435d78bdccc685acbcdad5c84bec576) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Open the cross-harness `~/AGENTS.md` instruction file from the footer and generate Claude Insights through a background session compatible with current Claude Code releases.

## 0.3.0

### Minor Changes

- [#2](https://github.com/mmurakaru/skillbox/pull/2) [`691c510`](https://github.com/mmurakaru/skillbox/commit/691c510521453b5cd4fd291100977ce42fbffadf) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Move Skillbox's default skills source of truth to `~/.agents/skills` and maintain `~/.claude/skills` as a Claude Code symlink mount.
