# Clipiary

Clipiary is a vibe coded macOS clipboard manager with an optional global copy-on-select mode (works for most apps).

## Development

Build the Swift package:

```sh
HOME="$PWD/.tmp-home" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift build
```

Build a stable app bundle for Accessibility approval:

```sh
./scripts/build_app.sh
```

Regenerate the app icon from a custom `1024x1024` PNG export:

```sh
./scripts/build_app_icon.sh /path/to/icon-1024.png
```

Optional local signing configuration:

Create a repo-local `.env` file with:

```sh
export CLIPIARY_CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

The build, run, and dev scripts will source `.env` automatically.

If `CLIPIARY_CODESIGN_IDENTITY` is not set, the app bundle is still ad-hoc signed so unsigned private releases behave more like standard "untrusted developer" apps on macOS.

Run the app bundle:

```sh
./scripts/run_app.sh
```

Run a dev watcher that rebuilds and relaunches the app on source changes:

```sh
./scripts/dev.sh
```

The app bundle path to approve in `System Settings > Privacy & Security > Accessibility` is:

`dist/Clipiary.app`

## Private Homebrew tap

This app is best distributed through a Homebrew cask in your own tap rather than `homebrew/cask`.

The install shape looks like this:

```sh
brew tap liamhess/tap
brew install --cask clipiary
```

The cask should live in a separate repository named `homebrew-tap` with:

```text
Casks/clipiary.rb
```

To build a release archive and generate the cask file locally:

```sh
./scripts/package_release.sh 0.2.1
```

That command writes:

- `dist/Clipiary-0.2.1.zip`
- `dist/Clipiary-0.2.1.sha256`
- `dist/clipiary.rb`

### CI release flow

The workflow in `.github/workflows/release.yml` is tag-driven and release-only. Pushing a tag such as `v0.2.1` from a commit on `main` will:

1. build the macOS app bundle
2. sign and notarize it when the Apple signing secrets are configured, otherwise fall back to ad-hoc signing
3. upload `Clipiary-<version>.zip` to the GitHub release
4. update `liamhess/homebrew-tap` with a new `Casks/clipiary.rb`

If a tag points to a commit that is not contained in `main`, the workflow exits without publishing.

Minimum GitHub Actions secret for unsigned private releases:

- `HOMEBREW_TAP_DEPLOY_KEY`

Optional GitHub Actions secrets for signed and notarized releases later:

- `CLIPIARY_DEVELOPER_ID_APPLICATION`
- `CLIPIARY_DEVELOPER_ID_P12_BASE64`
- `CLIPIARY_DEVELOPER_ID_P12_PASSWORD`
- `CLIPIARY_KEYCHAIN_PASSWORD`
- `CLIPIARY_NOTARY_APPLE_ID`
- `CLIPIARY_NOTARY_TEAM_ID`
- `CLIPIARY_NOTARY_PASSWORD`

If the Apple signing and notarization secrets are omitted, the workflow still works for a private tap. It will publish an ad-hoc-signed app archive and update the cask, but macOS will still treat it as an untrusted developer build rather than a trusted notarized app.

### Deploy key setup

Generate a dedicated SSH keypair for the tap:

```sh
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -C "homebrew tap deploy key" -N "" -f ~/.ssh/homebrew-tap-deploy
```

Add the public key to `liamhess/homebrew-tap` as a write-enabled deploy key:

```sh
gh repo deploy-key add ~/.ssh/homebrew-tap-deploy.pub \
  --repo liamhess/homebrew-tap \
  --allow-write \
  --title "homebrew tap deploy key"
```

Store the private key as a GitHub Actions secret in `liamhess/clipiary`:

```sh
gh secret set HOMEBREW_TAP_DEPLOY_KEY \
  --repo liamhess/clipiary \
  < ~/.ssh/homebrew-tap-deploy
```

After that, tagged releases can push cask updates to the tap over SSH without any personal access token.
