# Clipiary

Clipiary is a vibe coded macOS clipboard manager with an optional global copy-on-select mode (works for most apps).

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
