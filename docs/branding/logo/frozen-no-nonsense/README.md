# Mammoth No-Nonsense Brand Kit

This kit freezes the selected no-nonsense Mammoth mark: focused expression,
swept route crest, oversized tusk, and the trunk continuing behind the tusk
before curving left and upward.

## Status

The visual design is **frozen**. Do not redraw, regenerate, stretch, rotate, or
change the relationship between the head, eye, crest, trunk, and tusk.

The frozen source is a generated raster master. The PNG exports in this kit are
production-ready raster derivatives. Native path tracing remains a required
production step before this candidate replaces the canonical SVG assets.

Do not disguise an embedded bitmap as a finished vector logo.

## Brand idea

Mammoth is the PostgreSQL CDC Data Plane.

- Promise: **Carry Every Transaction.**
- Expression: no-nonsense, strong, focused, serious, operationally mature.
- Crest: fan-out and independent routes.
- Tusk: ordered, durable delivery.
- Trunk: PostgreSQL/WAL intake and continuity through the delivery path.
- Eye: operational awareness.

The mark must still work without this explanation. Mammoth recognition comes
first; product symbolism is secondary.

## Primary usage

Use the rich-black mark on white whenever practical. Use the reversed-white
mark on rich black for dark surfaces.

The PostgreSQL-blue mark is a secondary contextual variant for PostgreSQL-heavy
technical material. It is not the default corporate mark.

| Variant | Foreground | Background |
| --- | --- | --- |
| Primary | `#0F0F0F` | `#FFFFFF` |
| Reversed | `#FFFFFF` | `#0F0F0F` |
| PostgreSQL contextual | `#336791` | `#FFFFFF` |

## Clear space

Keep clear space equal to at least one quarter of the mark's rendered height on
all sides. Avatars may use one eighth when the containing square is visually
obvious.

## Minimum size

- Standalone digital mark: `24 px`
- Mark in a horizontal lockup: `32 px` high
- Print: `8 mm` high

At very small sizes, use the one-color mark. Do not add descriptor text.

## Typography

- Wordmark and headings: `Inter Black`, `Inter ExtraBold`, or `Geist Black`
- Supporting text: `Inter Medium`, `Inter Regular`, or `Geist`
- Technical material: `JetBrains Mono` or `IBM Plex Mono`

The included SVG composition templates specify Inter with system-safe fallbacks.
Before final release, render lockups with an approved Inter or Geist font file
and convert the wordmark to paths.

## Lockups

- Horizontal primary: icon + `MAMMOTH`
- Horizontal descriptor: icon + `MAMMOTH` + `POSTGRESQL CDC DATA PLANE`
- Stacked: icon above wordmark
- Standalone icon: use where Mammoth is already identified

Do not attach `Mammoth Platform` to the OSS mark as though the open-source
project includes the paid control plane.

## Do not

- Change the frozen geometry or expression.
- Separate, rotate, or rearrange the crest, trunk, or tusk.
- Add gradients, shadows, outlines, textures, or glow.
- Place the mark over a busy or low-contrast background.
- Use multiple colors inside the primary mark.
- Crop the tusk or trunk.
- Use the mammoth head as a decorative repeating pattern.
- Substitute an illustration or mascot for the primary mark.

## Files

### Source

- `source/mammoth-no-nonsense-frozen-master.png` — immutable generated source

### Core PNG exports

- `exports/png/mammoth-icon-black-transparent-2048.png`
- `exports/png/mammoth-icon-white-transparent-2048.png`
- `exports/png/mammoth-icon-postgres-blue-transparent-2048.png`
- `exports/png/mammoth-avatar-light-1024.png`
- `exports/png/mammoth-avatar-dark-1024.png`
- `exports/png/mammoth-primary-horizontal-light.png`
- `exports/png/mammoth-primary-horizontal-dark.png`
- `exports/png/mammoth-horizontal-light.png`
- `exports/png/mammoth-horizontal-dark.png`
- `exports/png/mammoth-stacked-light.png`
- `exports/png/mammoth-wordmark-black.png`
- `exports/png/mammoth-wordmark-white-on-black.png`

### App and browser icons

- `exports/favicon/favicon.ico`
- `exports/favicon/favicon-16.png`
- `exports/favicon/favicon-32.png`
- `exports/favicon/favicon-48.png`
- `exports/favicon/favicon-192.png`
- `exports/favicon/favicon-512.png`
- `exports/favicon/apple-touch-icon-180.png`
- `exports/favicon/site.webmanifest`

The 16 px file is provided only as a legacy browser fallback. Prefer 32 px or
larger because the frozen eye and crest details are intentionally intricate.

### Marketing exports

- `social/mammoth-social-preview-1280x640.png`
- `social/mammoth-youtube-banner-2560x1440.png`
- `social/mammoth-brand-standards-sheet.png`

### Templates

The SVG files under `templates/` are deterministic composition templates. They
reference the frozen PNG exports and are not substitutes for a native path-based
logo master.

The templates and their rendered lockups use an available system fallback when
Inter or Geist is not installed. They are composition references until the
approved wordmark font is packaged and its letters are converted to paths.

## Integrity

`asset-manifest.json` records the frozen source identity and distinguishes the
immutable mark from derivative exports.

## Final vectorization checklist

1. Trace the frozen silhouette manually with the fewest practical Bézier nodes.
2. Reproduce the negative spaces exactly.
3. Compare raster overlays at 100%, 50%, and 24 px.
4. Convert the approved wordmark to paths.
5. Run SVG optimization without altering geometry.
6. Replace canonical assets only after visual overlay approval.
