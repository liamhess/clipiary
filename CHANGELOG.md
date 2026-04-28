# Changelog
## [Unreleased]
### Added
- Configurable thresholds for the text size bar segments (gear icon in settings)

### Changed
- Use dedicated UI lists for the different tabs for better selection/scrolling preservation
- Bigger description field in favorites dialog

### Fixed
- Keyboard navigation to first/last item not fully scrolling to reveal content padding

## [1.9.0] - 2026-04-27
### Added
- Named separators: separators in favorites tabs can now have a text label, displayed as a full-width pill-styled badge (themeable width)
- Theme effects: search field inner shadow setting
- Theme fills: texture overlay support — any fill can now have a tiled image texture with configurable opacity and blend mode

### Fixed
- Mouse click areas for favorite/delete buttons were misaligned
- Drag-and-drop reorder indicator was off by one when dragging items downward

## [1.8.0] - 2026-04-17
### Added
- New character count segmented bar and/or badge indicating the size of the element
- History limit setting now has a help tooltip explaining that higher limits mostly affect search performance, and shows the current history file size

### Changed
- Themes: reworked/polished existing themes and added new ones
- Escape now clears the search field first when search text is present, instead of closing Clipiary immediately
- Pg Up/Down keys now scroll one page instead of only half a page
- Preview popup now limited to 10k chars max

### Fixed
- Theme builder partially showed wrong initial values for undefined/defaulted properties



## [1.7.1] - 2026-04-16
### Improvements
- Search highlight now appears after just 10ms and applies to all terms including single characters
- Multi-word search highlights every token (e.g. "k an" highlights both "k" and "an")

### Fixed
- Fixed search highlight rendering being extremely slow for clipboard items with large text bodies (display text was not being capped when items were loaded from disk)

## [1.7.0] - 2026-04-16
### Improvements
- Search is significantly faster: pre-indexed search corpus, incremental narrowing, faster string matching, and highlights debounced to avoid blocking typing
- History persistence no longer blocks the main thread (debounced background writes)

### Fixed
- Fixed a rare bug showing some items mirrored upside-down after wake-up
- Left-click in history list no longer has a delay
- Added missing shortcuts to the keyboard shortcuts cheatsheet
- Favorites dialog was missing a theme's accent color

## [1.6.1] - 2026-04-14
- Fixed missing "Add Separator" context menu entry

## [1.6.0] - 2026-04-13
### Added
- Context menu on history items: right-click the row, or press the configurable shortcut (default ⌘↩) to open a menu with all paste options and Add to Favorites
- New "paste raw source" shortcut (default ⌥⇧↩, configurable in Settings): pastes the literal HTML or RTF markup of a rich text item as plain text
- New "paste as Markdown" shortcut (default ⌥↩, configurable in Settings): converts HTML or RTF items to Markdown (best-effort, preserving headings, lists, bold, italic, links, code) and pastes the result as plain text
- Performance improvements
- Support cmd+a/x/c/v in search field
- Themes:
  - configurable blur for the panel backdrop behind the favorites tab picker overlay (frosted-glass effect)
  - `material` option now supports `ultraThin`, `thin`, `regular`, `thick`, or `ultraThick` vibrancy levels
  - `fonts` section — configure family, size, and weight separately for regular and monospace row text
  - `fills.contentArea` — dedicated fill slot for the scrollable area and search field, independent of `fills.panel` (the outer panel shell)
  - `rowDetailsSpacing` — configure spacing between row entry and its details


## [1.5.0] - 2026-04-07
### Added
- Added a Theme Builder UI
- Settings window now aligns to some UX patterns of the theme builder
- Full date in item details

### Fixed
- Settings panel title bar longer bleeds through content
- Separators in favorites tabs no longer reduce the effective history limit

## [1.4.0] - 2026-04-03
### Added
- Preview Panel now shows entry details (source app, format, timestamp)
- Optional smart paste for copy-on-select: when the current selection still matches copy-on-select clipboard text, Cmd+V restores the immediately previous clipboard instead
- Input Monitoring permission prompts/status for smart paste interception

### Fixed
- Copy-on-select now collapses prefix-growth selections into a single transient history item instead of polluting history with intermediate prefixes
- Settings toggles now align consistently at the left edge instead of indenting some dependent options
- In-app update release notes now keep proper bullet indentation and use clearer heading, spacing, and text styling

## [1.3.0] - 2026-04-03
### Added
- New update UI

## [1.2.0] - 2026-04-03
### Added
- Rich text support: captures RTF and HTML formatting from the clipboard by default (Settings → Rich Text to disable)
- Option to paste rich text by default; use a configurable alternate paste shortcut (default: Shift+Return) to paste the opposite format

## [1.1.0] - 2026-04-03
### Added
- Improved rendering/scrolling/search performance
- Allow to exempt favorites from "Move to top on paste"
- Preview popup now also shows the items's description (if set)
- Favorites dialog text fields (text, description) now support usual copy/select actions (Cmd+V/A/X/C/Z/Y)
- Favorites tabs: right-click any entry to insert a horizontal separator below it; right-click the separator to remove it
- Added right-click menu for Clipiary's menubar icon

## [1.0.1] - 2026-04-02
### Fixed
- fix global shortcuts recording

## [1.0.0] - 2026-04-02
### Added
- Edit copied text directly from the favorites picker (Cmd+D)
- Search match highlighting in history rows
- Theme engine greatly revamped
  - support linear gradients, per-element border styles (width, color, dash)
  - glow effects (colored shadows on selected rows, panel edges, texts)
  - MeshGradient support in theme fills (macOS 15+); new built-in "Nebula" theme showcases it; falls back to a diagonal linear gradient on macOS 14
  - animation support in theme fills (looping)
  - animation support for selectedRow border (one-shoot, upon selection change)
  - blendMode + multi-layered shadows for glow/neon like effects in themes (e.g. in the Sci-Fi theme)
  - new App icon

## [0.9.0] - 2026-03-28
### Added
- Favorite tab name badges on history rows (configurable in Settings > Appearance)
- JSON-based theming system: customize colors, corner radii, and spacing via theme files in `~/Library/Application Support/Clipiary/themes/`. Copy and edit `default.json` to create your own themes.
- Theme picker in Settings > Appearance
- Improved hints when accessibility permissions are missing

## [0.8.1] - 2026-03-27
### Added
- Update button now shows when an update is available
- Text settings now contain a preview of the configured text
- Configurable ignored-apps list (via their bundle IDs)
- Skip also clipboard items marked as `org.nspasteboard.TransientType` (e.g. OTP codes or passwords used by password manager's browser extensions)

## [0.8.0] - 2026-03-26
### Added
- BACKSPACE can now be used as well to delete history entries
- Skip clipboard items marked as concealed by password managers (respects `org.nspasteboard.ConcealedType` and `org.nspasteboard.AutoGeneratedType`)
- Added a confirmation dialog for clearing all items

## [0.7.6] - 2026-03-26
### Fixed
- Don't close clipiary on update actions

## [0.7.5] - 2026-03-26

## [0.7.4] - 2026-03-26
- use Sparkle release notes in markdown

## [0.7.3] - 2026-03-26

## [0.7.2] - 2026-03-26

## [0.7.1] - 2026-03-26

## [0.7.0] - 2026-03-26

### Added
- In-app updates via Sparkle framework
- Help icons on non-obvious settings with popover descriptions
- Auto-monospace: items copied from terminal emulators or IDEs (Terminal, iTerm2, Ghostty, VSCode, Goland) automatically use a console font, with configurable app list
- Favorites descriptions: add an optional searchable description to favorite items via the favorites popup

### Fixed
- Restore favorite tabs from history when config.json is missing or reset

## [0.6.2] - 2026-03-24

### Added
- Configurable item line limit
- ESC key closes preview before dismissing the panel

### Fixed
- Occasional ghost window on first startup
- Preview regression
