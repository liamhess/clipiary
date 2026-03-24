# Development

Build the Swift package:

```sh
HOME="$PWD/.tmp-home" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache" \
swift build
```

Build a stable app bundle for Accessibility approval:

```sh
python3 tools/clipiary.py build
```

Regenerate the app icon from a custom `1024x1024` PNG export:

```sh
python3 tools/clipiary.py icon --source /path/to/icon-1024.png
```

Optional local signing configuration:

Create a repo-local `.env` file with:

```sh
export CLIPIARY_CODESIGN_IDENTITY="Clipiary Release Signing"
```

The Python tooling loads `.env` automatically.

Use one stable signing identity for every build you expect users to approve in Accessibility settings. That can be an Apple certificate or a long-lived self-signed code-signing certificate. If `CLIPIARY_CODESIGN_IDENTITY` is not set, the app bundle falls back to ad-hoc signing, which is convenient for local testing but can cause macOS to treat upgrades as a new app for TCC permissions like Accessibility.

Run the app bundle:

```sh
python3 tools/clipiary.py run
```

Run a dev watcher that rebuilds and relaunches the app on source changes:

```sh
python3 tools/clipiary.py dev
```

The app bundle path to approve in `System Settings > Privacy & Security > Accessibility` is:

`dist/Clipiary.app`

## Private Homebrew tap

The cask should live in a separate repository named `homebrew-tap` with:

```text
Casks/clipiary.rb
```

To build a release archive and generate the cask file locally:

```sh
python3 tools/clipiary.py release --version <version>
```

That command writes:

- `dist/Clipiary-<version>.zip`
- `dist/Clipiary-<version>.sha256`
- `dist/clipiary.rb`

To kick off the tag-driven release flow from your machine:

```sh
python3 tools/clipiary.py start-release patch
python3 tools/clipiary.py start-release minor
python3 tools/clipiary.py start-release major
```

`start-release` stamps `CHANGELOG.md` (renames `[Unreleased]` to `[X.Y.Z] - date`, adds a fresh `[Unreleased]` section), commits the result as `release: prepare vX.Y.Z`, pushes to `origin/main`, and pushes the matching tag. The changelog section for the released version is used as the GitHub release body.

### Changelog

User-facing changes go in `CHANGELOG.md` under `## [Unreleased]`, grouped by:

- **Added** — new features
- **Fixed** — bug fixes
- **Changed** — changes to existing behavior
- **Removed** — removed features

Internal changes (tests, refactoring, CI) do not need changelog entries. Keep entries concise — one line per change, written from the user's perspective.

### CI release flow

The workflow in `.github/workflows/release.yml` is tag-driven and release-only. Pushing a tag such as `v<version>` from a commit on `main` will:

1. build the macOS app bundle
2. sign it when a stable signing identity is configured, and notarize it when the Apple notary secrets are also configured
3. upload `Clipiary-<version>.zip` to the GitHub release
4. update `liamhess/homebrew-tap` with a new `Casks/clipiary.rb`

If a tag points to a commit that is not contained in `main`, the workflow exits without publishing.

The workflow keeps release logic in the repo by delegating to:

```sh
python3 tools/clipiary.py ci-release --version <version> --build-number <run-number>
```

Minimum GitHub Actions secret for private tap releases:

- `HOMEBREW_TAP_DEPLOY_KEY`

Recommended GitHub Actions secrets for stable signed releases:

- `CLIPIARY_CODESIGN_IDENTITY`
- `CLIPIARY_CODESIGN_P12_BASE64`
- `CLIPIARY_CODESIGN_P12_PASSWORD`
- `CLIPIARY_KEYCHAIN_PASSWORD`

Optional legacy aliases still supported by the workflow:

- `CLIPIARY_DEVELOPER_ID_APPLICATION`
- `CLIPIARY_DEVELOPER_ID_P12_BASE64`
- `CLIPIARY_DEVELOPER_ID_P12_PASSWORD`

Optional GitHub Actions secrets for Apple notarization:

- `CLIPIARY_NOTARY_APPLE_ID`
- `CLIPIARY_NOTARY_TEAM_ID`
- `CLIPIARY_NOTARY_PASSWORD`

The best no-Apple-ID setup is a long-lived self-signed code-signing certificate exported as a `.p12` and reused for every release. That gives Homebrew users a stable app identity, which is the best chance of preserving Accessibility approval across upgrades. The app will still be an untrusted developer build for Gatekeeper because it is not notarized.

If all signing secrets are omitted, the workflow still works for a private tap. It will publish an ad-hoc-signed app archive and update the cask, but macOS may treat each upgrade as a new app for Accessibility approval.

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
