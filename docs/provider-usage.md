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
