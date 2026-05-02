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

## Release

Bump `CFBundleShortVersionString` in `Sources/Skillbox/Resources/Info.plist.template`, then:

```sh
VERSION=v0.1.0-beta.2     # adjust
make clean bundle
ditto -c -k --keepParent Skillbox.app Skillbox-$VERSION.zip
git tag -a $VERSION -m "$VERSION"
git push origin $VERSION
gh release create $VERSION --prerelease --title "$VERSION" --notes "..." Skillbox-$VERSION.zip
rm -f Skillbox-$VERSION.zip
```

Drop `--prerelease` once you tag a stable `vX.Y.Z` (no `-beta`/`-rc` suffix).
