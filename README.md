# Clipiary

Clipiary is a vibe coded macOS clipboard manager with powerful features and an optional global copy-on-select mode (works for most apps).

<img width="600" alt="Clipiary main view" src="docs/images/screenshot-main.png" />
<img width="600" alt="Clipiary settings" src="docs/images/screenshot-settings.png" />

## Copy On Select

https://github.com/user-attachments/assets/b31bc9ed-20f9-4b12-a1cf-d55aba12d529

## Installation

Clipiary can be installed through my own homebrew tap:

```sh
brew tap liamhess/tap
brew install --cask clipiary
```

Since I don't pay for a Apple Developer ID you will have to access the untrusted signing in the Privacy & Security settings.

For the copy-on-select feature to work you will have to grant Accessibility rights.

## Usage

Clipiary lives in your menu bar. Click the icon or press **Cmd+Shift+V** (configurable) to open it. Use **arrow keys** to navigate, **Return** to paste, and **Cmd+D** to favorite an item.

**Quick paste previous** — Press **Ctrl+Opt+Cmd+P** (configurable) to instantly paste the second item from your history without opening Clipiary. Useful for swapping between two clipboard entries.

**Copy-on-select** currently works for many apps but not for all (depending on the apps specific accessibility settings).
You can configure the amount of latest copy-on-select items that should be kept in the history, to avoid polluting it with mouse selections that were never intended to be copied/pasted (copy-on-select items that were actually pasted are exempt from removal).

### Custom Favorites Tabs

By default there is a single "Favorites" tab. You can configure multiple named favorites tabs by creating a config file at:

```
~/Library/Application Support/Clipiary/config.json
```

Example (see [docs/config.example.json](docs/config.example.json) for a full template):

```json
{
  "favorites": [
    { "name": "Snippets" },
    { "name": "Shell", "entries": ["git status", "docker ps"] }
  ]
}
```

Each tab can optionally include `entries` that are pre-populated on first launch and pinned (they cannot be unfavorited). When multiple tabs are configured, **Cmd+D** opens a picker where you can toggle an item's membership with **Space** or **arrow keys + Enter**, and dismiss with **Esc**.

## Development

Development, release, and tap-maintainer notes live in [DEVELOPMENT.md](DEVELOPMENT.md).

The repo automation lives in `python3 tools/clipiary.py`, with no external Python packages required.
