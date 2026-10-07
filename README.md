# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar app for Claude Code: skills, auto-memory, hooks, and env vars.

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
