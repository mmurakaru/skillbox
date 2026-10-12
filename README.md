# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar toolbox for AI coding agents: shared skills, provider usage for Claude Code, Codex, and Grok, and Claude Code memory, hooks, and env vars.

See [PRD.md](PRD.md) for the spec.

## Skill storage model

Skillbox treats `~/.agents/skills` as the canonical skill source of truth. Claude Code still reads `~/.claude/skills`, so Skillbox maintains that directory as a compatibility mount of symlinks:

```txt
~/.agents/skills/<skill>/...      # real files
~/.claude/skills/<skill>          # symlink -> ~/.agents/skills/<skill>
```

Installs, deletes, remote sync, and backup tooling operate on `.agents`; `.claude/skills` is the Claude-facing mount.

## Build & run

Requires macOS 26+ and Swift 6.2. Command Line Tools is enough. Build from source:

```sh
git clone https://github.com/mmurakaru/skillbox.git
cd skillbox
make run       # builds and opens Skillbox.app
make install   # builds and copies to /Applications
```

`make bundle` creates an ad-hoc signed `Skillbox.app`. Run tests with `swift test`.

## Usage overview

Open the Usage tab with ⌘5 to see stacked Codex, Grok, and Claude Code cards. Live cards refresh every five minutes, including while the panel is closed. Each card has a **Refresh** text button; explicitly refreshing a manual card resumes live data on success. Snapshot editors open in regular windows and keep unsaved edits when the menu bar panel loses focus. All bars show **percent used**; each provider keeps its own quota windows, reset times, credit units, and snapshot timestamp.

Codex reads the existing CLI sign-in from `$CODEX_HOME/auth.json` or `~/.codex/auth.json`. Claude Code uses the installed CLI’s read-only `auth status` and `/usage` commands, with hooks, tools, MCP startup, and session persistence disabled for the probe. The CLI handles its own credentials; Skillbox does not request its Keychain password. Identity is checked before and after the quota read; an account switch discards that result. If no CLI is installed, the reader can use `$CLAUDE_CONFIG_DIR/.credentials.json` or the default credentials file. Foreign Keychain access in that fallback requires an explicit **Connect Claude Code** action and lasts only for the app session. Automatic refresh never reads that foreign Keychain entry. Skillbox never rotates provider credentials. Reauthenticate in the provider CLI if access expires.

Grok reads the consumer CLI sign-in from `$GROK_HOME/auth.json` or `~/.grok/auth.json`. Use **Connect Grok** for the official CLI installation guide, then run `grok login` before refreshing; a grok.com browser session is separate. Add or edit a snapshot from the provider dashboard to record percentages, reset times, credits, auto-reload or extra usage, and reset passes. Manual snapshots persist locally and stay manual until an explicit **Refresh** succeeds for a supported provider. Failed refreshes retain the last successful snapshot. Live readers show the connected email and plan when available, quota windows, Codex and Grok credits, and Claude model-specific weekly windows. The Claude OAuth fallback also reports monthly extra spending. Claude automatically reads the currently active CLI account on refresh. Exact subscription price and renewal date are not returned by these usage connections. Record those fields manually from the billing page; usage reset dates are not subscription renewal dates.

Provider marks are bundled from [Lobe Icons](https://github.com/lobehub/lobe-icons), with source links and the MIT license in `Sources/Skillbox/Resources/ProviderLogos`.

The read-only endpoint formats follow the provider integrations documented by [CodexBar for Codex](https://github.com/steipete/CodexBar/blob/main/docs/codex-oauth.md) and [Claude](https://github.com/steipete/CodexBar/blob/main/docs/claude.md).

## Local models

Open the Models tab with ⌘6 to see the AI models stored on this Mac: Ollama, the Hugging Face cache (honoring `HF_HOME` and `HF_HUB_CACHE`), LM Studio, OpenWhispr, `models` folders under Application Support, and any extra folders you add. Each row shows the source, on-disk size, and an estimated RAM need of size × 1.2, with a badge comparing it to physical memory: **Fits** at 70% or less, **Tight** up to 100%, **Too big** beyond that. The estimate covers typical context lengths; long contexts need more memory.

**Find duplicate copies** groups byte-identical models and shows the space a single copy would reclaim. Models that share a content digest group immediately; other files are hashed only when another model has the same size. The inventory scans at launch and again when a scanned folder changes. Choose sources and extra folders under **Local models** in Settings. Scanning code lives in the `ModelInventory` library target.

## Native Usage UI checks

Run `make test-ui` on a logged-in macOS desktop. The harness compiles the production Usage views into a separate menu bar app with synthetic provider data and isolated persistence. It never accesses accounts, Keychain, or the network. macOS must allow the invoking terminal to automate System Events and use Accessibility.

The driver checks quota/plan labels, periodic and explicit refresh, editor activation, real mouse clicks and typing in fields, native reset/picker controls, save/cancel, and preserving manual snapshots. It fails with a nonzero status and saves screenshots, app output, and `results.json` under `.build/usage-ui`. Run `swift test` for quota parsing, account switching, refresh scheduling/cancellation, persistence, and the existing feature regression suite.

TypeSafe reads its saved API key at startup without allowing Keychain dialogs. Already authorized builds classify automatically. If rebuilding changes Keychain trust, classification waits for **Unlock saved key** in Settings; the saved key stays in Keychain. The reader temporarily disables legacy Keychain interaction as well as per-request UI, then restores the prior policy (the modern flags alone do not suppress file-based Keychain ACL prompts; see Chromium FB16959400).
