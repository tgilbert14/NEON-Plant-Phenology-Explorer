#!/usr/bin/env Rscript

# Fail-closed fixtures for the Plant Phenology scientific contracts. These tests
# use no network. Run from the repository root with the pinned app runtime:
#   Rscript scripts/test_helpers.R

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
root <- if (length(file_arg)) normalizePath(file.path(dirname(file_arg), "..")) else
  normalizePath(".")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(RColorBrewer)
})
source(file.path(root, "R", "phe_helpers.R"), chdir = TRUE)

passed <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(sprintf("FAIL: %s", label), call. = FALSE)
  passed <<- passed + 1L
  cat(sprintf("PASS %02d: %s\n", passed, label))
}

obs_row <- function(individualID, year, dayOfYear, status,
                    phenophaseName = "Breaking leaf buds",
                    scientificName = "Species alpha",
                    growthForm = "deciduous broadleaf",
                    is_species = TRUE) {
  tibble(
    individualID = individualID,
    scientificName = scientificName,
    growthForm = growthForm,
    phenophaseName = phenophaseName,
    year = as.integer(year),
    dayOfYear = as.numeric(dayOfYear),
    status = status,
    is_species = is_species
  )
}

# One yes and one no visit for A in 2020 collapse to one yes opportunity. A in
# 2021 remains a separate no opportunity. B/C/D supply three more no
# opportunities, making yes=1, n=5, rate=20. An uncertain E is excluded.
clock_fixture <- bind_rows(
  obs_row("A", 2020, 1, "no"),
  obs_row("A", 2020, 2, "yes"),
  obs_row("A", 2021, 1, "no"),
  obs_row("B", 2020, 1, "no"),
  obs_row("C", 2020, 1, "no"),
  obs_row("D", 2020, 1, "no"),
  obs_row("E", 2020, 1, "uncertain")
)
clock <- weekly_yesrate(clock_fixture)
check(nrow(clock) == 1L && clock$week[[1L]] == 1L &&
        clock$yes[[1L]] == 1L && clock$n[[1L]] == 5L &&
        identical(clock$rate[[1L]], 20),
      "clock collapses visits within plant-year-week but preserves year opportunities")

clock_sparse <- bind_rows(
  obs_row("A", 2020, 8, "yes"), obs_row("B", 2020, 8, "yes"),
  obs_row("C", 2020, 8, "yes"), obs_row("D", 2020, 8, "yes")
)
check(is.null(weekly_yesrate(clock_sparse)) || nrow(weekly_yesrate(clock_sparse)) == 0L,
      "clock suppresses weeks with fewer than five scored plant-year opportunities")

onset_fixture <- bind_rows(
  obs_row("I1", 2020, 100, "no"),
  obs_row("I1", 2020, 106, "yes"),
  obs_row("I2", 2020, 110, "yes")
)
on <- onset(onset_fixture)
i1 <- on[on$individualID == "I1", ]
i2 <- on[on$individualID == "I2", ]
check(nrow(on) == 2L && i1$onset_doy[[1L]] == 103 &&
        identical(i1$left_censored[[1L]], FALSE) &&
        i2$onset_doy[[1L]] == 110 && identical(i2$left_censored[[1L]], TRUE),
      "onset uses the no-to-yes midpoint and preserves left censoring")

# Two green-up phenophases per plant must first collapse to the earliest onset for
# that plant-year; the species-year support remains three plants, never six rows.
trend_year <- function(y) bind_rows(
  obs_row("T1", y, 100, "no", "Breaking leaf buds"),
  obs_row("T1", 2020, 104, "yes", "Breaking leaf buds"),
  obs_row("T1", 2020, 101, "no", "Initial growth"),
  obs_row("T1", 2020, 107, "yes", "Initial growth"),
  obs_row("T2", 2020, 102, "no", "Breaking leaf buds"),
  obs_row("T2", 2020, 108, "yes", "Breaking leaf buds"),
  obs_row("T2", 2020, 103, "no", "Initial growth"),
  obs_row("T2", 2020, 109, "yes", "Initial growth"),
  obs_row("T3", 2020, 104, "no", "Breaking leaf buds"),
  obs_row("T3", 2020, 110, "yes", "Breaking leaf buds"),
  obs_row("T3", 2020, 105, "no", "Initial growth"),
  obs_row("T3", 2020, 111, "yes", "Initial growth")
)
trend_fixture <- bind_rows(lapply(2019:2021, function(y) { d <- trend_year(y); d$year <- as.integer(y); d }))
tr <- onset_trend(trend_fixture)
check(nrow(tr) == 3L && all(tr$n == 3L) && all(tr$onset == 105),
      "onset trend de-pseudoreplicates phenophases to one value per plant-year")

# Green-up observations from only two individuals create candidate onsets, but no
# supported species-year. The public contract is an unavailable trend (NULL), not
# an empty data-frame container that can look like a valid derived table.
trend_sparse_fixture <- bind_rows(
  obs_row("S1", 2020, 100, "no"),
  obs_row("S1", 2020, 104, "yes"),
  obs_row("S2", 2020, 102, "no"),
  obs_row("S2", 2020, 108, "yes")
)
check(is.null(onset_trend(trend_sparse_fixture)),
      "onset trend normalizes an all-suppressed result to unavailable NULL")

# Two flushes in one year: leaves on days 1 and 8 (no on 15), off until day 50,
# then on days 57 and 64 (no on 71). Each run spans midpoint to midpoint, so the
# span is (11.5 - 1) + (67.5 - 53.5) = 24.5 days; leaf_weeks keeps the old
# weeks-with-yes x 7 (4 weeks = 28) as a QC column.
leaf_fixture <- bind_rows(
  obs_row("L1", 2020, 1, "yes", "Leaves"), obs_row("L1", 2020, 8, "yes", "Leaves"),
  obs_row("L1", 2020, 15, "no", "Leaves"), obs_row("L1", 2020, 50, "no", "Leaves"),
  obs_row("L1", 2020, 57, "yes", "Leaves"), obs_row("L1", 2020, 64, "yes", "Leaves"),
  obs_row("L1", 2020, 71, "no", "Leaves")
)
ko <- key_onsets(leaf_fixture)
check(nrow(ko) == 1L && ko$leaf_active[[1L]] == 24.5 && ko$leaf_weeks[[1L]] == 28L && ko$leaf_off[[1L]] == 64,
      "leaf-active is the interval-censored span of each leaf run and supports multiple flushes")

# A missed mid-season visit does not shorten the season (weeks x 7 did): the
# same plant seen every week or every other week spans the same run.
leaf_dense <- bind_rows(obs_row("L2", 2020, 0, "no", "Leaves"),
  obs_row("L2", 2020, seq(7, 98, by = 7), "yes", "Leaves"), obs_row("L2", 2020, 105, "no", "Leaves"))
leaf_sparse <- bind_rows(obs_row("L2", 2020, 0, "no", "Leaves"),
  obs_row("L2", 2020, seq(7, 98, by = 14), "yes", "Leaves"), obs_row("L2", 2020, 98, "yes", "Leaves"),
  obs_row("L2", 2020, 105, "no", "Leaves"))
check(identical(leaf_spans(leaf_dense)$leaf_active, leaf_spans(leaf_sparse)$leaf_active) &&
        leaf_spans(leaf_dense)$leaf_weeks > leaf_spans(leaf_sparse)$leaf_weeks,
      "leaf-active span is robust to missed mid-season visits while leaf_weeks is not")

coverage <- greenup_coverage(tibble(
  individualID = c("G1", "G2", "G3", "G4"),
  greenup = c(100, NA, 120, NA)
))
check(identical(coverage, 0.5),
      "green-up coverage uses the full tagged-plant denominator and retains structural NA")

gradient_fixture <- tibble(
  scientificName = c(rep("Species alpha", 4), rep("Species beta", 2)),
  greenup = c(100, 103, 103, 107, 130, 132),
  lat = c(30, 31, 32, 33, 30, 31),
  n_years = 3L
)
gradient <- within_species_gradient(gradient_fixture, min_sites = 4)
check(!is.null(gradient) && gradient$species == "Species alpha" &&
        gradient$n_sites == 4L && abs(gradient$slope - 2.1) < 1e-12 &&
        is.finite(gradient$lo) && is.finite(gradient$hi),
      "within-species gradient holds taxonomy constant and carries support plus CI")

# --- audit 2026-10-18 item 12 fixtures ------------------------------------
# n_years must count contributing years, not collapse to 0/1 (summarise
# reassignment gotcha): two plants watched three years each.
ny_fixture <- bind_rows(lapply(2019:2021, function(y) bind_rows(
  obs_row("N1", y, 100, "no"), obs_row("N1", y, 110, "yes"),
  obs_row("N1", y, 150, "yes", "Leaves"), obs_row("N1", y, 157, "yes", "Leaves"),
  obs_row("N2", y, 100, "no"), obs_row("N2", y, 114, "yes"))))
ny_inds <- tibble(individualID = c("N1", "N2"), scientificName = "Species alpha",
                  growthForm = "deciduous broadleaf", plotID = "P1", is_species = TRUE)
ny <- individual_summary(ny_fixture, ny_inds)
check(all(ny$greenup_n_years == 3L) && ny$leaf_active_n_years[ny$individualID == "N1"] == 3L &&
        ny$leaf_active_n_years[ny$individualID == "N2"] == 0L && all(ny$n_years == 3L),
      "per-metric n_years count every contributing year (no summarise reassignment cap)")

# A valid date with a blank dayOfYear is repaired from the date, not dropped.
doy_fixture <- tibble(individualID = "D1", date = as.Date(c("2017-02-14", "2017-03-01")),
                      dayOfYear = c(NA_integer_, 60L))
check(identical(normalize_doy(doy_fixture)$dayOfYear, c(45L, 60L)),
      "normalize_doy fills a blank dayOfYear from its valid date")

# Young leaves is green-up only for the fallback forms, only when no bud-break
# onset exists that plant-year, and the source is recorded.
yl_fixture <- bind_rows(
  obs_row("Y1", 2020, 60, "no", "Young leaves", growthForm = "Drought deciduous broadleaf"),
  obs_row("Y1", 2020, 70, "yes", "Young leaves", growthForm = "Drought deciduous broadleaf"),
  obs_row("Y2", 2020, 60, "no", "Young leaves", growthForm = "Deciduous broadleaf"),
  obs_row("Y2", 2020, 70, "yes", "Young leaves", growthForm = "Deciduous broadleaf"),
  obs_row("Y3", 2020, 80, "no", "Initial growth", growthForm = "Drought deciduous broadleaf"),
  obs_row("Y3", 2020, 90, "yes", "Initial growth", growthForm = "Drought deciduous broadleaf"),
  obs_row("Y3", 2020, 60, "no", "Young leaves", growthForm = "Drought deciduous broadleaf"),
  obs_row("Y3", 2020, 70, "yes", "Young leaves", growthForm = "Drought deciduous broadleaf"),
  obs_row("Y4", 2020, 60, "no", "Young leaves", growthForm = "Evergreen broadleaf - no leaf buds"),
  obs_row("Y4", 2020, 70, "yes", "Young leaves", growthForm = "Evergreen broadleaf - no leaf buds"))
yg <- greenup_onsets(yl_fixture)
check(identical(yg$greenup[yg$individualID == "Y1"], 65) &&
        identical(yg$greenup_source[yg$individualID == "Y1"], "young-leaves") &&
        !"Y2" %in% yg$individualID && !"Y4" %in% yg$individualID &&
        identical(yg$greenup[yg$individualID == "Y3"], 85) &&
        identical(yg$greenup_source[yg$individualID == "Y3"], "bud-break"),
      "Young-leaves green-up fallback is form-scoped, per plant-year, and bud-break wins")

# The species-year onset trend stays bud-break-only: three drought-deciduous
# plants with only a Young-leaves first flush give a per-plant green-up but no
# trend point (rain-driven flushes are not a single-cycle annual onset).
yl_trend <- bind_rows(lapply(c("Z1", "Z2", "Z3"), function(id) bind_rows(lapply(2019:2021, function(y) bind_rows(
  obs_row(id, y, 60, "no", "Young leaves", growthForm = "Drought deciduous broadleaf"),
  obs_row(id, y, 70, "yes", "Young leaves", growthForm = "Drought deciduous broadleaf"))))))
check(nrow(greenup_onsets(yl_trend)) == 9L && all(site_year_support(yl_trend)$greenup_supported) &&
        is.null(onset_trend(yl_trend)),
      "onset trend excludes Young-leaves first flushes while per-plant green-up keeps them")

# Site-year support: a year visited at half the usual weekly effort is excluded
# from leaf-active and green-up medians but kept in key_onsets with a flag.
sup_fixture <- bind_rows(lapply(c("S1", "S2", "S3"), function(id) bind_rows(
  bind_rows(lapply(2018:2020, function(y) {
    wk <- if (y == 2019) seq(1, 361, by = 14) else seq(1, 361, by = 7)
    obs_row(id, y, wk, "yes", "Leaves") })))))
sup <- site_year_support(sup_fixture)
ko_sup <- key_onsets(sup_fixture)
las <- leaf_active_trend(sup_fixture)
check(identical(sup$leaf_reason, c("supported", "low_effort", "supported")) &&
        identical(sup$greenup_reason, sup$leaf_reason) &&
        identical(sup$leaf_supported, c(TRUE, FALSE, TRUE)) &&
        all(!ko_sup$leaf_supported[ko_sup$year == 2019]) && !2019 %in% las$year,
      "site-year support gate excludes a half-effort year from leaf-active medians and trends")

# Partial-year (carry-over) rule. C1: 'yes' at the last December visit and at
# the first January visit, then no and a new yes: the onset is that later
# transition, not a censored January day. C2: 'no' in late December, 'yes' in
# early January: bounded by the new-year gap (clamped midpoint), not censored.
# C3: the previous visit is months earlier: genuinely left-censored.
carry_fixture <- bind_rows(
  obs_row("C1", 2019, 360, "yes", "Initial growth"), obs_row("C1", 2020, 4, "yes", "Initial growth"),
  obs_row("C1", 2020, 60, "no", "Initial growth"), obs_row("C1", 2020, 74, "yes", "Initial growth"),
  obs_row("C2", 2019, 358, "no", "Initial growth"), obs_row("C2", 2020, 10, "yes", "Initial growth"),
  obs_row("C3", 2019, 250, "no", "Initial growth"), obs_row("C3", 2020, 100, "yes", "Initial growth"))
cg <- greenup_onsets(carry_fixture); cg <- cg[cg$year == 2020, ]
c1 <- cg[cg$individualID == "C1", ]; c2 <- cg[cg$individualID == "C2", ]; c3 <- cg[cg$individualID == "C3", ]
check(identical(c1$greenup, 67) && isTRUE(c1$carryover) && identical(c1$left_censored, FALSE) &&
        identical(c2$greenup, 1.5) && identical(c2$left_censored, FALSE) &&
        identical(c3$greenup, 100) && isTRUE(c3$left_censored),
      "carry-over rule separates December leaves, bridged new-year onsets and true left-censoring")

# Autumn-germinating forms: a form with >= 10 plant-years and >= 35% of onsets
# on or after Oct 1 is dropped from green-up; a spring form at the same site stays.
autumn_fixture <- bind_rows(
  bind_rows(lapply(1:10, function(i) bind_rows(
    obs_row(paste0("A", i), 2020, 280, "no", "Initial growth", growthForm = "Graminoid"),
    obs_row(paste0("A", i), 2020, 300, "yes", "Initial growth", growthForm = "Graminoid")))),
  obs_row("B1", 2020, 80, "no", "Initial growth", growthForm = "Forb"),
  obs_row("B1", 2020, 90, "yes", "Initial growth", growthForm = "Forb"))
ag <- greenup_onsets(autumn_fixture)
check(identical(attr(ag, "autumn_forms"), "Graminoid") && identical(ag$individualID, "B1"),
      "autumn-germinating forms are dropped from calendar-year green-up")

# Carry-over-dominated forms: a form whose plant-years are mostly green across
# the new year (>= 35% of >= 10 carried over) has no calendar-year green-up; its
# "next flush" (here day 170) is a different event. A deciduous tree stays.
carry_form <- bind_rows(
  bind_rows(lapply(1:10, function(i) { id <- paste0("G", i); bind_rows(
    obs_row(id, 2019, c(5, 360), "yes", "Initial growth", growthForm = "Graminoid"),
    obs_row(id, 2020, 4, "yes", "Initial growth", growthForm = "Graminoid"),
    obs_row(id, 2020, 60, "no", "Initial growth", growthForm = "Graminoid"),
    obs_row(id, 2020, 280, "yes", "Initial growth", growthForm = "Graminoid")) })),
  obs_row("D1", 2020, 80, "no", "Breaking leaf buds", growthForm = "Deciduous broadleaf"),
  obs_row("D1", 2020, 90, "yes", "Breaking leaf buds", growthForm = "Deciduous broadleaf"))
cf <- greenup_onsets(carry_form)
check(identical(attr(cf, "carry_forms"), "Graminoid") && identical(attr(cf, "autumn_forms"), character(0)) &&
        identical(unique(cf$individualID), "D1"),
      "carry-over-dominated forms are dropped from calendar-year green-up")

# Late start: a first visit 40 days late is late_start only when most of that
# year's onsets were already underway; a late but uncensored year stays.
late_obs <- function(id, y, days, yes_from) bind_rows(
  obs_row(id, y, days[days < yes_from], "no", "Initial growth"),
  obs_row(id, y, days[days >= yes_from], "yes", "Initial growth"))
normal_days <- seq(10, 200, by = 7); late_days <- seq(50, 225, by = 7)
late_fixture <- bind_rows(lapply(c("P1", "P2", "P3"), function(id) bind_rows(
  bind_rows(lapply(2016:2019, function(y) late_obs(id, y, normal_days, 101))),
  late_obs(id, 2020, late_days, 101),
  late_obs(id, 2021, late_days, 0))))
ls_sup <- site_year_support(late_fixture)
check(identical(ls_sup$greenup_reason, c(rep("supported", 5), "late_start")) &&
        identical(ls_sup$lc_share, c(0, 0, 0, 0, 0, 1)) &&
        identical(ls_sup$leaf_reason, c(rep("supported", 4), "late_start", "late_start")),
      "late start counts per metric, only when that metric was already underway at the first visit")

# Coverage guard: a late year whose few onsets are uncensored but whose green-up
# coverage collapsed (bud-break ended before the first visit) is still late_start.
cov_fixture <- bind_rows(
  bind_rows(lapply(c("P1", "P2", "P3"), function(id)
    bind_rows(lapply(2016:2019, function(y) late_obs(id, y, normal_days, 101))))),
  late_obs("P1", 2020, late_days, 101),
  obs_row("P2", 2020, late_days, "no", "Leaves"), obs_row("P3", 2020, late_days, "no", "Leaves"))
cv_sup <- site_year_support(cov_fixture)
check(identical(cv_sup$greenup_reason, c(rep("supported", 4), "late_start")) &&
        identical(cv_sup$lc_share[5], 0) && cv_sup$greenup_coverage_ratio[5] < LATE_START_COVERAGE,
      "a late year with collapsed green-up coverage is late_start even when uncensored")

# Leaf metrics: a late year where most plants were already in leaf at the first
# visit is unsupported for leaf-active (the span is truncated) even when its
# green-up was observed; a late year that starts before leaf-out stays.
leaf_late <- function(id, y, days, leaf_from) bind_rows(
  obs_row(id, y, days[days < leaf_from], "no", "Leaves"),
  obs_row(id, y, days[days >= leaf_from], "yes", "Leaves"))
leaf_fixture <- bind_rows(lapply(c("Q1", "Q2", "Q3"), function(id) bind_rows(
  bind_rows(lapply(2016:2019, function(y) leaf_late(id, y, normal_days, 101))),
  leaf_late(id, 2020, late_days, 101),
  leaf_late(id, 2021, late_days, 0))))
lf_sup <- site_year_support(leaf_fixture)
check(identical(lf_sup$leaf_reason, c(rep("supported", 5), "late_start")) &&
        identical(lf_sup$leaf_first_share, c(0, 0, 0, 0, 0, 1)),
      "a late year already in leaf at the first visit is unsupported for leaf-active only")

# Two-stage bounds on plant-year visit brackets: tight brackets -> point; one
# censored plant-year among four -> range; most plants censored -> upper bound
# with the numeric value withheld. Brackets are the midpoint -/+ 3 days, and a
# censored plant-year has no lo and hi equal to its first 'yes' (the value).
bk <- function(g, lc) tibble(individualID = paste0("P", seq_along(g)), greenup = g,
                             greenup_lo = ifelse(lc, NA_real_, g - 3), greenup_hi = ifelse(lc, g, g + 3),
                             left_censored = lc)
b_point <- greenup_bounds(bk(c(100, 104, 110), c(FALSE, FALSE, FALSE)))
b_range <- greenup_bounds(bk(c(40, 60, 100, 120), c(FALSE, TRUE, FALSE, FALSE)))
b_upper <- greenup_bounds(bk(c(60, 70, 100), c(TRUE, TRUE, FALSE)))
check(b_point$status == "point" && b_point$value == 104 && b_point$lo == 101 && b_point$hi == 107 &&
        b_range$status == "range" && b_range$lo == 67 && b_range$hi == 82 && b_range$value == 80 &&
        identical(greenup_label(b_range$value, b_range$lo, b_range$hi, b_range$status), "day 67 to 82") &&
        identical(greenup_label(b_point$value, b_point$lo, b_point$hi, b_point$status), "day 104"),
      "two-stage bounds label a range when censoring moves the lower bound")
check(b_upper$status == "upper_bound" && is.na(b_upper$value) && is.na(b_upper$lo) &&
        b_upper$hi == 70 && identical(greenup_label(NA, NA, 70, "upper_bound"), "day 70 or earlier") &&
        identical(greenup_label(NA, NA, NA, "short_record", 2L),
                  "unavailable: 2 seasons monitored, too few to check the schedule") &&
        is.na(greenup_label(NA, NA, NA, "none")),
      "an upper-bound green-up withholds the number and reads 'or earlier'")

# --- estimand sign-off 2026-10-21 fixtures (iris; rules.md sections 2 to 9) ---
# 1. Per-plant-year brackets. C1 carried over: the later no-to-yes pair [60, 74];
# C2 bridged: [1, 10] (the December 'no' clamps to day 1); C3 left-censored: no
# lo, hi = the first 'yes'; C4 standard: [100, 107].
br_fixture <- bind_rows(carry_fixture,
  obs_row("C4", 2020, 100, "no", "Initial growth"), obs_row("C4", 2020, 107, "yes", "Initial growth"))
bg <- greenup_onsets(br_fixture); bg <- bg[bg$year == 2020, ]
bgi <- function(id) bg[bg$individualID == id, ]
check(identical(bgi("C1")$greenup, 67) && identical(bgi("C1")$greenup_lo, 60) && identical(bgi("C1")$greenup_hi, 74) &&
        isTRUE(bgi("C1")$carryover) &&
        identical(bgi("C2")$greenup, 1.5) && identical(bgi("C2")$greenup_lo, 1) && identical(bgi("C2")$greenup_hi, 10) &&
        identical(bgi("C3")$greenup, 100) && is.na(bgi("C3")$greenup_lo) && identical(bgi("C3")$greenup_hi, 100) &&
        isTRUE(bgi("C3")$left_censored) &&
        identical(bgi("C4")$greenup, 103.5) && identical(bgi("C4")$greenup_lo, 100) && identical(bgi("C4")$greenup_hi, 107),
      "green-up brackets follow the standard, bridged, carried-over and censored rules")

# 2. Site bounds from three plants per case, through greenup_onsets().
site_case <- function(no, yes) bind_rows(lapply(seq_along(yes), function(i) bind_rows(
  if (!is.na(no[i])) obs_row(paste0("B", i), 2020, no[i], "no"), obs_row(paste0("B", i), 2020, yes[i], "yes"))))
case_bounds <- function(no, yes) { b <- greenup_bounds(greenup_onsets(site_case(no, yes)))
  b$label <- greenup_label(b$value, b$lo, b$hi, b$status); b }
cb1 <- case_bounds(c(60, 60, 60), c(120, 120, 120))
cb2 <- case_bounds(c(100, 100, 100), c(113, 113, 113))
cb3 <- case_bounds(c(100, 100, 100), c(114, 114, 114))
cb4 <- case_bounds(c(NA, NA, 60), c(72, 74, 80))
check(cb1$status == "range" && cb1$value == 90 && identical(cb1$label, "day 60 to 120") &&
        cb2$status == "point" && cb2$value == 106 && identical(cb2$label, "day 106") &&
        cb3$status == "range" && identical(cb3$label, "day 100 to 114") &&
        cb4$status == "upper_bound" && is.na(cb4$value) && cb4$hi == 74 && identical(cb4$label, "day 74 or earlier"),
      "a 13-day bracket is a point, a 14-day bracket a range, an open bracket an upper bound")

# 3. lc_share per species-year: three censored plant-years of seven in 2020.
lc_fixture <- bind_rows(lapply(2018:2020, function(y) bind_rows(
  lapply(c("P1", "P2", "P3", "P4"), function(id)
    if (y == 2020 && id %in% c("P1", "P2")) obs_row(id, y, 100, "yes") else
      bind_rows(obs_row(id, y, 93, "no"), obs_row(id, y, 100, "yes"))),
  lapply(c("Q1", "Q2", "Q3"), function(id)
    if (y == 2020 && id == "Q1") obs_row(id, y, 100, "yes", scientificName = "Species beta") else
      bind_rows(obs_row(id, y, 93, "no", scientificName = "Species beta"),
                obs_row(id, y, 100, "yes", scientificName = "Species beta"))))))
lt_tr <- onset_trend(lc_fixture)
lt_a <- lt_tr[lt_tr$scientificName == "Species alpha" & lt_tr$year == 2020, ]
lt_b <- lt_tr[lt_tr$scientificName == "Species beta" & lt_tr$year == 2020, ]
lt_o <- lt_tr[lt_tr$year != 2020, ]
check(nrow(lt_tr) == 6L && identical(names(lt_tr)[ncol(lt_tr)], "lc_share") &&
        lt_a$onset == 98 && lt_a$lc_share == 0.5 &&
        lt_b$onset == 96 && lt_b$lc_share == 0.333 &&
        all(lt_o$onset == 96) && all(lt_o$lc_share == 0) &&
        identical(trend_hollow(lt_tr), lt_tr$scientificName == "Species alpha" & lt_tr$year == 2020),
      "onset trend carries lc_share and a half-censored species-year is hollow")

# 4. Trend verdict, one species point per year 2017-2022 (fit A 1.03 per year).
tv_base <- tibble(scientificName = "Species alpha", year = 2017:2022,
                  onset = c(100, 102, 101, 104, 103, 106), n = 3L, lc_share = 0)
tv_low <- bind_rows(tv_base, tibble(scientificName = "Species alpha", year = 2023L, onset = 60, n = 3L, lc_share = 0.5))
tv_high <- tv_low; tv_high$onset[tv_high$year == 2023] <- 108
tv_short <- tv_base; tv_short$lc_share[tv_short$year %in% c(2018, 2020)] <- 0.5
v_low <- trend_verdict(tv_low); v_high <- trend_verdict(tv_high); v_short <- trend_verdict(tv_short)
r2 <- function(x) round(x, 2)
check(v_low$verdict == "depends" && r2(v_low$slope) == 1.03 && r2(v_low$lo) == 0.30 && r2(v_low$hi) == 1.76 &&
        r2(v_low$slope_all) == -3.93 && r2(v_low$lo_all) == -11.30 && r2(v_low$hi_all) == 3.44 &&
        v_low$ny == 6L && v_low$ny_all == 7L && v_low$n_points == 7L && v_low$n_left_out == 1L &&
        v_high$verdict == "up" && r2(v_high$slope) == 1.03 &&
        v_short$verdict == "too_short" && v_short$ny == 4L &&
        all(is.na(unlist(v_short[c("slope", "lo", "hi", "slope_all", "lo_all", "hi_all")]))) &&
        trend_verdict(NULL)$verdict == "too_short" && trend_verdict(NULL)$n_points == 0L,
      "trend verdict separates a robust direction from one that depends on left-out points")

# 5. Leaf spans with the year-boundary bridge.
lf_full <- bind_rows(lapply(2019:2021, function(y) obs_row("F1", y, seq(5, 362, 14), "yes", "Leaves")))
lsf <- leaf_spans(lf_full)
check(identical(lsf$leaf_active, c(361, 366, 354)) &&
        identical(lsf$leaf_edge_start, c(TRUE, FALSE, FALSE)) && identical(lsf$leaf_edge_end, c(FALSE, FALSE, TRUE)) &&
        identical(lsf$leaf_active_hi, c(365, 366, 365)),
      "a plant in leaf all year is bridged across the new year, with edges only at the record's ends")
lf_clamp <- bind_rows(
  obs_row("K1", 2019, 358, "no", "Leaves"), obs_row("K1", 2020, c(10, 100), "yes", "Leaves"), obs_row("K1", 2020, 107, "no", "Leaves"),
  obs_row("K2", 2019, 350, "no", "Leaves"), obs_row("K2", 2020, c(10, 100), "yes", "Leaves"), obs_row("K2", 2020, 107, "no", "Leaves"),
  obs_row("K3", 2019, 340, "no", "Leaves"), obs_row("K3", 2020, c(10, 100), "yes", "Leaves"), obs_row("K3", 2020, 107, "no", "Leaves"),
  obs_row("K4", 2020, 200, "no", "Leaves"), obs_row("K4", 2020, c(207, 360), "yes", "Leaves"), obs_row("K4", 2021, 20, "no", "Leaves"),
  obs_row("K5", 2020, 200, "no", "Leaves"), obs_row("K5", 2020, c(207, 360), "yes", "Leaves"), obs_row("K5", 2021, 30, "no", "Leaves"))
lsc <- leaf_spans(lf_clamp)
lsc <- lsc[order(lsc$individualID, method = "radix"), ]
check(identical(lsc$individualID, paste0("K", 1:5)) && all(lsc$year == 2020L) &&
        identical(lsc$leaf_active, c(102, 102.5, 93.5, 163.5, 156.5)) &&
        identical(lsc$leaf_edge_start, c(FALSE, FALSE, TRUE, FALSE, FALSE)) &&
        identical(lsc$leaf_edge_end, c(FALSE, FALSE, FALSE, FALSE, TRUE)) &&
        lsc$leaf_active_hi[3] == 102.5 && lsc$leaf_active_hi[5] == 163.5,
      "a 'no' across the new year bridges to the clamped midpoint; beyond 31 days the edge is flagged")

# 6. Support plus bridge: the leaf trend reads spans built on every year, so the
# low-effort 2019 still closes the 2018 and 2020 edges.
lt_sup <- bind_rows(lapply(c("S1", "S2", "S3"), function(id) bind_rows(lapply(2018:2021, function(y)
  obs_row(id, y, if (y == 2019) seq(5, 362, 28) else seq(5, 362, 7), "yes", "Leaves")))))
lat <- leaf_active_trend(lt_sup); ko_lt <- key_onsets(lt_sup)
ko_s1 <- ko_lt[ko_lt$individualID == "S1" & ko_lt$year %in% lat$year, ]
check(identical(lat$year, c(2018L, 2020L, 2021L)) && identical(lat$onset, c(361, 366, 361)) &&
        identical(ko_s1$leaf_active[order(ko_s1$year)], lat$onset) &&
        identical(lat$onset_hi, c(365, 366, 365)) && !any(trend_hollow(lat)),
      "leaf-active trend builds spans on all years before keeping supported ones")

# 7. Leaf lower bound: E1 and E2 are still in leaf at their last visit every year,
# with no visit across the new year.
lb_obs <- function(last) bind_rows(lapply(2020:2021, function(y) bind_rows(
  obs_row("E1", y, 100, "no", "Leaves"), obs_row("E1", y, c(107, last), "yes", "Leaves"),
  obs_row("E2", y, 100, "no", "Leaves"), obs_row("E2", y, c(107, last), "yes", "Leaves"),
  obs_row("E3", y, 100, "no", "Leaves"), obs_row("E3", y, 107, "yes", "Leaves"), obs_row("E3", y, last, "no", "Leaves"))))
lb1 <- leaf_bounds(leaf_spans(lb_obs(300))); lb2 <- leaf_bounds(leaf_spans(lb_obs(355)))
check(lb1$status == "lower_bound" && lb1$value == 196 && lb1$hi == 263 &&
        identical(leaf_label(lb1$value, lb1$status), "at least 196 days") && lb1$edge_share == round(4 / 6, 3) &&
        lb2$status == "point" && lb2$value == 252 && identical(leaf_label(lb2$value, lb2$status), "252 days") &&
        leaf_bounds(NULL)$status == "none" && is.na(leaf_label(NA, "none")),
      "an unbridged leaf edge makes the site span a lower bound read 'at least'")

# individual_summary carries the leaf bound columns and counts edge years before
# any reassignment: three seasons so every year is supported.
ie_obs <- bind_rows(lapply(2019:2021, function(y) bind_rows(
  obs_row("E1", y, 100, "no", "Leaves"), obs_row("E1", y, c(107, 300), "yes", "Leaves"),
  obs_row("E3", y, 100, "no", "Leaves"), obs_row("E3", y, 107, "yes", "Leaves"), obs_row("E3", y, 300, "no", "Leaves"))))
ie_inds <- tibble(individualID = c("E1", "E3"), scientificName = "Species alpha",
                  growthForm = "deciduous broadleaf", plotID = "P1", is_species = TRUE)
ie <- individual_summary(ie_obs, ie_inds)
e1 <- ie[ie$individualID == "E1", ]; e3 <- ie[ie$individualID == "E3", ]
check(identical(names(ie), c(names(ie_inds), "greenup", "flower", "leaf_off", "leaf_active", "leaf_active_hi",
                             "greenup_source", "greenup_n_years", "flower_n_years", "leaf_active_n_years",
                             "greenup_lc_years", "leaf_edge_years", "leaf_active_lower_bound", "n_years",
                             "n_years_watched")) &&
        e1$leaf_edge_years == 3L && e3$leaf_edge_years == 0L &&
        e1$leaf_active == 196 && e1$leaf_active_hi == 262 && isTRUE(e1$leaf_active_lower_bound) &&
        e3$leaf_active == 100 && e3$leaf_active_hi == 100 && identical(e3$leaf_active_lower_bound, FALSE),
      "individual summary carries leaf_active_hi, leaf_edge_years and the lower-bound flag")

# --- within-species gradient amendments (hk, rules.md section 10) -------------
gr_rows <- function(sp, sites, lat, value, n_years, leaf_n_years = n_years)
  tibble(scientificName = sp, site = sites, lat = lat, greenup = value, leaf_active = value,
         n_years = n_years, leaf_n_years = leaf_n_years)
# The year floor runs before the species is chosen: A has 6 sites but 3 rest on
# 2 seasons; B keeps 5 (3 seasons is enough), and its 2-season and NA rows are
# the exact exclusions.
gf <- bind_rows(
  gr_rows("Species A", sprintf("S%02d", 1:6), 30:35, c(100, 102, 104, 106, 108, 110), c(5L, 5L, 5L, 2L, 2L, 2L)),
  gr_rows("Species B", sprintf("S%02d", c(1:5, 7, 8)), c(30:34, 36, 37), c(90, 93, 92, 96, 97, 99, 101),
          c(3L, 3L, 3L, 3L, 3L, 2L, NA)))
g_floor <- within_species_gradient(gf, min_sites = 4)
check(!is.null(g_floor) && g_floor$species == "Species B" && g_floor$n_sites == 5L &&
        g_floor$n_excluded_short == 2L && identical(g_floor$excluded_sites, c("S07", "S08")) &&
        is.null(within_species_gradient(gf[, names(gf) != "n_years"], min_sites = 4)),
      "gradient year floor runs before the species choice and names the excluded sites")
# Spearman rho with the Fisher z (Bonett-Wright) interval; perfect ranks give NA.
gr <- gr_rows("Species A", sprintf("S%02d", 1:6), 30:35, c(100, 101, 102, 104, 103, 105), 4L)
g_rho <- within_species_gradient(gr)
rho0 <- 33 / 35; zse <- sqrt((1 + rho0^2 / 2) / 3)
g_perf <- within_species_gradient(gr_rows("Species A", sprintf("S%02d", 1:7), 30:36, 100:106, 4L))
check(!is.null(g_rho) && abs(g_rho$rho - 33 / 35) < 1e-12 &&
        abs(g_rho$rho_lo - tanh(atanh(rho0) - qnorm(0.975) * zse)) < 1e-12 &&
        abs(g_rho$rho_hi - tanh(atanh(rho0) + qnorm(0.975) * zse)) < 1e-12 &&
        identical(g_rho$n_excluded_short, 0L) && identical(g_rho$excluded_sites, character(0)) &&
        !is.null(g_perf) && is.na(g_perf$rho_lo) && is.na(g_perf$rho_hi) &&
        is.null(within_species_gradient(gr[1:5, ])),
      "gradient carries Spearman rho with a Fisher z interval, NA at perfect ranks, and needs six sites")
# Radix tie-break, the per-metric year column, and a duplicated site.
g_tie <- within_species_gradient(bind_rows(
  gr_rows("Species b", sprintf("S%02d", 1:6), 30:35, 100:105, 3L),
  gr_rows("Species a", sprintf("S%02d", 1:6), 30:35, 110:115, 3L)))
gl <- gr_rows("Species A", sprintf("S%02d", 1:6), 30:35, c(100, 102, 101, 104, 106, 105), 5L,
              c(5L, 5L, 5L, 5L, 5L, 1L))
g_gu <- within_species_gradient(gl)
g_lf <- within_species_gradient(gl, value = "leaf_active", years = "leaf_n_years", min_sites = 5)
gdup <- gr; gdup$site[2] <- "S01"
check(!is.null(g_tie) && g_tie$species == "Species a" &&
        g_gu$n_sites == 6L && g_gu$n_excluded_short == 0L &&
        g_lf$n_sites == 5L && identical(g_lf$excluded_sites, "S06") &&
        is.null(within_species_gradient(gl, value = "leaf_active", years = "leaf_n_years")) &&
        is.null(within_species_gradient(gdup)),
      "gradient ties go to radix order, years are per metric, and a duplicated site gives NULL")
# national_onsets rows carry the years behind each value: 2019 is fully visited
# but has no leaf row (Leaves scored 'no'), so leaf_n_years is 2 of 3.
yo <- bind_rows(lapply(2019:2021, function(y) bind_rows(lapply(c("W1", "W2", "W3"), function(id) bind_rows(
  obs_row(id, y, 100, "no"), obs_row(id, y, 107, "yes"),
  obs_row(id, y, c(150, 157), if (y == 2019) "no" else "yes", "Leaves"))))))
yo_inds <- tibble(individualID = c("W1", "W2", "W3"), scientificName = "Species alpha",
                  growthForm = "deciduous broadleaf", is_species = TRUE)
yso <- site_species_onsets(yo, yo_inds, list(site = "XXXX", lat = 40, lng = -100))
check(nrow(yso) == 1L && identical(yso$n_years, 3L) && identical(yso$leaf_n_years, 2L) &&
        identical(names(yso)[match("leaf_active_lower_bound", names(yso)) + 1:2], c("n_years", "leaf_n_years")),
      "species x site rows count supported green-up years and leaf years separately")

# The site leaf value is built on the inds roster: a plant in obs but not in
# inds (DSNY 00653 in the committed data) must not move median_leaf_active, its
# hi or the edge share. Three seasons so every year is supported.
ri_obs <- bind_rows(lapply(2019:2021, function(y) bind_rows(
  obs_row("R1", y, 100, "no", "Leaves"), obs_row("R1", y, 107, "yes", "Leaves"), obs_row("R1", y, 200, "no", "Leaves"),
  obs_row("R2", y, 100, "no", "Leaves"), obs_row("R2", y, 107, "yes", "Leaves"), obs_row("R2", y, 220, "no", "Leaves"),
  obs_row("RX", y, 100, "no", "Leaves"), obs_row("RX", y, c(107, 300), "yes", "Leaves"))))
ri_obs$date <- obs_dates(ri_obs)
ri_inds <- tibble(individualID = c("R1", "R2"), scientificName = "Species alpha",
                  growthForm = "deciduous broadleaf", plotID = "P1", is_species = TRUE)
ri_meta <- list(site = "XXXX", lat = 40, lng = -100)
ri_all <- site_phe_summary(ri_obs, ri_inds, ri_meta)
ri_own <- site_phe_summary(ri_obs[ri_obs$individualID != "RX", ], ri_inds, ri_meta)
# R1 spans 50 days and R2 60 (median 55); RX's 196.5-day span with an end edge
# would move the value to 60, the hi up and the edge share above 0
check(identical(ri_all$median_leaf_active, 55) &&
        identical(ri_all$median_leaf_active, ri_own$median_leaf_active) &&
        identical(ri_all$leaf_active_hi, ri_own$leaf_active_hi) &&
        identical(ri_all$leaf_edge_share, 0) && identical(ri_all$leaf_active_status, "point"),
      "a plant in obs but not in inds does not move the site leaf-active summary")

# --- QC flags and uncertain share (iris sign-off 2026-10-21) ------------------
# qc_grid(): one plant's history from a phase x visit grid, one letter per visit
# day: Y yes, n no, u uncertain, . not scored.
qc_grid <- function(days, spec, year = 2020L) {
  code <- c(Y = "yes", n = "no", u = "uncertain")
  h <- bind_rows(lapply(names(spec), function(p) {
    s <- strsplit(spec[[p]], "")[[1]]; stopifnot(length(s) == length(days)); k <- s != "."
    tibble(year = as.integer(year), dayOfYear = as.numeric(days[k]), phenophaseName = p,
           status = unname(code[s[k]]), intensity = NA_character_) }))
  h$date <- as.Date(sprintf("%d-01-01", as.integer(year))) + h$dayOfYear - 1
  h[order(h$date, method = "radix"), ]
}
qc_flag <- function(h, gf, key) {
  f <- Filter(function(x) x$key == key, pheno_qc_flags(h, gf)$flags)
  if (length(f)) paste0(f[[1]]$level, ":", f[[1]]$n) else NA_character_
}
DB <- "Deciduous broadleaf"
d4 <- c(100, 107, 114, 121)
oo <- c(
  # OO-1: Colored leaves and Leaves first 'yes' at the same visit (a tie passes)
  oo1 = qc_flag(qc_grid(d4, list("Breaking leaf buds" = "nYYn", "Leaves" = "nnYY", "Colored leaves" = "nnYY")), DB, "outoforder"),
  # OO-2: the year is entered in leaf (first Leaves record 'yes'), so it is skipped
  oo2 = qc_flag(qc_grid(c(5, 12, 80, 87), list("Leaves" = "YYYY", "Colored leaves" = "YnnY",
                                                "Falling leaves" = "YYnn", "Breaking leaf buds" = "nnYn")), DB, "outoforder"),
  # OO-3: last year's leaves fall in February before bud-break: not this season's
  oo3 = qc_flag(qc_grid(c(5, 40, 47, 80, 87, 280, 287), list("Leaves" = "nnnnYYY", "Falling leaves" = "nYYnnnY",
                                                              "Breaking leaf buds" = "nnnYnnn", "Colored leaves" = "nnnnnYY")), DB, "outoforder"),
  # OO-4: Leaves at 104, bud-break at the very next visit (107): one-visit slack
  oo4 = qc_flag(qc_grid(c(100, 104, 107, 111), list("Breaking leaf buds" = "nnYY", "Leaves" = "nYYY")), DB, "outoforder"),
  # OO-6: a 'yes' more than 31 days after the 'no' is not an observed transition
  oo6 = qc_flag(qc_grid(c(2, 240, 247), list("Leaves" = "nYY", "Breaking leaf buds" = "nnY")), DB, "outoforder"),
  # OO-7: a forb is never checked
  oo7 = qc_flag(qc_grid(c(85, 88, 92, 99, 106, 113, 116), list("Initial growth" = "nnnnnYY", "Leaves" = "nYnnnnY")),
                "Forb", "outoforder"),
  # OO-8: Falling leaves before Colored leaves after leaf-out (same rank)
  oo8 = qc_flag(qc_grid(c(100, 110, 250, 260, 263), list("Breaking leaf buds" = "nYnnn", "Leaves" = "nYYYY",
                                                          "Falling leaves" = "nnnYY", "Colored leaves" = "nnnnY")), DB, "outoforder"))
check(all(is.na(oo)), "out-of-sequence check passes ties, in-leaf years, old-leaf fall, one-visit slack, long gaps, forbs and senescence order")
# OO-5: an isolated Leaves 'yes' 25 days before bud-break fires, warn, 3 rows
oo5_h <- qc_grid(c(85, 88, 92, 99, 106, 113, 116), list("Breaking leaf buds" = "nnnnnYY", "Leaves" = "nYnnnnY"))
oo5 <- Filter(function(x) x$key == "outoforder", pheno_qc_flags(oo5_h, DB)$flags)
# OO-9: Colored leaves during leaf-out, before Leaves by two visits, fires
oo9 <- qc_flag(qc_grid(c(100, 107, 114, 121, 128), list("Breaking leaf buds" = "nYYnn", "Colored leaves" = "nYYnn",
                                                         "Leaves" = "nnnYY")), DB, "outoforder")
check(length(oo5) == 1L && oo5[[1]]$level == "warn" && oo5[[1]]$n == 3L &&
        identical(oo5[[1]]$text, paste0("A later leaf stage was first recorded before an earlier one: Leaves on day 88 ",
                                        "before Breaking leaf buds on day 113 (2020). Check whether the earlier stage was ",
                                        "missed at those visits or the later record is a mistake.")) &&
        identical(oo9, "warn:3"),
      "a real leaf-stage inversion fires as warn with the stages, days and year in the text")
# Green-up outlier: single-cycle forms, uncensored and not carried-over years only.
qc_gu <- function(yrs, first_days, lc_year = NA) bind_rows(lapply(seq_along(yrs), function(i) {
  f <- first_days[i]
  if (identical(yrs[i], lc_year)) qc_grid(c(f, f + 7), list("Breaking leaf buds" = "YY"), yrs[i])
  else qc_grid(c(f - 7, f, f + 7), list("Breaking leaf buds" = "nYY"), yrs[i]) }))
out1 <- qc_flag(qc_gu(2016:2019, c(100, 102, 98, 40), lc_year = 2019L), DB, "outlier")
out2 <- qc_flag(qc_gu(2016:2018, c(60, 65, 150)), "Graminoid", "outlier")
out3 <- qc_flag(qc_gu(2016:2019, c(100, 104, 98, 160)), DB, "outlier")
check(is.na(out1) && is.na(out2) && identical(substr(out3, 1, 5), "warn:"),
      "green-up outlier skips censored years and multi-cycle forms and fires on a real outlier")
# Same-visit conflicts: a yes and a no on one day list both rows (warn when the
# day is the phase-year's first 'yes'); an exact duplicate is not a conflict.
cf_h <- qc_grid(c(100, 107), list("Breaking leaf buds" = "nY"))
cf1 <- bind_rows(cf_h, transform(cf_h[cf_h$dayOfYear == 107, ], status = "no"))
cf2 <- bind_rows(cf_h, cf_h[cf_h$dayOfYear == 107, ])
cf3_h <- qc_grid(c(100, 107, 114), list("Breaking leaf buds" = "nYY"))
cf3 <- bind_rows(cf3_h, transform(cf3_h[cf3_h$dayOfYear == 114, ], status = "no"))
cf1_flag <- Filter(function(x) x$key == "conflict", pheno_qc_flags(cf1, DB)$flags)
cf1_rep <- phe_qc_report(cf1, DB)
check(identical(qc_flag(cf1, DB, "conflict"), "warn:2") && is.na(qc_flag(cf2, DB, "conflict")) &&
        identical(qc_flag(cf3, DB, "conflict"), "info:2") &&
        grepl("^On 1 visit, two records", cf1_flag[[1]]$text) &&
        sum(cf1_rep$flag == "Same visit recorded both yes and no") == 2L,
      "a same-visit yes/no conflict lists both rows, warn only when it sets an onset, and reaches the QC report")
# uncertain_share: 2 of 7 scored rows are 'uncertain' (unrounded).
un_obs <- bind_rows(obs_row("U1", 2020, c(100, 107, 114), c("no", "yes", "uncertain"), "Leaves"),
                    obs_row("U2", 2020, c(100, 107, 114, 121), c("no", "uncertain", "yes", "yes"), "Leaves"))
un_obs$date <- obs_dates(un_obs)
un_site <- site_phe_summary(un_obs, tibble(individualID = c("U1", "U2"), scientificName = "Species alpha",
                                           growthForm = "deciduous broadleaf", plotID = "P1", is_species = TRUE),
                            list(site = "XXXX", lat = 40, lng = -100))
check(identical(un_site$uncertain_share, 2 / 7) &&
        identical(names(un_site)[match("greenup_fallback_share", names(un_site)) + 1L], "uncertain_share"),
      "uncertain_share is the unrounded share of scored rows recorded uncertain")

# A site watched for fewer than three seasons cannot be checked against itself.
short_fixture <- bind_rows(obs_row("S1", 2016, c(150, 157), "yes", "Leaves"),
                           obs_row("S1", 2017, c(150, 157), "yes", "Leaves"))
ss <- site_year_support(short_fixture)
check(!any(ss$greenup_supported) && !any(ss$leaf_supported) &&
        all(ss$greenup_reason == "short_record") && all(ss$leaf_reason == "short_record"),
      "fewer than three watched seasons marks every year short_record")

# Production-bundle smoke: the pure helpers must also execute against a committed
# site bundle. Exact science is covered above; this catches schema drift.
harv_path <- file.path(root, "data", "sites", "HARV.rds")
check(file.exists(harv_path), "committed HARV bundle exists")
b <- readRDS(harv_path)
check(is.list(b) && all(c("obs", "inds", "meta") %in% names(b)) &&
        nrow(b$obs) > 0L && nrow(b$inds) > 0L,
      "committed HARV bundle exposes non-empty obs/inds and metadata")
production_clock <- weekly_yesrate(b$obs)
production_summary <- individual_summary(b$obs, b$inds)
check(!is.null(production_clock) && nrow(production_clock) > 0L &&
        all(production_clock$n >= 5L) && !is.null(production_summary) &&
        nrow(production_summary) > 0L,
      "corrected clock and individual summary execute on the production schema")
production_site <- site_phe_summary(b$obs, b$inds, b$meta, production_summary)
production_med <- { v <- stats::median(production_summary$leaf_active, na.rm = TRUE); if (is.finite(v)) round(v) else NA_real_ }
check(nrow(production_site) == 1L &&
        all(c("leaf_active_hi", "leaf_active_status", "leaf_edge_share", "greenup_hi", "greenup_lo") %in% names(production_site)) &&
        identical(production_site$median_leaf_active, production_med),
      "site summary leaf value equals the median of the per-plant leaf-active medians")

cat(sprintf("\nAll %d Plant Phenology helper contract tests passed.\n", passed))
