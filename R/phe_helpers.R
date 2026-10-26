# ===========================================================================
# NEON Plant Phenology Explorer — phe_helpers.R
# The unit is a TAGGED plant individual with a weekly-resolution, multi-year
# phenophase career (a near-twin of the veg-structure tree career). Onset is
# interval-censored (weekly obs) -> midpoint between last 'no' and first 'yes'.
# The Phenology Clock pools years by design; onset trends must NOT pool (the
# never-pool rule). See docs/neonize-playbook.md.
# ===========================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
# most common value; ties break by C-locale (radix) order so bytes match across platforms
mode_chr <- function(x){ x<-as.character(x[!is.na(x)]); if(!length(x)) return(NA_character_)
  tb <- table(factor(x, levels = sort(unique(x), method = "radix"))); names(tb)[which.max(tb)] }
short_ind <- function(id) sub("^NEON\\.PLA\\.D[0-9]{2}\\.", "", as.character(id))
short_plot <- function(p) sub("^[A-Z]{4}_", "", as.character(p))

species_level_only <- function(d){ if (is.null(d)||!nrow(d)) return(d)
  if ("is_species" %in% names(d)) return(d[d$is_species %in% TRUE, , drop=FALSE])
  ok <- is.na(d$taxonRank)|d$taxonRank %in% c("species","subspecies","variety","speciesGroup"); d[ok,,drop=FALSE] }
# A categorical palette that NEVER interpolates Dark2 past its 8 discrete hues
# (interpolating across ~20 categories produces muddy, indistinguishable olives).
# Returns up to `cap` distinct Dark2 colours; an explicit grey "Other" bucket
# catches everything past the cap. `groups` should already be ordered so the most
# important (e.g. most-monitored) categories take the distinct colours.
OTHER_GREY <- "#9aa6b2"
capped_pal <- function(groups, cap = 8L) {
  g <- groups[!is.na(groups) & nzchar(groups)]
  if (!length(g)) return(stats::setNames(character(0), character(0)))
  keep <- utils::head(g, cap)
  cols <- RColorBrewer::brewer.pal(max(3L, min(8L, length(keep))), "Dark2")[seq_along(keep)]
  pal <- stats::setNames(cols, keep)
  c(pal, stats::setNames(OTHER_GREY, "Other"))
}
# ordered category vector for a frame `d` on column `col`, most-frequent first
# (so capped_pal hands the distinct hues to the categories that matter most).
ordered_levels <- function(d, col) {
  v <- as.character(d[[col]]); v <- v[!is.na(v) & nzchar(v)]
  if (!length(v)) return(character(0))
  names(sort(table(v), decreasing = TRUE))
}
# bucket a category vector to the cap: anything past the top `cap` -> "Other".
cap_groups <- function(x, levels_ordered, cap = 8L) {
  keep <- utils::head(levels_ordered, cap)
  x <- as.character(x); x[is.na(x) | !nzchar(x)] <- "Other"
  ifelse(x %in% keep, x, "Other")
}
make_species_pal <- function(d){ capped_pal(ordered_levels(d, "scientificName"), cap = 8L) }

# ordered phenophase sequence (for the clock rings + out-of-order QC). Higher rank
# = later in the season. Growth-form-specific phenophases share this ordering.
PHENO_RANK <- c("Breaking leaf buds"=1, "Emerging needles"=1, "Breaking needle buds"=1,
                "Initial growth"=1, "Young needles"=2, "Increasing leaf size"=2, "Young leaves"=2,
                "Leaves"=3, "Open flowers"=4, "Open pollen cones"=4, "Colored leaves"=5,
                "Falling leaves"=6, "Fruits"=4)
GREENUP <- c("Breaking leaf buds","Initial growth","Emerging needles","Breaking needle buds")
SENESCE <- c("Colored leaves","Falling leaves")
# ---------------------------------------------------------------------------
# Green-up and leaf-active estimand (audit 2026-10-18 item 12; rules set by the
# iris phenology review, 2026-10-21). Every threshold is a named constant here.
# ---------------------------------------------------------------------------
# Drought-deciduous shrubs: NEON never scores a bud-break phenophase for this form
# (issue log 2022-11-15); its green-up is the year's first new "Young leaves".
# Per plant-year, and only when no bud-break onset exists; greenup_source records
# which phase set the value. "Evergreen broadleaf - no leaf buds" (Larrea) is NOT a
# fallback form: its Young leaves are a rain flush on a plant that already carries
# leaves (79% already 'yes' at the first January visit), so like cacti it has no
# calendar-year green-up, but it stays in the coverage denominator.
GREENUP_FALLBACK_FORMS <- c("Drought deciduous broadleaf")
GREENUP_FALLBACK_PHASE <- "Young leaves"
# Partial-year (carry-over) rule. A phase already 'yes' at a plant's first visit of
# the year is checked against the plant's LAST visit of the previous year, when
# that visit was at most CARRYOVER_GAP days earlier: previous 'yes' means the
# leaves carried over from December, so the onset is the first later no-to-yes
# transition (else no green-up that year); previous 'no' bounds the onset to the
# new-year gap (midpoint, clamped to day 1), so it is not censored. Longer gaps
# (the usual winter break at seasonal sites) stay left-censored.
CARRYOVER_GAP <- 31
# Autumn-germinating forms. A growth form whose onsets mostly fall in autumn has
# its season split across two calendar years (SJER and SOAP annual grasses and
# forbs sprout with autumn rain), so a calendar-year green-up is not meaningful:
# a form with at least AUTUMN_MIN_N plant-years and at least AUTUMN_SHARE of its
# onsets on or after AUTUMN_DOY (Oct 1) is dropped from green-up at that site and
# read by leaf-active instead. Only SJER and SOAP forbs and graminoids qualify.
AUTUMN_DOY <- 274
AUTUMN_SHARE <- 0.35
AUTUMN_MIN_N <- 10
# Carry-over-dominated forms (hk review, iris sign-off). A carried-over plant-year
# takes the year's next flush, which for a form that is green across the new year
# most years is a different event from green-up (LAJA grasses: 56% of plant-years
# carry over). A form with at least CARRY_FORM_MIN_N plant-years and at least
# CARRY_FORM_SHARE of them carried over has no calendar-year green-up at that site.
CARRY_FORM_SHARE <- 0.35
CARRY_FORM_MIN_N <- 10
# Site-year support gate. A plant-year is only comparable with the site's other
# years when the site was visited on its usual schedule that year: the 2020-2021
# COVID reduction (NEON issue log 2020-11-19) halves visited weeks at most sites,
# which reads as a shorter leaf season and a later onset although nothing about
# the plants changed. A site-year is SUPPORTED when the median per-plant count of
# distinct visited weeks is at least SUPPORT_WEEK_RATIO of the site's typical
# (median across its years) AND scoring started no more than SUPPORT_LATE_START
# days after the site's typical first visit (a late start truncates the onsets it
# can see). A site with fewer than SUPPORT_MIN_YEARS watched years cannot be
# checked against itself, so every year is unsupported (reason short_record).
# Unsupported plant-years stay in the per-plant-year export (greenup_supported,
# leaf_supported FALSE) and are excluded from medians, trends and the site index.
SUPPORT_WEEK_RATIO <- 0.75
SUPPORT_LATE_START <- 30
SUPPORT_MIN_YEARS <- 3
# A late first visit only matters when it truncated what that metric could see,
# so the late-start test is per metric (hk review, iris sign-off). A late but
# untruncated year (a snowy spring at TEAK) is real, and dropping it biased site
# medians early. Green-up: the late year is unsupported when at least
# LATE_START_LC of its green-up onsets were already underway at the first visit,
# or its green-up coverage is below LATE_START_COVERAGE of the site's typical
# (bud-break ended before the first visit: NOGP 2016). Leaf metrics: the late
# year is unsupported when at least LATE_START_LC of its plant-years were already
# in leaf at the first visit (the leaf span is truncated: SRER 2021 read 212 days
# against a site median of 357).
LATE_START_LC <- 0.5
LATE_START_COVERAGE <- 0.5
# Visit-interval bounds (iris sign-off 2026-10-21, scripts/headline_rules.md sections 6 to 9). A
# green-up is bracketed by the last 'no' (lo) and the first 'yes' (hi) around it;
# the site value is a two-stage median of the midpoints and lies between the
# two-stage medians of lo and hi. BOUND_POINT_TOL is one weekly visit interval for
# the bracket itself plus one week of censoring, so a weekly-visited, uncensored
# site still reads as one day. It is used three ways: a green-up is a point when
# hi - lo < BOUND_POINT_TOL; a leaf-active value is a lower bound when
# hi - value >= BOUND_POINT_TOL; a leaf trend point is hollow when
# onset_hi - onset >= BOUND_POINT_TOL. A left-censored lo is -Inf, and a site lo
# of -Inf reads "day hi or earlier" with the numeric value withheld (NA) from the
# map, gradient and indexes.
BOUND_POINT_TOL <- 14
# A median of n values with k censored on one side has no bound on that side
# exactly when 2k >= n (R's median), that is when the censored share is at least
# BOUND_SHARE: a green-up trend point with lc_share >= BOUND_SHARE is hollow.
BOUND_SHARE <- 0.5
# Years with a solid (not hollow) trend point needed before any trend verdict; a
# shorter series reads "too short". One constant so a later review can move it.
TREND_MIN_YEARS <- 6

# NEON leaves dayOfYear blank on some valid-date rows (Oct 2016 to Mar 2017 at
# eight sites, ~15k rows); every onset filters on dayOfYear, so derive it from
# the date instead of dropping the visit. Idempotent and cheap; the bundler does
# this at build time and rebuild_indexes repairs older committed bundles.
normalize_doy <- function(obs) {
  if (is.null(obs) || !nrow(obs) || !all(c("dayOfYear", "date") %in% names(obs))) return(obs)
  miss <- is.na(obs$dayOfYear) & !is.na(obs$date)
  if (!any(miss)) return(obs)
  d <- suppressWarnings(as.Date(as.character(obs$date[miss])))
  obs$dayOfYear[miss] <- as.integer(format(d, "%j"))
  obs
}

# visit date of each row: the recorded date, else rebuilt from year + dayOfYear
# (fixtures and older tables may carry no date column)
obs_dates <- function(obs) {
  d <- if ("date" %in% names(obs)) {
    if (inherits(obs$date, "Date")) obs$date else suppressWarnings(as.Date(as.character(obs$date)))
  } else rep(as.Date(NA), nrow(obs))
  miss <- is.na(d) & is.finite(obs$year) & is.finite(obs$dayOfYear)
  if (any(miss))
    d[miss] <- as.Date(sprintf("%d-01-01", as.integer(obs$year[miss]))) + (as.integer(obs$dayOfYear[miss]) - 1L)
  d
}

# visit week of a day-of-year (1..53): the unit of the clock, the support gate and
# the leaf_weeks QC column, shared so every surface bins the same way.
doy_week <- function(doy) (as.integer(doy) - 1L) %/% 7L + 1L

site_year_support <- function(obs, week_ratio = SUPPORT_WEEK_RATIO, late_start = SUPPORT_LATE_START,
                              min_years = SUPPORT_MIN_YEARS, gu = NULL) {
  d <- obs[is.finite(obs$dayOfYear) & is.finite(obs$year), c("individualID", "year", "dayOfYear"), drop = FALSE]
  if (!nrow(d)) return(tibble::tibble(year = integer(), med_weeks = numeric(), typical_weeks = numeric(),
                                      week_ratio = numeric(), first_doy = numeric(), typical_first = numeric(),
                                      lc_share = numeric(), greenup_coverage_ratio = numeric(),
                                      leaf_first_share = numeric(),
                                      greenup_supported = logical(), leaf_supported = logical(),
                                      greenup_reason = character(), leaf_reason = character()))
  d$wk <- doy_week(d$dayOfYear)
  per_plant <- d %>% dplyr::distinct(.data$individualID, .data$year, .data$wk) %>%
    dplyr::count(.data$individualID, .data$year, name = "weeks")
  yr <- per_plant %>% dplyr::group_by(.data$year) %>%
    dplyr::summarise(med_weeks = stats::median(.data$weeks), n_plants = dplyr::n(), .groups = "drop")
  first <- d %>% dplyr::group_by(.data$year) %>% dplyr::summarise(first_doy = min(.data$dayOfYear), .groups = "drop")
  yr <- dplyr::left_join(yr, first, by = "year")
  yr$typical_weeks <- stats::median(yr$med_weeks)
  yr$typical_first <- stats::median(yr$first_doy)
  yr$week_ratio <- yr$med_weeks / yr$typical_weeks
  low <- !(is.finite(yr$week_ratio) & yr$week_ratio >= week_ratio)
  late_date <- (yr$first_doy - yr$typical_first) > late_start
  short <- nrow(yr) < min_years
  key <- as.character(yr$year)
  # green-up truncation: censored share and coverage of that year's onsets
  # (gu = the site's green-up onsets, from greenup_onsets() or key_onsets())
  if (is.null(gu)) gu <- greenup_onsets(obs)
  k <- if (!is.null(gu) && nrow(gu) && all(c("year", "greenup", "left_censored") %in% names(gu)))
    gu[is.finite(gu$greenup), , drop = FALSE] else NULL
  lc_y <- if (!is.null(k) && nrow(k)) unname(tapply(k$left_censored %in% TRUE, k$year, mean)[key]) else rep(NA_real_, nrow(yr))
  n_gu <- if (!is.null(k) && nrow(k)) unname(tapply(k$individualID, k$year, function(x) length(unique(x)))[key]) else rep(NA_real_, nrow(yr))
  n_gu[is.na(n_gu)] <- 0
  cov_y <- n_gu / yr$n_plants
  typical_cov <- stats::median(cov_y)
  cov_ratio <- if (is.finite(typical_cov) && typical_cov > 0) cov_y / typical_cov else rep(NA_real_, nrow(yr))
  # leaf truncation: share of plant-years already in leaf at their first visit
  lv <- obs[obs$phenophaseName == "Leaves" & obs$status %in% c("yes", "no") & is.finite(obs$dayOfYear),
            c("individualID", "year", "dayOfYear", "status"), drop = FALSE]
  leaf_first <- if (nrow(lv)) {
    f <- lv %>% dplyr::group_by(.data$individualID, .data$year) %>%
      dplyr::summarise(first_yes = { m <- min(.data$dayOfYear); any(.data$status[.data$dayOfYear == m] == "yes") },
                       .groups = "drop")
    unname(tapply(f$first_yes, f$year, mean)[key])
  } else rep(NA_real_, nrow(yr))
  yr$lc_share <- round(as.numeric(lc_y), 3)
  yr$greenup_coverage_ratio <- round(as.numeric(cov_ratio), 3)
  yr$leaf_first_share <- round(as.numeric(leaf_first), 3)
  late_gu <- late_date & (is.na(lc_y) | lc_y >= LATE_START_LC |
                            (is.finite(cov_ratio) & cov_ratio < LATE_START_COVERAGE))
  late_la <- late_date & (is.na(leaf_first) | leaf_first >= LATE_START_LC)
  # one reason per year and metric (precedence short_record > low_effort >
  # late_start); built by assignment, never ifelse() on the scalar `short`,
  # which would recycle the first year's reason over every year
  label <- function(late) { r <- rep("supported", nrow(yr)); r[late] <- "late_start"; r[low] <- "low_effort"
    if (short) r[] <- "short_record"; r }
  yr$greenup_reason <- label(late_gu)
  yr$leaf_reason <- label(late_la)
  yr$greenup_supported <- yr$greenup_reason == "supported"
  yr$leaf_supported <- yr$leaf_reason == "supported"
  yr$n_plants <- NULL
  yr[order(yr$year), , drop = FALSE]
}
# Each phenophase gets a DISTINCT colour (no duplicate hexes — overlapping petals
# must stay separable). The leaf stages ramp green but shift HUE as well as
# lightness (yellow-green onset -> blue-green full leaves) so they don't collapse
# into one band under colour-vision deficiency; the reproductive + senescence
# phenophases escape the green band entirely onto CVD-safe distinct hues —
# flowers magenta, pollen cones steel-blue, fruits violet, colored leaves warm
# orange, falling leaves rust — so the senescence/reproductive phenophases never
# read as leaf-green under protan/deutan (the failure the prior ramp had). Every
# pair clears dE>=14 under deutan AND protan (CVD-tuned + verified, chart review).
pheno_palette <- c(
  "Breaking leaf buds"  = "#cfe8a0", "Initial growth"      = "#b3db7a",
  "Breaking needle buds"= "#c2e08c", "Emerging needles"    = "#97cf6a",
  "Increasing leaf size"= "#69b33f", "Young leaves"        = "#7abf4a",
  "Young needles"       = "#52a23a", "Leaves"              = "#147a4a",
  "Open flowers"        = "#c8417a", "Open pollen cones"   = "#3f7faf",
  "Fruits"              = "#6a3fa0", "Colored leaves"      = "#d9701a",
  "Falling leaves"      = "#a83c14")

COL_OF_PHENO <- function(p) unname(ifelse(p %in% names(pheno_palette), pheno_palette[p], "#9aa6b2"))

# ---------------------------------------------------------------------------
# onset(): first 'yes' day-of-year per individual x phenophase x year, interval-
# censored to the midpoint between the last preceding 'no' and the first 'yes'.
# Returns one row per (individualID, phenophaseName, year).
# ---------------------------------------------------------------------------
onset <- function(obs, phenophases = NULL) {
  d <- obs[obs$status %in% c("yes","no") & !is.na(obs$dayOfYear), , drop=FALSE]
  if (!is.null(phenophases)) d <- d[d$phenophaseName %in% phenophases, , drop=FALSE]
  if (!nrow(d)) return(NULL)
  d %>% dplyr::group_by(.data$individualID, .data$scientificName, .data$growthForm, .data$phenophaseName, .data$year) %>%
    dplyr::summarise(onset_doy = {
        yes <- .data$dayOfYear[.data$status == "yes"]; no <- .data$dayOfYear[.data$status == "no"]
        if (!length(yes)) NA_real_ else { f <- min(yes); pno <- no[no < f]
          if (length(pno)) (max(pno) + f) / 2 else f } },   # midpoint of the interval (or left-censored = first yes)
      # left-censored = a 'yes' with NO preceding 'no', so true onset is earlier
      # than recorded (the first visit already caught the phenophase active).
      left_censored = {
        yes <- .data$dayOfYear[.data$status == "yes"]; no <- .data$dayOfYear[.data$status == "no"]
        if (!length(yes)) NA else !length(no[no < min(yes)]) },
      first_yes = if (any(.data$status=="yes")) min(.data$dayOfYear[.data$status=="yes"]) else NA_real_,
      .groups = "drop") %>%
    dplyr::filter(is.finite(.data$onset_doy))
}

# green-up / flowering / leaf-off / leaf-active per individual per year.
# leaf_off = last day "Leaves" was recorded 'yes'. We do NOT use first 'Colored
# leaves' as senescence: NEON records it for a few early-stressed leaves (e.g.
# day 163 in June), which makes first-coloration a wildly early marker.
# leaf_active = distinct weeks with leaves present x 7 ≈ days the plant actually
# carries leaves. This is the honest growing-extent metric for EVERY growth form:
# greenup→leaf_off would span ~300 days for a drought-deciduous desert plant that
# flushes and drops several times a year, whereas leaf_active sums only the weeks
# leaves are really present (~110 days). So the Onset Lab uses leaf_active, not a
# green-up-to-leaf-off span.
# Defensive at the 46-site scale: a site may lack green-up, flowering, or leaf
# records entirely — each branch falls back to an empty keyed tibble so a missing
# phenophase never crashes the join (it just yields NA columns).
# Interval-censored onset per plant x phase x year with the carry-over rule (see
# CARRYOVER_GAP). Same midpoint rule as onset(), plus: when the phase is already
# 'yes' at the first visit, the plant's last visit of the previous year decides
# whether that 'yes' is carried-over leaves (previous 'yes': onset is the first
# later no-to-yes transition, else NA), a bridged new-year onset (previous 'no':
# clamped midpoint, not censored) or a genuinely left-censored onset (no visit
# within CARRYOVER_GAP days). One record per visit day; 'yes' wins a same-day
# conflict, exactly as in onset().
# onset_lo and onset_hi bracket the onset (scripts/headline_rules.md section 2): standard, the last
# 'no' before the first 'yes' (NA when left-censored) and that first 'yes';
# bridged, day 1 (the December 'no' expressed as a day of this year, clamped to 1)
# and the first January 'yes'; carried over, the later no-to-yes pair (both NA when
# there is no later transition, like onset_doy).
onset_carry <- function(obs, phenophases, max_gap = CARRYOVER_GAP) {
  d <- obs[obs$status %in% c("yes", "no") & is.finite(obs$dayOfYear) &
             obs$phenophaseName %in% phenophases, , drop = FALSE]
  if (!nrow(d)) return(NULL)
  d$visit_date <- obs_dates(d)
  d <- d[!is.na(d$visit_date), , drop = FALSE]
  if (!nrow(d)) return(NULL)
  v <- d %>%
    dplyr::group_by(.data$individualID, .data$phenophaseName, .data$year, .data$visit_date) %>%
    dplyr::summarise(doy = min(.data$dayOfYear), yes = any(.data$status == "yes"), .groups = "drop") %>%
    dplyr::arrange(.data$individualID, .data$phenophaseName, .data$visit_date)
  yr <- v %>% dplyr::group_by(.data$individualID, .data$phenophaseName, .data$year) %>%
    dplyr::summarise(
      first_date = dplyr::first(.data$visit_date), first_yes = dplyr::first(.data$yes),
      last_date = dplyr::last(.data$visit_date), last_yes = dplyr::last(.data$yes),
      onset_std = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]
        if (!length(y)) NA_real_ else { f <- min(y); p <- n[n < f]; if (length(p)) (max(p) + f) / 2 else f } },
      lc_std = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]
        if (!length(y)) NA else !any(n < min(y)) },
      lo_std = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]
        if (!length(y)) NA_real_ else { p <- n[n < min(y)]; if (length(p)) as.numeric(max(p)) else NA_real_ } },
      hi_std = { y <- .data$doy[.data$yes]; if (!length(y)) NA_real_ else as.numeric(min(y)) },
      onset_later = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]; f <- .data$doy[1]
        n1 <- n[n > f]
        if (!length(n1)) NA_real_ else { y2 <- y[y > min(n1)]
          if (!length(y2)) NA_real_ else { y2 <- min(y2); (max(n[n < y2]) + y2) / 2 } } },
      lo_later = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]; f <- .data$doy[1]
        n1 <- n[n > f]
        if (!length(n1)) NA_real_ else { y2 <- y[y > min(n1)]
          if (!length(y2)) NA_real_ else as.numeric(max(n[n < min(y2)])) } },
      hi_later = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]; f <- .data$doy[1]
        n1 <- n[n > f]
        if (!length(n1)) NA_real_ else { y2 <- y[y > min(n1)]
          if (!length(y2)) NA_real_ else as.numeric(min(y2)) } },
      .groups = "drop")
  prev <- yr %>% dplyr::transmute(.data$individualID, .data$phenophaseName, year = .data$year + 1L,
                                  prev_date = .data$last_date, prev_yes = .data$last_yes)
  yr <- dplyr::left_join(yr, prev, by = c("individualID", "phenophaseName", "year"))
  near <- !is.na(yr$prev_date) & as.numeric(yr$first_date - yr$prev_date) <= max_gap
  carry <- near & yr$first_yes %in% TRUE & yr$prev_yes %in% TRUE
  bridged <- near & yr$first_yes %in% TRUE & yr$prev_yes %in% FALSE
  onset_doy <- yr$onset_std; lc <- yr$lc_std; lo <- yr$lo_std; hi <- yr$hi_std
  if (any(bridged)) {
    jan1 <- as.Date(sprintf("%d-01-01", as.integer(yr$year[bridged])))
    prev_doy <- as.numeric(yr$prev_date[bridged] - jan1) + 1   # <= 0: days before Jan 1
    onset_doy[bridged] <- pmax(1, (prev_doy + yr$onset_std[bridged]) / 2)
    lo[bridged] <- pmax(1, prev_doy)
    lc[bridged] <- FALSE
  }
  onset_doy[carry] <- yr$onset_later[carry]; lc[carry] <- FALSE
  lo[carry] <- yr$lo_later[carry]; hi[carry] <- yr$hi_later[carry]
  tibble::tibble(individualID = yr$individualID, phenophaseName = yr$phenophaseName, year = yr$year,
                 onset_doy = onset_doy, onset_lo = lo, onset_hi = hi, left_censored = lc, carryover = carry)
}

# green-up per plant-year: earliest bud-break onset, else (drought-deciduous
# shrubs only) the first Young-leaves onset, both under the carry-over rule; then
# growth forms whose onsets mostly fall in autumn are dropped (AUTUMN_*). One row
# per plant-year with greenup, its visit bracket (greenup_lo, greenup_hi, from
# the same phase row), left_censored, carryover and greenup_source; the
# dropped forms ride along as attr(, "autumn_forms"). Shared by key_onsets(),
# onset_trend() and site_species_onsets() so every green-up surface agrees.
greenup_onsets <- function(obs) {
  ek <- tibble::tibble(individualID = character(), year = integer(), greenup = numeric(),
                       greenup_lo = numeric(), greenup_hi = numeric(),
                       left_censored = logical(), carryover = logical(), greenup_source = character())
  ph <- onset_carry(obs, c(GREENUP, GREENUP_FALLBACK_PHASE))
  if (is.null(ph) || !nrow(ph)) return(NULL)
  forms <- obs[!duplicated(obs$individualID), c("individualID", "growthForm"), drop = FALSE]
  ph$growthForm <- as.character(forms$growthForm[match(ph$individualID, forms$individualID)])
  # carry-over share per growth form over EVERY plant-year with a scored green-up
  # phase (a carried-over year with no later flush counts too), all years
  rel <- ph[ph$phenophaseName %in% GREENUP |
              (ph$phenophaseName %in% GREENUP_FALLBACK_PHASE & ph$growthForm %in% GREENUP_FALLBACK_FORMS), , drop = FALSE]
  carry_tab <- if (nrow(rel)) rel %>%
      dplyr::group_by(.data$individualID, .data$year, .data$growthForm) %>%
      dplyr::summarise(c = any(.data$carryover), .groups = "drop") %>%
      dplyr::group_by(.data$growthForm) %>%
      dplyr::summarise(n = dplyr::n(), carry = mean(.data$c), .groups = "drop")
    else tibble::tibble(growthForm = character(), n = integer(), carry = numeric())
  ph <- ph[is.finite(ph$onset_doy), , drop = FALSE]
  collapse <- function(o, src) {
    if (!nrow(o)) return(ek)
    o %>% dplyr::group_by(.data$individualID, .data$year) %>%
      dplyr::summarise(greenup = min(.data$onset_doy),
                       # the bracket comes from the same phase row as the value
                       greenup_lo = .data$onset_lo[which.min(.data$onset_doy)],
                       greenup_hi = .data$onset_hi[which.min(.data$onset_doy)],
                       left_censored = .data$left_censored[which.min(.data$onset_doy)],
                       carryover = .data$carryover[which.min(.data$onset_doy)], .groups = "drop") %>%
      dplyr::mutate(greenup_source = src)
  }
  bud <- collapse(ph[ph$phenophaseName %in% GREENUP, , drop = FALSE], "bud-break")
  yl <- collapse(ph[ph$phenophaseName %in% GREENUP_FALLBACK_PHASE &
                      ph$growthForm %in% GREENUP_FALLBACK_FORMS, , drop = FALSE], "young-leaves")
  if (nrow(yl)) yl <- dplyr::anti_join(yl, bud, by = c("individualID", "year"))
  out <- dplyr::bind_rows(bud, yl)
  if (!nrow(out)) return(NULL)
  out$growthForm <- as.character(forms$growthForm[match(out$individualID, forms$individualID)])
  tab <- out %>% dplyr::group_by(.data$growthForm) %>%
    dplyr::summarise(n = dplyr::n(), autumn = mean(.data$greenup >= AUTUMN_DOY), .groups = "drop")
  autumn_forms <- sort(tab$growthForm[!is.na(tab$growthForm) & tab$n >= AUTUMN_MIN_N & tab$autumn >= AUTUMN_SHARE],
                       method = "radix")
  carry_forms <- sort(setdiff(carry_tab$growthForm[!is.na(carry_tab$growthForm) & carry_tab$n >= CARRY_FORM_MIN_N &
                                                     carry_tab$carry >= CARRY_FORM_SHARE], autumn_forms), method = "radix")
  out <- out[!out$growthForm %in% c(autumn_forms, carry_forms), setdiff(names(out), "growthForm"), drop = FALSE]
  out <- out[order(out$individualID, out$year, method = "radix"), , drop = FALSE]
  attr(out, "autumn_forms") <- autumn_forms
  attr(out, "carry_forms") <- carry_forms
  if (!nrow(out)) return(structure(ek, autumn_forms = autumn_forms, carry_forms = carry_forms))
  out
}

# Leaf-active days per plant-year: the interval-censored span of 'Leaves' = yes.
# Each run of consecutive yes visits counts from the midpoint after the previous
# 'no' (else the first yes) to the midpoint before the next 'no' (else the last
# yes); runs are summed, so a shrub that flushes twice with the rains is credited
# two short seasons, not one 300-day season, and a missed mid-season visit does
# not shorten the season (weeks-with-yes x 7 did: it tracked visit effort, with
# a within-site correlation of 0.73 against visited weeks). leaf_weeks keeps the
# old weeks-with-yes x 7 as a QC column. leaf_off = last 'Leaves' = yes day.
leaf_run_span <- function(doy, yes) {
  if (!any(yes)) return(NA_real_)
  r <- rle(yes); ends <- cumsum(r$lengths); starts <- ends - r$lengths + 1L
  total <- 0
  for (k in which(r$values)) {
    a <- if (starts[k] > 1L) (doy[starts[k] - 1L] + doy[starts[k]]) / 2 else doy[starts[k]]
    b <- if (ends[k] < length(doy)) (doy[ends[k]] + doy[ends[k] + 1L]) / 2 else doy[ends[k]]
    total <- total + (b - a)
  }
  total
}
# Year-boundary bridge (scripts/headline_rules.md section 7). A run that touches the year's first
# or last Leaves visit is censored there unless a visit across the new year closes
# it: the plant's last Leaves visit of the previous year (or first of the next) at
# most CARRYOVER_GAP (31) days away, the same gap as the green-up carry-over rule.
# A 'yes' across the boundary moves the run's edge to the boundary itself (day 1,
# or day ylen + 1); a 'no' moves it to the midpoint, clamped to the boundary. With
# no such visit the edge is flagged (leaf_edge_start, leaf_edge_end) and
# leaf_active_hi adds the unwatched days between the edge and the boundary: the
# longest span the visits allow, so leaf_active is then a lower bound. Every year's
# visits feed the bridge (a year with no 'yes', supported or not), so callers pass
# all years and filter afterwards. Within-year runs are exactly leaf_run_span().
leaf_spans <- function(obs) {
  ek <- tibble::tibble(individualID = character(), year = integer(), leaf_active = numeric(),
                       leaf_weeks = integer(), leaf_off = numeric(), leaf_edge_start = logical(),
                       leaf_edge_end = logical(), leaf_active_hi = numeric())
  d <- obs[obs$phenophaseName == "Leaves" & obs$status %in% c("yes", "no") & is.finite(obs$dayOfYear),
           c("individualID", "year", "dayOfYear", "status"), drop = FALSE]
  if (!nrow(d)) return(ek)
  v <- d %>% dplyr::group_by(.data$individualID, .data$year, .data$dayOfYear) %>%
    dplyr::summarise(yes = any(.data$status == "yes"), .groups = "drop") %>%
    dplyr::arrange(.data$individualID, .data$year, .data$dayOfYear)
  # every plant-year's first and last Leaves visit, 'yes' or not (the bridge ends)
  ends <- v %>% dplyr::group_by(.data$individualID, .data$year) %>%
    dplyr::summarise(first_day = dplyr::first(.data$dayOfYear), first_yes = dplyr::first(.data$yes),
                     last_day = dplyr::last(.data$dayOfYear), last_yes = dplyr::last(.data$yes),
                     .groups = "drop")
  out <- v %>% dplyr::group_by(.data$individualID, .data$year) %>%
    dplyr::summarise(leaf_active = leaf_run_span(.data$dayOfYear, .data$yes),
                     leaf_weeks = dplyr::n_distinct(doy_week(.data$dayOfYear[.data$yes])) * 7L,
                     leaf_off = if (any(.data$yes)) as.numeric(max(.data$dayOfYear[.data$yes])) else NA_real_,
                     .groups = "drop")
  out <- out[out$leaf_weeks > 0L, , drop = FALSE]
  if (!nrow(out)) return(ek)
  out <- dplyr::left_join(out, ends, by = c("individualID", "year"))
  prev <- dplyr::transmute(ends, .data$individualID, year = .data$year + 1L,
                           p_day = .data$last_day, p_yes = .data$last_yes)
  nxt <- dplyr::transmute(ends, .data$individualID, year = .data$year - 1L,
                          q_day = .data$first_day, q_yes = .data$first_yes)
  out <- dplyr::left_join(out, prev, by = c("individualID", "year"))
  out <- dplyr::left_join(out, nxt, by = c("individualID", "year"))
  ylen <- function(y) ifelse((y %% 4L == 0L & y %% 100L != 0L) | y %% 400L == 0L, 366, 365)
  yl <- ylen(out$year)
  p_rel <- out$p_day - ylen(out$year - 1L)   # previous visit as a day <= 0 of this year
  q_rel <- out$q_day + yl                    # next visit as a day > ylen of this year
  near_s <- out$first_yes & !is.na(out$p_day) & (out$first_day - p_rel) <= CARRYOVER_GAP
  near_e <- out$last_yes & !is.na(out$q_day) & (q_rel - out$last_day) <= CARRYOVER_GAP
  near_s <- near_s %in% TRUE; near_e <- near_e %in% TRUE
  # a run touching the first (last) visit starts (ends) exactly there inside
  # leaf_run_span(), so the bridge only moves that one edge
  new_start <- ifelse(out$p_yes %in% TRUE, 1, pmax(1, (p_rel + out$first_day) / 2))
  new_end <- ifelse(out$q_yes %in% TRUE, yl + 1, pmin(yl + 1, (out$last_day + q_rel) / 2))
  out$leaf_active <- out$leaf_active + ifelse(near_s, out$first_day - new_start, 0) +
    ifelse(near_e, new_end - out$last_day, 0)
  out$leaf_edge_start <- out$first_yes & !near_s
  out$leaf_edge_end <- out$last_yes & !near_e
  out$leaf_active_hi <- out$leaf_active + (out$first_day - 1) * out$leaf_edge_start +
    (yl + 1 - out$last_day) * out$leaf_edge_end
  out[, names(ek), drop = FALSE]
}

key_onsets <- function(obs, support = NULL) {
  obs <- normalize_doy(obs)
  ek <- tibble::tibble(individualID = character(), year = integer())
  guo <- greenup_onsets(obs)
  gu <- if (!is.null(guo) && nrow(guo)) guo else
    dplyr::mutate(ek, greenup = numeric(), greenup_lo = numeric(), greenup_hi = numeric(),
                  left_censored = logical(), carryover = logical(), greenup_source = character())
  flo <- onset(obs, "Open flowers")
  fl <- if (!is.null(flo) && nrow(flo)) flo %>% dplyr::transmute(individualID, year, flower = .data$onset_doy)
        else dplyr::mutate(ek, flower = numeric())
  la <- leaf_spans(obs)
  out <- Reduce(function(a,b) dplyr::full_join(a,b,by=c("individualID","year")), list(gu, fl, la))
  if (is.null(out) || !nrow(out)) return(NULL)
  if (is.null(support)) support <- site_year_support(obs, gu = guo)
  # onset metrics (greenup, flower) follow the green-up support flag; the leaf
  # metrics (leaf_active, leaf_weeks, leaf_off) follow the leaf flag
  out$greenup_supported <- out$year %in% support$year[support$greenup_supported]
  out$leaf_supported <- out$year %in% support$year[support$leaf_supported]
  attr(out, "autumn_forms") <- attr(guo, "autumn_forms")
  attr(out, "carry_forms") <- attr(guo, "carry_forms")
  out
}

# green-up COVERAGE share: fraction of tagged plants that ever resolve a finite
# green-up onset. In warm deserts the green-up *phenophase* ("Breaking leaf buds"
# / "Initial growth") is rarely scored — drought-deciduous / cactus / evergreen
# plants are logged straight into "Leaves" — so a desert median_greenup rests on a
# small, non-random subsample (SRER 19%, JORN 54%) while leaf_active survives.
# This is the number behind the coverage badge; computed at runtime from the
# per-plant summary so it needs no bundle rebuild.
greenup_coverage <- function(ind_s) {
  if (is.null(ind_s) || !nrow(ind_s) || !("greenup" %in% names(ind_s))) return(NA_real_)
  n <- nrow(ind_s); if (!n) return(NA_real_)
  # no plant has a supported year (a short-record site): coverage is undefined,
  # not 0%, so no "0% of plants" badge appears beside "too few seasons"
  if ("n_years" %in% names(ind_s) && !any(ind_s$n_years > 0, na.rm = TRUE)) return(NA_real_)
  sum(is.finite(ind_s$greenup)) / n
}

# one row per individual: median green-up / leaf-active etc. (Onset Lab + picker)
individual_summary <- function(obs, inds) {
  ko <- key_onsets(obs); if (is.null(ko) || !nrow(ko)) return(NULL)
  med <- function(x) { v <- suppressWarnings(stats::median(x, na.rm = TRUE)); if (is.finite(v)) round(v) else NA_real_ }
  agg <- ko %>% dplyr::group_by(.data$individualID) %>%
    # COUNT columns come FIRST. Inside one summarise(), once `greenup` is reassigned
    # to its scalar median, a later `.data$greenup` is that scalar (is.finite -> 0/1),
    # so every *_n_years used to read 0 or 1 in every bundle. Keep the counts above
    # the reassignments (same rule as gu_share in plot_summary_phe). Onset metrics
    # use the green-up support flag, leaf metrics the leaf flag.
    dplyr::summarise(greenup_n_years     = sum(is.finite(.data$greenup) & .data$greenup_supported),
                     flower_n_years      = sum(is.finite(.data$flower) & .data$greenup_supported),
                     leaf_active_n_years = sum(is.finite(.data$leaf_active) & .data$leaf_supported),
                     # supported years with ANY key metric (leaf-only evergreens are not 0)
                     n_years = dplyr::n_distinct(.data$year[
                       (.data$greenup_supported & (is.finite(.data$greenup) | is.finite(.data$flower))) |
                       (.data$leaf_supported & (is.finite(.data$leaf_off) | is.finite(.data$leaf_active)))]),
                     greenup_lc_years = sum(.data$left_censored %in% TRUE & is.finite(.data$greenup) & .data$greenup_supported),
                     # supported leaf years whose span touches an unbridged edge (a count,
                     # so it stays above the leaf_active reassignment)
                     leaf_edge_years = sum(is.finite(.data$leaf_active) & .data$leaf_supported &
                                             (.data$leaf_edge_start %in% TRUE | .data$leaf_edge_end %in% TRUE)),
                     greenup_source = mode_chr(.data$greenup_source[is.finite(.data$greenup) & .data$greenup_supported]),
                     greenup = med(.data$greenup[.data$greenup_supported]),
                     flower = med(.data$flower[.data$greenup_supported]),
                     leaf_off = med(.data$leaf_off[.data$leaf_supported]),
                     leaf_active_hi = med(.data$leaf_active_hi[.data$leaf_supported]),
                     leaf_active = med(.data$leaf_active[.data$leaf_supported]),
                     .groups="drop")
  # the median span is a lower bound when the visits allow a much longer one
  # (scripts/headline_rules.md section 8 applied to one plant)
  agg$leaf_active_lower_bound <- ifelse(is.na(agg$leaf_active), NA,
                                        agg$leaf_active_hi - agg$leaf_active >= BOUND_POINT_TOL)
  # years watched regardless of support, so a plant whose only years were
  # unsupported still shows as watched (with n_years 0 and NA medians)
  watched <- ko %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(n_years_watched = dplyr::n_distinct(.data$year), .groups = "drop")
  out <- dplyr::left_join(inds, agg, by = "individualID")
  out <- dplyr::left_join(out, watched, by = "individualID")
  for (cc in c("greenup_n_years", "flower_n_years", "leaf_active_n_years", "n_years", "greenup_lc_years",
               "leaf_edge_years"))
    out[[cc]][is.na(out[[cc]]) & !is.na(out$n_years_watched)] <- 0L
  out[, c(names(inds), "greenup", "flower", "leaf_off", "leaf_active", "leaf_active_hi", "greenup_source",
          "greenup_n_years", "flower_n_years", "leaf_active_n_years", "greenup_lc_years",
          "leaf_edge_years", "leaf_active_lower_bound", "n_years", "n_years_watched"), drop = FALSE]
}

# share of SUPPORTED plant-year green-up onsets that were left-censored (already
# 'yes' at a first visit with no scored visit in the CARRYOVER_GAP before it).
# Reported beside the bounds; censored onsets are never dropped (dropping them
# biases the median late: SJER would move to November).
greenup_lc_share <- function(ko) {
  if (is.null(ko) || !nrow(ko) || !all(c("greenup", "left_censored", "greenup_supported") %in% names(ko))) return(NA_real_)
  k <- ko[ko$greenup_supported %in% TRUE & is.finite(ko$greenup), , drop = FALSE]
  if (!nrow(k)) return(NA_real_)
  round(mean(k$left_censored %in% TRUE), 3)
}
# share of plants whose green-up came from the Young-leaves fallback
greenup_fallback_share <- function(ind_s) {
  if (is.null(ind_s) || !nrow(ind_s) || !("greenup_source" %in% names(ind_s))) return(NA_real_)
  fin <- is.finite(ind_s$greenup); if (!any(fin)) return(NA_real_)
  round(mean(ind_s$greenup_source[fin] %in% "young-leaves"), 3)
}
# Two-stage green-up bounds over a set of plant-years (supported years with a
# finite green-up; one group = one site or one species at a site), scripts/headline_rules.md
# section 6. k needs individualID, greenup, greenup_lo, greenup_hi, left_censored.
#   per plant: mid = median green-up; lo = median last 'no' (a left-censored or
#     missing lo counts as -Inf); hi = median first 'yes'
#   site: value = median of the plants' mid; lo and hi = medians of their lo, hi
# The value lies between lo and hi. status: "upper_bound" (lo = -Inf: at least
# half the plants' brackets are open below), "point" (hi - lo < BOUND_POINT_TOL),
# "range" (finite lo), or "none". value is the number the map, gradient and
# indexes may use: NA unless point or range. lo is NA unless finite; hi is
# published whenever there are rows (it is the "or earlier" day of an upper bound).
greenup_bounds <- function(k) {
  none <- list(value = NA_real_, lo = NA_real_, hi = NA_real_, status = "none", n_plants = 0L)
  if (is.null(k) || !nrow(k)) return(none)
  k <- k[is.finite(k$greenup), , drop = FALSE]
  if (!nrow(k)) return(none)
  k$lo_b <- ifelse(k$left_censored %in% TRUE | !is.finite(k$greenup_lo), -Inf, k$greenup_lo)
  per <- k %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(mid = round(stats::median(.data$greenup)),
                     lo = stats::median(.data$lo_b),
                     hi = round(stats::median(.data$greenup_hi)),
                     .groups = "drop")
  per$lo <- ifelse(is.finite(per$lo), round(per$lo), per$lo)
  value <- round(stats::median(per$mid)); hi <- round(stats::median(per$hi))
  lo <- stats::median(per$lo); if (is.finite(lo)) lo <- round(lo)
  status <- if (!is.finite(lo)) "upper_bound" else if (hi - lo < BOUND_POINT_TOL) "point" else "range"
  list(value = if (status %in% c("point", "range")) value else NA_real_,
       lo = if (is.finite(lo)) lo else NA_real_, hi = hi, status = status, n_plants = nrow(per))
}
# plain-words headline for a green-up summary (value, lo, hi, status from
# greenup_bounds(), plus "short_record"): a point names the value, a range its
# visit bracket, an upper bound the median first 'yes'. The app adds the month
# and the explanation around it.
greenup_label <- function(value, lo, hi, status, n_seasons = NA_integer_) {
  switch(as.character(status %||% "none"),
    point = sprintf("day %d", as.integer(round(value))),
    range = sprintf("day %d to %d", as.integer(round(lo)), as.integer(round(hi))),
    upper_bound = sprintf("day %d or earlier", as.integer(round(hi))),
    short_record = if (is.finite(n_seasons)) sprintf("unavailable: %d season%s monitored, too few to check the schedule",
                                                     as.integer(n_seasons), if (n_seasons == 1) "" else "s")
                   else "unavailable: too few seasons monitored to check the schedule",
    NA_character_)
}

# Two-stage leaf-active summary (scripts/headline_rules.md section 8). k = plant-year rows that are
# leaf-supported with a finite leaf_active, carrying individualID, leaf_active,
# leaf_active_hi, leaf_edge_start and leaf_edge_end. Per plant n = median span and
# m = median longest-allowed span; value and hi are their medians across plants
# (value equals the median of individual_summary's leaf_active). "lower_bound"
# when hi - value >= BOUND_POINT_TOL (unbridged edges could hide that many more
# days), else "point"; "none" with no rows. edge_share = share of the rows with an
# unbridged edge (NA with no rows).
leaf_bounds <- function(k) {
  none <- list(value = NA_real_, hi = NA_real_, status = "none", edge_share = NA_real_, n_plants = 0L)
  if (is.null(k) || !nrow(k)) return(none)
  k <- k[is.finite(k$leaf_active), , drop = FALSE]
  if (!nrow(k)) return(none)
  per <- k %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(n = round(stats::median(.data$leaf_active)),
                     m = round(stats::median(.data$leaf_active_hi)), .groups = "drop")
  value <- round(stats::median(per$n)); hi <- round(stats::median(per$m))
  list(value = value, hi = hi, status = if (hi - value >= BOUND_POINT_TOL) "lower_bound" else "point",
       edge_share = round(mean(k$leaf_edge_start %in% TRUE | k$leaf_edge_end %in% TRUE), 3),
       n_plants = nrow(per))
}
# plain-words headline for a leaf-active summary
leaf_label <- function(value, status) {
  switch(as.character(status %||% "none"),
    point = sprintf("%d days", as.integer(round(value))),
    lower_bound = sprintf("at least %d days", as.integer(round(value))),
    NA_character_)
}

# ---------------------------------------------------------------------------
# Phenology Clock data: % of scored PLANT-YEAR opportunities 'yes' per
# phenophase/week-of-year, for one species (or all). Pools plant-year opportunities
# across years BY DESIGN (caption it), but never collapses a plant across years.
# Restricted to the phenophases that species' growth form actually records.
# ---------------------------------------------------------------------------
weekly_yesrate <- function(obs, sci = NULL) {
  d <- species_level_only(obs); d <- d[d$status %in% c("yes","no") & is.finite(d$dayOfYear), , drop=FALSE]
  if (!is.null(sci)) d <- d[d$scientificName %in% sci, , drop=FALSE]
  if (!nrow(d)) return(NULL)
  d$week <- pmin(52L, ((d$dayOfYear - 1L) %/% 7L) + 1L)
  # PLANT-YEAR-weighted, not visit-weighted or ever-yes weighted: a plant visited
  # twice in the same week/year counts ONCE, while that plant scored in the same
  # week in a second year is a second opportunity. Collapse to one row per
  # individual x phenophase x year x week; the plant-year counts 'yes' if ANY
  # visit in that cell was 'yes' (the phenophase was active that week/year).
  d <- d %>% dplyr::group_by(.data$individualID, .data$phenophaseName, .data$year, .data$week) %>%
    dplyr::summarise(plant_year_yes = any(.data$status == "yes"), .groups = "drop")
  d %>% dplyr::group_by(.data$phenophaseName, .data$week) %>%
    dplyr::summarise(yes = sum(.data$plant_year_yes), n = dplyr::n(), .groups="drop") %>%
    dplyr::mutate(rate = round(100 * .data$yes / .data$n, 1)) %>%
    dplyr::filter(.data$n >= 5)   # suppress sub-threshold weeks: a 100%-of-3 ring must not look as solid as 100%-of-1000 (n is scored plant-year opportunities/week)
}

# onset trend per species x year (the climate-shift signal — NOT pooled).
# Collapse to each individual's EARLIEST green-up per year FIRST (the same
# min-across-green-up-phenophases that key_onsets/individual_summary use), so a
# plant that records two green-up phenophases in a year (e.g. "Breaking leaf
# buds" + "Initial growth", or a conifer's needle pair) isn't pseudo-replicated
# into the species-year median and the trend matches the per-plant green-up.
onset_trend <- function(obs) {
  obs <- normalize_doy(obs)
  # Bud-break onsets only: the trend is a single-cycle onset series, and the
  # Young-leaves fallback forms flush with rain several times a year, so their
  # first flush of the calendar year is not a comparable annual onset. Those
  # sites lean on the leaf-active trend instead (audit 2026-10-18).
  g_all <- greenup_onsets(obs); if (is.null(g_all) || !nrow(g_all)) return(NULL)
  sup <- site_year_support(obs, gu = g_all)
  g <- g_all[g_all$greenup_source %in% "bud-break", , drop = FALSE]
  if (!nrow(g)) return(NULL)
  g <- g[g$year %in% sup$year[sup$greenup_supported], , drop = FALSE]   # supported site-years only
  if (!nrow(g)) return(NULL)
  sci <- obs[!duplicated(obs$individualID), c("individualID", "scientificName"), drop = FALSE]
  o <- dplyr::left_join(g, sci, by = "individualID") %>%
    dplyr::transmute(individualID, scientificName, year, onset_doy = .data$greenup,
                     left_censored = .data$left_censored)
  # lc_share = share of the species-year's plant-years left-censored; at
  # BOUND_SHARE or above the median has no lower bound (a hollow point)
  out <- o %>% dplyr::group_by(.data$scientificName, .data$year) %>%
    dplyr::summarise(onset = round(stats::median(.data$onset_doy)), n = dplyr::n_distinct(.data$individualID),
                     lc_share = round(mean(.data$left_censored %in% TRUE), 3), .groups="drop") %>%
    dplyr::filter(.data$n >= 3)   # >=3 individuals/species/year before a point is shown
  # A site can have green-up observations yet no species-year that clears the
  # support gate. Preserve that as an unavailable result, not a typed 0-row table:
  # bundle and UI contracts use NULL to distinguish "no supported trend" from a
  # trend table with meaningful rows.
  if (!nrow(out)) return(NULL)
  out
}

# leaf-active YEAR-trend: median days-carrying-leaves per species per year, the
# desert-safe companion to onset_trend(). leaf_active never touches the green-up
# phenophase, so this trend works at warm-desert sites (e.g. SRER: 7 years / 12
# species) where the green-up trend is too thin to fit. Same de-pseudoreplication
# as onset_trend (collapse to one leaf_active per individual-year first, then the
# species-year median); scientificName comes from obs (key_onsets drops it). The
# value column is named `onset` ON PURPOSE so trendPlot/trendInsight reuse the same
# machinery — it carries leaf-active DAYS here, not a day-of-year.
leaf_active_trend <- function(obs, support = NULL) {
  obs <- normalize_doy(obs)
  sup <- if (!is.null(support)) support else site_year_support(obs)
  # spans from ALL years first (the year-boundary bridge reads the neighbouring
  # years, supported or not), then the leaf-supported site-years only: filtering
  # first leaves a false edge (357 days instead of 361 for a plant in leaf all year)
  la <- leaf_spans(obs)
  la <- la[la$year %in% sup$year[sup$leaf_supported], , drop = FALSE]
  if (!nrow(la)) return(NULL)
  sci <- obs[!duplicated(obs$individualID), c("individualID", "scientificName"), drop = FALSE]
  la$scientificName <- sci$scientificName[match(la$individualID, sci$individualID)]
  # onset_hi = median longest span the visits allow; the point is hollow when it
  # exceeds onset by BOUND_POINT_TOL or more (trend_hollow)
  out <- la %>% dplyr::group_by(.data$scientificName, .data$year) %>%
    dplyr::summarise(onset = round(stats::median(.data$leaf_active)), n = dplyr::n_distinct(.data$individualID),
                     onset_hi = round(stats::median(.data$leaf_active_hi)), .groups="drop") %>%
    dplyr::filter(.data$n >= 3)
  if (!nrow(out)) return(NULL)
  out
}

# Hollow trend points (scripts/headline_rules.md section 9): a green-up point whose median has no
# lower bound (lc_share >= BOUND_SHARE), or a leaf point whose unbridged edges
# allow BOUND_POINT_TOL or more extra days (onset_hi - onset). Logical, never NA.
trend_hollow <- function(tr) {
  if (is.null(tr) || !nrow(tr)) return(logical(0))
  if ("lc_share" %in% names(tr)) return(!is.na(tr$lc_share) & tr$lc_share >= BOUND_SHARE)
  if ("onset_hi" %in% names(tr)) { w <- tr$onset_hi - tr$onset; return(!is.na(w) & w >= BOUND_POINT_TOL) }
  rep(FALSE, nrow(tr))
}
# Trend verdict (scripts/headline_rules.md section 9). Fit A = lm(year median ~ year) over the solid
# points only (the year median is the median of that year's solid species
# points); fit B = the same over every point as recorded. Fewer than min_years
# years with a solid point -> "too_short". A's 95% CI (slope -/+ qt(0.975, ny - 2)
# x se) spanning zero -> "none". A and B both excluding zero on the same side ->
# "up" (positive slope: later green-up or a longer leaf season) or "down",
# reported from A. A excluding zero while B does not, or points the other way ->
# "depends" (the direction rests on the left-out points). n_left_out = hollow
# points; site_yr = fit A's year medians.
trend_verdict <- function(tr, hollow = trend_hollow(tr), min_years = TREND_MIN_YEARS) {
  yr_med <- function(d) {
    if (!nrow(d)) return(tibble::tibble(year = integer(), onset = numeric()))
    d %>% dplyr::group_by(.data$year) %>%
      dplyr::summarise(onset = stats::median(.data$onset), .groups = "drop")
  }
  fit <- function(sy) {
    na <- list(slope = NA_real_, lo = NA_real_, hi = NA_real_)
    if (nrow(sy) < 3L || diff(range(sy$year)) == 0) return(na)
    co <- summary(stats::lm(onset ~ year, data = sy))$coefficients
    if (nrow(co) < 2L || !is.finite(co[2, 2])) return(na)
    tc <- stats::qt(0.975, df = nrow(sy) - 2L)
    list(slope = co[2, 1], lo = co[2, 1] - tc * co[2, 2], hi = co[2, 1] + tc * co[2, 2])
  }
  if (is.null(tr) || !nrow(tr))
    return(list(verdict = "too_short", slope = NA_real_, lo = NA_real_, hi = NA_real_,
                slope_all = NA_real_, lo_all = NA_real_, hi_all = NA_real_, ny = 0L, ny_all = 0L,
                n_points = 0L, n_left_out = 0L, site_yr = tibble::tibble(year = integer(), onset = numeric())))
  hollow <- hollow %in% TRUE
  site_yr <- yr_med(tr[!hollow, , drop = FALSE]); all_yr <- yr_med(tr)
  a <- fit(site_yr); b <- fit(all_yr)
  side <- function(f) if (!is.finite(f$lo)) 0L else if (f$lo > 0) 1L else if (f$hi < 0) -1L else 0L
  sa <- side(a); sb <- side(b)
  verdict <- if (nrow(site_yr) < min_years) "too_short" else if (sa == 0L) "none" else
    if (sb == sa) (if (sa > 0L) "up" else "down") else "depends"
  # a refused verdict carries no slope, so no caller can print one
  if (verdict == "too_short") a <- b <- list(slope = NA_real_, lo = NA_real_, hi = NA_real_)
  list(verdict = verdict, slope = a$slope, lo = a$lo, hi = a$hi,
       slope_all = b$slope, lo_all = b$lo, hi_all = b$hi,
       ny = nrow(site_yr), ny_all = nrow(all_yr), n_points = nrow(tr), n_left_out = sum(hollow),
       site_yr = site_yr)
}

# one individual's full phenophase record (the career timeline + card)
indiv_history <- function(obs, id) {
  if (is.null(obs) || is.null(id)) return(NULL)
  h <- obs[obs$individualID == id & !is.na(obs$date), , drop=FALSE]; if (!nrow(h)) return(NULL)
  h[order(h$date), c("date","year","dayOfYear","phenophaseName","status","intensity")]
}

# vegetative-only sequence for the ordering check. Reproductive phenophases
# (Open flowers, Fruits, pollen cones) are EXCLUDED: many trees flower before
# leaf-out (e.g. red maple), so flower-before-leaf is not an error. Colored and
# Falling leaves share rank 4 (iris 2026-10-21): leaves often start to fall
# before most of the canopy colours, so their order is not a recording error.
VEG_SEQ <- c("Breaking leaf buds"=1, "Initial growth"=1, "Emerging needles"=1, "Breaking needle buds"=1,
             "Increasing leaf size"=2, "Young leaves"=2, "Young needles"=2,
             "Leaves"=3, "Colored leaves"=4, "Falling leaves"=4)
# Growth forms with one orderly leaf cycle per year: the only forms the ordering
# and green-up outlier checks apply to. Drought-deciduous, forb, graminoid and
# semi-evergreen plants flush and drop leaves several times a year with the rain.
SINGLE_CYCLE_FORMS <- "^Deciduous|conifer|^Pine"
# An inversion whose earlier stage was first seen at the plant's very next visit
# lies inside one visit interval, so the two onsets cannot be ordered: allow it.
OO_SLACK_VISITS <- 1L
# Green-up year-outlier: a same-season (uncensored, not carried-over) onset more
# than OUTLIER_DAYS from the plant's own median, among at least OUTLIER_MIN_YEARS
# such years.
OUTLIER_DAYS <- 45
OUTLIER_MIN_YEARS <- 3

# Per-year leaf-stage onsets used only by the ordering check (iris 2026-10-21).
# doy, phase, yes are one year's scored VEG_SEQ rows of one plant. One status per
# phase per visit day ('yes' wins). The year is skipped (NULL) when the first
# scored Leaves record is 'yes': the plant entered the year carrying leaves, so the
# year holds no single cycle to order. A leaf-out stage (rank 1 to 3) has an onset
# only when its first 'yes' directly follows a 'no' of that phase at most max_gap
# days earlier (an observed transition); a senescence stage (rank 4) takes its
# first observed no-to-yes transition on or after the year's first leaf-out 'yes',
# so last year's leaves falling in February are not read as this year's. Returns a
# named vector phase -> onset day, observed onsets only.
oo_year_onsets <- function(doy, phase, yes, max_gap = CARRYOVER_GAP) {
  v <- stats::aggregate(list(yes = yes), by = list(phase = phase, doy = doy), FUN = any)
  v <- v[order(v$phase, v$doy, method = "radix"), , drop = FALSE]
  byp <- split(v, v$phase)
  lv <- byp[["Leaves"]]
  if (!is.null(lv) && isTRUE(lv$yes[1])) return(NULL)
  rk <- VEG_SEQ[names(byp)]
  observed <- function(x) x$yes & c(FALSE, !x$yes[-nrow(x)]) & c(Inf, diff(x$doy)) <= max_gap
  lo_yes <- unlist(lapply(byp[names(byp)[rk <= 3]], function(x) x$doy[x$yes]))
  anchor <- if (length(lo_yes)) min(lo_yes) else NA_real_
  on <- vapply(names(byp), function(p) {
    x <- byp[[p]]; t <- observed(x)
    if (rk[[p]] <= 3) { f <- which(x$yes)[1]; if (!is.na(f) && t[f]) x$doy[f] else NA_real_ }
    else { if (!is.finite(anchor)) return(NA_real_)
      k <- which(t & x$doy >= anchor); if (length(k)) x$doy[k[1]] else NA_real_ } }, 0)
  on[is.finite(on)]
}

# per-individual QC flags (ported from veg tree_qc_flags). Low-noise by design:
# "verify, not wrong": only flag things a human should actually look at.
# growth_form gates the ordering and outlier checks (SINGLE_CYCLE_FORMS).
# Returns list(flags = list(level,text,key,n), sets = named list of the exact
# offending rows behind each flag). The UI lists each flag clickable -> a DT
# inspector of its `sets[[key]]` + a per-flag CSV downloadHandler, and
# phe_qc_report() rolls every set into one ranked report CSV. Flagged rows are
# always RETAINED, never dropped. (Ported to the suite QC-inspector standard;
# see docs/neonize-playbook.md, memory neonize-qc-flag-pattern.)
QC_COLS <- c("date","year","dayOfYear","phenophaseName","status","intensity")
pheno_qc_flags <- function(hist, growth_form = NULL) {
  out <- list(flags = list(), sets = list())
  if (is.null(hist) || !nrow(hist)) return(out)
  cols <- intersect(QC_COLS, names(hist))
  tidy <- function(rows, label) { rows <- rows[!is.na(rows)]; if (!length(rows)) return(NULL)
    x <- hist[rows, cols, drop=FALSE]; if (!nrow(x)) return(NULL); x$flag <- label; x[order(x$year, x$dayOfYear), , drop=FALSE] }
  # add a flag ONLY when it has offending rows (a 0-row check is a no-op, never a
  # phantom flag); allow_empty=TRUE keeps a genuine no-row note (e.g. "no yes yet").
  add <- function(level, title, key, rows, text, allow_empty = FALSE) {
    rows <- unique(rows[!is.na(rows)]); n <- length(rows)
    if (!n && !allow_empty) return(invisible())
    out$flags[[length(out$flags)+1L]] <<- list(level=level, title=title, key=key, n=n, text=text)
    if (n) out$sets[[key]] <<- tidy(rows, title) }

  ph <- as.character(hist$phenophaseName); st <- as.character(hist$status)
  yes_idx <- which(st == "yes")
  if (!length(yes_idx)) { add("info", "No phenophase recorded 'yes' yet", "noyes", integer(0),
    "No phenophase has been recorded 'yes' yet for this plant.", allow_empty = TRUE); return(out) }
  single_cycle <- is.null(growth_form) || grepl(SINGLE_CYCLE_FORMS, growth_form)

  # (1) leaf stages out of sequence, per calendar year (single-cycle forms only).
  # Fires when a higher-rank stage's observed onset is strictly earlier than a
  # lower-rank one (a same-visit tie passes), unless the lower one came at the
  # next visit (OO_SLACK_VISITS). Rows: the later stage's onset 'yes' and the
  # earlier stage's rows on both onset days.
  oo_rows <- integer(0); oo_desc <- character(0)
  if (single_cycle) for (y in sort(unique(hist$year[yes_idx]))) {
    iy <- which(hist$year == y & ph %in% names(VEG_SEQ) & st %in% c("yes", "no") & is.finite(hist$dayOfYear))
    if (!length(iy)) next
    on <- oo_year_onsets(hist$dayOfYear[iy], ph[iy], st[iy] == "yes")
    if (length(on) < 2) next
    r <- VEG_SEQ[names(on)]
    visits <- sort(unique(hist$dayOfYear[hist$year == y & is.finite(hist$dayOfYear)]))
    bad <- which(outer(on, on, "<") & outer(r, r, ">"), arr.ind = TRUE)
    bad <- bad[order(on[bad[, 1]], on[bad[, 2]]), , drop = FALSE]
    for (k in seq_len(nrow(bad))) {
      a <- bad[k, 1]; b <- bad[k, 2]
      if (sum(visits > on[[a]] & visits <= on[[b]]) <= OO_SLACK_VISITS) next
      late <- names(on)[a]; early <- names(on)[b]
      oo_rows <- c(oo_rows, iy[ph[iy] == late & hist$dayOfYear[iy] == on[[a]] & st[iy] == "yes"],
                   iy[ph[iy] == early & hist$dayOfYear[iy] %in% c(on[[a]], on[[b]])])
      oo_desc <- c(oo_desc, sprintf("%s on day %d before %s on day %d (%d)", late, as.integer(on[[a]]),
                                    early, as.integer(on[[b]]), as.integer(y)))
    }
  }
  if (length(oo_desc)) add("warn", "Leaf phenophases out of sequence", "outoforder", oo_rows,
    sprintf("A later leaf stage was first recorded before an earlier one: %s. Check whether the earlier stage was missed at those visits or the later record is a mistake.",
            paste(oo_desc, collapse = "; ")))

  # Same visit recorded both yes and no: the same phenophase on the same date has
  # a 'yes' row and a 'no' row (an exact duplicate is not a conflict). Yes-wins
  # counts the visit as 'yes'; that matters most when the visit is the phase-year's
  # first 'yes', where it sets an onset, so those conflicts are "warn", the rest
  # "info". Both rows of every conflict are listed.
  vd <- obs_dates(hist)
  sc <- st %in% c("yes", "no") & !is.na(vd)
  ck <- paste(format(vd), ph, sep = "\r")
  has_yes <- tapply(st[sc] == "yes", ck[sc], any); has_no <- tapply(st[sc] == "no", ck[sc], any)
  cf_keys <- names(has_yes)[has_yes & has_no[names(has_yes)]]
  cf_rows <- which(sc & ck %in% cf_keys)
  if (length(cf_rows)) {
    nv <- length(cf_keys)
    # first 'yes' date per phenophase x year
    yi <- which(sc & st == "yes")
    first_yes <- tapply(vd[yi], paste(ph[yi], hist$year[yi], sep = "\r"), min)
    cf_first <- any(vd[cf_rows] == as.Date(first_yes[paste(ph[cf_rows], hist$year[cf_rows], sep = "\r")]), na.rm = TRUE)
    add(if (cf_first) "warn" else "info", "Same visit recorded both yes and no", "conflict", cf_rows,
      sprintf("On %d visit%s, two records for the same phenophase on the same day disagree: one says 'yes', the other 'no' (often two observers checking each other). The app counts the phenophase as 'yes' on that visit. Check which record is right.",
              nv, if (nv == 1) "" else "s"))
  }

  # Bud-break phases only. The Young-leaves fallback forms flush with rain, so a
  # first flush in January one year and July the next is biology, not a date to
  # verify; the plant-history checks stay bud-break-only (audit 2026-10-18). Both
  # checks read the same carry-over-aware onsets as the estimand, so leaves
  # carried over from December are neither an "early year" nor a censored onset.
  gy_idx <- which(st == "yes" & ph %in% GREENUP & is.finite(hist$dayOfYear))
  oc <- if (length(gy_idx)) onset_carry(cbind(individualID = "plant", hist, stringsAsFactors = FALSE), GREENUP) else NULL
  oc <- if (!is.null(oc)) oc[is.finite(oc$onset_doy), , drop = FALSE] else NULL
  per_year <- if (!is.null(oc) && nrow(oc)) oc %>% dplyr::group_by(.data$year) %>%
      dplyr::summarise(onset = min(.data$onset_doy), lc = .data$left_censored[which.min(.data$onset_doy)],
                       carry = .data$carryover[which.min(.data$onset_doy)], .groups = "drop")
    else NULL

  # (2) green-up year-outlier: a year more than OUTLIER_DAYS from this plant's own
  # median, single-cycle forms only, over observed same-season onsets (a censored
  # or carried-over year is not a comparable onset).
  py <- if (!is.null(per_year) && single_cycle)
    per_year[!(per_year$lc %in% TRUE) & !(per_year$carry %in% TRUE), , drop = FALSE] else NULL
  if (!is.null(py) && nrow(py) >= OUTLIER_MIN_YEARS) {
    med <- stats::median(py$onset); off <- py$onset - med
    i <- which.max(abs(off))
    if (length(i) == 1 && is.finite(off[i]) && abs(off[i]) > OUTLIER_DAYS) {
      oy <- py$year[i]
      out_rows <- gy_idx[hist$year[gy_idx] == oy]
      add("warn", "Green-up year well off the plant's norm", "outlier", out_rows,
        sprintf("In %s this plant broke leaf around day %d, %d days %s than its usual day-%d. Could be a real shift, or a date to verify.",
          oy, round(py$onset[i]), round(abs(off[i])), if (off[i] < 0) "earlier" else "later", round(med)))
    }
  }

  # (3) left-censored onset: leaf-out already 'yes' at a first visit with no
  # scored visit in the weeks before it, so true onset is earlier than recorded.
  if (!is.null(per_year) && any(per_year$lc %in% TRUE)) {
    lc_rows <- integer(0)
    for (y in per_year$year[per_year$lc %in% TRUE]) {
      yy <- gy_idx[hist$year[gy_idx] == y]
      if (length(yy)) lc_rows <- c(lc_rows, yy[hist$dayOfYear[yy] == min(hist$dayOfYear[yy])])
    }
    add("info", "Leaf-out already underway at first visit", "leftcensored", lc_rows,
      "Some years' leaf-out was already underway at the first visit, so the true onset may be a little earlier than shown.")
  }

  # (4) sparse: only one year of monitoring
  if (dplyr::n_distinct(hist$year) == 1L)
    add("info", "Watched in a single year so far", "single_year", yes_idx,
      "Watched in a single year so far. Onset dates can't be compared across years yet.")
  out
}
# roll every flag's offending rows into one ranked report data.frame for CSV
# download (high -> warn -> info), or NULL if the plant is clean.
phe_qc_report <- function(hist, growth_form = NULL) {
  q <- pheno_qc_flags(hist, growth_form); if (!length(q$sets)) return(NULL)
  lvl <- vapply(q$flags, function(f) f$level, ""); names(lvl) <- vapply(q$flags, function(f) f$key, "")
  ord <- c("high"=1,"warn"=2,"info"=3)
  keys <- names(q$sets)[order(ord[lvl[names(q$sets)]])]
  do.call(rbind, c(lapply(keys, function(k) { x <- q$sets[[k]]; x$level <- lvl[[k]]; x }), list(make.row.names = FALSE)))
}

# growth-form / species composition (Overview)
comp_by <- function(inds, by = c("growthForm","scientificName")) {
  by <- match.arg(by); inds %>% dplyr::count(.data[[by]], name="n") %>% dplyr::arrange(dplyr::desc(.data$n)) }

# per-plot summary for the map (n individuals + median green-up onset). Accepts a
# precomputed individual_summary so the Map tab needn't recompute it (perf).
# Also carries gu_share (fraction of the plot's plants that resolve a green-up
# onset) so the map can flag plots where green-up rests on a thin subsample, and
# leaf_active (median days carrying leaves) for the biome-conditional metric
# switch — leaf_active survives where green-up collapses in warm deserts.
plot_summary_phe <- function(obs, inds, ind_s = NULL) {
  if (is.null(ind_s)) ind_s <- individual_summary(obs, inds)
  if (is.null(ind_s)) return(NULL)
  # a summary built before leaf_active_hi existed reads as unknown, not as a point
  if (!"leaf_active_hi" %in% names(ind_s)) ind_s$leaf_active_hi <- NA_real_
  ind_s %>% dplyr::group_by(.data$plotID) %>%
    # gu_share MUST be computed BEFORE the `greenup =` redefine below: inside one
    # summarise(), once `greenup` is reassigned to the scalar median, `.data$greenup`
    # in a later expression refers to THAT scalar (is.finite -> 0/1), not the column.
    # Order bug = every plot reading ~0% or ~1/n coverage. Keep gu_share first.
    dplyr::summarise(n_ind = dplyr::n(),
                     gu_share = sum(is.finite(.data$greenup)) / dplyr::n(),
                     greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
                     # the lower-bound flag comes BEFORE the `leaf_active_hi =` and
                     # `leaf_active =` redefines and takes both medians itself from the
                     # plot's columns, so it reads no reassigned name (same gotcha as
                     # gu_share; suite lint L13)
                     leaf_active_lower_bound = {
                       hi <- round(stats::median(.data$leaf_active_hi, na.rm=TRUE))
                       la <- round(stats::median(.data$leaf_active, na.rm=TRUE))
                       if (is.finite(hi) && is.finite(la)) hi - la >= BOUND_POINT_TOL else NA },
                     leaf_active_hi = round(stats::median(.data$leaf_active_hi, na.rm=TRUE)),
                     leaf_active = round(stats::median(.data$leaf_active, na.rm=TRUE)),
                     lat = stats::median(.data$lat, na.rm=TRUE), lng = stats::median(.data$lng, na.rm=TRUE), .groups="drop")
}

# ---------------------------------------------------------------------------
# Cross-site / national layer (precomputed at bundle time; the app reads the
# rolled-up tables, never every bundle). green-up DOY → colour ramp shared by
# the single-site and national maps so "earlier" reads the same on both:
# early green-up = fresh green, late = senescence amber (on-theme + intuitive).
# ---------------------------------------------------------------------------
GREENUP_RAMP <- c("#15502f","#3f8f3a","#9ccf6a","#e0b341","#d98014")
# Robust green-up colour domain: a handful of THIN-COVERAGE sites carry wild
# median_greenup values (KONA day 226 at gu_share 0.03; LAJA day 5) that, on a raw
# range(), wash every well-covered site into one flat mid-band. So clamp the colour
# domain to the 5th/95th percentile of the WELL-COVERED sites (gu_share >= floor)
# and PIN out-of-range values to the endpoints. Pass gu_share to use the coverage
# filter; omit it (legacy callers / per-plot maps) to fall back to robust quantiles
# of the values themselves. Returns a palette FUNCTION that clamps before mapping,
# so an outlier reads as "off the deep/late end", never as a fabricated NA gap.
# The robust [p5,p95] colour domain for green-up DOY, computed from well-covered
# sites only (gu_share >= floor) when a coverage vector is supplied. Returned so
# the legend, the markers, and the value-clamp all share ONE domain.
greenup_domain <- function(domain, gu_share = NULL, floor = 0.5) {
  v <- suppressWarnings(as.numeric(domain))
  base <- if (!is.null(gu_share)) {
    gs <- suppressWarnings(as.numeric(gu_share))
    well <- v[is.finite(v) & is.finite(gs) & gs >= floor]
    if (length(well) >= 3) well else v[is.finite(v)]
  } else v[is.finite(v)]
  d <- if (length(base)) stats::quantile(base, c(.05, .95), names = FALSE, na.rm = TRUE) else c(100, 200)
  if (!all(is.finite(d)) || diff(d) == 0) { m <- if (length(base)) stats::median(base, na.rm = TRUE) else 150; d <- c(m - 1, m + 1) }
  d
}
# Green-up palette on the ROBUST domain (p5/p95 of well-covered sites). A handful
# of THIN-COVERAGE sites carry wild median_greenup values (KONA day 226 at
# gu_share 0.03; LAJA day 5) that on a raw range() wash every well-covered site
# into one flat mid-band. Build the palette on the robust domain instead; callers
# clamp the values they map with gp_clamp() so an outlier pins to the deep/late
# endpoint rather than reading as a fabricated NA gap. Returns a leaflet
# colorNumeric object so addLegend() still draws a continuous legend.
greenup_pal <- function(domain, gu_share = NULL, floor = 0.5) {
  d <- greenup_domain(domain, gu_share = gu_share, floor = floor)
  pal <- leaflet::colorNumeric(GREENUP_RAMP, domain = d, na.color = "#c4c0b2")
  attr(pal, "gp_domain") <- d   # so callers can clamp values + legend ticks to it
  pal
}
# clamp a value vector to a palette's robust domain (so out-of-range outliers pin
# to the endpoint colour instead of falling outside the leaflet domain -> NA).
gp_clamp <- function(pal, x) {
  d <- attr(pal, "gp_domain"); x <- suppressWarnings(as.numeric(x))
  if (is.null(d)) return(x)
  pmin(pmax(x, d[1]), d[2])
}

# Effective VISIT CADENCE: the median gap (in days) between consecutive distinct
# visit dates within a growing season, per plant, pooled across the site. Onset is
# interval-censored to the gap between visits, so a site visited every ~7 days
# resolves onset far more tightly than one visited monthly — part of a cross-site
# onset difference can be censoring geometry, not biology (the phenology analog of
# detection probability). This is the number behind the cadence badge + the
# coarse-cadence grey on the gradient. Restricted to in-season gaps (<= 60 d) so a
# winter dormancy gap between seasons doesn't inflate it. Returns NA if a site has
# too few visits to estimate a gap.
visit_interval_days <- function(obs) {
  d <- obs[!is.na(obs$date) & is.finite(obs$year), c("individualID","year","date"), drop=FALSE]
  if (!nrow(d)) return(NA_real_)
  d <- d[!duplicated(d[c("individualID","year","date")]), , drop=FALSE]
  d <- d[order(d$individualID, d$year, d$date), , drop=FALSE]
  key <- paste(d$individualID, d$year)
  gap <- as.numeric(diff(as.Date(d$date)))
  same <- key[-1] == key[-length(key)]                 # only gaps within one plant-year
  g <- gap[same & is.finite(gap) & gap > 0 & gap <= 60] # in-season gaps only
  if (length(g) < 5) return(NA_real_)
  round(stats::median(g), 1)
}

# one row per site: the picker-map + cross-site numbers (computed in the bundler)
site_phe_summary <- function(obs, inds, meta, ind_s = NULL) {
  obs <- normalize_doy(obs)
  if (is.null(ind_s)) ind_s <- individual_summary(obs, inds)
  ko <- key_onsets(obs); sup <- site_year_support(obs, gu = ko)
  sp <- species_level_only(inds)
  # green-up bounds over supported plant-years: value is the median of the
  # per-plant medians in ind_s, hi the median first 'yes', lo the median last
  # 'no', and value lies between them. A site with too few seasons is short_record.
  bnd <- greenup_bounds(if (!is.null(ko)) ko[ko$greenup_supported %in% TRUE, , drop = FALSE] else NULL)
  short <- nrow(sup) > 0L && all(sup$greenup_reason == "short_record")
  if (short) bnd <- list(value = NA_real_, lo = NA_real_, hi = NA_real_, status = "short_record", n_plants = 0L)
  # leaf-active summary over leaf-supported plant-years (value equals the median
  # of ind_s$leaf_active); hi is the median longest span the visits allow. Only
  # plants listed in inds count (scripts/headline_rules.md section 8): the site value has always
  # come from individual_summary(), which is built on inds, and an obs plant
  # missing from inds (DSNY 00653) must not move the value, hi or edge share.
  # Green-up stays on every plant in obs (section 6).
  lb <- leaf_bounds(if (!is.null(ko) && "leaf_active_hi" %in% names(ko))
                      ko[ko$leaf_supported %in% TRUE & is.finite(ko$leaf_active) &
                           ko$individualID %in% inds$individualID, , drop = FALSE] else NULL)
  if (short) lb <- list(value = NA_real_, hi = NA_real_, status = "short_record", edge_share = NA_real_, n_plants = 0L)
  autumn <- attr(ko, "autumn_forms"); carry_f <- attr(ko, "carry_forms")
  ksup <- if (!is.null(ko)) ko[ko$greenup_supported %in% TRUE & is.finite(ko$greenup), , drop = FALSE] else NULL
  tibble::tibble(
    site = meta$site, n_individuals = nrow(inds),
    n_species = dplyr::n_distinct(sp$scientificName[!is.na(sp$scientificName)]),
    n_obs = nrow(obs), n_plots = dplyr::n_distinct(inds$plotID),
    dominant_form = mode_chr(inds$growthForm),
    # NA unless the green-up summary is a point or a range (an upper bound or a
    # short record is withheld from the map, gradient and search)
    median_greenup = bnd$value,
    greenup_hi = bnd$hi, greenup_lo = bnd$lo, greenup_status = bnd$status,
    median_leaf_active = lb$value,
    # leaf_active_hi: the longest span the visits allow (unbridged edges filled to
    # the year boundary); status lower_bound when it exceeds the value by
    # BOUND_POINT_TOL or more; leaf_edge_share = share of the plant-years with an
    # unbridged edge
    leaf_active_hi = lb$hi, leaf_active_status = lb$status, leaf_edge_share = lb$edge_share,
    # green-up COVERAGE share (fraction of plants with a green-up onset in a
    # supported year). Cacti, leafless and no-leaf-bud evergreens and autumn-
    # germinating forms have none, so this flags when median_greenup rests on a
    # subset of the roster. Carried to site_index for the coverage badge.
    gu_share = if (!is.null(ind_s)) round(greenup_coverage(ind_s), 3) else NA_real_,
    # median in-season visit interval (days). Cross-site onset comparisons aren't
    # cadence-controlled, so a coarse-cadence site's onset carries wide censoring
    # uncertainty; carried to site_index for the cadence badge + gradient footnote.
    median_visit_interval = visit_interval_days(obs),
    # left-censoring share of supported plant-year green-up onsets, the Young-
    # leaves fallback share, the growth forms dropped as autumn-germinating, and
    # how many site-years passed the support gate (the n behind every median).
    greenup_lc_share = greenup_lc_share(ko),
    greenup_fallback_share = greenup_fallback_share(ind_s),
    # share of the site's scored rows (yes, no or uncertain; all years and
    # phenophases) recorded 'uncertain', which every onset and share ignores.
    # Kept unrounded (iris): the app discloses it at >= 0.10 on the raw value.
    # Computed on the obs received (the rebuild de-duplicates obs first).
    uncertain_share = { n_sc <- sum(obs$status %in% c("yes", "no", "uncertain"))
                        if (n_sc) sum(obs$status %in% "uncertain") / n_sc else NA_real_ },
    greenup_autumn_forms = if (length(autumn)) paste(autumn, collapse = "; ") else NA_character_,
    greenup_carry_forms = if (length(carry_f)) paste(carry_f, collapse = "; ") else NA_character_,
    # share of the supported green-up plant-years whose value is the next flush
    # after leaves carried over from December (see CARRYOVER_GAP)
    greenup_carry_share = if (!is.null(ksup) && nrow(ksup)) round(mean(ksup$carryover %in% TRUE), 3) else NA_real_,
    n_supported_years = sum(sup$greenup_supported),
    n_leaf_supported_years = sum(sup$leaf_supported),
    n_years_watched = nrow(sup),
    year_min = suppressWarnings(min(obs$year, na.rm=TRUE)),
    year_max = suppressWarnings(max(obs$year, na.rm=TRUE)),
    lat = meta$lat, lng = meta$lng)
}

# within-species latitude gradient: the CONFOUND-CONTROLLED read of the cross-
# site gradient. The network slope (median_greenup ~ lat) pools different species
# mixes at every site; holding ONE widespread species constant removes that
# confound. On the 2026-10-21 bundles red maple (Acer rubrum, 8 sites with at
# least 3 seasons; SCBI's single season is dropped) gives green-up +4.33 d per
# degree N (95% CI 1.91 to 6.76, R2 0.76, rho 0.87) and leaf-active -8.25 days
# per degree N (-11.99 to -4.51, R2 0.83, rho -0.92).
# Reads the precomputed national_onsets table (one row per site x species) for one
# value column (greenup, or leaf_active with years = "leaf_n_years"). Rows whose
# value or lat is not finite, or with fewer than min_years supported years behind
# the value, are dropped BEFORE the species is chosen, so a species cannot win on
# sites that rest on one or two seasons. The species with the most remaining sites
# (at least min_sites; ties to the first in radix order) is fitted value ~ lat with
# base lm (slope, t CI, R2, p), plus Spearman's rho with a Fisher z interval using
# the Bonett-Wright variance (NA at perfect ranks, where atanh is infinite).
# n_excluded_short and excluded_sites name the chosen species' rows the year floor
# dropped. NULL when a needed column is missing, when no species qualifies, or when
# a site appears twice within the chosen species (a growth-form split that would
# double-count the site). The site column is optional; without it the duplicate
# check and excluded_sites are skipped.
within_species_gradient <- function(national_onsets, value = "greenup", years = "n_years",
                                    min_sites = 6, min_years = SUPPORT_MIN_YEARS) {
  no <- national_onsets
  if (is.null(no) || !nrow(no) || !all(c("scientificName", value, years, "lat") %in% names(no))) return(NULL)
  v <- suppressWarnings(as.numeric(no[[value]])); ny <- suppressWarnings(as.numeric(no[[years]]))
  has_site <- "site" %in% names(no)
  ok_val <- is.finite(v) & is.finite(no$lat) & !is.na(no$scientificName)
  keep <- ok_val & !is.na(ny) & ny >= min_years
  if (!any(keep)) return(NULL)
  sp_all <- as.character(no$scientificName[keep])
  tab <- table(factor(sp_all, levels = sort(unique(sp_all), method = "radix")))
  if (max(tab) < min_sites) return(NULL)
  sp <- names(tab)[which.max(tab)]   # first maximum in radix order wins a tie
  in_sp <- no$scientificName %in% sp
  if (has_site && anyDuplicated(as.character(no$site[in_sp]))) return(NULL)
  short <- in_sp & ok_val & !keep
  excluded <- if (has_site) sort(unique(as.character(no$site[short])), method = "radix") else character(0)
  d <- data.frame(value = v[in_sp & keep], lat = no$lat[in_sp & keep])
  if (nrow(d) < 3 || diff(range(d$lat)) == 0) return(NULL)
  fit <- stats::lm(value ~ lat, data = d); co <- summary(fit)$coefficients
  if (nrow(co) < 2) return(NULL)
  slope <- co[2,1]; se <- co[2,2]; df <- nrow(d) - 2
  tcrit <- stats::qt(0.975, df = df)
  n <- nrow(d)
  rho <- stats::cor(d$lat, d$value, method = "spearman")
  rho_ci <- if (is.finite(rho) && abs(rho) <= 1 - 1e-9 && n > 3) {
    z <- atanh(rho); zse <- sqrt((1 + rho^2 / 2) / (n - 3)); q <- stats::qnorm(0.975)
    c(tanh(z - q * zse), tanh(z + q * zse)) } else c(NA_real_, NA_real_)
  list(species = sp, n_sites = n, slope = slope,
       lo = slope - tcrit*se, hi = slope + tcrit*se,
       r2 = summary(fit)$r.squared, p = co[2,4],
       rho = rho, rho_lo = rho_ci[1], rho_hi = rho_ci[2],
       n_excluded_short = sum(short), excluded_sites = excluded)
}

# one row per (site × species-level taxon) with ≥3 individuals: feeds the
# same-species-across-sites cross-site comparison (computed in the bundler).
# greenup is the two-stage median of the plant-year midpoints (NA unless a point
# or a range); greenup_hi is the median first 'yes', greenup_lo the median last
# 'no' (NA when censoring leaves it open), and greenup lies between them.
site_species_onsets <- function(obs, inds, meta) {
  ko <- key_onsets(obs); if (is.null(ko)) return(NULL)
  ko_leaf <- ko[ko$leaf_supported %in% TRUE & is.finite(ko$leaf_active), , drop = FALSE]
  spmap <- inds[, c("individualID","scientificName","growthForm","is_species"), drop=FALSE]
  # flowering and leaf-active are two-stage too (per plant over ALL its supported
  # years, then across plants), not pooled over only the plant-years that also
  # had a green-up: the within-species leaf-active gradient reads these values
  per_plant <- ko %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(fl = suppressWarnings(stats::median(.data$flower[.data$greenup_supported], na.rm = TRUE)),
                     la = suppressWarnings(stats::median(.data$leaf_active[.data$leaf_supported], na.rm = TRUE)),
                     la_hi = suppressWarnings(stats::median(.data$leaf_active_hi[.data$leaf_supported], na.rm = TRUE)),
                     .groups = "drop")
  ko <- ko[ko$greenup_supported %in% TRUE, , drop = FALSE]   # supported site-years only
  d <- dplyr::left_join(ko, spmap, by = "individualID")
  d <- d[d$is_species %in% TRUE & !is.na(d$scientificName) & is.finite(d$greenup), , drop=FALSE]
  if (!nrow(d)) return(NULL)
  key <- paste(d$scientificName, d$growthForm, sep = "\r")
  out <- dplyr::bind_rows(lapply(split(seq_len(nrow(d)), key), function(rows) {
    g <- d[rows, , drop = FALSE]
    b <- greenup_bounds(g)   # same two-stage bounds and labels as the site summary
    tibble::tibble(scientificName = g$scientificName[1], growthForm = g$growthForm[1],
                   n_ind = dplyr::n_distinct(g$individualID),
                   greenup = b$value, greenup_hi = b$hi, greenup_lo = b$lo, greenup_status = b$status,
                   lc_share = round(mean(g$left_censored %in% TRUE), 3),
                   flower = { v <- per_plant$fl[per_plant$individualID %in% g$individualID]
                              v <- v[is.finite(v)]; if (length(v)) round(stats::median(v)) else NA_real_ },
                   leaf_active = { v <- per_plant$la[per_plant$individualID %in% g$individualID]
                                   v <- v[is.finite(v)]; if (length(v)) round(stats::median(v)) else NA_real_ },
                   # same plants as leaf_active (a finite la); the edge share is over
                   # their supported plant-years with a finite leaf_active
                   leaf_active_hi = { pp <- per_plant[per_plant$individualID %in% g$individualID & is.finite(per_plant$la), ]
                                      if (nrow(pp)) round(stats::median(pp$la_hi)) else NA_real_ },
                   leaf_edge_share = { r <- ko_leaf[ko_leaf$individualID %in% g$individualID, , drop = FALSE]
                                       if (nrow(r)) round(mean(r$leaf_edge_start %in% TRUE | r$leaf_edge_end %in% TRUE), 3)
                                       else NA_real_ })
  }))
  out$leaf_active_lower_bound <- ifelse(is.na(out$leaf_active), NA,
                                        out$leaf_active_hi - out$leaf_active >= BOUND_POINT_TOL)
  # years behind each value (scripts/headline_rules.md section 10), the floor the gradient applies:
  # n_years = distinct supported green-up years among the group's rows;
  # leaf_n_years = distinct leaf-supported years with a leaf row for any of its plants
  yrs <- lapply(split(seq_len(nrow(d)), key), function(rows) {
    ids <- unique(d$individualID[rows])
    c(n_years = length(unique(d$year[rows])),
      leaf_n_years = length(unique(ko_leaf$year[ko_leaf$individualID %in% ids]))) })
  # (split() orders groups exactly as for `out` above, so rows align)
  out$n_years <- as.integer(vapply(yrs, `[[`, 0, "n_years"))
  out$leaf_n_years <- as.integer(vapply(yrs, `[[`, 0, "leaf_n_years"))
  out <- out[out$n_ind >= 3, , drop = FALSE]
  if (!nrow(out)) return(NULL)
  # C-locale (radix) order, like dplyr's grouping, so bytes match across platforms
  out <- out[order(out$scientificName, out$growthForm, method = "radix"), , drop = FALSE]
  out$site <- meta$site; out$lat <- meta$lat; out$lng <- meta$lng
  out
}
