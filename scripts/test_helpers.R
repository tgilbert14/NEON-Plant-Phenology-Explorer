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
  lat = c(30, 31, 32, 33, 30, 31)
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
check(nrow(greenup_onsets(yl_trend)) == 9L && all(site_year_support(yl_trend)$year_supported) &&
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
check(identical(sup$reason, c("supported", "low_effort", "supported")) &&
        identical(sup$year_supported, c(TRUE, FALSE, TRUE)) &&
        all(!ko_sup$year_supported[ko_sup$year == 2019]) && !2019 %in% las$year,
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

# Two-stage bounds: no censoring -> point; some censored plant-years -> range;
# most plants censored -> upper bound with the numeric value withheld.
bk <- function(g, lc) tibble(individualID = paste0("P", seq_along(g)), greenup = g, left_censored = lc)
b_point <- greenup_bounds(bk(c(100, 104, 110), c(FALSE, FALSE, FALSE)))
b_range <- greenup_bounds(bk(c(40, 60, 100, 120), c(FALSE, TRUE, FALSE, FALSE)))
b_upper <- greenup_bounds(bk(c(60, 70, 100), c(TRUE, TRUE, FALSE)))
check(b_point$status == "point" && b_point$value == 104 &&
        b_range$status == "range" && b_range$lo == 70 && b_range$hi == 80 && b_range$value == 80 &&
        identical(greenup_label(80, 70, "range"), "day 70 to 80"),
      "two-stage bounds label a range when censoring moves the lower bound")
check(b_point$status == "point" && b_upper$status == "upper_bound" && is.na(b_upper$value) &&
        b_upper$hi == 70 && identical(greenup_label(70, NA, "upper_bound"), "day 70 or earlier"),
      "an upper-bound green-up withholds the number and reads 'or earlier'")

# A site watched for fewer than three seasons cannot be checked against itself.
short_fixture <- bind_rows(obs_row("S1", 2016, c(150, 157), "yes", "Leaves"),
                           obs_row("S1", 2017, c(150, 157), "yes", "Leaves"))
ss <- site_year_support(short_fixture)
check(!any(ss$year_supported) && all(ss$reason == "short_record"),
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

cat(sprintf("\nAll %d Plant Phenology helper contract tests passed.\n", passed))
