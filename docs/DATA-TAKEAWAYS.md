# NEON Plant Phenology Explorer — Data Takeaways & Critical Review
_Suite audit — June 2026. NEON DP1.10055.001 (Plant phenology observations)._

This is the app that produces the suite's **one robust pooled link** — temperature → green-up onset.
It is also the cleanest-built sibling reviewed: honest metric definitions, a shipped codebook, n-gates,
and CI-aware verdicts. The findings below are about sharpening the cascade hand-off and one structural
coverage trap, not fixing the machinery.

## What the data actually shows
- **Coverage is deep and national.** 46 sites, **9,515 tagged plant individuals**, **5.59M phenophase
  observations** (`obs`), 2016–2024, latitude **18.0–71.3 °N**, elevation **4–3,490 m**. NA rate on the
  precomputed `median_greenup` / `median_leaf_active` is **0/46 sites** — every bundled site resolves a
  green-up and a leaf-active number.
- **The latitude gradient is real and strong.** Across all 46 sites, `median_greenup ~ lat` gives
  **+2.50 days per °N** (p = 1.6e-6, R² = 0.41). Adding elevation: **+2.45 d/°N and +1.74 d per 100 m**
  (R² = 0.51, both p < 0.01). This is the spatial echo of the temporal temp→green-up link — same sign,
  same mechanism, laid out in space.
- **The same-species gradient is cleaner than the network gradient — lead with it.** *Acer rubrum*
  (red maple), the most widespread species (**10 sites**), green-up vs latitude = **+4.4 d/°N
  (p = 7e-4, R² = 0.78)** — holding species constant nearly doubles R² and the slope. *Liriodendron
  tulipifera* across 5 sites is monotonic (DOY 69→88 from TALL to SERC). **51 species span ≥3 sites**,
  133 span ≥2 (`national_onsets`, 723 site×species rows, 499 distinct species).
- **Earliest vs latest leaf-out spans 221 days.** Earliest site medians: **LAJA day 5** (tropical forb),
  **SRER day 42**, **DSNY day 46**, **CLBJ day 62**. Latest: **KONA day 226**, **STER day 186**,
  **BARR day 175** (Arctic, 71 °N), **NIWO day 161** (alpine, 3,490 m). Site-median green-up: min 5,
  median 98, max 226 DOY.
- **Onset is genuinely interval-censored, not a raw first-yes.** At HARV, **55.4%** of per-plant green-up
  onsets land on a `.5` midpoint (the midpoint between last 'no' and first 'yes'), only **0.3%** are
  left-censored, and the mean gap between `first_yes` and the censored `onset_doy` is **2.47 days** —
  exactly the half-interval of twice-weekly visits. The metric is defensible to a phenology reviewer.
- **Year-to-year green-up variability is biome-structured** — the cascade's whole point. Stable temperate
  forests: HARV swings **13 d** across 6 years (SD 4.3), BART 11.75 d (SD 4.6). Deserts/grasslands swing
  wildly: WOOD **60 d**, CPER **49.5 d**, SRER **36 d** (SD 18.7). The QC year-outlier threshold (45 d) is
  correctly tuned to *not* cry wolf at desert sites where 6-week swings are rain-driven and real.
- **CRITICAL coverage trap for the cascade: desert green-up is built on a biased ~1/5 of plants.** At
  HARV/SCBI, **91–92%** of tagged plants have a finite green-up onset. At **SRER only 19%** do
  (40 of 215); JORN 54%, MOAB 61%, ONAQ 63%. Desert drought-deciduous/cactus/evergreen plants rarely
  record a *green-up phenophase* ("Breaking leaf buds" / "Initial growth") — they're scored straight into
  "Leaves"/"Young leaves". So a desert site's `median_greenup` is a small, non-random subset, while
  **`leaf_active` survives** (SRER 67%, ONAQ 99%).
- **`leaf_active` is the honest growing-extent metric and it spans the whole network** (site medians
  **35–266 days**). For multi-flush desert plants, green-up→leaf-off would fabricate a ~300-day season;
  counting distinct leaf-weeks × 7 yields the real ~110. The bundle ships this, not the span.
- **Onset trends sit in the small-n regime — and the app respects it.** 45/46 sites carry a trend table;
  median **63.5 species-year points/site**; 41/46 sites have ≥5 distinct site-years (fittable). But each
  species-year point rests on a **median of n = 5 individuals**, with **71% of points at n = 3–6** — a
  false-negative regime. The app gates at n ≥ 3, refuses any slope below 5 annual points, and reports
  days/year with a 95% CI that says "spans zero" when it does.

## How it's built
- **Source → raw:** `scripts/fetch_all_phe.R` pulls `DP1.10055.001` per site via `neonUtilities::loadByProduct`
  (2016-01 to 2024-12, resumable) to `../phe-data-fetch/<SITE>_raw.rds`. Two tables matter:
  `phe_statusintensity` (the yes/no/uncertain phenophase scores) and `phe_perindividual` (tag identity,
  growthForm, lat/lng, nativeStatusCode).
- **Raw → bundle:** `scripts/bundle_phe_data.R` builds per-site `data/sites/<SITE>.rds` =
  `list(obs, inds, meta, ind_summary, trend)`. `obs` is the tidy long table (one row per
  `individualID × visit × phenophaseName`); `phenophaseStatus == "missed"` is dropped, `uncertain` kept
  but excluded from every denominator. Low-cardinality columns are factor-encoded (~40% RAM). It also rolls
  up `data/site_index.rds` (one row/site, drives picker + national map) and `data/national_onsets.rds`
  (one row per site×species with ≥3 individuals, drives the cross-site tab).
- **Metric definitions (`R/phe_helpers.R`):**
  - `onset()` → first-yes day per individual×phenophase×year, **interval-censored to the midpoint** of
    the last-'no'/first-'yes' interval; flags `left_censored` when no preceding 'no'.
  - `key_onsets()` → per individual-year `greenup` (earliest onset across the green-up phenophases),
    `flower`, `leaf_off` (last 'Leaves'='yes' day — explicitly *not* first "Colored leaves"), and
    `leaf_active` (distinct leaf-weeks × 7).
  - `individual_summary()` → median across years per plant. `onset_trend()` → species×year median green-up,
    **n ≥ 3 individuals** gate, **never pooled across years** (the climate-shift signal).
  - `weekly_yesrate()` → the Phenology Clock: % of plants 'yes' per phenophase per week, **n ≥ 5** gate,
    **pooled across years by design** (and captioned as such).
- **App renders:** Overview (growth-form composition + auto-written narrative + analysis-ready zip),
  Phenology Clock (polar petals + CI-honest onset-shift verdict), Onset Lab (pin-card scatter:
  green-up × leaf-active), Plant Profile (downloadable card + phenophase calendar + growth-form-aware QC
  flags), Map, and Across-sites (latitude gradient + same-species-across-range).

## Critical findings by lens

### NEONize (suite cohesion / gold-standard parity)
- **[strength]** Full flagship parity: splash national picker, demo-on-startup (HARV bundle present, 156k
  obs), hero count-up band, pin-card interactive (Onset Lab), downloadable QC card, shipped codebook,
  CI-honest insight banners, dark mode. This is the cleanest sibling audited.
- **[low → fix]** The desert green-up coverage gap (19% at SRER) is **not surfaced in-app**. The Onset Lab
  caption says "X of Y plants placeable", but the hero "median green-up" stat and the Map's per-plot
  green-up give no hint that at a desert site they rest on a fifth of the roster. Add a coverage badge
  ("green-up scored for 19% of plants here — read leaf-active") when `gu_share < ~0.5`.
- **[low]** README headline says "499 species"; `national_onsets` confirms 499 distinct species but
  `site_index$n_species` sums to 818 across sites (double-counting shared species). Both are right for
  what they count — worth a one-word label ("499 distinct / 818 site-species") to avoid confusion.

### Ecological (Jornada / phenology domain)
- **[strength]** The field method is represented correctly: fixed roster of tagged individuals,
  twice-weekly visits, phenophase status (not abundance), individual-level repeated measures, growth-form
  -specific phenophase sets. The "timing, not abundance" framing is everywhere and correct.
- **[strength]** `leaf_off` ≠ senescence is handled exactly right: first "Colored leaves" is rejected
  (NEON logs it for a few early-stressed leaves — a red oak in June), `leaf_active` is the honest extent,
  and QC ordering checks are suppressed for multi-flush drought-deciduous/forb forms.
- **[med → fix]** **Biome-conditional metric, not just biome-conditional prior.** In warm deserts the
  green-up *phenophase itself* is largely unrecorded (SRER 19% coverage), so "green-up onset" is a
  temperate-forest construct mis-applied. For desert sites the defensible leaf-phenology signal is
  `leaf_active` (presence extent) and the *first "Leaves"=yes* week, not the green-up-onset phenophase.
  This is the per-app expression of the suite's `biome-conditional-priors` truth — surface it as a
  metric switch, not just a caption.
- **[low]** Conifer green-up (*Pinus strobus* via "Emerging needles") is correctly mapped into the
  GREENUP set; the cross-site *P. strobus* series is non-monotonic with latitude (ORNL 108 → BART 155 →
  TREE 129), a fair read given needle-flush timing differs from broadleaf — worth a note that conifer and
  broadleaf green-up are not directly comparable.

### Data science (Quinn — analysis-ready export)
- **[strength]** Export is genuinely FAIR: 5 tidy CSVs (obs_long, onsets_by_individual_year,
  individual_summary, phenology_clock_weekly, onset_trend_by_species_year) + a **72-row codebook**
  covering every column's type/units/allowed-values/definition + phenophase decode + a provenance block
  naming the unit of analysis, censoring rule, and suppression gates. README.txt ships in the zip.
- **[strength]** Honest typing: factor-encoding internal-only, `na=""` on export, `left_censored` flag
  carried, the "leaf_off − greenup ≠ leaf_active" reconciliation warning is in the codebook.
- **[low → fix]** `flower` is NA for 91 of 723 national rows (and for whole growth forms that don't flower
  on the roster). That's structural-missing, not failure — but the per-site export doesn't distinguish
  "not monitored" from "monitored, never yes". A `flower_n_years` companion column would let a downstream
  analyst tell the two apart.
- **[low]** The export ships per-site only; there is no one-click national bundle (`site_index` +
  `national_onsets`) for someone who wants the cross-site gradient table the app already computes.

### Statistics (small-n honesty / pooling / CI)
- **[strength]** The within-site onset-shift verdict is textbook-honest: refuses to fit < 5 annual points,
  reports days/**year** (never extrapolated per-decade), prints the 95% CI, and says "spans zero — drift
  vs noise" instead of a directional verdict when the CI straddles zero. n travels with every point.
- **[strength]** n-gates throughout: clock n ≥ 5 obs/week, trend n ≥ 3 individuals/species-year,
  gradient needs ≥ 4 sites; the same-species cross-site plot draws **markers only** (no fabricated
  continuous latitudinal line).
- **[med → fix]** The **network latitude gradient pools across different species mixes** — the
  `gradientInsight` caption flags this, but the headline slope (2.5 d/°N) is reported from a single OLS
  with no CI in the banner. Report the CI, and prefer leading with the **within-species** slope
  (red maple 4.4 d/°N, R² 0.78) which controls the confound. The app *has* the same-species view — make
  it the headline read, not the secondary panel.
- **[low]** Trend points rest on median n = 5 individuals (71% at n = 3–6). The app gates and pools
  correctly, but a reader could still over-read a single site's species line. The existing "a signal,
  not a verdict" caption mitigates this; keep it prominent.

## Honest-stats & caveats — what this app must NOT be read to claim
- **Not abundance.** Every rate/count is timing on a fixed roster; it says nothing about how common a
  species is. (Labelled everywhere — keep it that way.)
- **Desert "green-up onset" is a thin, biased estimate.** At SRER/JORN/MOAB it rests on 19–61% of plants.
  Do not feed a desert-site `median_greenup` into the cascade as if it had forest-grade coverage; pair it
  with `leaf_active` and the coverage share.
- **Composition vs productivity.** Phenology is *timing*, not productivity; it doesn't measure biomass or
  richness. It complements — does not replace — the veg-structure basal-area floor.
- **The clock pools years.** It's the typical calendar, not a trend; between-year shifts live only in
  `onset_trend`.
- **Cross-site gradients are observational and confounded by species mix.** The within-species slope is
  the controlled read; the network slope is a coarse echo, not a controlled comparison.
- **Single-site, short-series onset slopes are signals, not verdicts** (median n = 5 plants/point;
  many sites < 9 years). Pool, and report CIs.

## Place in the cascade
This app produces the **climate → plants** rung's most defensible link in the entire suite. The
temporal signal (warmer spring → earlier green-up, pooled across ~32 sites, p ≈ 0.01) is corroborated
here **in space**: green-up shifts +2.5 d/°N across the network and **+4.4 d/°N within red maple alone**
(R² 0.78) — the same temperature mechanism, two independent geometries. The Driver Cascade should:
1. **Lead with green-up, and lead with the within-species gradient** — it's the cleanest evidence the
   suite owns.
2. **Carry the metric switch the biome demands.** Use green-up onset as the plant signal in temperate
   biomes; in warm deserts swap to `leaf_active` / first-leaf-week, because the green-up *phenophase* is
   only scored for ~1/5 of desert plants. This operationalizes the `biome-conditional-priors` truth at the
   data level, not just the prior level.
3. **Treat phenology as timing, not productivity** — corroborate it against veg-structure basal area
   (the slow state floor), never substitute it for richness.
4. **Inherit the honesty machinery** — interval-censoring, n-gates, CI-or-silence verdicts, the
   pooled-not-per-site discipline are all correct here and should propagate downstream unchanged.
