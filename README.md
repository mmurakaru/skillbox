# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar toolbox for AI coding agents: shared skills, provider usage for Claude Code, Codex, and Grok, and Claude Code memory, hooks, and env vars.

<img width="433" height="520" alt="skillbox_screenshot" src="https://github.com/user-attachments/assets/42d95c04-6555-4df7-b944-0b16d847b358" />



## Tabs

- **Skills**
- **Memory**
- **Env**
- **Usage**
- **Models**
- **Explore**

Provider marks come from [Lobe Icons](https://github.com/lobehub/lobe-icons) (MIT, see `Sources/Skillbox/Resources/ProviderLogos`).

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

## Lint & format

```sh
make format    # swift-format, blank-line padding, then SwiftLint autofix
make lint      # the same checks CI runs
```

`swift format` comes with the Swift toolchain and reads `.swift-format`. SwiftLint is a pinned, checksum-verified binary that `make` downloads into `.build/tools`, so nothing is installed system-wide. `.swiftlint.yml` holds the type-safety rules: no force casts, tries, or unwraps without a `SAFETY:` reason, no `Any` parameters, returns, or aliases, and untyped JSON dictionaries only in files that state they parse external JSON. `Tools/StatementPadding` adds blank lines around `if` statements, after declaration groups, and before `return`.

## Tests

```sh
swift test     # unit and integration tests
make test-ui   # native Usage UI harness, needs a logged-in desktop
```
