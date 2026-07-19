# NEON Plant Phenology Explorer

**[Live landing & launch →](https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/)** · [Deploy runbook](DEPLOY.md) · NEON `DP1.10055.001` · 46 sites · 9,515 tagged plants · 499 species

An (unofficial) R/Shiny explorer for NEON's **Plant phenology observations**
(**DP1.10055.001**) — a *NEONize* sibling of the Small Mammal Tracker, built to the same
Desert Data Labs quality bar.

> The unit is a **tagged plant individual** with a weekly-resolution, multi-year phenophase
> career. The honesty backbone: phenology is monitored on a **fixed roster** of tagged plants
> along transects, so it is a **timing** signal (when each phenophase happens), *not* a measure
> of abundance. Onset is **interval-censored** to the midpoint between the last 'no' and first
> 'yes' visit — honest about the twice-weekly resolution.

Theme: **"Field Notebook"** — a naturalist's seasonal journal (forest-canopy green, terracotta, senescence amber on warm parchment, Fraunces headings) — deliberately distinct from the Small Mammal Tracker's navy/cardinal/gold.

## Tabs
- **Overview** — what's tagged here (by growth form), the story so far, and a one-click **analysis-ready export** (a zip of tidy CSVs + a codebook).
- **Phenology Clock** (flagship) — the typical year as overlapping seasonal petals: each phenophase's *share of scored plant-year opportunities 'yes'* by week-of-year, pooled into a descriptive seasonal profile. Repeated visits collapse within a plant-year-week; years remain separate opportunities. Defaults to the dominant species; switch to compare. Beside it: **is green-up shifting?** (median leaf-out day per year, ≥3 plants/species-year, with a CI-honest verdict).
- **Onset Lab** — every plant as a dot: **green-up onset** (median day it first breaks leaf) × **days carrying leaves** (counted week by week). Tap to pin a card; faint plants don't yet have both recorded.
- **Plant Profile** — a downloadable card (PNG + CSV): green-up / flowering / last-leaf-week / days-carrying-leaves, the **phenophase calendar** (when each phase happens across years), and low-noise quality checks.
- **Map** — phenology plots, sized by plants tagged, coloured by median green-up (honest grey for plots with none).
- **Across sites** — the national gradient the multi-site data unlocks: median green-up vs **latitude** (the spatial echo of Hopkins' bioclimatic law), and the **same species across its sites**.

## Run it
R 4.5.x, bundle-only: `shiny::runApp(".", port = 8193)`. Demo = **HARV** (Harvard Forest — red maple, red oak). **All ~46 NEON terrestrial sites** with plant phenology are bundled (HARV/SCBI/SRER … through the desert, prairie, alpine, tundra, and tropics) — pick one from the national map on the splash, the sidebar (by state), or the search box.

## Data
Per-site `data/sites/<SITE>.rds` = `list(obs, inds, meta, ind_summary, trend)`. `obs` = one row per phenophase
observation (`individualID, plotID, year, date, dayOfYear, phenophaseName, status` [yes/no/uncertain],
`intensity, scientificName, growthForm, is_species`); `inds` = one row per tagged plant
(identity, coordinates, native-status code, taxon rank, and species-level flag).

Each bundle now also carries **precomputed** `ind_summary` + `trend` (no ~430ms recompute on load), and the low-cardinality `obs` columns are factor-encoded (~40% less RAM). `data/site_index.rds` (one row/site: counts, median green-up, elevation) drives the picker + national map; `data/national_onsets.rds` (one row per site×species, ≥3 plants) drives the cross-site views.

### Rebuild
1. `PHE_RAW_OUT_DIR=/empty/staging Rscript scripts/fetch_all_phe.R` — pulls every expected NEON terrestrial site. `PHE_ENDDATE` defaults to the current `YYYY-MM`; set it explicitly to reproduce a historical pull. The fetch lane needs `neonUtilities` and `NEON_TOKEN`.
2. `PHE_RAW_DIR=/validated/staging Rscript scripts/bundle_phe_data.R` — builds the 46 site bundles, demo, national/site/search indexes, and deterministic data-through receipt.
3. `Rscript scripts/verify_bundle.R` — requires the exact site roster, schemas, keys, thresholds, cross-index agreement, manifest checksums, and package provenance.

The scheduled workflow stages a candidate in pinned fetch/validator lanes and opens
a review PR. It never writes refreshed data directly to `master`. See
[`DEPLOY.md`](DEPLOY.md) and [`docs/BUILD-TEST-HANDOFF.md`](docs/BUILD-TEST-HANDOFF.md)
for the complete release contract.

## Honesty notes
- **Timing, not abundance** (a fixed roster — labelled everywhere). Onset is interval-censored.
- **Growing extent = leaf-active days** (distinct weeks with leaves present × 7), *not* green-up → leaf-off span and *not* first "Colored leaves". Two traps avoided: (a) NEON records `Colored leaves: yes` for even a few early-stressed leaves (a red oak in mid-June), so first-coloration is a wildly early false senescence; (b) a drought-deciduous desert plant flushes and drops several times a year, so green-up→leaf-off spans ~300 days while it only carries leaves ~110. Counting leaf-active weeks is honest for *every* growth form.
- The Phenology Clock **pools plant-year opportunities** by design (the typical season) — repeat visits collapse within a plant-year-week, years stay separate, and year-to-year shifts live in the onset trend.
- **QC flags are growth-form-aware**: the leaf-sequence-out-of-order check is suppressed for drought-deciduous / forb plants, which legitimately flush and drop leaves **several times a year** with the rains (so "leaf-out after leaf-drop" is normal for them, not an error).

Built by Desert Data Labs · desertdatalabs@gmail.com. Not affiliated with NEON/Battelle/NSF.
