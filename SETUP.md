# One-time Skillbox setup (maintainer)

Most of the project works out of the box. These three steps are needed **once** for the auto-update + automated-release pipeline to function.

## 1. Generate Sparkle EdDSA keys

Sparkle signs every released zip with an EdDSA private key. The matching public key is embedded in the app's `Info.plist` so installed copies can verify the update is authentic.

Download Sparkle's tools (matches the version in `.github/workflows/release.yml`):

```sh
SPARKLE_VERSION=2.6.4
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

## How the pipeline runs end-to-end

1. PR ships with a changeset → merge to `main`.
2. `.github/workflows/changesets.yml` opens a "Version Packages" PR that bumps `package.json` + `Info.plist.template` and rebuilds `CHANGELOG.md`.
3. Maintainer merges the Version PR → changesets creates `vX.Y.Z` tag.
4. Tag push fires `.github/workflows/release.yml`:
   - `make bundle` produces `Skillbox.app`
   - Sparkle-signs the zip with `SPARKLE_ED_PRIVATE_KEY`
   - `gh release create` uploads the signed zip
   - `scripts/append-appcast.mjs` adds a new `<item>` to `docs/appcast.xml`
   - Commits the appcast back to `main`
5. Pages serves the new appcast within ~30 seconds.
6. Installed apps see the new version on their next daily check, or via Settings → Updates → "Check for Updates…".
