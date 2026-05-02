# <img src="Sources/Skillbox/Resources/AppIcon.svg" alt="" height="48" valign="middle" /> skillbox

Native macOS menu bar app for managing claude skills installed at `~/.claude/skills/`.

See [PRD.md](PRD.md) for the spec.

## Build & run

Requires macOS 14+, Swift 6 toolchain (Command Line Tools is enough).

```sh
make bundle    # produces ./Skillbox.app, ad-hoc signed
make run       # builds and opens
make install   # copies to /Applications
make clean
```
