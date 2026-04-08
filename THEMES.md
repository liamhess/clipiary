# Clipiary Themes

Themes are JSON files in `~/Library/Application Support/Clipiary/themes/`. Clipiary ships with built-in themes and watches the directory for changes. To create your own, copy any built-in `.json` file, give it a new filename, change the `id` and `name`, and start editing. Press **Ctrl+R** in the panel to reload without restarting.

Every section and field is optional. Omitted fields fall back to the default theme values.

## Top-level

| Field | Type | Description |
|---|---|---|
| `id` | string | **Required.** Unique identifier (used internally and for the filename). |
| `name` | string | **Required.** Display name shown in the theme picker. |
| `options` | object | Global behavior flags. |
| `fills` | object | Background fills (solid colors or gradients). |
| `colors` | object | Flat colors for accents, text, indicators, small UI elements. |
| `borders` | object | Per-element border styling. |
| `effects` | object | Glow / shadow effects. |
| `cornerRadii` | object | Corner radius for each UI element. |
| `spacing` | object | Padding and spacing values. |

## `options`

| Field | Type | Default | Description |
|---|---|---|---|
| `useMaterial` | bool | `true` | Use macOS vibrancy material for the panel background. When `false`, the panel uses the solid `fills.panel` value instead. |
| `useSystemAccent` | bool | `true` | Use the system accent color (from System Settings). When `false`, uses `colors.accent`. |
| `appearance` | string | `"dark"` | Color scheme: `"dark"`, `"light"`, or `"system"`. Controls how SwiftUI semantic colors (`.primary`, `.secondary`) resolve. |
| `animatedPanel` | bool | `false` | Overlay a slowly orbiting gradient spotlight on the panel background. Works with both `useMaterial: true` and `false`. |
| `animatedPanelColor` | string | accent | Hex color of the animated spotlight. Omit to use the resolved accent color. |
| `animatedPanelPeriod` | number | `8.0` | Seconds per full orbit. Lower = faster. |
| `overlayBlurRadius` | number | none | Gaussian blur radius (in points) applied to panel content when the favorites tab picker overlay is open. Omit (or `null`) for the default plain-darkened overlay. Values around `4`–`8` produce a readable frosted-glass effect. |

## `fills`

Fills are the backgrounds of major UI areas. Each fill is an object that can represent a **solid color**, a **linear gradient**, or a **mesh gradient**.

### Solid fill

```json
{ "color": "#1E1E1E", "opacity": 0.85 }
```

### Linear gradient fill

```json
{
  "gradient": ["#0D0D12", "#1A0A1A"],
  "from": "top",
  "to": "bottom",
  "opacity": 1.0
}
```

`from` / `to` accept: `"top"`, `"bottom"`, `"leading"`, `"trailing"`, `"topLeading"`, `"topTrailing"`, `"bottomLeading"`, `"bottomTrailing"`, `"center"`.

### Mesh gradient fill (macOS 15+)

A multi-point gradient that blends colors across a 2D grid, producing organic color fields.

```json
{
  "mesh": ["#120030", "#0A1A40", "#003030",
           "#1E0048", "#0C1E48", "#004040",
           "#0A0818", "#081428", "#041818"],
  "meshColumns": 3,
  "meshRows": 3,
  "opacity": 1.0
}
```

| Field | Type | Description |
|---|---|---|
| `mesh` | [string] | `meshColumns × meshRows` hex colors, in row-major order (left→right, top→bottom). |
| `meshColumns` | number | Grid width (columns). |
| `meshRows` | number | Grid height (rows). |
| `meshPoints` | [[number, number]] | Optional control-point overrides in 0–1 range, one `[x, y]` pair per grid cell. Omit for a regular grid. |
| `opacity` | number | Overall opacity. |

On macOS 14, mesh gradient fills fall back to a diagonal linear gradient between the top-left and bottom-right corner colors.

### Fill slots

| Field | Default | Where it appears |
|---|---|---|
| `panel` | `#1E1E1E` @ 0.85 | Main panel background (when material is off), content scroll area, search field. |
| `tabBar` | `#000000` @ 0.05 | Tab bar strip behind the History/Favorites tabs. |
| `tabButtonSelected` | panel fill | Background of the active tab button. Defaults to `fills.panel` when omitted — useful when the panel uses a mesh gradient and you want a flat color inside the tab bar instead. |
| `rowSelected` | accent @ 0.18 | Background of the currently selected clipboard row. |
| `rowHovered` | accent @ 0.09 | Background of a row on mouse hover. |
| `card` | `#000000` @ 0.15 | Settings card backgrounds. |
| `overlay` | `#000000` @ 0.15 | Semi-transparent backdrop behind the favorites picker overlay. |

When a fill has no `color` and no `gradient` (just `opacity`), it uses the theme's resolved accent color as the base. This is the default for `rowSelected` and `rowHovered`.

## `colors`

Flat hex colors (`#RRGGBB` or `#RRGGBBAA`) for small UI elements and foreground styling. Set to `null` to use the system default.

| Field | Default | Description |
|---|---|---|
| `accent` | `#007AFF` | Primary interactive color (favorites star, copy-on-select badge, drop indicator). Ignored when `useSystemAccent` is `true`. |
| `pillBackground` | system secondary | Background of keyboard hint badges and shortcut pills. |
| `pillBackgroundOpacity` | `0.12` | Opacity for pill backgrounds. |
| `shortcutKeyBackground` | `#000000` | Background of shortcut key capsules in the help popover. |
| `shortcutKeyBackgroundOpacity` | `0.06` | Opacity for shortcut key backgrounds. |
| `cardStroke` | `#FFFFFF` | Default stroke color for settings cards (used when no `borders.card` is set). |
| `cardStrokeOpacity` | `0.08` | Opacity for card strokes. |
| `textPrimary` | system | Primary text color. `null` = system `.primary`. |
| `textSecondary` | system | Secondary text color. `null` = system `.secondary`. |
| `textTertiary` | system | Tertiary text color. `null` = system `.tertiary`. |
| `imageIndicator` | `#FF9500` | Color of the image/photo icon on image clipboard entries. |
| `statusReady` | `#34C759` | Status dot color when accessibility is granted. |
| `statusWarning` | `#FF9500` | Status dot color when accessibility is missing. |
| `gaugeUnfilled` | system secondary | Color of unfilled paste-count gauge segments. |
| `gaugeUnfilledOpacity` | `0.15` | Opacity for unfilled gauge segments. |
| `searchHighlight` | accent | Text color of matched search substrings. `null` = uses the resolved accent color. |
| `searchHighlightBackground` | none | Background color of matched search substrings. `null` = no background. |
| `searchHighlightBackgroundOpacity` | `0.15` | Opacity for search highlight backgrounds. |
| `separator` | card stroke | Color of horizontal separators in favorites tabs. `null` = uses the resolved card stroke color. |
| `separatorOpacity` | `0.35` | Opacity for separator lines. |

## `borders`

Per-element border definitions. Each is an object or `null` (no border). By default, only the settings card has a visible border.

### Border object

| Field | Type | Default | Description |
|---|---|---|---|
| `color` | string | varies | Hex color. Falls back to element-specific default. |
| `width` | number | `0` | Stroke width in points. `0` = no border. |
| `opacity` | number | `1.0` | Opacity applied to the border color. |
| `dash` | [number] | `null` | Dash pattern, e.g. `[5, 3]` for dashed. `null` = solid. |
| `animation` | string | `null` | One-shot animation when the row becomes selected. `"flash"` = brightness pulse. `"sweep"` = border draws on simultaneously from the top-left and bottom-right, meeting in the middle. |
| `animationDuration` | number | `0.6` | Duration of the border animation in seconds. |

### Border slots

| Field | Default width | Where it appears |
|---|---|---|
| `panel` | 0 | Outer border of the entire panel window. |
| `contentArea` | 0 | Border around the scrollable content area. |
| `selectedRow` | 0 | Border on the currently selected row. |
| `card` | 1 | Border on settings cards (falls back to `cardStroke` color). |
| `searchField` | 0 | Border around the search field. |
| `tabBar` | 0 | Border around the tab bar. |

## `effects`

Glow effects rendered as colored shadows. Each is an object or `null` (no effect). All are `null` by default.

### Glow object

| Field | Type | Default | Description |
|---|---|---|---|
| `color` | string | none | Hex color for the glow. |
| `radius` | number | `8` | Blur radius of the outer (wide, dim) shadow. |
| `opacity` | number | `0.5` | Opacity of the outer glow color. |
| `innerRadius` | number | none | Blur radius of the inner (tight, bright) shadow. When set, enables the double-glow neon effect. |
| `innerOpacity` | number | `0.8` | Opacity of the inner glow color. |

Setting `innerRadius` activates a tighter, brighter glow layer on top of the outer one, producing the characteristic neon "hot tube" look on dark backgrounds. How the inner layer is rendered depends on the element:

- **Rows** (`selectedRowGlow`, `hoveredRowGlow`): uses a `.shadow()` + `.blendMode(.screen)` fill overlay.
- **Separator** (`separatorGlow`): uses stacked blurred capsule layers (the scroll view clips `.shadow()` for thin shapes, so blurred layers are used instead — the visual result is identical).

**Single-layer glow** (subtle ambient):
```json
"selectedRowGlow": { "color": "#FF2D6F", "radius": 8, "opacity": 0.4 }
```

**Double-layer neon glow**:
```json
"selectedRowGlow": {
  "color": "#FF2D6F",
  "radius": 14,
  "opacity": 0.3,
  "innerRadius": 3,
  "innerOpacity": 0.85
}
```

### Effect slots

| Field | Where it appears |
|---|---|
| `selectedRowGlow` | Shadow around the selected row. |
| `hoveredRowGlow` | Shadow around a hovered row. |
| `panelGlow` | Outer shadow around the entire panel. |
| `selectedRowTextGlow` | Glow applied to the text of the selected row. |
| `hoveredRowTextGlow` | Glow applied to the text of a hovered row. |
| `searchHighlightTextGlow` | Glow applied to the main text when search highlights are active. |
| `separatorGlow` | Glow around horizontal separators in favorites tabs. |

## `cornerRadii`

Corner radius (in points) for each UI element.

| Field | Default | Element |
|---|---|---|
| `panel` | `14` | Main panel window. |
| `contentArea` | `12` | Scrollable history/favorites area. |
| `card` | `10` | Settings cards. |
| `tabBar` | `10` | Tab bar background. |
| `row` | `8` | Clipboard history rows. |
| `searchField` | `8` | Search input field. |
| `tabButton` | `8` | Individual tab buttons. |
| `pickerRow` | `6` | Favorites picker rows. |
| `shortcutRecordField` | `6` | Shortcut recording field in settings. |
| `keyBadge` | `3` | Keyboard shortcut hint badges. |
| `gauge` | `1` | Paste-count gauge bar segments. |

## `spacing`

Layout spacing values (in points).

| Field | Default | Description |
|---|---|---|
| `panelPadding` | `12` | Outer padding inside the panel. |
| `sectionSpacing` | `12` | Vertical space between header, content area, and footer. |
| `rowHorizontalPadding` | `8` | Horizontal padding inside each row. |
| `rowVerticalPadding` | `8` | Vertical padding inside each row. |
| `contentAreaPadding` | `10` | Padding inside the scroll area. |
| `rowSpacing` | `2` | Vertical gap between rows. |
| `separatorThickness` | `3` | Height in points of horizontal separators in favorites tabs. |

## Example: minimal custom theme

```json
{
  "id": "my-theme",
  "name": "My Theme",
  "options": {
    "useMaterial": false,
    "useSystemAccent": false,
    "appearance": "dark"
  },
  "fills": {
    "panel": { "color": "#1A1A2E", "opacity": 1.0 },
    "rowSelected": { "color": "#E94560", "opacity": 0.2 }
  },
  "colors": {
    "accent": "#E94560"
  }
}
```

## Example: animated panel

A slowly orbiting colored spotlight over a dark mesh gradient background. The spotlight completes one full orbit every 5 seconds.

```json
{
  "id": "my-animated",
  "name": "My Animated",
  "options": {
    "useMaterial": false,
    "useSystemAccent": false,
    "animatedPanel": true,
    "animatedPanelColor": "#FF71CE",
    "animatedPanelPeriod": 5.0
  },
  "fills": {
    "panel": {
      "mesh": ["#1A1028", "#0A1A40", "#001428",
               "#220E38", "#0C1E48", "#002A38",
               "#140820", "#081428", "#041018"],
      "meshColumns": 3,
      "meshRows": 3
    }
  },
  "colors": {
    "accent": "#FF71CE"
  }
}
```

`animatedPanel` works with `useMaterial: true` as well — the spotlight then sweeps over the frosted-glass vibrancy layer.

Everything not specified falls back to the default values listed above.

## Example: gradient + glow theme

```json
{
  "id": "aurora",
  "name": "Aurora",
  "options": {
    "useMaterial": false,
    "useSystemAccent": false
  },
  "fills": {
    "panel": {
      "gradient": ["#0B0C10", "#1F2833"],
      "from": "top",
      "to": "bottom"
    },
    "rowSelected": {
      "gradient": ["#66FCF1", "#45A29E"],
      "from": "leading",
      "to": "trailing",
      "opacity": 0.2
    }
  },
  "colors": {
    "accent": "#66FCF1"
  },
  "borders": {
    "panel": { "color": "#66FCF1", "width": 1, "opacity": 0.2 },
    "selectedRow": { "color": "#66FCF1", "width": 1, "opacity": 0.4 }
  },
  "effects": {
    "selectedRowGlow": { "color": "#66FCF1", "radius": 8, "opacity": 0.3 },
    "panelGlow": { "color": "#45A29E", "radius": 12, "opacity": 0.1 }
  },
  "cornerRadii": {
    "panel": 10,
    "row": 4
  }
}
```
