# Provider usage overview

## Implementation checklist

- [x] Add a Usage tab with stacked Codex, Grok, and Claude Code cards.
- [x] Keep the menu bar window at the same size across tabs.
- [x] Bundle local white provider marks with attribution.
- [x] Read provider usage from existing CLI sign-ins.
- [x] Show the connected account email and reported plan.
- [x] Keep quota periods, reset dates, and credit units specific to each provider.
- [x] Refresh live usage every five minutes and provide a per-card Refresh button.
- [x] Preserve manual snapshots until an explicit live refresh succeeds.
- [x] Remove dashboard links and explanatory card paragraphs.
- [x] Open snapshot editors in independent windows so menu bar dismissal does not discard edits.
- [x] Prevent automatic credential reads from showing Keychain permission dialogs.
- [x] Cover parsers, account identity, persistence, scheduling, and credential interaction with automated tests.
- [x] Verify native mouse interaction through the isolated desktop UI harness.

## Data boundaries

Provider credentials remain in provider-owned credential storage and never enter snapshots, tests, logs, or release artifacts. Tests use fictional accounts. Price and renewal date are manual fields when the provider connection does not report them. Usage reset dates do not imply subscription renewal dates.

The native UI harness uses synthetic data and isolated persistence. Its desktop interactions require a logged-in macOS session with Accessibility and Automation permissions; unit tests cover refresh scheduling independently.

## Release process

Merge the minor changeset through a reviewed PR. The main-branch workflow versions, tags, and publishes the source release. Build that version with `make install`, which ad-hoc signs and copies the app to /Applications without an Apple Developer account.

## Provider connections

Open the Usage tab with ⌘5 to see stacked Codex, Grok, and Claude Code cards. Live cards refresh every five minutes, including while the panel is closed. Each card has a **Refresh** text button; explicitly refreshing a manual card resumes live data on success. Snapshot editors open in regular windows and keep unsaved edits when the menu bar panel loses focus. All bars show **percent used**; each provider keeps its own quota windows, reset times, credit units, and snapshot timestamp.

Codex reads the existing CLI sign-in from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`. Claude Code uses the installed CLI’s read-only `auth status` and `/usage` commands, with hooks, tools, MCP startup, and session persistence disabled for the probe. The CLI handles its own credentials; Skillbox does not request its Keychain password. Identity is checked before and after the quota read; an account switch discards that result. If no CLI is installed, the reader can use `$CLAUDE_CONFIG_DIR/.credentials.json` or the default credentials file. Foreign Keychain access in that fallback requires an explicit **Connect Claude Code** action and lasts only for the app session. Automatic refresh never reads that foreign Keychain entry. Skillbox never rotates provider credentials. Reauthenticate in the provider CLI if access expires.

Grok reads the consumer CLI sign-in from `$GROK_HOME/auth.json` or `~/.grok/auth.json`. Use **Connect Grok** for the official CLI installation guide, then run `grok login` before refreshing; a grok.com browser session is separate. Add or edit a snapshot from the provider dashboard to record percentages, reset times, credits, auto-reload or extra usage, and reset passes. Manual snapshots persist locally and stay manual until an explicit **Refresh** succeeds for a supported provider. Failed refreshes retain the last successful snapshot. Live readers show the connected email and plan when available, quota windows, Codex and Grok credits, and Claude model-specific weekly windows. The Claude OAuth fallback also reports monthly extra spending. Claude automatically reads the currently active CLI account on refresh. Exact subscription price and renewal date are not returned by these usage connections. Record those fields manually from the billing page; usage reset dates are not subscription renewal dates.

Provider marks are bundled from [Lobe Icons](https://github.com/lobehub/lobe-icons), with source links and the MIT license in `Sources/Skillbox/Resources/ProviderLogos`.

The read-only endpoint formats follow the provider integrations documented by [CodexBar for Codex](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md) and [Claude](https://github.com/steipete/CodexBar/blob/main/docs/claude.md).

## Native Usage UI checks

Run `make test-ui` on a logged-in macOS desktop. The harness compiles the production Usage views into a separate menu bar app with synthetic provider data and isolated persistence. It never accesses accounts, Keychain, or the network. macOS must allow the invoking terminal to automate System Events and use Accessibility.

The driver checks quota/plan labels, periodic and explicit refresh, editor activation, real mouse clicks and typing in fields, native reset/picker controls, save/cancel, and preserving manual snapshots. It fails with a nonzero status and saves screenshots, app output, and `results.json` under `.build/usage-ui`. Run `swift test` for quota parsing, account switching, refresh scheduling/cancellation, persistence, and the existing feature regression suite.

TypeSafe reads its saved API key at startup without allowing Keychain dialogs. Already authorized builds classify automatically. If rebuilding changes Keychain trust, classification waits for **Unlock saved key** in Settings; the saved key stays in Keychain. The reader temporarily disables legacy Keychain interaction as well as per-request UI, then restores the prior policy (the modern flags alone do not suppress file-based Keychain ACL prompts; see Chromium FB16959400).
