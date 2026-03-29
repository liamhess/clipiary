## Top/Soon

- think about rich-text handling (currently only plain text and images are supported, no rich text)
- move to top on paste to exclude direct shortcut pasted items?

## Theme Ideas

### Color manipulation
- `.saturation(_:)` — 0 for grayscale, >1 for oversaturation; expose as theme option for hover/selection states
- `.brightness(_:)` / `.contrast(_:)` — lighten/darken rows or the panel
- `.colorMultiply(_:)` — tint all pixels by a color; useful for overlay effects
- `.hue(rotation:)` — shift hues by degrees; could power dynamic/animated themes

### Blending & compositing
- `.blendMode(_:)` — screen, overlay, softLight, hardLight, multiply, difference, etc.; stacking a colored layer with `.blendMode(.screen)` over a dark background produces neon effects
- Multi-layer `.shadow()` — multiple stacked shadow calls at different radii simulate a neon double-glow (inner bright tight, outer wide dim)

### Blur
- `.blur(radius:)` — gaussian blur; could blur the overlay backdrop behind the favorites picker instead of just darkening it; frosted-glass panel option

### Material variants
- Currently only `regularMaterial` is used; expose `.ultraThinMaterial`, `.thinMaterial`, `.thickMaterial`, `.ultraThickMaterial` as theme options for the panel or tab bar
