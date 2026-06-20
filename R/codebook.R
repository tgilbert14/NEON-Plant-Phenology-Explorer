# ===========================================================================
# NEON Plant Phenology Explorer — SHIPPED CODEBOOK
# Decodes every analysis-ready download (obs, onsets, individual_summary,
# clock, onset_trend). Source of truth: R/phe_helpers.R + scripts/bundle_phe_data.R.
# A codebook.csv built from these ships INSIDE every download zip so the export
# is reusable in 5 years without re-reading the source.
# Data product: NEON DP1.10055.001. Unit of analysis: a tagged plant individual,
# repeated-measures across weeks and years; plotID is the spatial block.
# (Drafted by the data-science review; see docs/neonize-playbook.md.)
# ===========================================================================

# ---- (A) per-column codebook across all five exported tables --------------
PHE_CODEBOOK_ROWS <- tibble::tribble(
  ~table, ~column, ~type, ~units, ~allowed_values, ~definition,

  # 1. obs (long; one row per individualID x date x phenophaseName)
  "obs", "individualID", "character", "", "NEON tag, e.g. NEON.PLA.D01.HARV.06012", "Stable unique ID of the tagged plant individual; the repeated-measures subject and the join key to individual_summary.",
  "obs", "plotID", "character", "", "NEON plot code, e.g. HARV_001", "Phenology plot the individual sits in; the spatial block (treat as a random effect / cluster, not an independent replicate).",
  "obs", "year", "integer", "calendar year", "e.g. 2015-2024", "Calendar year of the observation, parsed from the date; the grouping unit for per-year onset.",
  "obs", "date", "Date", "", "ISO YYYY-MM-DD", "Observation (visit) date; observers visit a fixed roster up to twice weekly through the growing season.",
  "obs", "dayOfYear", "integer", "day-of-year", "1-366", "Ordinal day within the year (Jan 1 = 1); the timing axis for all onset and clock computations.",
  "obs", "phenophaseName", "character", "", "see PHE_PHENOPHASE_DECODE", "The phenophase scored on this visit; growth-form-specific. See PHE_PHENOPHASE_DECODE.",
  "obs", "status", "character", "", "yes | no | uncertain", "Whether the phenophase was active; 'uncertain' is retained here but EXCLUDED from every yes-share denominator and onset. NEON's 'missed' is dropped at bundle time.",
  "obs", "intensity", "character", "", "ordinal bin label; phenophase-specific", "Ordinal NEON intensity bin (NOT a number): percent-of-canopy bins for leaf/flower phases vs geometric COUNT bins for fruit/cone phases. Bin sets DIFFER by phenophase, so intensity must NEVER be averaged across phenophases; recorded only when status=='yes'.",
  "obs", "scientificName", "character", "", "Genus species (may be 'genus sp.' or a slash)", "Taxon of the individual (denormalized from identity); rows with 'sp.' or '/' are not species-level (see is_species).",
  "obs", "growthForm", "character", "", "e.g. Deciduous broadleaf, Evergreen conifer, Forb, Graminoid", "NEON-assigned growth form; gates which phenophases are recorded and whether one orderly leaf cycle per year is expected.",
  "obs", "nativeStatusCode", "character", "", "N | I | NI", "Native status: N = native, I = introduced, NI = native and introduced.",
  "obs", "is_species", "logical", "", "TRUE | FALSE", "TRUE if resolved to species level (and not a 'sp.'/slash ambiguity). Filter to TRUE for any species-level summary.",

  # 2. onsets (per individualID x year; key_onsets() + left_censored)
  "onsets", "individualID", "character", "", "NEON tag", "Tagged plant individual; join key.",
  "onsets", "year", "integer", "calendar year", "e.g. 2015-2024", "Calendar year these onset dates belong to; one row per individual per monitored year.",
  "onsets", "scientificName", "character", "", "Genus species", "Taxon (joined for a self-contained table).",
  "onsets", "growthForm", "character", "", "see obs", "NEON growth form.",
  "onsets", "greenup", "numeric", "day-of-year", "1-366; NA if no green-up phase reached 'yes'", "Green-up onset: EARLIEST interval-censored onset across green-up phenophases. Interval-censored = midpoint between last preceding 'no' and first 'yes'; may be a .5. If no preceding 'no', left-censored to first 'yes' (see left_censored).",
  "onsets", "flower", "numeric", "day-of-year", "1-366; NA if 'Open flowers' never 'yes'", "Flowering onset: interval-censored onset for 'Open flowers'.",
  "onsets", "leaf_off", "numeric", "day-of-year", "1-366; NA if 'Leaves'=='yes' never recorded", "LAST day 'Leaves' was 'yes' that year. WARNING: last leaf-WEEK observed, NOT measured senescence; meaningless for multi-flush/drought-deciduous plants. First 'Colored leaves' deliberately NOT used.",
  "onsets", "leaf_active", "integer", "days", ">=7 in multiples of 7; NA if no 'Leaves' yes", "Days the plant actually carried leaves = (distinct weeks with 'Leaves'=='yes') x 7. A summed presence extent, NOT a green-up-to-leaf-off span; honest for multi-flush plants. Quantized to 7-day units. NOTE: leaf_off MINUS greenup is NOT leaf_active and will not reconcile for multi-flush plants. CADENCE-SENSITIVE: has a hard 7-day floor (one scored leaf-week -> 7 days) and undercounts at sites with sparse visits (a leaf-present week never visited is never credited), so it is honest but not visit-cadence-immune.",
  "onsets", "left_censored", "logical", "", "TRUE | FALSE", "TRUE if the earliest visit was already 'yes' for a green-up phenophase (no preceding 'no'). Then greenup equals the first 'yes' and TRUE onset is EARLIER than shown; exclude or model as censored for onset-timing analysis. SCOPE is GREEN-UP only; NA when greenup is NA — do NOT filter left_censored==FALSE to clean flower/leaf_off/leaf_active rows (those are uncensored regardless).",

  # 3. individual_summary (one row per individualID; medians across years)
  "individual_summary", "individualID", "character", "", "NEON tag", "Tagged plant individual; primary key.",
  "individual_summary", "scientificName", "character", "", "Genus species", "Taxon.",
  "individual_summary", "growthForm", "character", "", "see obs", "NEON growth form.",
  "individual_summary", "plotID", "character", "", "NEON plot code", "Phenology plot / spatial block.",
  "individual_summary", "lat", "numeric", "decimal degrees (WGS84)", ">=6 dp", "Plant/plot latitude (NEON publishes plot-level, possibly fuzzed locations).",
  "individual_summary", "lng", "numeric", "decimal degrees (WGS84)", ">=6 dp", "Plant/plot longitude (see lat caveat).",
  "individual_summary", "nativeStatusCode", "character", "", "N | I | NI", "Native status.",
  "individual_summary", "greenup", "numeric", "day-of-year", "1-366; NA if never observed", "MEDIAN across the individual's years of per-year greenup (rounded). Collapses year-to-year variation and any left-censoring.",
  "individual_summary", "flower", "numeric", "day-of-year", "1-366; NA", "Median across years of flowering onset (rounded).",
  "individual_summary", "leaf_off", "numeric", "day-of-year", "1-366; NA", "Median across years of leaf_off (rounded); same 'last leaf-week, not senescence' caveat.",
  "individual_summary", "leaf_active", "numeric", "days", ">=0; NA", "Median across years of leaf_active days (rounded).",
  "individual_summary", "n_years", "integer", "count", ">=1", "Number of distinct years with ANY finite key metric (greenup/flower/leaf_off/leaf_active) — i.e. years watched, NOT necessarily the n behind each specific median (a green-up median may rest on fewer years than leaf_active). Small n_years means sparse monitoring.",

  # 4. clock / weekly_yesrate (one row per phenophaseName x week; n>=5 gate)
  "clock", "phenophaseName", "character", "", "see PHE_PHENOPHASE_DECODE", "Phenophase whose weekly active-share is summarized.",
  "clock", "week", "integer", "week-of-year", "1-52 (final partial week folded into 52)", "Week of year (7-day bins from Jan 1).",
  "clock", "yes", "integer", "count", ">=0", "Number of DISTINCT plants recorded 'yes' for this phenophase in this week (a plant visited twice in a week counts once), POOLED ACROSS ALL YEARS (and the selected species, or all).",
  "clock", "n", "integer", "count", ">=5 (rows with n<5 suppressed)", "Denominator: DISTINCT plants with a yes-or-no record for this phenophase-week (PLANT-weighted, not visit-weighted; uncertain excluded). Weeks with n<5 distinct plants dropped.",
  "clock", "rate", "numeric", "percent", "0-100, one decimal", "100 * yes / n: percent of monitored PLANTS in this phenophase this week (plant-weighted), pooled across years. A TIMING signal, NOT abundance.",

  # 5. onset_trend (one row per scientificName x year; n>=3 gate)
  "onset_trend", "scientificName", "character", "", "Genus species (species-level only)", "Species whose green-up trend is tracked.",
  "onset_trend", "year", "integer", "calendar year", "e.g. 2015-2024", "Calendar year of the annual onset point (NOT pooled, by design).",
  "onset_trend", "onset", "numeric", "day-of-year", "1-366 (rounded)", "MEDIAN across that species' individuals of per-individual green-up onset for that year. Compare across years, not within.",
  "onset_trend", "n", "integer", "count", ">=3 (species-years with n<3 suppressed)", "Distinct individuals contributing to that species-year; an unbalanced n across years means the trend partly reflects which individuals were monitored when."
)

# ---- (B) plain-language decode for every phenophaseName -------------------
PHE_PHENOPHASE_DECODE <- c(
  "Breaking leaf buds"   = "Broadleaf green-up onset: leaf buds have broken and a green leaf tip is visible, but leaves have not yet unfolded.",
  "Increasing leaf size" = "Young broadleaf leaves are unfolding and still expanding toward full size.",
  "Leaves"               = "Fully developed (mature, unfolded) leaves are present — the main leaf-on phenophase used for leaf_off and leaf_active.",
  "Colored leaves"       = "Leaves have changed to autumn (non-green) color; NEON may log this for a few early-stressed leaves, so first-coloration is not a reliable whole-plant senescence date.",
  "Falling leaves"       = "Leaves are actively dropping from the plant (autumn leaf fall in progress).",
  "Open flowers"         = "Open, fresh flowers are present with reproductive parts visible — the flowering-onset phenophase.",
  "Open pollen cones"    = "Conifer pollen (male) cones are open and shedding pollen — the conifer analog of flowering.",
  "Fruits"               = "Fruits or seed cones are present (intensity for this phase uses COUNT bins, not percent-of-canopy).",
  "Emerging needles"     = "Conifer green-up onset: new needles are emerging from breaking needle buds but not yet elongated.",
  "Breaking needle buds" = "Conifer needle buds have broken and new needle growth is just becoming visible.",
  "Young needles"        = "New conifer needles are elongating toward full size but not yet mature.",
  "Young leaves"         = "Newly emerged broadleaf leaves that are not yet fully expanded/mature.",
  "Initial growth"       = "Herbaceous (forb/graminoid) green-up onset: new basal/initial vegetative growth has emerged at the start of the season."
)

# ---- (C) provenance / methods block (site/version/date filled at export) --
PHE_PROVENANCE <- list(
  data_product      = "DP1.10055.001",
  data_product_name = "Plant phenology observations",
  source            = "NEON (National Ecological Observatory Network), data.neonscience.org",
  unit_of_analysis  = "tagged plant individual (repeated-measures across weeks and years); plotID = spatial block. Observations are NOT independent: cluster/random-effect by individualID nested in plotID.",
  status_handling   = "phenophaseStatus retained as yes/no/uncertain; 'missed' dropped at bundle time. 'uncertain' kept in obs but EXCLUDED from every yes-share denominator and all onset computations.",
  onset_rule        = "Onset is interval-censored to the midpoint between the last preceding 'no' day and the first 'yes' day, reflecting up-to-twice-weekly visits. With no preceding 'no', left-censored to the first 'yes' (true onset earlier; see onsets$left_censored). greenup = earliest such onset across green-up phenophases.",
  leaf_active_rule  = "leaf_active = (distinct weeks with 'Leaves'=='yes') x 7 days. A summed leaf-presence extent (honest for multi-flush/drought-deciduous plants), NOT a green-up-to-leaf-off span. leaf_off = last day 'Leaves'=='yes' = last leaf-week observed, NOT measured senescence.",
  intensity_rule    = "intensity is an ORDINAL, phenophase-specific bin recorded only when status=='yes'. Bins are incommensurable across phenophases: do NOT average bin midpoints, and do NOT mix intensity across phenophases.",
  caveats           = c(
    "TIMING, not abundance: a fixed roster of tagged individuals is scored for WHEN phenophases occur; rates and counts here do not measure how common a species is.",
    "The clock (weekly_yesrate) POOLS all years into one average calendar by design; for between-year shifts use onset_trend.",
    "individual_summary fields are medians-of-per-year values; onset_trend$onset is a median across individuals per species-year. Both collapse within-group variance, so n must travel with any point.",
    "Suppression gates: clock rows need n>=5 DISTINCT PLANTS/phenophase-week (plant-weighted, not visit-weighted); onset_trend points need n>=3 individuals/species-year. Suppressed cells are absent rows, NOT zeros.",
    "Left-censored onsets bias greenup LATE; not-sampled / not-yet-reached phenophases appear as NA, distinct from a structural 'no'.",
    "GREEN-UP COVERAGE varies by biome: in warm deserts the green-up PHENOPHASE itself is scored for only ~1/5 of plants (drought-deciduous/cactus/evergreen forms are logged straight into 'Leaves'), so a desert median_greenup rests on a small, non-random subsample. Pair it with the green-up coverage share and read leaf_active, which survives where green-up collapses.",
    "CROSS-SITE onset comparisons are not cadence-controlled: sites differ in effective visit frequency, so part of an onset difference between two sites can be censoring geometry, not plant biology (the phenology analog of detection probability). leaf_active is likewise visit-cadence-sensitive (7-day floor; undercounts at sparse-visit sites).",
    "Coordinates are NEON-published plot locations (may be fuzzed); treat as plot-level."
  ),
  site         = NA_character_,
  app_version  = NA_character_,
  export_date  = NA_character_,
  neon_release = NA_character_
)

# Build a single multi-section codebook data.frame ready to write as one CSV.
phe_codebook_csv <- function(site = NA_character_, app_version = NA_character_) {
  prov <- PHE_PROVENANCE; prov$site <- site; prov$app_version <- app_version
  prov$export_date <- as.character(Sys.Date())
  meta <- data.frame(
    table = "_provenance",
    column = c("data_product", "data_product_name", "source", "unit_of_analysis",
               "status_handling", "onset_rule", "leaf_active_rule", "intensity_rule",
               paste0("caveat_", seq_along(prov$caveats)), "site", "app_version", "export_date"),
    type = "", units = "", allowed_values = "",
    definition = c(prov$data_product, prov$data_product_name, prov$source, prov$unit_of_analysis,
                   prov$status_handling, prov$onset_rule, prov$leaf_active_rule, prov$intensity_rule,
                   prov$caveats, prov$site %||% "", prov$app_version %||% "", prov$export_date),
    stringsAsFactors = FALSE)
  decode <- data.frame(
    table = "_phenophase_decode", column = names(PHE_PHENOPHASE_DECODE),
    type = "", units = "", allowed_values = "",
    definition = unname(PHE_PHENOPHASE_DECODE), stringsAsFactors = FALSE)
  rbind(as.data.frame(PHE_CODEBOOK_ROWS), decode, meta)
}
