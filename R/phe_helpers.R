# ===========================================================================
# NEON Plant Phenology Explorer — phe_helpers.R
# The unit is a TAGGED plant individual with a weekly-resolution, multi-year
# phenophase career (a near-twin of the veg-structure tree career). Onset is
# interval-censored (weekly obs) -> midpoint between last 'no' and first 'yes'.
# The Phenology Clock pools years by design; onset trends must NOT pool (the
# never-pool rule). See docs/neonize-playbook.md.
# ===========================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
mode_chr <- function(x){ x<-x[!is.na(x)]; if(!length(x)) return(NA_character_); names(sort(table(x),decreasing=TRUE))[1] }
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
# Unsupported plant-years stay in the per-plant-year export with year_supported =
# FALSE and are excluded from medians, trends and the site index.
SUPPORT_WEEK_RATIO <- 0.75
SUPPORT_LATE_START <- 30
SUPPORT_MIN_YEARS <- 3
# Left-censoring bounds. hi = the two-stage median (per plant over supported
# years, then across plants); lo = the same with every left-censored plant-year
# set to -Inf, the tightest valid lower bound. hi - lo < BOUND_POINT_TOL reads as
# one day; a finite lo reads as a range; lo = -Inf reads "day hi or earlier" and
# the numeric median is withheld (NA) from the map, gradient and indexes.
BOUND_POINT_TOL <- 7

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
                              min_years = SUPPORT_MIN_YEARS) {
  d <- obs[is.finite(obs$dayOfYear) & is.finite(obs$year), c("individualID", "year", "dayOfYear"), drop = FALSE]
  if (!nrow(d)) return(tibble::tibble(year = integer(), med_weeks = numeric(), typical_weeks = numeric(),
                                      week_ratio = numeric(), first_doy = numeric(), typical_first = numeric(),
                                      year_supported = logical(), reason = character()))
  d$wk <- doy_week(d$dayOfYear)
  per_plant <- d %>% dplyr::distinct(.data$individualID, .data$year, .data$wk) %>%
    dplyr::count(.data$individualID, .data$year, name = "weeks")
  yr <- per_plant %>% dplyr::group_by(.data$year) %>%
    dplyr::summarise(med_weeks = stats::median(.data$weeks), .groups = "drop")
  first <- d %>% dplyr::group_by(.data$year) %>% dplyr::summarise(first_doy = min(.data$dayOfYear), .groups = "drop")
  yr <- dplyr::left_join(yr, first, by = "year")
  yr$typical_weeks <- stats::median(yr$med_weeks)
  yr$typical_first <- stats::median(yr$first_doy)
  yr$week_ratio <- yr$med_weeks / yr$typical_weeks
  low <- !(is.finite(yr$week_ratio) & yr$week_ratio >= week_ratio)
  late <- (yr$first_doy - yr$typical_first) > late_start
  short <- nrow(yr) < min_years
  yr$year_supported <- !short & !low & !late
  # one reason per year (precedence short_record > low_effort > late_start); built
  # by assignment, never ifelse() on the scalar `short`, which would recycle the
  # first year's reason over every year
  reason <- rep("supported", nrow(yr))
  reason[late] <- "late_start"
  reason[low] <- "low_effort"
  if (short) reason[] <- "short_record"
  yr$reason <- reason
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
      onset_later = { y <- .data$doy[.data$yes]; n <- .data$doy[!.data$yes]; f <- .data$doy[1]
        n1 <- n[n > f]
        if (!length(n1)) NA_real_ else { y2 <- y[y > min(n1)]
          if (!length(y2)) NA_real_ else { y2 <- min(y2); (max(n[n < y2]) + y2) / 2 } } },
      .groups = "drop")
  prev <- yr %>% dplyr::transmute(.data$individualID, .data$phenophaseName, year = .data$year + 1L,
                                  prev_date = .data$last_date, prev_yes = .data$last_yes)
  yr <- dplyr::left_join(yr, prev, by = c("individualID", "phenophaseName", "year"))
  near <- !is.na(yr$prev_date) & as.numeric(yr$first_date - yr$prev_date) <= max_gap
  carry <- near & yr$first_yes %in% TRUE & yr$prev_yes %in% TRUE
  bridged <- near & yr$first_yes %in% TRUE & yr$prev_yes %in% FALSE
  onset_doy <- yr$onset_std; lc <- yr$lc_std
  if (any(bridged)) {
    jan1 <- as.Date(sprintf("%d-01-01", as.integer(yr$year[bridged])))
    prev_doy <- as.numeric(yr$prev_date[bridged] - jan1) + 1   # <= 0: days before Jan 1
    onset_doy[bridged] <- pmax(1, (prev_doy + yr$onset_std[bridged]) / 2)
    lc[bridged] <- FALSE
  }
  onset_doy[carry] <- yr$onset_later[carry]; lc[carry] <- FALSE
  tibble::tibble(individualID = yr$individualID, phenophaseName = yr$phenophaseName, year = yr$year,
                 onset_doy = onset_doy, left_censored = lc, carryover = carry)
}

# green-up per plant-year: earliest bud-break onset, else (drought-deciduous
# shrubs only) the first Young-leaves onset, both under the carry-over rule; then
# growth forms whose onsets mostly fall in autumn are dropped (AUTUMN_*). One row
# per plant-year with greenup, left_censored, carryover and greenup_source; the
# dropped forms ride along as attr(, "autumn_forms"). Shared by key_onsets(),
# onset_trend() and site_species_onsets() so every green-up surface agrees.
greenup_onsets <- function(obs) {
  ek <- tibble::tibble(individualID = character(), year = integer(), greenup = numeric(),
                       left_censored = logical(), carryover = logical(), greenup_source = character())
  ph <- onset_carry(obs, c(GREENUP, GREENUP_FALLBACK_PHASE))
  if (is.null(ph) || !nrow(ph)) return(NULL)
  forms <- obs[!duplicated(obs$individualID), c("individualID", "growthForm"), drop = FALSE]
  ph$growthForm <- as.character(forms$growthForm[match(ph$individualID, forms$individualID)])
  ph <- ph[is.finite(ph$onset_doy), , drop = FALSE]
  collapse <- function(o, src) {
    if (!nrow(o)) return(ek)
    o %>% dplyr::group_by(.data$individualID, .data$year) %>%
      dplyr::summarise(greenup = min(.data$onset_doy),
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
  autumn_forms <- sort(tab$growthForm[!is.na(tab$growthForm) & tab$n >= AUTUMN_MIN_N & tab$autumn >= AUTUMN_SHARE])
  out <- out[!out$growthForm %in% autumn_forms, setdiff(names(out), "growthForm"), drop = FALSE]
  out <- out[order(out$individualID, out$year, method = "radix"), , drop = FALSE]
  attr(out, "autumn_forms") <- autumn_forms
  if (!nrow(out)) return(structure(ek, autumn_forms = autumn_forms))
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
leaf_spans <- function(obs) {
  ek <- tibble::tibble(individualID = character(), year = integer(), leaf_active = numeric(),
                       leaf_weeks = integer(), leaf_off = numeric())
  d <- obs[obs$phenophaseName == "Leaves" & obs$status %in% c("yes", "no") & is.finite(obs$dayOfYear),
           c("individualID", "year", "dayOfYear", "status"), drop = FALSE]
  if (!nrow(d)) return(ek)
  v <- d %>% dplyr::group_by(.data$individualID, .data$year, .data$dayOfYear) %>%
    dplyr::summarise(yes = any(.data$status == "yes"), .groups = "drop") %>%
    dplyr::arrange(.data$individualID, .data$year, .data$dayOfYear)
  out <- v %>% dplyr::group_by(.data$individualID, .data$year) %>%
    dplyr::summarise(leaf_active = leaf_run_span(.data$dayOfYear, .data$yes),
                     leaf_weeks = dplyr::n_distinct(doy_week(.data$dayOfYear[.data$yes])) * 7L,
                     leaf_off = if (any(.data$yes)) as.numeric(max(.data$dayOfYear[.data$yes])) else NA_real_,
                     .groups = "drop")
  out[out$leaf_weeks > 0L, , drop = FALSE]
}

key_onsets <- function(obs, support = NULL) {
  obs <- normalize_doy(obs)
  ek <- tibble::tibble(individualID = character(), year = integer())
  guo <- greenup_onsets(obs)
  gu <- if (!is.null(guo) && nrow(guo)) guo else
    dplyr::mutate(ek, greenup = numeric(), left_censored = logical(), carryover = logical(), greenup_source = character())
  flo <- onset(obs, "Open flowers")
  fl <- if (!is.null(flo) && nrow(flo)) flo %>% dplyr::transmute(individualID, year, flower = .data$onset_doy)
        else dplyr::mutate(ek, flower = numeric())
  la <- leaf_spans(obs)
  out <- Reduce(function(a,b) dplyr::full_join(a,b,by=c("individualID","year")), list(gu, fl, la))
  if (is.null(out) || !nrow(out)) return(NULL)
  if (is.null(support)) support <- site_year_support(obs)
  out$year_supported <- out$year %in% support$year[support$year_supported]
  attr(out, "autumn_forms") <- attr(guo, "autumn_forms")
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
  sum(is.finite(ind_s$greenup)) / n
}

# one row per individual: median green-up / leaf-active etc. (Onset Lab + picker)
individual_summary <- function(obs, inds) {
  ko <- key_onsets(obs); if (is.null(ko) || !nrow(ko)) return(NULL)
  sup <- ko[ko$year_supported %in% TRUE, , drop = FALSE]
  med <- function(x) { v <- suppressWarnings(stats::median(x, na.rm = TRUE)); if (is.finite(v)) round(v) else NA_real_ }
  agg <- sup %>% dplyr::group_by(.data$individualID) %>%
    # COUNT columns come FIRST. Inside one summarise(), once `greenup` is reassigned
    # to its scalar median, a later `.data$greenup` is that scalar (is.finite -> 0/1),
    # so every *_n_years used to read 0 or 1 in every bundle. Keep the counts above
    # the reassignments (same rule as gu_share in plot_summary_phe).
    dplyr::summarise(greenup_n_years     = sum(is.finite(.data$greenup)),
                     flower_n_years      = sum(is.finite(.data$flower)),
                     leaf_active_n_years = sum(is.finite(.data$leaf_active)),
                     # years with ANY key metric (leaf-only evergreens are not 0)
                     n_years = dplyr::n_distinct(.data$year[is.finite(.data$greenup) | is.finite(.data$flower) |
                                                            is.finite(.data$leaf_off) | is.finite(.data$leaf_active)]),
                     greenup_lc_years = sum(.data$left_censored %in% TRUE & is.finite(.data$greenup)),
                     greenup_source = mode_chr(.data$greenup_source[is.finite(.data$greenup)]),
                     greenup = med(.data$greenup),
                     flower = med(.data$flower),
                     leaf_off = med(.data$leaf_off),
                     leaf_active = med(.data$leaf_active),
                     .groups="drop")
  # years watched regardless of support, so a plant whose only years were
  # unsupported still shows as watched (with n_years 0 and NA medians)
  watched <- ko %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(n_years_watched = dplyr::n_distinct(.data$year), .groups = "drop")
  out <- dplyr::left_join(inds, agg, by = "individualID")
  out <- dplyr::left_join(out, watched, by = "individualID")
  for (cc in c("greenup_n_years", "flower_n_years", "leaf_active_n_years", "n_years", "greenup_lc_years"))
    out[[cc]][is.na(out[[cc]]) & !is.na(out$n_years_watched)] <- 0L
  out[, c(names(inds), "greenup", "flower", "leaf_off", "leaf_active", "greenup_source",
          "greenup_n_years", "flower_n_years", "leaf_active_n_years", "greenup_lc_years",
          "n_years", "n_years_watched"), drop = FALSE]
}

# share of SUPPORTED plant-year green-up onsets that were left-censored (already
# 'yes' at a first visit with no scored visit in the CARRYOVER_GAP before it).
# Reported beside the bounds; censored onsets are never dropped (dropping them
# biases the median late: SJER would move to November).
greenup_lc_share <- function(ko) {
  if (is.null(ko) || !nrow(ko) || !all(c("greenup", "left_censored", "year_supported") %in% names(ko))) return(NA_real_)
  k <- ko[ko$year_supported %in% TRUE & is.finite(ko$greenup), , drop = FALSE]
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
# finite green-up; one group = one site or one species at a site):
#   hi = median across plants of each plant's median (the published median)
#   lo = the same with every left-censored plant-year set to -Inf
# status: "point" (hi - lo < BOUND_POINT_TOL), "range" (finite lo), "upper_bound"
# (lo = -Inf: most plants were already greening at the first visit), or "none".
# value is the number the map, gradient and indexes may use: hi for point and
# range, NA for upper_bound (the median is only an upper bound there).
greenup_bounds <- function(k) {
  none <- list(value = NA_real_, hi = NA_real_, lo = NA_real_, status = "none", n_plants = 0L)
  if (is.null(k) || !nrow(k)) return(none)
  k <- k[is.finite(k$greenup), , drop = FALSE]
  if (!nrow(k)) return(none)
  per <- k %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(hi = round(stats::median(.data$greenup)),
                     lo = stats::median(ifelse(.data$left_censored %in% TRUE, -Inf, .data$greenup)),
                     .groups = "drop")
  per$lo <- ifelse(is.finite(per$lo), round(per$lo), per$lo)
  hi <- round(stats::median(per$hi))
  lo <- stats::median(per$lo); if (is.finite(lo)) lo <- round(lo)
  status <- if (!is.finite(lo)) "upper_bound" else if (hi - lo < BOUND_POINT_TOL) "point" else "range"
  list(value = if (status %in% c("point", "range")) hi else NA_real_, hi = hi,
       lo = if (is.finite(lo)) lo else NA_real_, status = status, n_plants = nrow(per))
}
# plain-words headline for a green-up summary (hi, lo, status as above, plus
# "short_record"); the app adds the month and the explanation around it
greenup_label <- function(hi, lo, status, n_seasons = NA_integer_) {
  switch(as.character(status %||% "none"),
    point = sprintf("day %d", round(hi)),
    range = sprintf("day %d to %d", round(lo), round(hi)),
    upper_bound = sprintf("day %d or earlier", round(hi)),
    short_record = if (is.finite(n_seasons)) sprintf("unavailable: %d season%s monitored, too few to check the schedule",
                                                     as.integer(n_seasons), if (n_seasons == 1) "" else "s")
                   else "unavailable: too few seasons monitored to check the schedule",
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
  g <- greenup_onsets(obs); if (is.null(g) || !nrow(g)) return(NULL)
  g <- g[g$greenup_source %in% "bud-break", , drop = FALSE]
  if (!nrow(g)) return(NULL)
  sup <- site_year_support(obs)
  g <- g[g$year %in% sup$year[sup$year_supported], , drop = FALSE]   # supported site-years only
  if (!nrow(g)) return(NULL)
  sci <- obs[!duplicated(obs$individualID), c("individualID", "scientificName"), drop = FALSE]
  o <- dplyr::left_join(g, sci, by = "individualID") %>%
    dplyr::transmute(individualID, scientificName, year, onset_doy = .data$greenup)
  out <- o %>% dplyr::group_by(.data$scientificName, .data$year) %>%
    dplyr::summarise(onset = round(stats::median(.data$onset_doy)), n = dplyr::n_distinct(.data$individualID), .groups="drop") %>%
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
leaf_active_trend <- function(obs) {
  obs <- normalize_doy(obs)
  sup <- site_year_support(obs)
  la <- leaf_spans(obs[obs$year %in% sup$year[sup$year_supported], , drop = FALSE])   # supported site-years only
  if (!nrow(la)) return(NULL)
  sci <- obs[!duplicated(obs$individualID), c("individualID", "scientificName"), drop = FALSE]
  la$scientificName <- sci$scientificName[match(la$individualID, sci$individualID)]
  out <- la %>% dplyr::group_by(.data$scientificName, .data$year) %>%
    dplyr::summarise(onset = round(stats::median(.data$leaf_active)), n = dplyr::n_distinct(.data$individualID), .groups="drop") %>%
    dplyr::filter(.data$n >= 3)
  if (!nrow(out)) return(NULL)
  out
}

# one individual's full phenophase record (the career timeline + card)
indiv_history <- function(obs, id) {
  if (is.null(obs) || is.null(id)) return(NULL)
  h <- obs[obs$individualID == id & !is.na(obs$date), , drop=FALSE]; if (!nrow(h)) return(NULL)
  h[order(h$date), c("date","year","dayOfYear","phenophaseName","status","intensity")]
}

# vegetative-only sequence for the ordering check. Reproductive phenophases
# (Open flowers, Fruits, pollen cones) are EXCLUDED — many trees flower before
# leaf-out (e.g. red maple), so flower-before-leaf is not an error.
VEG_SEQ <- c("Breaking leaf buds"=1, "Initial growth"=1, "Emerging needles"=1, "Breaking needle buds"=1,
             "Increasing leaf size"=2, "Young leaves"=2, "Young needles"=2,
             "Leaves"=3, "Colored leaves"=4, "Falling leaves"=5)

# per-individual QC flags (ported from veg tree_qc_flags). Low-noise by design:
# "verify, not wrong" — only flag things a human should actually look at.
# growth_form gates the ordering check: drought-deciduous / forb / semi-evergreen
# plants legitimately flush and drop leaves MULTIPLE times a year (rain-driven),
# so leaf-stage "out of order" within a year is normal for them, not an error.
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

  yes_idx <- which(hist$status == "yes")
  if (!length(yes_idx)) { add("info", "No phenophase recorded 'yes' yet", "noyes", integer(0),
    "No phenophase has been recorded 'yes' yet for this plant.", allow_empty = TRUE); return(out) }

  # (1) out-of-order VEGETATIVE phenophases within a year (single-cycle plants only).
  single_cycle <- is.null(growth_form) || grepl("^Deciduous|conifer|^Pine", growth_form)
  oo_rows <- integer(0); oo_years <- integer(0)
  if (single_cycle) for (y in unique(hist$year[yes_idx])) {
    yidx <- which(hist$status == "yes" & hist$year == y & hist$phenophaseName %in% names(VEG_SEQ) & is.finite(hist$dayOfYear))
    if (!length(yidx)) next
    fr <- tapply(hist$dayOfYear[yidx], as.character(hist$phenophaseName[yidx]), min)
    rk <- VEG_SEQ[names(fr)]; ok <- is.finite(rk) & is.finite(fr); fr <- fr[ok]; rk <- rk[ok]
    if (length(fr) >= 2) { o <- order(fr)
      if (any(diff(rk[o]) < 0)) { oo_rows <- c(oo_rows, yidx); oo_years <- c(oo_years, y) } }
  }
  add("high", "Leaf phenophases out of sequence", "outoforder", oo_rows,
    sprintf("In %s, leaf phenophases were recorded out of sequence (a later leaf stage before an earlier one, e.g. falling/colored leaves before leaf-out). Worth checking the records for %s.",
      paste(sort(unique(oo_years)), collapse=", "), if (length(unique(oo_years))==1) "that year" else "those years"))

  # Bud-break phases only. The Young-leaves fallback forms flush with rain, so a
  # first flush in January one year and July the next is biology, not a date to
  # verify; the plant-history checks stay bud-break-only (audit 2026-10-18). Both
  # checks read the same carry-over-aware onsets as the estimand, so leaves
  # carried over from December are neither an "early year" nor a censored onset.
  gy_idx <- which(hist$status == "yes" & hist$phenophaseName %in% GREENUP & is.finite(hist$dayOfYear))
  oc <- if (length(gy_idx)) onset_carry(cbind(individualID = "plant", hist, stringsAsFactors = FALSE), GREENUP) else NULL
  oc <- if (!is.null(oc)) oc[is.finite(oc$onset_doy), , drop = FALSE] else NULL
  per_year <- if (!is.null(oc) && nrow(oc)) oc %>% dplyr::group_by(.data$year) %>%
      dplyr::summarise(onset = min(.data$onset_doy), lc = .data$left_censored[which.min(.data$onset_doy)], .groups = "drop")
    else NULL

  # (2) green-up year-outlier: a year >45 d from this plant's own median.
  if (!is.null(per_year) && nrow(per_year) >= 3) {
    med <- stats::median(per_year$onset); off <- per_year$onset - med
    i <- which.max(abs(off))
    if (length(i) == 1 && is.finite(off[i]) && abs(off[i]) > 45) {
      oy <- per_year$year[i]
      out_rows <- gy_idx[hist$year[gy_idx] == oy]
      add("warn", "Green-up year well off the plant's norm", "outlier", out_rows,
        sprintf("In %s this plant broke leaf around day %d, %d days %s than its usual day-%d. Could be a real shift, or a date to verify.",
          oy, round(per_year$onset[i]), round(abs(off[i])), if (off[i] < 0) "earlier" else "later", round(med)))
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
  ind_s %>% dplyr::group_by(.data$plotID) %>%
    # gu_share MUST be computed BEFORE the `greenup =` redefine below: inside one
    # summarise(), once `greenup` is reassigned to the scalar median, `.data$greenup`
    # in a later expression refers to THAT scalar (is.finite -> 0/1), not the column.
    # Order bug = every plot reading ~0% or ~1/n coverage. Keep gu_share first.
    dplyr::summarise(n_ind = dplyr::n(),
                     gu_share = sum(is.finite(.data$greenup)) / dplyr::n(),
                     greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
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
  ko <- key_onsets(obs); sup <- site_year_support(obs)
  sp <- species_level_only(inds)
  safe_med <- function(x) { v <- suppressWarnings(stats::median(x, na.rm=TRUE)); if (is.finite(v)) round(v) else NA_real_ }
  # green-up bounds over supported plant-years (hi equals the median of the
  # per-plant medians in ind_s); a site with too few seasons is short_record
  bnd <- greenup_bounds(if (!is.null(ko)) ko[ko$year_supported %in% TRUE, , drop = FALSE] else NULL)
  short <- nrow(sup) > 0L && all(sup$reason == "short_record")
  if (short) bnd <- list(value = NA_real_, hi = NA_real_, lo = NA_real_, status = "short_record", n_plants = 0L)
  autumn <- attr(ko, "autumn_forms")
  tibble::tibble(
    site = meta$site, n_individuals = nrow(inds),
    n_species = dplyr::n_distinct(sp$scientificName[!is.na(sp$scientificName)]),
    n_obs = nrow(obs), n_plots = dplyr::n_distinct(inds$plotID),
    dominant_form = mode_chr(inds$growthForm),
    # NA unless the green-up summary is a point or a range (an upper bound or a
    # short record is withheld from the map, gradient and search)
    median_greenup = bnd$value,
    greenup_hi = bnd$hi, greenup_lo = bnd$lo, greenup_status = bnd$status,
    median_leaf_active = if (!is.null(ind_s) && !short) safe_med(ind_s$leaf_active) else NA_real_,
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
    greenup_autumn_forms = if (length(autumn)) paste(autumn, collapse = "; ") else NA_character_,
    n_supported_years = sum(sup$year_supported),
    n_years_watched = nrow(sup),
    year_min = suppressWarnings(min(obs$year, na.rm=TRUE)),
    year_max = suppressWarnings(max(obs$year, na.rm=TRUE)),
    lat = meta$lat, lng = meta$lng)
}

# within-species latitude gradient — the CONFOUND-CONTROLLED read of the cross-
# site gradient. The network slope (median_greenup ~ lat) pools different species
# mixes at every site; holding ONE widespread species constant removes that
# confound (red maple alone ~ +4.4 d/°N, R² 0.78 vs the network's +2.5, R² 0.41).
# Picks the species spanning the most sites (>= min_sites), fits greenup ~ lat,
# and returns the slope + its 95% CI + R² so the banner can LEAD with it. Reads
# the precomputed national_onsets table (one row per site×species); NULL if none
# qualifies. Pure base lm, no extra deps.
within_species_gradient <- function(national_onsets, min_sites = 4) {
  no <- national_onsets
  if (is.null(no) || !nrow(no) || !all(c("scientificName","greenup","lat") %in% names(no))) return(NULL)
  no <- no[is.finite(no$greenup) & is.finite(no$lat), , drop=FALSE]
  if (!nrow(no)) return(NULL)
  tab <- sort(table(no$scientificName), decreasing = TRUE)
  cand <- names(tab)[tab >= min_sites]
  if (!length(cand)) return(NULL)
  sp <- cand[1]                       # the most widely-monitored species
  d <- no[no$scientificName == sp, , drop=FALSE]
  if (nrow(d) < 3 || diff(range(d$lat)) == 0) return(NULL)
  fit <- stats::lm(greenup ~ lat, data = d); co <- summary(fit)$coefficients
  if (nrow(co) < 2) return(NULL)
  slope <- co[2,1]; se <- co[2,2]; df <- nrow(d) - 2
  tcrit <- stats::qt(0.975, df = df)
  list(species = sp, n_sites = nrow(d), slope = slope,
       lo = slope - tcrit*se, hi = slope + tcrit*se,
       r2 = summary(fit)$r.squared, p = co[2,4])
}

# one row per (site × species-level taxon) with ≥3 individuals: feeds the
# same-species-across-sites cross-site comparison (computed in the bundler).
site_species_onsets <- function(obs, inds, meta) {
  ko <- key_onsets(obs); if (is.null(ko)) return(NULL)
  ko <- ko[ko$year_supported %in% TRUE, , drop = FALSE]   # supported site-years only
  spmap <- inds[, c("individualID","scientificName","growthForm","is_species"), drop=FALSE]
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
                   flower = round(stats::median(g$flower, na.rm = TRUE)),
                   leaf_active = round(stats::median(g$leaf_active, na.rm = TRUE)))
  }))
  out <- out[out$n_ind >= 3, , drop = FALSE]
  if (!nrow(out)) return(NULL)
  # C-locale (radix) order, like dplyr's grouping, so bytes match across platforms
  out <- out[order(out$scientificName, out$growthForm, method = "radix"), , drop = FALSE]
  out$site <- meta$site; out$lat <- meta$lat; out$lng <- meta$lng
  out
}
