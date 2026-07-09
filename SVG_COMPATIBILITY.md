# SVG Compatibility Reference

This document defines the SVG features **supported** and **not supported** by Tokengotchi's built-in SVG renderer. It is intended for pet designers and AI agents generating pet JSON files.

---

## ✅ Supported Elements

| Element | Notes |
|---|---|
| `<svg>` | Root container; `viewBox`, `xmlns`, `id`, `transform`, `opacity` |
| `<g>` | Group with `id` for animation targeting; `transform`, `opacity`, `clip-path` |
| `<path>` | Full path command set (see below) |
| `<circle>` | `cx`, `cy`, `r` |
| `<ellipse>` | `cx`, `cy`, `rx`, `ry` |
| `<rect>` | `x`, `y`, `width`, `height`, `rx`, `ry` (rounded corners) |
| `<line>` | `x1`, `y1`, `x2`, `y2` |
| `<polyline>` | `points` |
| `<polygon>` | `points` (auto-closed) |
| `<defs>` | Container for reusable definitions |
| `<linearGradient>` | `id`, `x1`, `y1`, `x2`, `y2`, `gradientUnits` |
| `<radialGradient>` | `id`, `cx`, `cy`, `r`, `fx`, `fy`, `gradientUnits` |
| `<stop>` | `offset`, `stop-color`, `stop-opacity` |
| `<clipPath>` | `id`; child shapes used as clip mask |

---

## ✅ Supported Presentation Attributes

### Fill
| Attribute | Notes |
|---|---|
| `fill` | Hex, named colour, `var(--key)`, `none`, `url(#gradId)` |
| `fill-opacity` | 0.0 – 1.0 |
| `fill-rule` | `nonzero` (default), `evenodd` |

### Stroke
| Attribute | Notes |
|---|---|
| `stroke` | Hex, named colour, `var(--key)`, `none`, `url(#gradId)` |
| `stroke-width` | Numeric |
| `stroke-opacity` | 0.0 – 1.0 |
| `stroke-linecap` | `butt` (default), `round`, `square` |
| `stroke-linejoin` | `miter` (default), `round`, `bevel` |
| `stroke-miterlimit` | Numeric (default 4) |
| `stroke-dasharray` | Space/comma-separated numbers, or `none` |
| `stroke-dashoffset` | Numeric |

### Compositing
| Attribute | Notes |
|---|---|
| `opacity` | 0.0 – 1.0, applies to entire element or group |
| `clip-path` | `url(#clipPathId)` |

### Transform
| Attribute | Notes |
|---|---|
| `transform` | `translate()`, `scale()`, `rotate()`, `matrix()`, `skewX()`, `skewY()` |

### Inline Style
| Feature | Notes |
|---|---|
| `style="..."` | Inline CSS properties take priority over presentation attributes |

---

## ✅ Supported Colour Formats

| Format | Example |
|---|---|
| 6-digit hex | `#74B9FF` |
| 3-digit hex | `#7BF` (expanded to `#77BBFF`) |
| 8-digit hex (with alpha) | `#74B9FF80` |
| 4-digit hex (with alpha) | `#7BF8` |
| `transparent` | Fully transparent black |
| SVG/CSS named colours | `red`, `cornflowerblue`, `goldenrod`, … (all 147 SVG 1.1 names) |
| Palette variables | `var(--base)`, `var(--accent)`, `var(--glow)`, `var(--dark)` |

---

## ✅ Supported Path Commands

All SVG path data commands from SVG 1.1:

| Command | Description |
|---|---|
| `M` / `m` | Move to (absolute / relative) |
| `L` / `l` | Line to |
| `H` / `h` | Horizontal line to |
| `V` / `v` | Vertical line to |
| `C` / `c` | Cubic Bézier curve |
| `S` / `s` | Smooth cubic Bézier |
| `Q` / `q` | Quadratic Bézier curve |
| `T` / `t` | Smooth quadratic Bézier |
| `A` / `a` | Arc *(approximated as a straight line — see limitations below)* |
| `Z` / `z` | Close path |

---

## ❌ Not Supported

| Feature | Reason |
|---|---|
| `<text>` | CoreText glyph-path conversion is complex; use `<path>` outlines instead |
| `<image>` | Embedded raster images inside SVG |
| `<use>` / `<symbol>` | Symbol reference resolution |
| `<marker>` | Arrow/marker on stroke paths |
| `<pattern>` | Repeating fill patterns |
| `<filter>` | SVG filters (blur, drop-shadow, etc.) |
| `<mask>` | Luminance/alpha masks |
| `<animate>` / SMIL | SVG native animation; use Tokengotchi keyframe tracks instead |
| CSS `<style>` blocks | Embedded stylesheet rules; use `style=""` attribute instead |
| `class` attribute | CSS class-based styling |
| `A` arc command (exact) | Arcs are linearly approximated; use Bézier curves for smooth arcs |
| `gradientTransform` | Gradient coordinate transforms |
| `xlink:href` gradient inheritance | `href`-linked gradient stops |
| `currentColor` | CSS cascade colour keyword |

---

## 🎨 Palette Variables

Tokengotchi pets use a custom `var(--key)` syntax resolved at render time from the pet's `palette` object:

```json
"palette": {
  "base":   "#74B9FF",
  "accent": "#FF7F6B",
  "glow":   "#5EEAD4",
  "dark":   "#2D3561"
}
```

Use `fill='var(--base)'`, `stroke='var(--glow)'`, etc. in SVG strings. This works in any supported attribute that accepts a colour value, including gradient `stop-color`.

---

## 🎬 Animation Architecture

Animations use a **named-group keyframe** system:

- Name your SVG groups with descriptive `id` attributes: `id="body"`, `id="left_eye"`, etc.
- In the animation's `tracks` array, reference groups by `targetId`
- Each keyframe specifies `time`, `tx`, `ty`, `rotate`, `sx`, `sy`

This architecture is intentionally AI-friendly — keyframe tracks can be generated reliably by language models.

---

## ⚠️ Known Limitations

- **Arc commands** (`A`/`a`): Approximated as straight lines. Use cubic Bézier curves (`C`/`c`) for smooth arc-like shapes.
- **Gradient bounding box coordinates**: When `gradientUnits="objectBoundingBox"` (the default), gradient coordinates are relative to the element's axis-aligned bounding box, not the visual shape boundary. For complex rotated shapes, use `gradientUnits="userSpaceOnUse"`.
- **Clip-path transforms**: Clip paths are applied in the SVG coordinate space before keyframe animation transforms.
