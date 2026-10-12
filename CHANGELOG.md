# skillbox

## 0.9.3

### Patch Changes

- [#33](https://github.com/mmurakaru/skillbox/pull/33) [`f563482`](https://github.com/mmurakaru/skillbox/commit/f5634829f2b51c3cb3b762426720d052667a3ba7) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Shorten the README to one line per tab and move provider connection details to the provider usage doc.

## 0.9.2

### Patch Changes

- [#32](https://github.com/mmurakaru/skillbox/pull/32) [`14fadb2`](https://github.com/mmurakaru/skillbox/commit/14fadb2c9e2e237c3c9bb024f448f410768364f2) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Open the add env var and MCP server connection forms in regular windows, so clicking them no longer closes the menu bar panel.

## 0.9.1

### Patch Changes

- [#29](https://github.com/mmurakaru/skillbox/pull/29) [`edb4f09`](https://github.com/mmurakaru/skillbox/commit/edb4f090f6b9a43b892c52631e66ff7207df9608) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Show the name of every icon-only action in the menu bar panel on hover, and keep scope and Keychain badges on one line so variable names have more room.

- [#27](https://github.com/mmurakaru/skillbox/pull/27) [`d5e90a6`](https://github.com/mmurakaru/skillbox/commit/d5e90a60d4cfb1c0bc164f432f162529ccb2cf98) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Add `make lint` and `make format` with swift-format, SwiftLint type-safety rules, and blank-line padding, and run them in CI.

## 0.9.0

### Minor Changes

- [#25](https://github.com/mmurakaru/skillbox/pull/25) [`e8abc86`](https://github.com/mmurakaru/skillbox/commit/e8abc86f5be910d1a934dd5f3c25090082a0b74e) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Add an Explore tab that searches the Hugging Face Hub without a token, filters by lab, format, size, and sort, keeps the last results offline, marks models already on this Mac, and copies an Ollama or Hugging Face CLI download command.

## 0.8.0

### Minor Changes

- [#21](https://github.com/mmurakaru/skillbox/pull/21) [`f2972f4`](https://github.com/mmurakaru/skillbox/commit/f2972f433d2831fbf4b68a23d8cd1749f14f3825) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Add a Models tab listing the AI models stored on this Mac from Ollama, the Hugging Face cache, LM Studio, OpenWhispr, Application Support model folders, and custom folders, with on-disk size, an estimated RAM fit badge, duplicate detection, and reveal in Finder. Choose scan sources under Local models in Settings.

- [#23](https://github.com/mmurakaru/skillbox/pull/23) [`f48c12f`](https://github.com/mmurakaru/skillbox/commit/f48c12fe2a69502a0836adb6b3ad3015e215c180) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Show which local models are loaded in memory while the Models tab is visible, unload Ollama models and dedicated llama-server processes after confirmation, and move flat weight files and Hugging Face cache repos to the Trash.

## 0.7.0

### Minor Changes

- [#30](https://github.com/mmurakaru/skillbox/pull/30) [`bf5bbe8`](https://github.com/mmurakaru/skillbox/commit/bf5bbe82c7f81f814b9ecf0141c8454579330d8f) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Store new Env tab secrets in the login Keychain instead of settings.json, list them with masked values, and move existing plaintext secrets into the Keychain with a verified copy before a separately confirmed removal of the plaintext value.

- [#26](https://github.com/mmurakaru/skillbox/pull/26) [`95d2378`](https://github.com/mmurakaru/skillbox/commit/95d23784085c4eadb317adbf0a5423dd960e36ba) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Connect a Keychain secret to a user-scope Claude Code HTTP MCP server through a headers helper. Skillbox verifies the helper before and after an atomic, lock-respecting config update, keeps static headers as a fallback, and removes a static header only as a separate confirmed step.

## 0.6.0

### Minor Changes

- [#20](https://github.com/mmurakaru/skillbox/pull/20) [`ca6329e`](https://github.com/mmurakaru/skillbox/commit/ca6329ec099b5127a295fdc7dfe16a7df5c3b5d9) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Recognize secrets in the Env tab by name or an explicit mark. Mask their values with reveal and copy actions, use secure entry, refuse the shared project scope, and remove a disabled secret's value instead of stashing it in plaintext.

### Patch Changes

- [#22](https://github.com/mmurakaru/skillbox/pull/22) [`3bc05e5`](https://github.com/mmurakaru/skillbox/commit/3bc05e5eccd462e73187ceac65304c58f897c4ff) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Describe Skillbox as a toolbox for AI coding agents, and add a header to every sidebar tab that names the harness it applies to.

## 0.5.0

### Minor Changes

- [#12](https://github.com/mmurakaru/skillbox/pull/12) [`950aeb0`](https://github.com/mmurakaru/skillbox/commit/950aeb075f9dd2f529295e4ef7b7eb68d258855e) Thanks [@mmurakaru](https://github.com/mmurakaru)! - Add a Usage tab with live Codex, Grok, and Claude Code quota cards, account and plan labels, periodic refresh, and persistent manual snapshots. Open snapshot editors in independent windows and suppress automatic Keychain permission dialogs.

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
