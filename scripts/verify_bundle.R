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
suppressPackageStartupMessages({ library(dplyr); library(tibble) })
source("R/phe_helpers.R")
source("scripts/bundle_identity.R")   # canonical_obs: the committed obs order
if (!exists("BOUND_POINT_TOL") || !is.numeric(BOUND_POINT_TOL) || length(BOUND_POINT_TOL) != 1L ||
    !is.finite(BOUND_POINT_TOL))
  stop("R/phe_helpers.R does not define a finite BOUND_POINT_TOL.", call. = FALSE)
DEMO_SITE <- "SRER"
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
  "greenup_hi", "greenup_lo", "greenup_status", "greenup_autumn_forms",
  "greenup_carry_forms", "greenup_carry_share",
  "greenup_lc_share", "greenup_fallback_share", "n_supported_years", "n_leaf_supported_years",
  "n_years_watched", "leaf_active_hi", "leaf_edge_share", "leaf_active_status",
  "uncertain_share", "year_min", "year_max", "elevation_m"
)
IND_SUMMARY_REQUIRED <- c(
  INDS_REQUIRED, "greenup", "flower", "leaf_off", "leaf_active",
  "greenup_n_years", "flower_n_years", "leaf_active_n_years", "n_years",
  "greenup_source", "greenup_lc_years", "n_years_watched",
  "leaf_active_hi", "leaf_edge_years", "leaf_active_lower_bound"
)
GREENUP_SOURCES <- c("bud-break", "young-leaves")
GREENUP_STATUSES <- c("point", "range", "upper_bound", "short_record", "none")
LEAF_STATUSES <- c("point", "lower_bound", "short_record", "none")
TREND_REQUIRED <- c("scientificName", "year", "onset", "n", "lc_share")
NATIONAL_REQUIRED <- c(
  "site", "scientificName", "n_ind", "greenup", "greenup_lo", "greenup_hi",
  "greenup_status", "leaf_active", "leaf_active_hi", "leaf_edge_share",
  "leaf_active_lower_bound", "n_years", "leaf_n_years"
)
# Independent oracle comparison, four levels. Each column carries the type both
# sides are coerced to before the exact comparison: num, lgl or chr.
ORACLE_PATH <- "scripts/headline_oracle.R"
ORACLE_LINES_PER_LEVEL <- 30L
ORACLE_SITE_COLUMNS <- c(
  median_greenup = "num", greenup_lo = "num", greenup_hi = "num", greenup_status = "chr",
  median_leaf_active = "num", leaf_active_hi = "num", leaf_active_status = "chr",
  leaf_edge_share = "num", n_years_watched = "num", n_supported_years = "num",
  n_leaf_supported_years = "num"
)
ORACLE_SUPPORT_COLUMNS <- c(
  greenup_reason = "chr", leaf_reason = "chr", greenup_supported = "lgl",
  leaf_supported = "lgl"
)
ORACLE_PLANT_YEAR_COLUMNS <- c(
  greenup = "num", greenup_lo = "num", greenup_hi = "num", left_censored = "lgl",
  carryover = "lgl", greenup_source = "chr", leaf_active = "num", leaf_active_hi = "num",
  leaf_edge_start = "lgl", leaf_edge_end = "lgl", greenup_supported = "lgl",
  leaf_supported = "lgl"
)
ORACLE_SPECIES_COLUMNS <- c(
  n_ind = "num", greenup = "num", greenup_lo = "num", greenup_hi = "num",
  greenup_status = "chr", lc_share = "num", leaf_active = "num", leaf_active_hi = "num",
  leaf_active_lower_bound = "lgl", leaf_edge_share = "num", n_years = "num",
  leaf_n_years = "num"
)
SEARCH_TAXA_REQUIRED <- c(
  "scientificName", "growthForm", "site", "state", "lat", "lng",
  "elevation_m", "n_ind", "greenup", "flower", "leaf_active",
  "leaf_active_lower_bound", "year_min", "year_max", "name"
)
SEARCH_SITES_REQUIRED <- c(
  "site", "median_greenup", "median_leaf_active", "greenup_hi", "n_species",
  "n_individuals", "gu_share", "year_min", "year_max", "name", "state",
  "lat", "lng"
)

# Element-wise equality where NA matches NA and nothing else does.
same_value <- function(a, b) {
  if (is.numeric(a) && is.numeric(b)) {
    a <- as.numeric(a); b <- as.numeric(b)
  } else {
    a <- as.character(a); b <- as.character(b)
  }
  out <- (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
  out[is.na(out)] <- FALSE
  out
}
show_keys <- function(keys, limit = 10L) {
  keys <- unique(keys)
  shown <- paste(utils::head(keys, limit), collapse = ", ")
  if (length(keys) > limit) shown <- sprintf("%s, and %d more", shown, length(keys) - limit)
  shown
}

# The green-up bracket (scripts/headline_rules.md section 6): a point or a range carries a finite
# lo <= value <= hi, a point is narrower than BOUND_POINT_TOL and a range is not;
# an upper bound publishes only hi.
check_greenup_bracket <- function(x, label, value_col, keys) {
  need <- c(value_col, "greenup_lo", "greenup_hi", "greenup_status")
  if (!all(need %in% names(x))) return(invisible(NULL))
  st <- as.character(x$greenup_status)
  v <- suppressWarnings(as.numeric(x[[value_col]]))
  lo <- suppressWarnings(as.numeric(x$greenup_lo))
  hi <- suppressWarnings(as.numeric(x$greenup_hi))
  shown <- st %in% c("point", "range")
  bracket <- shown & !(is.finite(lo) & is.finite(v) & is.finite(hi) & lo <= v & v <= hi)
  if (any(bracket))
    note(sprintf("%s point/range rows lack a finite lo <= %s <= hi: %s",
                 label, value_col, show_keys(keys[bracket])))
  ok <- shown & !bracket
  narrow <- ok & st == "point" & !(hi - lo < BOUND_POINT_TOL)
  if (any(narrow))
    note(sprintf("%s point rows have hi - lo >= %s days: %s",
                 label, BOUND_POINT_TOL, show_keys(keys[narrow])))
  wide <- ok & st == "range" & !(hi - lo >= BOUND_POINT_TOL)
  if (any(wide))
    note(sprintf("%s range rows have hi - lo < %s days: %s",
                 label, BOUND_POINT_TOL, show_keys(keys[wide])))
  upper <- st == "upper_bound" & !(is.na(v) & is.na(lo) & is.finite(hi))
  if (any(upper))
    note(sprintf("%s upper_bound rows must have %s NA, greenup_lo NA and a finite greenup_hi: %s",
                 label, value_col, show_keys(keys[upper])))
  invisible(NULL)
}

# Oracle comparison policy, kept in one place (hk: exact, no tolerance; every
# value is a multiple of 0.25). Both sides are coerced to the column's declared
# type, then compared cell by cell with NA matching NA and nothing else. Rows are
# matched on `keys`; a key on one side only, a duplicated key, or a column absent
# from either side is itself a mismatch. Returns one line per mismatch, starting
# "SITE:key:column" (the key part is omitted at site level, where it is the site).
coerce_as <- function(x, type) {
  switch(type,
         num = suppressWarnings(as.numeric(as.character(x))),
         lgl = as.logical(if (is.factor(x)) as.character(x) else x),
         chr = as.character(x),
         stop(sprintf("unknown comparison type %s", type), call. = FALSE))
}
compare_oracle <- function(app, oracle, keys, columns, app_label) {
  key_of <- function(x) {
    if (!all(keys %in% names(x))) return(NULL)
    rest <- setdiff(keys, "site")
    k <- if (length(rest)) do.call(paste, c(lapply(x[rest], as.character), sep = "/")) else ""
    paste(as.character(x$site), k, sep = "\r")
  }
  show <- function(k, column, detail) {
    if (!length(k)) return(character(0))
    parts <- strsplit(k, "\r", fixed = TRUE)
    site <- vapply(parts, `[`, "", 1L)
    rest <- vapply(parts, function(p) if (length(p) > 1L) p[[2L]] else "", "")
    paste0(site, ifelse(nzchar(rest), paste0(":", rest), ""), ":", column, " ", detail)
  }
  a_keys <- key_of(app)
  o_keys <- key_of(oracle)
  if (is.null(a_keys)) return(sprintf("%s lacks key columns %s", app_label, paste(keys, collapse = ",")))
  if (is.null(o_keys)) return(sprintf("oracle lacks key columns %s", paste(keys, collapse = ",")))
  out <- c(show(unique(a_keys[duplicated(a_keys)]), "*", sprintf("(duplicate key in %s)", app_label)),
           show(unique(o_keys[duplicated(o_keys)]), "*", "(duplicate key in oracle)"),
           show(setdiff(o_keys, a_keys), "*", sprintf("(row missing from %s)", app_label)),
           show(setdiff(a_keys, o_keys), "*", "(row missing from oracle)"))
  both <- sort(intersect(a_keys, o_keys), method = "radix")
  ai <- match(both, a_keys)
  oi <- match(both, o_keys)
  for (column in names(columns)) {
    if (!column %in% names(app)) { out <- c(out, sprintf("%s lacks column %s", app_label, column)); next }
    if (!column %in% names(oracle)) { out <- c(out, sprintf("oracle lacks column %s", column)); next }
    a <- coerce_as(app[[column]], columns[[column]])[ai]
    o <- coerce_as(oracle[[column]], columns[[column]])[oi]
    bad <- !same_value(a, o)
    if (any(bad))
      out <- c(out, show(both[bad], column, sprintf("%s=%s oracle=%s", app_label, a[bad], o[bad])))
  }
  out
}
oracle_mismatches <- list(site = character(0), support = character(0),
                          plant_years = character(0), species = character(0))
# oracle rows compared per level, printed as a receipt so a passing log shows the
# comparison ran rather than staying silent
oracle_rows <- c(site = 0L, support = 0L, plant_years = 0L, species = 0L)
add_oracle_mismatches <- function(level, lines)
  oracle_mismatches[[level]] <<- c(oracle_mismatches[[level]], lines)

# The oracle is loaded as its header documents: into an environment whose parent
# is base R only, so it cannot reach the app helpers, dplyr or the workspace.
oracle_env <- NULL
if (!file.exists(ORACLE_PATH)) {
  note(sprintf("%s is missing: the headline metrics have no independent oracle", ORACLE_PATH))
} else {
  oracle_env <- new.env(parent = baseenv())
  loaded_oracle <- tryCatch(sys.source(ORACLE_PATH, envir = oracle_env), error = function(e) e)
  if (inherits(loaded_oracle, "error") || !is.function(oracle_env$headline_oracle_tables)) {
    note(sprintf("%s failed to load or lacks headline_oracle_tables(): %s", ORACLE_PATH,
                 if (inherits(loaded_oracle, "error")) conditionMessage(loaded_oracle) else "no function"))
    oracle_env <- NULL
  }
}
oracle_site_rows <- list()
oracle_species_rows <- list()

# ---- site bundles -----------------------------------------------------------
site_files <- list.files("data/sites", pattern = "\\.rds$", full.names = TRUE)
site_codes <- sort(sub("\\.rds$", "", basename(site_files)))
if (!identical(site_codes, EXPECTED_SITES))
  note(sprintf("site set mismatch: missing=[%s] extra=[%s]",
               paste(setdiff(EXPECTED_SITES, site_codes), collapse = ","),
               paste(setdiff(site_codes, EXPECTED_SITES), collapse = ",")))

loaded <- 0L
roster_keys <- character(0)   # every species-level site x scientificName in the bundles
uncertain_by_site <- numeric(0)   # independent uncertain_share per site, from obs
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
  # audit 2026-10-18 item 12: a valid date must always carry its dayOfYear
  if (is.data.frame(bundle$obs) && all(c("dayOfYear", "date") %in% names(bundle$obs)) &&
      any(is.na(bundle$obs$dayOfYear) & !is.na(bundle$obs$date)))
    note(sprintf("%s has %d valid-date rows with NA dayOfYear (coalesce from date)", path,
                 sum(is.na(bundle$obs$dayOfYear) & !is.na(bundle$obs$date))))
  # obs is stored in canonical order without exact duplicate rows, and inds in
  # individualID order, so the same observations always give the same bytes
  if (is.data.frame(bundle$obs)) {
    canon <- tryCatch(canonical_obs(bundle$obs), error = function(e) e)
    if (inherits(canon, "error")) {
      note(sprintf("%s obs cannot be canonicalized: %s", path, conditionMessage(canon)))
    } else {
      n_dup <- rows_of(bundle$obs) - rows_of(canon)
      if (n_dup > 0L)
        note(sprintf("%s obs has %d exact duplicate row(s)", path, n_dup))
      if (!identical(canon, bundle$obs))
        note(sprintf("%s obs is not in canonical order (canonical_obs(obs) differs from obs)", path))
    }
  }
  if (is.data.frame(bundle$inds) && "individualID" %in% names(bundle$inds)) {
    ids <- as.character(bundle$inds$individualID)
    if (!identical(order(ids, method = "radix"), seq_along(ids)))
      note(sprintf("%s inds is not ordered by individualID", path))
  }
  # the stored per-plant summary and trend must reproduce from obs under the
  # current helpers (catches the n_years cap, a stale estimand, or a summary
  # rebuilt without the Young-leaves fallback or the site-year support gate)
  if (is.data.frame(bundle$obs) && is.data.frame(bundle$inds) && is.data.frame(bundle$ind_summary)) {
    obs_chr <- bundle$obs
    for (cc in c("phenophaseName", "status", "intensity", "growthForm"))
      if (cc %in% names(obs_chr)) obs_chr[[cc]] <- as.character(obs_chr[[cc]])
    fresh <- tryCatch(individual_summary(obs_chr, bundle$inds), error = function(e) e)
    if (inherits(fresh, "error")) {
      note(sprintf("%s individual_summary failed: %s", path, conditionMessage(fresh)))
    } else if (!is.null(fresh)) {
      cols <- intersect(c("greenup", "flower", "leaf_off", "leaf_active", "greenup_source", "greenup_n_years",
                          "flower_n_years", "leaf_active_n_years", "greenup_lc_years", "n_years",
                          "n_years_watched", "leaf_active_hi", "leaf_edge_years",
                          "leaf_active_lower_bound"), names(bundle$ind_summary))
      a <- as.data.frame(fresh)[order(fresh$individualID), cols, drop = FALSE]
      b <- as.data.frame(bundle$ind_summary)[order(bundle$ind_summary$individualID), cols, drop = FALSE]
      if (nrow(a) != nrow(b) || !isTRUE(all.equal(a, b, check.attributes = FALSE)))
        note(sprintf("%s ind_summary does not reproduce from obs (stale estimand or n_years bug)", path))
      # the summarise-reassignment signature: plants with a green-up in several
      # years, yet the stored count never exceeds 1
      stored_n <- bundle$ind_summary$greenup_n_years
      if (!is.null(stored_n) && "greenup_n_years" %in% names(fresh) &&
          any(fresh$greenup_n_years > 1L, na.rm = TRUE) && max(c(0L, stored_n), na.rm = TRUE) <= 1L)
        note(sprintf("%s greenup_n_years is capped at 1 (summarise reassignment)", path))
      if ("greenup_source" %in% names(bundle$ind_summary)) {
        src <- bundle$ind_summary$greenup_source
        if (any(!is.na(src) & !src %in% GREENUP_SOURCES))
          note(sprintf("%s ind_summary has an unknown greenup_source", path))
        if (any(is.finite(bundle$ind_summary$greenup) & is.na(src)))
          note(sprintf("%s ind_summary has a green-up value with no greenup_source", path))
      }
    }
    fresh_trend <- tryCatch(onset_trend(obs_chr), error = function(e) e)
    if (!inherits(fresh_trend, "error") &&
        !isTRUE(all.equal(as.data.frame(fresh_trend %||% data.frame()),
                          as.data.frame(bundle$trend %||% data.frame()), check.attributes = FALSE)))
      note(sprintf("%s trend does not reproduce from obs under the current helpers", path))
    sup <- site_year_support(obs_chr)
    if (!is.null(bundle$trend) && is.data.frame(bundle$trend) && "year" %in% names(bundle$trend) &&
        any(!bundle$trend$year %in% sup$year[sup$greenup_supported]))
      note(sprintf("%s trend contains an unsupported site-year", path))
  }
  # independent oracle, levels b (support) and c (plant-years) per bundle; the
  # site and species rows are kept for the index comparisons below
  if (!is.null(oracle_env) && is.data.frame(bundle$obs)) {
    tables <- tryCatch(oracle_env$headline_oracle_tables(bundle), error = function(e) e)
    if (inherits(tables, "error")) {
      note(sprintf("%s headline oracle failed: %s", path, conditionMessage(tables)))
    } else {
      oracle_site_rows[[code]] <- tables$site
      oracle_species_rows[[code]] <- tables$species
      oracle_rows[["support"]] <- oracle_rows[["support"]] + nrow(tables$support)
      oracle_rows[["plant_years"]] <- oracle_rows[["plant_years"]] + nrow(tables$plant_years)
      obs_cmp <- bundle$obs
      for (cc in c("phenophaseName", "status", "intensity", "growthForm"))
        if (cc %in% names(obs_cmp)) obs_cmp[[cc]] <- as.character(obs_cmp[[cc]])
      obs_cmp <- normalize_doy(obs_cmp)
      app_support <- tryCatch(site_year_support(obs_cmp), error = function(e) e)
      if (inherits(app_support, "error")) {
        note(sprintf("%s site_year_support failed: %s", path, conditionMessage(app_support)))
      } else {
        app_support <- as.data.frame(app_support)
        app_support$site <- rep(code, nrow(app_support))
        add_oracle_mismatches("support", compare_oracle(
          app_support, tables$support, c("site", "year"), ORACLE_SUPPORT_COLUMNS,
          "site_year_support"))
      }
      app_py <- tryCatch(key_onsets(obs_cmp), error = function(e) e)
      if (inherits(app_py, "error")) {
        note(sprintf("%s key_onsets failed: %s", path, conditionMessage(app_py)))
      } else {
        app_py <- as.data.frame(app_py)
        keep <- is.finite(app_py$greenup %||% rep(NA_real_, nrow(app_py))) |
          is.finite(app_py$leaf_active %||% rep(NA_real_, nrow(app_py)))
        app_py <- app_py[keep, , drop = FALSE]
        app_py$site <- rep(code, nrow(app_py))
        add_oracle_mismatches("plant_years", compare_oracle(
          app_py, tables$plant_years, c("site", "individualID", "year"),
          ORACLE_PLANT_YEAR_COLUMNS, "key_onsets"))
      }
    }
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
    ins <- bundle$ind_summary
    if (all(c("leaf_edge_years", "leaf_active_n_years") %in% names(ins)) &&
        any(ins$leaf_edge_years > ins$leaf_active_n_years, na.rm = TRUE))
      note(sprintf("%s ind_summary has leaf_edge_years above leaf_active_n_years for %d plant(s)",
                   path, sum(ins$leaf_edge_years > ins$leaf_active_n_years, na.rm = TRUE)))
    if (all(c("leaf_active", "leaf_active_hi") %in% names(ins))) {
      both <- is.finite(ins$leaf_active) & is.finite(ins$leaf_active_hi)
      if (any(both & ins$leaf_active_hi < ins$leaf_active))
        note(sprintf("%s ind_summary has leaf_active_hi below leaf_active for %d plant(s)",
                     path, sum(both & ins$leaf_active_hi < ins$leaf_active)))
      if ("leaf_active_lower_bound" %in% names(ins)) {
        want <- ifelse(is.finite(ins$leaf_active),
                       ins$leaf_active_hi - ins$leaf_active >= BOUND_POINT_TOL, NA)
        bad <- !same_value(as.logical(ins$leaf_active_lower_bound), as.logical(want))
        if (any(bad))
          note(sprintf(paste0("%s ind_summary leaf_active_lower_bound disagrees with ",
                              "leaf_active_hi - leaf_active >= %s (NA when leaf_active is NA) for %d plant(s)"),
                       path, BOUND_POINT_TOL, sum(bad)))
      }
    }
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
      if ("lc_share" %in% names(bundle$trend)) {
        lc <- suppressWarnings(as.numeric(bundle$trend$lc_share))
        if (any(!is.finite(lc) | lc < 0 | lc > 1))
          note(sprintf("%s trend lc_share must be finite and within [0, 1] (%d bad row(s))",
                       path, sum(!is.finite(lc) | lc < 0 | lc > 1)))
      }
    }
  }
  if (is.data.frame(bundle$inds) && all(c("scientificName", "is_species") %in% names(bundle$inds))) {
    sp <- bundle$inds[bundle$inds$is_species %in% TRUE & !is.na(bundle$inds$scientificName), , drop = FALSE]
    roster_keys <- c(roster_keys, paste(code, sp$scientificName, sep = "\r"))
  }
  # the uncertain share recomputed here in base R from the stored obs, never through
  # the helpers, so site_index$uncertain_share has an independent check
  if (is.data.frame(bundle$obs) && "status" %in% names(bundle$obs)) {
    st <- as.character(bundle$obs$status)
    n_scored <- sum(st %in% c("yes", "no", "uncertain"))
    uncertain_by_site[[code]] <- if (n_scored) sum(st %in% "uncertain") / n_scored else NA_real_
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
    if ("greenup_status" %in% names(site_index)) {
      st <- as.character(site_index$greenup_status)
      if (any(!st %in% GREENUP_STATUSES))
        note("site_index has an unknown greenup_status")
      # the numeric median is published only for a point or a range; an upper
      # bound or a short record must stay NA so no map or index reads it as a day
      shown <- st %in% c("point", "range")
      if (any(is.finite(site_index$median_greenup) & !shown) || any(!is.finite(site_index$median_greenup) & shown))
        note("site_index median_greenup disagrees with greenup_status")
      if (any(st == "range" & !(is.finite(site_index$greenup_lo) & site_index$greenup_lo < site_index$greenup_hi)))
        note("site_index has a green-up range without a finite lower bound below the upper")
      if (any(st == "short_record" & is.finite(site_index$median_leaf_active)))
        note("site_index publishes leaf-active for a short-record site")
    }
    check_greenup_bracket(site_index, "site_index", "median_greenup",
                          as.character(site_index$site))
    if (all(c("leaf_active_status", "median_leaf_active", "leaf_active_hi") %in% names(site_index))) {
      ls <- as.character(site_index$leaf_active_status)
      la <- suppressWarnings(as.numeric(site_index$median_leaf_active))
      la_hi <- suppressWarnings(as.numeric(site_index$leaf_active_hi))
      keys <- as.character(site_index$site)
      if (any(!ls %in% LEAF_STATUSES))
        note(sprintf("site_index has an unknown leaf_active_status: %s",
                     show_keys(keys[!ls %in% LEAF_STATUSES])))
      published <- ls %in% c("point", "lower_bound")
      if (any(published != is.finite(la)))
        note(sprintf("site_index median_leaf_active is finite exactly when leaf_active_status is point or lower_bound; fails at: %s",
                     show_keys(keys[published != is.finite(la)])))
      want_lower <- is.finite(la) & is.finite(la_hi) & la_hi - la >= BOUND_POINT_TOL
      if (any((ls == "lower_bound") != want_lower))
        note(sprintf("site_index leaf_active_status is lower_bound exactly when leaf_active_hi - median_leaf_active >= %s; fails at: %s",
                     BOUND_POINT_TOL, show_keys(keys[(ls == "lower_bound") != want_lower])))
      if ("greenup_status" %in% names(site_index)) {
        gs <- as.character(site_index$greenup_status)
        short_bad <- (ls == "short_record") != (gs %in% "short_record")
        if (any(short_bad))
          note(sprintf("site_index leaf_active_status is short_record exactly when greenup_status is; fails at: %s",
                       show_keys(keys[short_bad])))
      }
    }
    if ("leaf_edge_share" %in% names(site_index)) {
      es <- suppressWarnings(as.numeric(site_index$leaf_edge_share))
      bad <- !is.na(es) & !(is.finite(es) & es >= 0 & es <= 1)
      if (any(bad))
        note(sprintf("site_index leaf_edge_share must be within [0, 1] or NA; fails at: %s",
                     show_keys(as.character(site_index$site)[bad])))
    }
    if ("uncertain_share" %in% names(site_index)) {
      us <- suppressWarnings(as.numeric(site_index$uncertain_share))
      keys <- as.character(site_index$site)
      bad_range <- !(is.finite(us) & us >= 0 & us <= 1)
      if (any(bad_range))
        note(sprintf("site_index uncertain_share must be within [0, 1]; fails at: %s",
                     show_keys(keys[bad_range])))
      want <- unname(uncertain_by_site[keys])
      bad_eq <- !bad_range & !(is.finite(want) & us == want)
      if (any(bad_eq))
        note(sprintf("site_index uncertain_share differs from the share of stored obs rows recorded 'uncertain'; fails at: %s",
                     show_keys(keys[bad_eq])))
    }
  }
}

national <- load_index("data/national_onsets.rds")
if (!is.null(national) &&
    (!is.data.frame(national) || nrow(national) <= 0L ||
     !all(c("site", "scientificName", "n_ind", "greenup", "leaf_active") %in% names(national)) ||
     any(!as.character(national$site) %in% EXPECTED_SITES)))
  note("national_onsets is empty, malformed, or contains an unknown site")
if (!is.null(national) && is.data.frame(national)) {
  missing_national <- setdiff(NATIONAL_REQUIRED, names(national))
  if (length(missing_national))
    note(sprintf("national_onsets lacks: %s", paste(missing_national, collapse = ",")))
  if (all(c("site", "scientificName") %in% names(national))) {
    national_keys <- paste(national$site, national$scientificName, sep = " ")
    check_greenup_bracket(national, "national_onsets", "greenup", national_keys)
    # a published value needs a whole number of supported years behind it
    for (pair in list(c("n_years", "greenup"), c("leaf_n_years", "leaf_active"))) {
      if (!all(pair %in% names(national))) next
      years <- suppressWarnings(as.numeric(national[[pair[[1L]]]]))
      shown <- is.finite(suppressWarnings(as.numeric(national[[pair[[2L]]]])))
      bad <- shown & !(is.finite(years) & years >= 1 & years == round(years))
      if (any(bad))
        note(sprintf("national_onsets %s must be an integer >= 1 where %s is finite; fails at: %s",
                     pair[[1L]], pair[[2L]], show_keys(national_keys[bad])))
    }
  }
}

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
      # the search roster is every species-level plant in the bundles (audit item
      # 13: Prosopis/Larrea were missing because the roster was national_onsets);
      # every supported national_onsets row must still be findable
      if (length(setdiff(national_keys, search_keys)))
        note("search_index taxa lacks site-species rows that national_onsets carries")
      missing_roster <- setdiff(unique(roster_keys), search_keys)
      if (length(missing_roster))
        note(sprintf("search_index cannot find %d species-level plants in the bundles, e.g. %s",
                     length(missing_roster), sub("\r", " ", missing_roster[1], fixed = TRUE)))
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
if (!is.null(demo)) {
  if (!is.list(demo) || is.null(demo$obs) || rows_of(demo$obs) <= 0L ||
      !identical(as.character(demo$meta$site), DEMO_SITE)) {
    note(sprintf("demo bundle must be a non-empty %s app bundle (meta$site is %s)", DEMO_SITE,
                 if (is.list(demo)) as.character(demo$meta$site %||% "<missing>") else "<not a list>"))
  } else {
    demo_source <- file.path("data/sites", paste0(DEMO_SITE, ".rds"))
    committed <- if (file.exists(demo_source)) tryCatch(readRDS(demo_source), error = function(e) NULL)
    if (is.null(committed) || !identical(demo, committed))
      note(sprintf("data-sample/demo.rds is not identical to %s", demo_source))
  }
}

# ---- independent headline oracle ---------------------------------------------
# The reproduction gates above re-run the app's own helpers, so a helper bug would
# reproduce itself. scripts/headline_oracle.R implements the written rules
# separately in base R. Four levels must agree with it exactly: the site row
# (site_index), the per-year support, the plant-years and the species rows
# (national_onsets). Each level reports up to ORACLE_LINES_PER_LEVEL mismatches
# and its total count.
if (!is.null(oracle_env)) {
  if (length(oracle_site_rows) && !is.null(site_index) && is.data.frame(site_index))
    add_oracle_mismatches("site", compare_oracle(
      as.data.frame(site_index), do.call(rbind, oracle_site_rows), "site",
      ORACLE_SITE_COLUMNS, "site_index"))
  if (length(oracle_species_rows) && !is.null(national) && is.data.frame(national))
    add_oracle_mismatches("species", compare_oracle(
      as.data.frame(national), do.call(rbind, oracle_species_rows),
      c("site", "scientificName", "growthForm"), ORACLE_SPECIES_COLUMNS, "national_onsets"))
  for (level in names(oracle_mismatches)) {
    lines <- oracle_mismatches[[level]]
    if (!length(lines)) next
    # per-column totals, so a capped listing still shows where the disagreement is
    column <- ifelse(grepl("^.*:[A-Za-z_*]+ [^:]*$", lines),
                     sub("^.*:([A-Za-z_*]+) [^:]*$", "\\1", lines), "structure")
    tally <- table(column)
    tally <- paste(sprintf("%s %d", names(tally), as.integer(tally)), collapse = ", ")
    note(sprintf("headline oracle, %s level: %d mismatch(es) [%s]%s", level, length(lines), tally,
                 if (length(lines) > ORACLE_LINES_PER_LEVEL)
                   sprintf(" (first %d listed)", ORACLE_LINES_PER_LEVEL) else ""))
    for (line in utils::head(lines, ORACLE_LINES_PER_LEVEL))
      note(sprintf("headline oracle, %s: %s", level, line))
  }
  oracle_rows[["site"]] <- sum(vapply(oracle_site_rows, nrow, integer(1)))
  oracle_rows[["species"]] <- sum(vapply(oracle_species_rows, function(x) if (is.null(x)) 0L else nrow(x), integer(1)))
  cat(sprintf("headline oracle: compared %s rows; mismatches %s\n",
              paste(sprintf("%s %d", names(oracle_rows), oracle_rows), collapse = ", "),
              paste(sprintf("%s %d", names(oracle_mismatches), lengths(oracle_mismatches)), collapse = ", ")))
}

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
