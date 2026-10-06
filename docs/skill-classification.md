# Skill classification and navigation

This enhancement adds explicit Jev classification to Skillbox and replaces the top tabs with an icon sidebar. All changes, including dependency updates, ship in one PR.

## Acceptance checklist

- [ ] Settings can save and remove a TypeSafe API key in macOS Keychain.
- [ ] A Classify button processes all installed skills, independently of search and filters.
- [ ] Classification assigns multiple subject categories and one primary activity.
- [ ] Category and Activity filters combine with text search and offer an Unclassified option.
- [ ] Results persist locally across launches. Changed skills need classification again.
- [ ] Unchanged results are reused, with an explicit action to reclassify all skills.
- [ ] Classification shows progress, supports cancellation, and reports failures without losing successful results.
- [ ] Navigation uses a left icon sidebar: package, brain, bolt, lock. Existing shortcuts remain available.
- [ ] Settings, visible item count, and Quit move into the sidebar. Insights and AGENTS.md move into Settings.
- [ ] Refresh is removed; event-driven watching detects nested changes, atomic saves, missing roots, and linked skills without polling.
- [ ] The + button installs remote skills. Local creation and the optional skill-name input and CLI argument are removed.
- [ ] Install progress uses readable statuses and installed names, with bounded errors and no raw process dump.
- [ ] A download fixture verifies installed files, provenance, mounts, and user-facing results. A render harness creates installation previews.
- [ ] All direct app and release-tool dependencies use their latest stable versions at implementation time.
- [ ] Build and tests pass, code review is complete, and one PR is ready with green CI.

Categories: Engineering, Productivity, Design, Writing, Research, Other. Activities: Planning, Building, Debugging, Reviewing, Researching, Writing, Learning, Setup, Other.

The initial category probability threshold is 0.8, and the activity confidence threshold is 0.6. These are conservative starting values, not measured accuracy guarantees. Uncertain labels remain unclassified. Classification sends SKILL.md contents to TypeSafe only when requested.

Sources: [Matt Pocock's collection](https://github.com/mattpocock/skills#reference), [TypeSafe API](https://docs.typesafe.ai/api), [Noul](https://docs.typesafe.ai/primitives/noul), [Choice](https://docs.typesafe.ai/primitives/choice).
