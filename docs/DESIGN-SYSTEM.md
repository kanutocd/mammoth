# Mammoth Design System

The Mammoth design system keeps the public documentation, GitHub assets, diagrams, and future platform components visually consistent.

## Canonical Assets

- `docs/branding/logo/frozen-no-nonsense/source/mammoth-no-nonsense-frozen-master.png`
- `docs/branding/logo/frozen-no-nonsense/exports/png/mammoth-icon-black-transparent-2048.png`
- `docs/branding/logo/frozen-no-nonsense/exports/png/mammoth-icon-white-transparent-2048.png`
- `docs/branding/logo/frozen-no-nonsense/exports/png/mammoth-primary-horizontal-light.png`
- `docs/branding/logo/frozen-no-nonsense/exports/favicon/favicon.ico`
- `docs/branding/tokens/mammoth.css`
- `docs/branding/diagrams/mammoth-data-plane.svg`

## Color Tokens

| Token | Value | Usage |
|---|---:|---|
| Rich Black | `#0F0F0F` | Primary mark, dark surfaces |
| PostgreSQL Blue | `#336791` | Links, CTAs, diagram arrows |
| Stream Blue | `#5BA0E6` | Secondary diagram accents |
| Slate | `#64748B` | Secondary text |
| Light Gray | `#E8EBEF` | Borders and panels |
| White | `#FFFFFF` | Reverse surfaces |

## Implementation Note

The selected no-nonsense mark is visually frozen. Its SVG composition templates
still reference raster exports and must not be presented as native-vector
masters. Complete manual path construction and overlay approval before
promoting a canonical SVG.
