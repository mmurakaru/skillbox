# Skill classification and navigation

This enhancement adds automatic Jev classification to Skillbox and replaces the top tabs with an icon sidebar. All changes, including dependency updates, ship in one PR.

## Acceptance checklist

- [x] Settings can save and remove a TypeSafe API key in macOS Keychain.
- [x] Classification automatically processes new or changed skills on launch and when added, independently of search and filters.
- [x] Classification assigns multiple subject categories and one primary activity.
- [x] Category and Activity filters combine with text search and offer an Unclassified option.
- [x] Results persist locally across launches. Changed skills need classification again.
- [x] Unchanged results are reused; Settings provides a Retry classification action.
- [x] Classification shows progress, supports cancellation, and reports failures without losing successful results.
- [x] Rows omit repeated section icons; Env retains its enable switch.
- [x] Classification controls and status live only in Settings; the skill list contains filters.
- [x] Navigation uses a left icon sidebar: package, brain, bolt, lock. Existing shortcuts remain available.
- [x] Settings, visible item count, and Quit move into the sidebar. Insights and AGENTS.md move into Settings.
- [x] Memory, Hooks, and Env headers omit redundant folder/settings-file buttons and their actions.
- [x] Refresh is removed; event-driven watching detects nested changes, atomic saves, missing roots, and linked skills without polling.
- [x] The + button installs remote skills. Local creation and the optional skill-name input and CLI argument are removed.
- [x] Install progress uses readable statuses and installed names, with bounded errors and no raw process dump.
- [x] A download fixture verifies installed files, provenance, mounts, and user-facing results. A render harness creates installation previews.
- [x] All direct app and release-tool dependencies use their latest stable versions at implementation time.
- [ ] Build and tests pass, code review is complete, and one PR is ready with green CI.

Categories: Engineering, Productivity, Design, Writing, Research, Other. Activities: Planning, Building, Debugging, Reviewing, Researching, Writing, Learning, Setup, Other.

The initial category probability threshold is 0.8, and the activity confidence threshold is 0.6. These are conservative starting values, not measured accuracy guarantees. Uncertain labels remain unclassified. With a saved API key, classification sends new or changed SKILL.md contents to TypeSafe automatically. Failed attempts are not repeated for unchanged files until retried in Settings.

Sources: [Matt Pocock's collection](https://github.com/mattpocock/skills#reference), [TypeSafe API](https://docs.typesafe.ai/api), [Noul](https://docs.typesafe.ai/primitives/noul), [Choice](https://docs.typesafe.ai/primitives/choice).
