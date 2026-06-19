# NEON Plant Phenology Explorer

An (unofficial) R/Shiny explorer for NEON's **Plant phenology observations**
(**DP1.10055.001**) — a *NEONize* sibling of the Small Mammal Tracker, built to the same
Desert Data Labs quality bar.

> The unit is a **tagged plant individual** with a weekly-resolution, multi-year phenophase
> career. The honesty backbone: phenology is monitored on a **fixed roster** of tagged plants
> along transects, so it is a **timing** signal (when each phenophase happens), *not* a measure
> of abundance. Onset is **interval-censored** to the midpoint between the last 'no' and first
> 'yes' visit — honest about the twice-weekly resolution.

## Tabs
- **Overview** — what's tagged here (by growth form), the story so far.
- **Phenology Clock** (flagship) — the typical year as overlapping seasonal petals: each phenophase's *share of plants 'yes'* by week-of-year, pooled across years. Switch species to compare. Beside it: **is green-up shifting?** (median leaf-out day per year, ≥3 plants/species-year).
- **Onset Lab** — every plant as a dot: **green-up onset** (median day it first breaks leaf) × **growing-season length** (green-up → leaf-off). Tap to pin a card; faint plants don't yet have both dates.
- **Plant Profile** — a downloadable card (PNG + CSV): green-up / flowering / leaf-off days, season length, the **phenophase calendar** (when each phase happens across years), and low-noise quality checks.
- **Map** — phenology plots, sized by plants tagged, coloured by median green-up.

## Run it
R 4.5.x, bundle-only: `shiny::runApp(".", port = 8193)`. Demo = **HARV** (Harvard Forest — red maple, red oak). Also bundled: **SCBI** (Virginia deciduous forest), **SRER** (Sonoran desert — drought-deciduous).

## Data
Per-site `data/sites/<SITE>.rds` = `list(obs, inds, meta)`. `obs` = one row per phenophase
observation (`individualID, plotID, year, date, dayOfYear, phenophaseName, status` [yes/no/uncertain],
`intensity, scientificName, growthForm, nativeStatusCode`); `inds` = per tagged plant (identity + lat/lng).

### Rebuild
1. `Rscript-4.1.1 ../App-NEON-Small-Mammal-Tracker/scripts/fetch_phe_demo.R`  2. `Rscript scripts/bundle_phe_data.R`

## Honesty notes
- **Timing, not abundance** (a fixed roster — labelled everywhere). Onset is interval-censored.
- **Season length = green-up → last day "Leaves" is present**, *not* first "Colored leaves": NEON records `Colored leaves: yes` for even a few early-stressed leaves (e.g. a red oak in mid-June), which would make first-coloration a wildly early, misleading end-of-season marker. Last-leaf-present is the robust canopy-duration end.
- The Phenology Clock **pools years** by design (the typical season) — captioned; year-to-year shifts live in the onset trend.
- **QC flags are growth-form-aware**: the leaf-sequence-out-of-order check is suppressed for drought-deciduous / forb plants, which legitimately flush and drop leaves **several times a year** with the rains (so "leaf-out after leaf-drop" is normal for them, not an error).

Built by Desert Data Labs · desertdatalabs@gmail.com. Not affiliated with NEON/Battelle/NSF.
