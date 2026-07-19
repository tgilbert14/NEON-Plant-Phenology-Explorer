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
trend_fixture <- bind_rows(
  obs_row("T1", 2020, 100, "no", "Breaking leaf buds"),
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
tr <- onset_trend(trend_fixture)
check(nrow(tr) == 1L && tr$n[[1L]] == 3L && tr$onset[[1L]] == 105,
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

# Days 1 and 2 share a week; day 8 and day 100 are two more active weeks. The
# multi-flush-safe extent is therefore three distinct weeks x seven days.
leaf_fixture <- bind_rows(
  obs_row("L1", 2020, 1, "yes", "Leaves"),
  obs_row("L1", 2020, 2, "yes", "Leaves"),
  obs_row("L1", 2020, 8, "yes", "Leaves"),
  obs_row("L1", 2020, 100, "yes", "Leaves")
)
ko <- key_onsets(leaf_fixture)
check(nrow(ko) == 1L && ko$leaf_active[[1L]] == 21L && ko$leaf_off[[1L]] == 100,
      "leaf-active duration counts distinct active weeks and supports multiple flushes")

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
