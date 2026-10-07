# One-time Skillbox setup (maintainer)

Source releases work without an Apple Developer account or repository secrets. The setup below is optional and enables Sparkle updates when binary distribution is enabled.

## 1. Generate Sparkle EdDSA keys

Sparkle signs every released zip with an EdDSA private key. The matching public key is embedded in the app's `Info.plist` so installed copies can verify the update is authentic.

Download Sparkle's tools (matches the version in `.github/workflows/release.yml`):

```sh
SPARKLE_VERSION=2.10.0
curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
  | tar -xJ -C /tmp/
```

Generate a key pair:

```sh
/tmp/Sparkle-*/bin/generate_keys
```

This prints the **public key** to stdout and stores the **private key** in your login Keychain (account: `ed25519`). Copy the public key into:

- `Sources/Skillbox/Resources/Info.plist.template` → replace the placeholder value of `SUPublicEDKey`.

Export the private key for CI:

```sh
/tmp/Sparkle-*/bin/generate_keys -x sparkle-private-key.txt
```

Open the file, copy the entire contents, and add it as a **GitHub Actions secret** named `SPARKLE_ED_PRIVATE_KEY` on this repo. Delete the local file once it's stored as a secret:

```sh
rm sparkle-private-key.txt
```

> **Keep the private key safe.** If you lose it, all currently-installed copies of the app can no longer auto-update - they'll reject updates signed by any other key. You'd have to ship a new build with a new `SUPublicEDKey` that users must install manually.

## 2. Enable GitHub Pages

The `appcast.xml` (Sparkle's manifest) is served from this repo's `docs/` folder via GitHub Pages.

- Settings → Pages
- Source: **Deploy from a branch**
- Branch: `main` / folder `/docs`
- Save

After Pages is enabled, the appcast URL becomes `https://mmurakaru.github.io/skillbox/appcast.xml` - which matches `SUFeedURL` in `Info.plist.template`.

## 3. (Optional) Make the first changeset

```sh
npm install
npx changeset
```

Pick `skillbox`, choose a bump type, write a summary. Commit the resulting `.changeset/*.md` file. From here on, every PR with a user-visible change should ship with a changeset.

---

## Automatic releases

The release workflow runs on pushes to `main`. It consumes pending changesets, updates `package.json`, the lockfile, `Info.plist.template`, and `CHANGELOG.md`, then commits the version and creates a `vX.Y.Z` tag and GitHub source release. There is no version PR or manual tagging step. Tags with a prerelease suffix publish as GitHub prereleases.

The default release contains source archives. Users build with `make run` or `make install`; no signing secrets, Pages setup, or Apple Developer account are required.

## Optional binary distribution

Set the repository Actions variable `RELEASE_BINARIES` to `true` to enable the macOS bundle job. It uploads an ad-hoc signed zip to the same release. The Sparkle key setup above enables update signatures and appcast publishing; Sparkle signatures do not provide Apple code signing or notarization.

A future Apple Developer account can add Developer ID signing and notarization to the binary job. The source release workflow does not depend on that account.
