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
  "obs", "year", "integer", "calendar year", "e.g. 2016-2024", "Calendar year of the observation, parsed from the date; the grouping unit for per-year onset.",
  "obs", "date", "Date", "", "ISO YYYY-MM-DD", "Observation (visit) date; observers visit a fixed roster about weekly, up to 2 or 3 times a week during fast transitions.",
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
  "onsets", "year", "integer", "calendar year", "e.g. 2016-2024", "Calendar year these onset dates belong to; one row per individual per monitored year.",
  "onsets", "scientificName", "character", "", "Genus species", "Taxon (joined for a self-contained table).",
  "onsets", "growthForm", "character", "", "see obs", "NEON growth form.",
  "onsets", "greenup", "numeric", "day-of-year", "1-366; NA if no green-up phase reached 'yes'", "Green-up onset: EARLIEST interval-censored onset across the bud-break phenophases (Breaking leaf buds, Initial growth, Emerging needles, Breaking needle buds). For Drought deciduous broadleaf, which NEON never scores for bud-break, a plant-year with no bud-break onset falls back to its first 'Young leaves' onset after a 'no' (see greenup_source). Interval-censored = midpoint between last preceding 'no' and first 'yes'; may be a .5. Carry-over rule: when a phase is 'yes' at the first visit of the year and the plant's last visit of the previous year (at most 31 days earlier) was also 'yes', those are leaves carried over from December, so the onset is the first later no-to-yes transition (NA if none; see carryover); when that December visit was 'no', the onset is the midpoint across the new year, clamped to day 1. With no visit in the 31 days before a first-visit 'yes', left-censored to that first 'yes' (see left_censored). A growth form with at least 35% of its (>= 10) onsets on or after day 274 at a site (SJER and SOAP forbs and graminoids, which sprout with autumn rain), or with at least 35% of its (>= 10) plant-years carried over from December (LAJA graminoids and semi-evergreen broadleaf, SERC semi-evergreen broadleaf), has no calendar-year green-up there and is NA.",
  "onsets", "greenup_lo", "numeric", "day-of-year", "1-366; NA when left_censored or greenup is NA", "Lower end of the visit bracket around greenup, from the same phase as greenup: the last 'no' day before the first 'yes' (for a carried-over plant-year, the 'no' of the later no-to-yes transition; for an onset bridged across the new year, day 1). NA when the onset is left-censored: the true onset could be any earlier day.",
  "onsets", "greenup_hi", "numeric", "day-of-year", "1-366; NA when greenup is NA", "Upper end of the visit bracket around greenup: the first 'yes' day of the onset (the later transition's 'yes' for a carried-over plant-year). greenup lies between greenup_lo and greenup_hi; the bracket bounds visit spacing and censoring, not sampling error.",
  "onsets", "greenup_source", "character", "", "bud-break | young-leaves; NA when greenup is NA", "Which phenophase set greenup for this plant-year: a bud-break phase, or the Young-leaves fallback for drought-deciduous shrubs. Evergreen broadleaf - no leaf buds (e.g. Larrea), cacti and leafless evergreens have no green-up: their Young leaves are a rain flush on a plant that already carries leaves. A young-leaves value is a slightly later stage than bud-break and is kept out of onset_trend.",
  "onsets", "carryover", "logical", "", "TRUE | FALSE", "TRUE when the plant-year's green-up phase was already 'yes' at the first visit and also 'yes' at the plant's last visit of the previous year (at most 31 days earlier): the leaves carried over from December, so greenup is the first later no-to-yes transition, not a January onset.",
  "onsets", "flower", "numeric", "day-of-year", "1-366; NA if 'Open flowers' never 'yes'", "Flowering onset: interval-censored onset for 'Open flowers'.",
  "onsets", "leaf_off", "numeric", "day-of-year", "1-366; NA if 'Leaves'=='yes' never recorded", "LAST day 'Leaves' was 'yes' that year. WARNING: last leaf-WEEK observed, NOT measured senescence; meaningless for multi-flush/drought-deciduous plants. First 'Colored leaves' deliberately NOT used.",
  "onsets", "leaf_active", "numeric", "days", ">=0; NA if no 'Leaves' yes", "Days the plant carried leaves: the interval-censored span of each run of consecutive 'Leaves'=='yes' visits, from the midpoint after the previous 'no' (else the first yes) to the midpoint before the next 'no' (else the last yes), summed over runs. A run touching the year's first (last) visit is bridged across the new year when the plant's nearest Leaves visit on the other side is at most 31 days away: a 'yes' there extends the run to the year boundary, a 'no' to the midpoint (clamped to the boundary), so a plant in leaf all year gets exactly 365 or 366 days. An unbridged edge is flagged (leaf_edge_start, leaf_edge_end) and the span is then a lower bound (see leaf_active_hi). Valid for multi-flush plants (each flush counts separately) and robust to a missed mid-season visit. NOT a green-up-to-leaf-off span: leaf_off MINUS greenup will not reconcile for multi-flush plants.",
  "onsets", "leaf_edge_start", "logical", "", "TRUE | FALSE; NA if no 'Leaves' yes", "TRUE when the plant was already in leaf at its first Leaves visit of the year and no Leaves visit of the previous year lies within 31 days before it: the leaf run's start is unknown, so leaf_active counts only from that first visit.",
  "onsets", "leaf_edge_end", "logical", "", "TRUE | FALSE; NA if no 'Leaves' yes", "TRUE when the plant was still in leaf at its last Leaves visit of the year and no Leaves visit of the next year lies within 31 days after it: the leaf run's end is unknown, so leaf_active counts only to that last visit.",
  "onsets", "leaf_active_hi", "numeric", "days", ">=leaf_active, <=366; NA if no 'Leaves' yes", "Longest leaf span the visits allow within the year: leaf_active plus the unwatched days between an unbridged edge and the year boundary (first visit day - 1 for a start edge; year length + 1 - last visit day for an end edge). Equals leaf_active when neither edge is flagged.",
  "onsets", "leaf_weeks", "integer", "days", ">=7 in multiples of 7; NA if no 'Leaves' yes", "QC column: distinct weeks with 'Leaves'=='yes' x 7, the earlier leaf_active definition. It tracks visit effort (a week never visited is never credited), so use it only to check leaf_active, never as a season length.",
  "onsets", "greenup_supported", "logical", "", "TRUE | FALSE", "TRUE when this site-year counts for the onset metrics (greenup, flower): the site was watched for at least 3 seasons, the median plant had at least 0.75 of the site's typical count of visited weeks, and the year did not start more than 30 days after the site's typical first visit with its green-up truncated (at least half of that year's green-up onsets already underway at the first visit, or green-up coverage below half the site's typical). A late but untruncated year, such as a snowy spring, stays supported. FALSE years (for example the 2020 COVID reduction) stay in this table but are EXCLUDED from individual_summary, onset_trend and the site index.",
  "onsets", "leaf_supported", "logical", "", "TRUE | FALSE", "TRUE when this site-year counts for the leaf metrics (leaf_active, leaf_weeks, leaf_off): the same short-record and visit-effort tests as greenup_supported, but a late first visit makes the year unsupported only when at least half of its plant-years were already in leaf at that visit (the leaf span would be truncated). See site_year_support.csv for both reasons per year.",
  "onsets", "left_censored", "logical", "", "TRUE | FALSE", "TRUE if the green-up phase was already 'yes' at the first visit and no visit in the 31 days before it was scored (see the carry-over rule under greenup). Then greenup equals the first 'yes', greenup_lo is NA and the TRUE onset is EARLIER than shown. Do not drop these rows: dropping censored onsets biases the median late. The site and species summaries bound it instead: a censored plant-year's lower bound is open (minus infinity), and when at least half the plants' bounds are open the summary reads 'day greenup_hi or earlier' (greenup_status upper_bound). SCOPE is green-up only; NA when greenup is NA.",

  # 3. individual_summary (one row per individualID; medians across years)
  "individual_summary", "individualID", "character", "", "NEON tag", "Tagged plant individual; primary key.",
  "individual_summary", "scientificName", "character", "", "Genus species", "Taxon.",
  "individual_summary", "growthForm", "character", "", "see obs", "NEON growth form.",
  "individual_summary", "taxonRank", "character", "", "e.g. species | subspecies | variety | genus | family; NA", "NEON-assigned taxonomic rank of the identification. Coarser-than-species ranks (genus/family) mean the plant was not resolved to species; pairs with is_species.",
  "individual_summary", "is_species", "logical", "", "TRUE | FALSE", "TRUE if resolved to species level (rank species/subspecies/variety/speciesGroup AND not a 'sp.'/slash ambiguity). Filter to TRUE for any species-level summary.",
  "individual_summary", "plotID", "character", "", "NEON plot code", "Phenology plot / spatial block.",
  "individual_summary", "lat", "numeric", "decimal degrees (WGS84)", ">=6 dp", "Plant/plot latitude (NEON publishes plot-level, possibly fuzzed locations).",
  "individual_summary", "lng", "numeric", "decimal degrees (WGS84)", ">=6 dp", "Plant/plot longitude (see lat caveat).",
  "individual_summary", "nativeStatusCode", "character", "", "N | I | NI", "Native status.",
  "individual_summary", "greenup", "numeric", "day-of-year", "1-366; NA if never observed", "MEDIAN across the individual's SUPPORTED years of per-year greenup (rounded). Collapses year-to-year variation and any left-censoring. A NA here can be STRUCTURAL (this growth form is rarely scored for a green-up phenophase, e.g. desert evergreens); read greenup_n_years to tell structural-zero from a missing record.",
  "individual_summary", "flower", "numeric", "day-of-year", "1-366; NA", "Median across years of flowering onset (rounded). NA may be structural (never flowers in the monitored window); see flower_n_years.",
  "individual_summary", "leaf_off", "numeric", "day-of-year", "1-366; NA", "Median across years of leaf_off (rounded); same 'last leaf-week, not senescence' caveat.",
  "individual_summary", "leaf_active", "numeric", "days", ">=0; NA", "Median across SUPPORTED years of leaf_active days (rounded). See leaf_active_n_years for the contributing-year count.",
  "individual_summary", "leaf_active_hi", "numeric", "days", ">=leaf_active; NA", "Median across SUPPORTED years of onsets$leaf_active_hi (rounded): the longest leaf span the visits allow. Far above leaf_active when the plant's runs often touch an unbridged first or last visit.",
  "individual_summary", "leaf_edge_years", "integer", "count", ">=0", "Supported years with a finite leaf_active whose span touches an unbridged edge (onsets$leaf_edge_start or leaf_edge_end): the years where leaf_active is a lower bound.",
  "individual_summary", "leaf_active_lower_bound", "logical", "", "TRUE | FALSE; NA when leaf_active is NA", "TRUE when leaf_active_hi - leaf_active >= 14 days: unbridged edges could hide two weeks or more, so read leaf_active as 'at least' that many days, not as the full leaf period.",
  "individual_summary", "greenup_source", "character", "", "bud-break | young-leaves; NA", "Most common greenup_source across the plant's supported years with a finite green-up (see onsets$greenup_source).",
  "individual_summary", "greenup_lc_years", "integer", "count", ">=0", "Supported years whose green-up onset was left-censored (already 'yes' at the first visit). Compare with greenup_n_years: a high ratio means the greenup median is an upper bound.",
  "individual_summary", "n_years_watched", "integer", "count", ">=1", "Distinct years with any key metric, INCLUDING unsupported years. n_years counts supported years only.",
  "individual_summary", "greenup_n_years", "integer", "count", ">=0", "Number of the individual's monitored years that produced a FINITE green-up onset (the n behind the greenup median). 0 means green-up was NEVER resolvable for this plant, so greenup==NA is a STRUCTURAL absence (phenophase not scored), not a sampling gap.",
  "individual_summary", "flower_n_years", "integer", "count", ">=0", "Years contributing a finite flowering onset (the n behind the flower median). 0 -> flower==NA is structural (no 'Open flowers' ever recorded), not a missing record.",
  "individual_summary", "leaf_active_n_years", "integer", "count", ">=0", "Years contributing a finite leaf_active value (the n behind the leaf_active median). 0 -> no 'Leaves'=='yes' ever recorded for this plant.",
  "individual_summary", "n_years", "integer", "count", ">=0", "Number of distinct SUPPORTED years with ANY finite key metric (greenup/flower/leaf_off/leaf_active), i.e. years watched, NOT necessarily the n behind each specific median (a green-up median may rest on fewer years than leaf_active; see the per-metric *_n_years columns). Small n_years means sparse monitoring.",

  # 4. clock / weekly_yesrate (one row per phenophaseName x week; n>=5 gate)
  "clock", "phenophaseName", "character", "", "see PHE_PHENOPHASE_DECODE", "Phenophase whose weekly active-share is summarized.",
  "clock", "week", "integer", "week-of-year", "1-52 (final partial week folded into 52)", "Week of year (7-day bins from Jan 1).",
  "clock", "yes", "integer", "count", ">=0", "Number of scored PLANT-YEAR-WEEK opportunities recorded 'yes' for this phenophase. Multiple visits to one plant in the same year/week count once (any 'yes' wins); the same plant scored in another year is a separate opportunity.",
  "clock", "n", "integer", "count", ">=5 (rows with n<5 suppressed)", "Denominator: scored individual x phenophase x year x week opportunities with a yes-or-no record (PLANT-YEAR-weighted, not visit-weighted; uncertain excluded). Weeks with n<5 opportunities are dropped.",
  "clock", "rate", "numeric", "percent", "0-100, one decimal", "100 * yes / n: percent of scored PLANT-YEAR opportunities 'yes' for this phenophase/week, pooled into a descriptive typical-year profile. A TIMING signal, NOT abundance or a population trend.",

  # 5. onset_trend (one row per scientificName x year; n>=3 gate)
  "onset_trend", "scientificName", "character", "", "Genus species (species-level only)", "Species whose green-up trend is tracked.",
  "onset_trend", "year", "integer", "calendar year", "e.g. 2016-2024", "Calendar year of the annual onset point (NOT pooled, by design).",
  "onset_trend", "onset", "numeric", "day-of-year", "1-366 (rounded)", "MEDIAN across that species' individuals of per-individual green-up onset for that year. Compare across years, not within.",
  "onset_trend", "n", "integer", "count", ">=3 (species-years with n<3 suppressed)", "Distinct individuals contributing to that species-year; an unbalanced n across years means the trend partly reflects which individuals were monitored when.",
  "onset_trend", "lc_share", "numeric", "proportion", "0-1, three decimals", "Share of that species-year's plant-year onsets that were left-censored (already 'yes' at the first visit). At 0.5 or above the median has no lower bound (with k of n censored, 2k >= n), so the app draws the point hollow and fits the trend without it, reporting how many points were left out and whether the direction depends on them."
)

# ---- (B) plain-language decode for every phenophaseName -------------------
PHE_PHENOPHASE_DECODE <- c(
  "Breaking leaf buds"   = "Broadleaf green-up onset: leaf buds have broken and a green leaf tip is visible, but leaves have not yet unfolded.",
  "Increasing leaf size" = "Young broadleaf leaves are unfolding and still expanding toward full size.",
  "Leaves"               = "Fully developed (mature, unfolded) leaves are present, the main leaf-on phenophase used for leaf_off and leaf_active.",
  "Colored leaves"       = "Leaves have changed to autumn (non-green) color; NEON may log this for a few early-stressed leaves, so first-coloration is not a reliable whole-plant senescence date.",
  "Falling leaves"       = "Leaves are actively dropping from the plant (autumn leaf fall in progress).",
  "Open flowers"         = "Open, fresh flowers are present with reproductive parts visible, the flowering-onset phenophase.",
  "Open pollen cones"    = "Conifer pollen (male) cones are open and shedding pollen, the conifer analog of flowering.",
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
  license           = "Source: NEON DP1.10055.001, CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/); aggregated and derived by this app.",
  unit_of_analysis  = "tagged plant individual (repeated-measures across weeks and years); plotID = spatial block. Observations are NOT independent: cluster/random-effect by individualID nested in plotID.",
  status_handling   = "phenophaseStatus retained as yes/no/uncertain; 'missed' dropped at bundle time. 'uncertain' kept in obs but EXCLUDED from every yes-share denominator and all onset computations.",
  onset_rule        = "Onset is interval-censored to the midpoint between the last preceding 'no' day and the first 'yes' day, reflecting visits about weekly, up to 2 or 3 times a week during fast transitions; greenup_lo and greenup_hi keep that bracket. With no preceding 'no', left-censored to the first 'yes' (true onset earlier, greenup_lo NA; see onsets$left_censored). greenup = earliest such onset across the bud-break phenophases, with the first 'Young leaves' onset as a per-plant-year fallback for Drought deciduous broadleaf (greenup_source records which), under the 31-day carry-over rule (see onsets$greenup). Site and species green-up summaries are two-stage (per plant over supported years, then across plants): the published value is the median of the plants' median onsets; greenup_hi is the same median of the first 'yes' days and greenup_lo of the last 'no' days, with a left-censored plant-year's lower bound open (minus infinity), so the value lies between them. Status point when greenup_hi - greenup_lo < 14 days (one weekly visit interval plus one week of censoring; label 'day N'), range otherwise (label 'day A to B'), upper_bound when greenup_lo is open (at least half the plants' brackets open below; label 'day greenup_hi or earlier', the numeric value withheld) or short_record (fewer than 3 seasons). The bracket bounds visit spacing and censoring; it is not a confidence interval.",
  support_rule      = "A site watched fewer than 3 seasons has no supported year (reason short_record). A year whose first visit came more than 30 days after the site's typical first visit is late_start for green-up only when at least half of its green-up onsets were already underway at that visit or its green-up coverage fell below half the site's typical, and late_start for the leaf metrics only when at least half of its plant-years were already in leaf at that visit (greenup_supported and leaf_supported are separate flags). Otherwise a site-year is SUPPORTED when the median per-plant count of distinct visited weeks is >= 0.75 of the site's typical (median across its years) AND the first visit is no more than 30 days after the site's typical first visit. Only supported years enter medians, trends and the site index; all years stay in the onsets table with greenup_supported and leaf_supported.",
  leaf_active_rule  = "leaf_active = interval-censored span of each run of 'Leaves'=='yes' visits (midpoint to midpoint), summed per plant-year and summarized over SUPPORTED site-years only. A run touching the year's first or last Leaves visit is bridged across the new year when the plant's nearest visit on the other side is at most 31 days away (a 'yes' extends it to the boundary, a 'no' to the clamped midpoint); spans are built on every year before the supported ones are kept, so a low-effort neighbour year still closes an edge. An unbridged edge is flagged (leaf_edge_start, leaf_edge_end) and leaf_active_hi adds the unwatched days to the year boundary. The site value is two-stage (median of the plants' median leaf_active); leaf_active_hi is the same median of the plants' median leaf_active_hi; status lower_bound (label 'at least N days') when leaf_active_hi exceeds the value by 14 days or more, else point (label 'N days'); leaf_edge_share is the share of the supported plant-years with an unbridged edge. leaf_weeks keeps the earlier (distinct weeks with 'Leaves'=='yes') x 7 as a QC column; it tracks visit effort (within-site correlation 0.73 with visited weeks) and is not a season length. A summed leaf-presence extent (valid for multi-flush and drought-deciduous plants), NOT a green-up-to-leaf-off span. leaf_off = last day 'Leaves'=='yes' = last leaf-week observed, NOT measured senescence.",
  intensity_rule    = "intensity is an ORDINAL, phenophase-specific bin recorded only when status=='yes'. Bins are incommensurable across phenophases: do NOT average bin midpoints, and do NOT mix intensity across phenophases.",
  caveats           = c(
    "TIMING, not abundance: a fixed roster of tagged individuals is scored for WHEN phenophases occur; rates and counts here do not measure how common a species is.",
    "The clock (weekly_yesrate) POOLS scored plant-year-week opportunities into one average calendar by design; repeated visits collapse within a plant-year-week, years remain separate opportunities, and between-year shifts belong in onset_trend.",
    "individual_summary fields are medians-of-per-year values; onset_trend$onset is a median across individuals per species-year. Both collapse within-group variance, so n must travel with any point.",
    "Suppression gates: clock rows need n>=5 scored PLANT-YEAR opportunities/phenophase-week (plant-year-weighted, not visit-weighted; uncertain excluded); onset_trend points need n>=3 individuals/species-year. Suppressed cells are absent rows, NOT zeros.",
    "Left-censored onsets bias greenup LATE; not-sampled / not-yet-reached phenophases appear as NA, distinct from a structural 'no'.",
    "GREEN-UP COVERAGE varies by biome: drought-deciduous shrubs are scored for 'Young leaves' rather than bud-break, so their green-up is that first new flush (greenup_source == 'young-leaves'); evergreen shrubs without leaf buds, cacti, leafless evergreens and annuals that sprout with autumn rain have no calendar-year green-up. Pair median_greenup with the green-up coverage share and read leaf_active where coverage is thin.",
    "This export CANNOT give: a calendar-year green-up for evergreens, cacti or autumn-sprouting annuals; a Young-leaves green-up that is the same day-for-day event as bud-break; a confidence interval from a green-up range (the range bounds visit spacing and censoring, not sampling error); a green-up where most plants were already greening at the first visit, or from fewer than three seasons; the full leaf period from a value that reads 'at least N days'; a trend direction that flips depending on how censoring-heavy points are treated; a leaf-active slope through lower-bound sites.",
    "CROSS-SITE onset comparisons are not cadence-controlled: sites differ in effective visit frequency, so part of an onset difference between two sites can be censoring geometry, not plant biology (the phenology analog of detection probability). leaf_active edges are bridged across the new year when a Leaves visit on the other side lies within 31 days; an unbridged edge (no such visit) makes that span a lower bound, flagged by leaf_edge_start or leaf_edge_end and reported as 'at least N days' when leaf_active_hi exceeds it by 14 days or more.",
    "Coordinates are NEON-published plot locations (may be fuzzed); treat as plot-level."
  ),
  site         = NA_character_,
  app_version  = NA_character_,
  export_date  = NA_character_,
  neon_release = NA_character_,
  neon_doi     = NA_character_
)

# Build a single multi-section codebook data.frame ready to write as one CSV.
phe_codebook_csv <- function(site = NA_character_, app_version = NA_character_) {
  prov <- PHE_PROVENANCE; prov$site <- site; prov$app_version <- app_version
  prov$export_date <- as.character(Sys.Date())
  # the NEON release pinned for the bundles, when R/site_metadata.R defines it
  rel <- if (exists("PHE_RELEASE")) get("PHE_RELEASE") else NULL
  prov$neon_release <- if (!is.null(rel) && !is.null(rel[["tag"]])) as.character(rel[["tag"]]) else NA_character_
  prov$neon_doi <- if (!is.null(rel) && !is.null(rel[["doi"]])) as.character(rel[["doi"]]) else NA_character_
  meta <- data.frame(
    table = "_provenance",
    column = c("data_product", "data_product_name", "source", "license", "unit_of_analysis",
               "status_handling", "onset_rule", "support_rule", "leaf_active_rule", "intensity_rule",
               paste0("caveat_", seq_along(prov$caveats)), "site", "app_version", "export_date",
               "neon_release", "neon_doi"),
    type = "", units = "", allowed_values = "",
    definition = c(prov$data_product, prov$data_product_name, prov$source, prov$license, prov$unit_of_analysis,
                   prov$status_handling, prov$onset_rule, prov$support_rule, prov$leaf_active_rule, prov$intensity_rule,
                   prov$caveats, prov$site %||% "", prov$app_version %||% "", prov$export_date,
                   prov$neon_release, prov$neon_doi),
    stringsAsFactors = FALSE)
  decode <- data.frame(
    table = "_phenophase_decode", column = names(PHE_PHENOPHASE_DECODE),
    type = "", units = "", allowed_values = "",
    definition = unname(PHE_PHENOPHASE_DECODE), stringsAsFactors = FALSE)
  rbind(as.data.frame(PHE_CODEBOOK_ROWS), decode, meta)
}
