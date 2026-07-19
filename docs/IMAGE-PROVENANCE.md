# Cover and social image provenance

This record distinguishes illustrative design assets from scientific figures. None
of these images encodes measurements, site positions, dates, phenophase values, or
model results.

## Generation receipt

- Generated: 2026-07-18 (America/Phoenix)
- Tool: OpenAI built-in image generation tool; the specific model identifier was
  not exposed by the tool.
- Art direction: premium cut-paper / low-poly editorial illustration, tactile
  layered paper, restrained shadow, rich botanical detail, no labels, no logos,
  no charts, no maps, and no false data precision.

Landscape prompt, lightly normalized from the submitted instruction:

> Create a wide premium cut-paper editorial landscape for a plant phenology web
> experience. Show one ecological scene moving through spring budburst, summer
> canopy, autumn senescence, and winter dormancy. Use layered paper texture,
> dimensional shadows, botanical greens, warm amber and coral, muted sky blue, a
> dark forest ground, and ample calm composition. No text, labels, logos, charts,
> map geometry, people, or scientific measurements.

Portrait prompt, lightly normalized from the submitted instruction:

> Create a tall mobile companion to the seasonal plant phenology landscape in the
> same premium cut-paper / low-poly style. Emphasize a single tree passing through
> spring, summer, autumn, and winter from foreground to background, with tactile
> layers, botanical detail, restrained shadows, and a dark forest palette. No
> text, labels, logos, charts, maps, people, or implied measured values.

The original generated PNGs are retained so later maintainers can make new web
derivatives without compounding JPEG loss. The cover uses locally served JPEG
derivatives at quality 88. The social card is composed locally from the landscape
asset and project typography in `phenology-social-render.html`; its exact
1200 × 630 browser render is `docs/og-image-v2.jpg`. The editable SVG composition
is retained as an additional layout source.

## Asset register

| Asset | Dimensions | SHA-256 | Purpose |
|---|---:|---|---|
| `docs/assets/phenology-seasonal-hero-v1-source.png` | 1666 × 944 | `5bdd6989e8c02bd6318dc01395ac7fd7589580ebe0dc282e33abb33d330f5250` | Original landscape generation |
| `docs/assets/phenology-seasonal-hero-v1.jpg` | 1666 × 944 | `6111a72cfc178a3b0751d44a99ebee3f15c71b8c766d45ec9cfd1615a17ef317` | Desktop cover image |
| `docs/assets/phenology-seasonal-mobile-v1-source.png` | 864 × 1821 | `17fd2d13a56315967a93480a8f9fda930c438834650fb9df023ee15ffe6ce6bc` | Original portrait generation |
| `docs/assets/phenology-seasonal-mobile-v1.jpg` | 864 × 1821 | `b11c9940e56b1c2d49f86b6ea01d6ef6ad5ad82f2ab020d2d03d381711771576` | Mobile cover image |
| `docs/assets/phenology-social-render.html` | 1200 × 630 render contract | `cf90af5460efad7f8e0839f5ee820d36a3c84781f5c92c61991e3776c3fc6bd0` | Executable social-card source |
| `docs/assets/phenology-social-v1.svg` | 1200 × 630 | `75967b496aaecd0489a3784e7a929dec70b0a62e23f92b05c029b5410943e0fb` | Editable social-card layout source |
| `docs/og-image-v2.jpg` | 1200 × 630 | `a9415052fab1af2ba6d2aebb4c247ebefaaaaecf8d9cdb8a9d3dc28abb9e62ed` | Published Open Graph and Twitter card |

## Accessibility and interpretation

- Cover alternative text: “Cut-paper landscape showing the same tree through
  spring, summer, autumn, and winter.”
- Social-card alternative text: “Four seasonal trees beside the title Plant
  Phenology Explorer and the phrase Read the seasons.”
- The cover image reinforces the seasonal concept but is not required to understand
  any control, claim, or release state.
- The illustration is intentionally generic. Species identity, phenophase date,
  climate driver, and geographic location must not be inferred from it.

`scripts/check_cover.mjs` fails closed on the published image hashes, natural
dimensions, local references, metadata, suite links, and core accessibility and
claim-boundary contracts.
