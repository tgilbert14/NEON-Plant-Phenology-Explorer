#!/usr/bin/env Rscript

# Non-network pre-publication gate for the complete Plant Phenology release
# surface: all 46 bundles, derived indexes, demo, and exact manifest semantics.

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a
problems <- character(0)
note <- function(message) problems[[length(problems) + 1L]] <<- message
rows_of <- function(x) {
  out <- tryCatch(nrow(x), error = function(e) NA_integer_)
  if (is.null(out)) NA_integer_ else out
}

source("R/site_metadata.R")
EXPECTED_SITES <- sort(as.character(neon_sites$site))
EXPECTED_R_PLATFORM <- "4.5.2"
EXPECTED_REPOSITORY <-
  "https://packagemanager.posit.co/cran/__linux__/jammy/2026-07-15"
REQUIRED_RUNTIME_PKGS <- c(
  "shiny", "bslib", "bsicons", "dplyr", "tidyr", "stringr", "tibble",
  "plotly", "leaflet", "DT", "shinyjs", "shinycssloaders", "RColorBrewer",
  "htmltools", "zip"
)
FORBIDDEN_RUNTIME_PKGS <- c("neonUtilities", "arrow", "rsconnect")
EXPECTED_GEO_PINS <- c(
  terra = "1.8-50", sf = "1.1-1", s2 = "1.1.11", units = "1.0-1",
  wk = "0.9.5", classInt = "0.4-11", raster = "3.6-32", sp = "2.2-1"
)
EXPECTED_GEO_URLS <- c(
  terra = "https://cran.r-project.org/src/contrib/Archive/terra/terra_1.8-50.tar.gz",
  sf = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/sf_1.1-1.tar.gz",
  s2 = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/s2_1.1.11.tar.gz",
  units = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/units_1.0-1.tar.gz",
  wk = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/wk_0.9.5.tar.gz",
  classInt = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/classInt_0.4-11.tar.gz",
  raster = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/raster_3.6-32.tar.gz",
  sp = "https://packagemanager.posit.co/cran/2026-07-15/src/contrib/sp_2.2-1.tar.gz"
)

OBS_REQUIRED <- c(
  "individualID", "plotID", "scientificName", "growthForm", "year", "date",
  "dayOfYear", "phenophaseName", "status", "intensity", "is_species"
)
INDS_REQUIRED <- c(
  "individualID", "scientificName", "growthForm", "plotID", "lat", "lng",
  "nativeStatusCode", "taxonRank", "is_species"
)
SITE_INDEX_REQUIRED <- c(
  "site", "n_individuals", "n_species", "n_obs", "n_plots", "dominant_form",
  "median_greenup", "median_leaf_active", "gu_share", "median_visit_interval",
  "year_min", "year_max", "elevation_m"
)
IND_SUMMARY_REQUIRED <- c(
  INDS_REQUIRED, "greenup", "flower", "leaf_off", "leaf_active",
  "greenup_n_years", "flower_n_years", "leaf_active_n_years", "n_years"
)
TREND_REQUIRED <- c("scientificName", "year", "onset", "n")
SEARCH_TAXA_REQUIRED <- c(
  "scientificName", "growthForm", "site", "state", "lat", "lng",
  "elevation_m", "n_ind", "greenup", "flower", "leaf_active",
  "year_min", "year_max", "name"
)
SEARCH_SITES_REQUIRED <- c(
  "site", "median_greenup", "median_leaf_active", "n_species",
  "n_individuals", "gu_share", "year_min", "year_max", "name", "state",
  "lat", "lng"
)

# ---- site bundles -----------------------------------------------------------
site_files <- list.files("data/sites", pattern = "\\.rds$", full.names = TRUE)
site_codes <- sort(sub("\\.rds$", "", basename(site_files)))
if (!identical(site_codes, EXPECTED_SITES))
  note(sprintf("site set mismatch: missing=[%s] extra=[%s]",
               paste(setdiff(EXPECTED_SITES, site_codes), collapse = ","),
               paste(setdiff(site_codes, EXPECTED_SITES), collapse = ",")))

loaded <- 0L
latest_observation_date <- as.Date(NA)
for (path in site_files) {
  code <- sub("\\.rds$", "", basename(path))
  bundle <- tryCatch(readRDS(path), error = function(e) e)
  if (inherits(bundle, "error")) {
    note(sprintf("%s failed to load: %s", path, conditionMessage(bundle)))
    next
  }
  if (!is.list(bundle) || !all(c("obs", "inds", "meta", "ind_summary", "trend") %in% names(bundle))) {
    note(sprintf("%s is not the required obs/inds/meta/summary/trend bundle", path))
    next
  }
  if (!is.data.frame(bundle$obs) || rows_of(bundle$obs) <= 0L)
    note(sprintf("%s has an empty/non-data-frame obs table", path))
  if (!is.data.frame(bundle$inds) || rows_of(bundle$inds) <= 0L)
    note(sprintf("%s has an empty/non-data-frame inds table", path))
  miss_obs <- setdiff(OBS_REQUIRED, names(bundle$obs))
  miss_inds <- setdiff(INDS_REQUIRED, names(bundle$inds))
  if (length(miss_obs)) note(sprintf("%s obs lacks: %s", path, paste(miss_obs, collapse = ",")))
  if (length(miss_inds)) note(sprintf("%s inds lacks: %s", path, paste(miss_inds, collapse = ",")))
  if (!is.list(bundle$meta) || !all(c("site", "lat", "lng", "years") %in% names(bundle$meta)) ||
      !identical(as.character(bundle$meta$site), code))
    note(sprintf("%s metadata is incomplete or identifies another site", path))
  if (is.data.frame(bundle$obs) && "status" %in% names(bundle$obs) &&
      any(!as.character(bundle$obs$status) %in% c("yes", "no", "uncertain")))
    note(sprintf("%s contains an unsupported phenophase status", path))
  if (is.data.frame(bundle$inds) && anyDuplicated(as.character(bundle$inds$individualID)))
    note(sprintf("%s has duplicate individualID rows in inds", path))
  if (is.data.frame(bundle$obs) && "date" %in% names(bundle$obs)) {
    observed_dates <- suppressWarnings(as.Date(as.character(bundle$obs$date)))
    observed_dates <- observed_dates[!is.na(observed_dates)]
    if (length(observed_dates))
      latest_observation_date <- max(c(latest_observation_date, observed_dates), na.rm = TRUE)
  }
  if (!is.data.frame(bundle$ind_summary) || rows_of(bundle$ind_summary) <= 0L) {
    note(sprintf("%s has an empty/non-data-frame ind_summary", path))
  } else {
    missing_summary <- setdiff(IND_SUMMARY_REQUIRED, names(bundle$ind_summary))
    if (length(missing_summary))
      note(sprintf("%s ind_summary lacks: %s", path, paste(missing_summary, collapse = ",")))
    if ("individualID" %in% names(bundle$ind_summary) &&
        anyDuplicated(as.character(bundle$ind_summary$individualID)))
      note(sprintf("%s ind_summary has duplicate individualID rows", path))
    if (all(c("individualID") %in% names(bundle$ind_summary)) &&
        any(!as.character(bundle$ind_summary$individualID) %in%
            as.character(bundle$inds$individualID)))
      note(sprintf("%s ind_summary contains an unknown individualID", path))
  }
  if (!is.null(bundle$trend)) {
    if (!is.data.frame(bundle$trend) || rows_of(bundle$trend) <= 0L) {
      note(sprintf("%s trend must be NULL or a non-empty data frame", path))
    } else {
      missing_trend <- setdiff(TREND_REQUIRED, names(bundle$trend))
      if (length(missing_trend))
        note(sprintf("%s trend lacks: %s", path, paste(missing_trend, collapse = ",")))
      if (all(c("scientificName", "year") %in% names(bundle$trend)) &&
          anyDuplicated(paste(bundle$trend$scientificName, bundle$trend$year, sep = "\r")))
        note(sprintf("%s trend has duplicate species-year rows", path))
      if ("n" %in% names(bundle$trend) && any(bundle$trend$n < 3L, na.rm = TRUE))
        note(sprintf("%s trend contains a sub-threshold species-year", path))
      if ("year" %in% names(bundle$trend) && "year" %in% names(bundle$obs) &&
          any(!bundle$trend$year %in% unique(bundle$obs$year)))
        note(sprintf("%s trend contains a year absent from obs", path))
    }
  }
  loaded <- loaded + 1L
}
cat(sprintf("bundles: %d expected, %d loaded with required container\n",
            length(EXPECTED_SITES), loaded))

# ---- indexes and demo -------------------------------------------------------
load_index <- function(path) {
  if (!file.exists(path)) { note(sprintf("missing index: %s", path)); return(NULL) }
  value <- tryCatch(readRDS(path), error = function(e) e)
  if (inherits(value, "error")) {
    note(sprintf("%s failed to load: %s", path, conditionMessage(value)))
    return(NULL)
  }
  value
}

site_index <- load_index("data/site_index.rds")
if (!is.null(site_index)) {
  if (!is.data.frame(site_index) || nrow(site_index) != length(EXPECTED_SITES))
    note("site_index must be a 46-row data frame")
  else {
    missing <- setdiff(SITE_INDEX_REQUIRED, names(site_index))
    if (length(missing)) note(sprintf("site_index lacks: %s", paste(missing, collapse = ",")))
    if (!identical(sort(as.character(site_index$site)), EXPECTED_SITES))
      note("site_index site set does not match R/site_metadata.R")
  }
}

national <- load_index("data/national_onsets.rds")
if (!is.null(national) &&
    (!is.data.frame(national) || nrow(national) <= 0L ||
     !all(c("site", "scientificName", "n_ind", "greenup", "leaf_active") %in% names(national)) ||
     any(!as.character(national$site) %in% EXPECTED_SITES)))
  note("national_onsets is empty, malformed, or contains an unknown site")

search <- load_index("data/search_index.rds")
if (!is.null(search)) {
  if (!is.list(search) || !all(c("taxa", "sites", "built") %in% names(search))) {
    note("search_index must be a taxa/sites/built list")
  } else if (!is.data.frame(search$taxa) || nrow(search$taxa) <= 0L ||
             !is.data.frame(search$sites) || nrow(search$sites) <= 0L) {
    note("search_index taxa and sites must be non-empty data frames")
  } else {
    missing_taxa <- setdiff(SEARCH_TAXA_REQUIRED, names(search$taxa))
    missing_sites <- setdiff(SEARCH_SITES_REQUIRED, names(search$sites))
    if (length(missing_taxa))
      note(sprintf("search_index taxa lacks: %s", paste(missing_taxa, collapse = ",")))
    if (length(missing_sites))
      note(sprintf("search_index sites lacks: %s", paste(missing_sites, collapse = ",")))
    if ("site" %in% names(search$taxa) &&
        any(!as.character(search$taxa$site) %in% EXPECTED_SITES))
      note("search_index taxa contains an unknown site")
    if ("site" %in% names(search$sites) &&
        any(!as.character(search$sites$site) %in% EXPECTED_SITES))
      note("search_index sites contains an unknown site")
    if (all(c("site", "scientificName") %in% names(search$taxa)) &&
        anyDuplicated(paste(search$taxa$site, search$taxa$scientificName, sep = "\r")))
      note("search_index taxa has duplicate site-species rows")
    if ("site" %in% names(search$sites) && anyDuplicated(as.character(search$sites$site)))
      note("search_index sites has duplicate site rows")
    if (!is.null(national) && is.data.frame(national) &&
        all(c("site", "scientificName") %in% names(national)) &&
        all(c("site", "scientificName") %in% names(search$taxa))) {
      national_keys <- sort(unique(paste(national$site, national$scientificName, sep = "\r")))
      search_keys <- sort(unique(paste(search$taxa$site, search$taxa$scientificName, sep = "\r")))
      if (!identical(search_keys, national_keys))
        note("search_index taxa keys do not match national_onsets")
    }
    if (!is.null(site_index) && is.data.frame(site_index) &&
        all(c("site", "median_greenup") %in% names(site_index)) &&
        "site" %in% names(search$sites)) {
      expected_search_sites <- sort(as.character(site_index$site[is.finite(site_index$median_greenup)]))
      if (!identical(sort(as.character(search$sites$site)), expected_search_sites))
        note("search_index site keys do not match supported site_index rows")
    }
    if (is.na(latest_observation_date) ||
        !identical(as.character(search$built), as.character(latest_observation_date)))
      note("search_index built receipt is not the maximum committed observation date")
  }
}

demo <- load_index("data-sample/demo.rds")
if (!is.null(demo) &&
    (!is.list(demo) || is.null(demo$obs) || nrow(demo$obs) <= 0L ||
     !identical(as.character(demo$meta$site), "HARV")))
  note("demo bundle must be a non-empty HARV app bundle")

# ---- manifest ---------------------------------------------------------------
if (!file.exists("manifest.json")) {
  note("manifest.json is missing")
} else {
  manifest <- tryCatch(jsonlite::fromJSON("manifest.json", simplifyVector = FALSE),
                       error = function(e) e)
  if (inherits(manifest, "error")) {
    note(sprintf("manifest JSON parse failed: %s", conditionMessage(manifest)))
  } else {
    expected_files <- c(
      "global.R", "ui.R", "server.R",
      list.files("R", pattern = "\\.R$", full.names = TRUE),
      list.files("www", recursive = TRUE, full.names = TRUE),
      Sys.glob("data/*.rds"),
      list.files("data/sites", pattern = "\\.rds$", full.names = TRUE),
      list.files("data-sample", pattern = "\\.rds$", full.names = TRUE)
    )
    expected_files <- sort(unique(expected_files[file.exists(expected_files)]))
    declared_files <- sort(names(manifest$files %||% list()))
    if (!identical(declared_files, expected_files))
      note(sprintf("manifest file set differs: missing=[%s] extra=[%s]",
                   paste(setdiff(expected_files, declared_files), collapse = ","),
                   paste(setdiff(declared_files, expected_files), collapse = ",")))
    present <- intersect(declared_files, expected_files)
    bad_md5 <- vapply(present, function(path) {
      expected <- tolower(as.character(manifest$files[[path]]$checksum %||% ""))
      actual <- tolower(unname(tools::md5sum(path)))
      !identical(expected, actual)
    }, logical(1))
    if (any(bad_md5))
      note(sprintf("manifest checksum mismatch: %s",
                   paste(present[bad_md5], collapse = ",")))

    if (!identical(as.character(manifest$platform %||% ""), EXPECTED_R_PLATFORM))
      note(sprintf("manifest platform is %s, expected %s",
                   as.character(manifest$platform %||% "<missing>"),
                   EXPECTED_R_PLATFORM))

    packages <- manifest$packages %||% list()
    keys <- names(packages)
    missing_runtime <- setdiff(REQUIRED_RUNTIME_PKGS, keys)
    forbidden <- intersect(FORBIDDEN_RUNTIME_PKGS, keys)
    if (length(missing_runtime))
      note(sprintf("manifest lacks runtime packages: %s", paste(missing_runtime, collapse = ",")))
    if (length(forbidden))
      note(sprintf("manifest contains forbidden packages: %s", paste(forbidden, collapse = ",")))

    for (pkg in keys) {
      info <- packages[[pkg]]
      version <- as.character(info$description$Version %||% "")
      declared <- as.character(info$description$Package %||% "")
      if (!identical(declared, pkg) || length(version) != 1L || !nzchar(version))
        note(sprintf("manifest package identity is incomplete: %s", pkg))
      if (!pkg %in% names(EXPECTED_GEO_PINS) &&
          (!identical(as.character(info$Source %||% ""), "CRAN") ||
           !identical(as.character(info$Repository %||% ""), EXPECTED_REPOSITORY)))
        note(sprintf("ordinary package provenance is not pinned: %s", pkg))
    }
    for (pkg in names(EXPECTED_GEO_PINS)) {
      info <- packages[[pkg]]
      if (is.null(info)) { note(sprintf("manifest lacks geospatial package: %s", pkg)); next }
      want_ref <- paste0("url::", unname(EXPECTED_GEO_URLS[[pkg]]))
      if (!identical(as.character(info$description$Version %||% ""),
                     unname(EXPECTED_GEO_PINS[[pkg]])) ||
          !identical(as.character(info$Source %||% ""), "CRAN") ||
          !identical(as.character(info$Repository %||% ""), "https://cran.r-project.org") ||
          !identical(as.character(info$description$RemoteType %||% ""), "url") ||
          !identical(as.character(info$description$RemotePkgRef %||% ""), want_ref) ||
          nzchar(as.character(info$description$Built %||% "")))
        note(sprintf("geospatial package provenance is invalid: %s", pkg))
    }
  }
}

if (length(problems)) {
  for (problem in problems)
    cat(sprintf("::error title=Phenology release verification::%s\n", problem))
  stop(sprintf("Phenology release verification FAILED with %d problem(s).",
               length(problems)), call. = FALSE)
}

cat("\nPhenology release verification PASSED: 46 bundles, indexes, demo, and exact manifest.\n")
