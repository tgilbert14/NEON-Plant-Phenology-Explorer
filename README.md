# NEON Plant Phenology Explorer

**[Live landing and launch](https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/)** · [Live app (Posit Connect)](https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/) · [Deploy runbook](DEPLOY.md) · [Project status](docs/project-status.md) · NEON `DP1.10055.001` · RELEASE-2026 ([DOI 10.48443/p75s-7p48](https://doi.org/10.48443/p75s-7p48)) · 46 sites · observations 2016 to December 2024

An unofficial R/Shiny explorer for NEON's **Plant phenology observations**
(**DP1.10055.001**), a sibling of the Small Mammal Tracker in the NEON explorer suite.
The suite hub is the
[NEON Cross-Product Response Atlas](https://tgilbert14.github.io/NEON-Driver-Cascade/).

> The unit is a **tagged plant individual** with a multi-year phenophase record. Phenology
> is monitored on a **fixed roster** of tagged plants along transects, so it is a **timing**
> signal (when each phenophase happens), not a measure of abundance, productivity, or a
> causal climate effect. Onset is **interval-censored** to the midpoint between the last
> 'no' and the first 'yes' visit. Visits run about weekly, and 2 or 3 times a week while
> plants are changing fast.

Theme: **Field Notebook**, a naturalist's seasonal journal (forest-canopy green, terracotta,
senescence amber on warm parchment, Fraunces headings).

## Tabs
- **Overview**: what is tagged here (by growth form), the story so far, a PDF report, and an
  analysis-ready export (a zip of tidy CSVs plus a codebook).
- **Phenology Clock**: the typical year as seasonal petals. Each phenophase's share of
  scored plant-year opportunities 'yes', by week of year, pooled into a descriptive
  seasonal profile. Repeated visits collapse within a plant-year-week; years stay separate.
  Beside it, the green-up and leaf-active trends by year (at least 3 plants per
  species-year, at least 6 years before a verdict, with a 95% CI).
- **Onset Lab**: every plant as a dot, green-up onset by days carrying leaves. Tap to pin a
  card and save the board as a PNG.
- **Plant Profile**: a downloadable card (PNG and CSV) with the phenophase calendar and
  quality checks that ask you to verify, not to delete.
- **Map**: phenology plots sized by plants tagged, coloured by the selected metric.
- **Across sites**: median green-up against latitude (a space-for-time pattern, not a
  temperature effect) and the same species across its sites.
- **Search**: find a plant species across the network, or find sites by green-up day.

## How green-up and leaf-active are measured
- **Green-up** is a plant-year's earliest bud-break onset. Drought-deciduous shrubs have no
  bud-break stage in NEON's protocol, so their green-up is the year's first new Young
  leaves. A January 'yes' that was already 'yes' at the plant's last December visit is
  leaves carried over, not a new green-up. Evergreen shrubs without leaf buds, cacti, and
  growth forms that sprout with autumn rain or stay green across the new year have no
  calendar-year green-up.
- **Site green-up** is the median across plants of each plant's median. Each onset lies
  between a plant's last 'no' and first 'yes' visit, so the app also takes the same
  median of those two days. When they are 14 or more days apart it shows a range (it
  bounds visit spacing and censoring, not sampling error). When most onsets were
  already underway at the first visit, it shows "day N or earlier" and no single day.
- **Leaf-active days** are the interval-censored span of each run of visits with leaves
  present, summed per plant-year, so a shrub that flushes twice with the rains gets two
  short seasons, not one 300-day season. A run that reaches the new year is bridged when
  the next visit is within 31 days. Where runs cut off at the year's first or last visit
  could add 14 or more days, the site reads "at least N days".
- **Trends** need 6 years. Green-up years where at least half the plants were already
  greening at the first visit, and leaf-active years whose spans could run 14 or more
  days longer, are drawn open and left out of the fit; no direction is claimed when
  leaving them out changes it.
- **Support**: a site-year counts only when the site was visited on its usual schedule that
  year (the 2020 sampling cut is left out), when a late first visit did not cut off what
  that metric could see, and when the site has at least 3 monitored seasons.

## Run it
R 4.5.x, bundle-only: `shiny::runApp(".", port = 8193)`. The app opens on **SRER** (Santa
Rita Experimental Range, Arizona). All 46 NEON terrestrial sites with released plant
phenology are bundled; pick one from the national map on the splash, by state, or by name.
Add `?site=HARV` (any four-letter code) to open a site directly.

## Data
Per-site `data/sites/<SITE>.rds` = `list(obs, inds, meta, ind_summary, trend)`. `obs` has
one row per phenophase observation (`individualID, plotID, year, date, dayOfYear,
phenophaseName, status` [yes/no/uncertain], `intensity, scientificName, growthForm,
is_species`); `inds` has one row per tagged plant. `ind_summary` and `trend` are
precomputed and are re-derived from `obs` on every index rebuild. `data/site_index.rds`
(one row per site) drives the picker and national map; `data/national_onsets.rds` (one row
per site and species, at least 3 plants with a green-up) drives the cross-site views;
`data/search_index.rds` drives Search.

The data are NEON **RELEASE-2026**, released data only, observations from January 2016
through December 2024. The 2013 to 2015 seasons that exist for 28 sites are not bundled:
they were early, pre-operational years under an earlier protocol, and starting every site
in 2016 keeps sites comparable. PUUM (Pu'u Maka'ala, Hawaii) is not yet bundled; see
[`docs/project-status.md`](docs/project-status.md). NEON's issue log records that from
2026 plant phenology is observed only at core sites and that Dead Lake (DELA) closed at
the end of 2025, so releases covering 2026 onward add years only at core sites.

Exact duplicate observation rows are dropped and rows are stored in a canonical order, so
rebuilding the same release gives byte-identical bundles. `scripts/verify_bundle.R`
checks every headline number against an independent oracle (`scripts/headline_oracle.R`,
written from the rule sheet `scripts/headline_rules.md`).

### Rebuild
1. `PHE_RAW_OUT_DIR=/empty/staging Rscript scripts/fetch_all_phe.R` pulls every expected
   site from the pinned release (`PHE_RELEASE` in `R/site_metadata.R`). `PHE_STARTDATE`
   (default `2016-01`) and `PHE_ENDDATE` (default the current month) bound the pull. The
   fetch lane needs `neonUtilities` 4.0.1 and `NEON_TOKEN`, and fails on any site error.
2. `PHE_RAW_DIR=/validated/staging Rscript scripts/bundle_phe_data.R` builds the 46 site
   bundles, the demo, the national, site and search indexes, and the data-through receipt.
3. `Rscript scripts/verify_bundle.R` checks the site roster, schemas, keys, thresholds,
   cross-index agreement, that each stored summary reproduces from `obs`, manifest
   checksums and package provenance.

The scheduled workflow stages a candidate in pinned fetch and validator lanes, warns when
NEON publishes a newer release or logs a product issue after the pinned one, publishes a
review branch, and opens a "Phenology refresh ready for review" issue. It never writes
refreshed data directly to `master`. See [`DEPLOY.md`](DEPLOY.md) and
[`docs/BUILD-TEST-HANDOFF.md`](docs/BUILD-TEST-HANDOFF.md) for the release contract.

## Data attribution
NEON (National Ecological Observatory Network). Plant phenology observations
(DP1.10055.001), RELEASE-2026. https://doi.org/10.48443/p75s-7p48. Provided under
CC BY 4.0. NEON is a program of the U.S. National Science Foundation operated by Battelle.

Built by Desert Data Labs · desertdatalabs@gmail.com. Unofficial, and not endorsed by
NEON, Battelle, or the NSF.
