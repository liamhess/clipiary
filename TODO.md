## Top/Soon
- Full date in item details

## Theme Ideas

- Pixel art effects
- Font configuration

### Color manipulation
- `.saturation(_:)` — 0 for grayscale, >1 for oversaturation; expose as theme option for hover/selection states
- `.brightness(_:)` / `.contrast(_:)` — lighten/darken rows or the panel
- `.colorMultiply(_:)` — tint all pixels by a color; useful for overlay effects
- `.hue(rotation:)` — shift hues by degrees; could power dynamic/animated themes

### Blur
- `.blur(radius:)` — gaussian blur; could blur the overlay backdrop behind the favorites picker instead of just darkening it; frosted-glass panel option

### Material variants
- Currently only `regularMaterial` is used; expose `.ultraThinMaterial`, `.thinMaterial`, `.thickMaterial`, `.ultraThickMaterial` as theme options for the panel or tab bar
