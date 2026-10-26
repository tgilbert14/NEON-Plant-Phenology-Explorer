#!/usr/bin/env Rscript

# Raw per-individual identity and producer-container boundary fixtures. The
# data.table dependency reproduces neonUtilities' live fetch result. Run from any
# working directory:
#   Rscript --vanilla scripts/test_bundle_identity.R

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
root <- if (length(file_arg)) normalizePath(file.path(dirname(file_arg), "..")) else
  normalizePath(".")
source(file.path(root, "scripts", "bundle_identity.R"), chdir = TRUE)
if (!requireNamespace("data.table", quietly = TRUE)) {
  stop("The raw-boundary contract tests require data.table.", call. = FALSE)
}

passed <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(sprintf("FAIL: %s", label), call. = FALSE)
  passed <<- passed + 1L
  cat(sprintf("PASS %02d: %s\n", passed, label))
}
errors_with <- function(expr, pattern) {
  message <- tryCatch({
    force(expr)
    ""
  }, error = function(e) conditionMessage(e))
  nzchar(message) && grepl(pattern, message, fixed = TRUE)
}

# The raw table is not promised to arrive in key order and can repeat a tagged
# plant. The latest record wins (newest editedDate, then newest date, then the
# smallest uid), whatever order the rows arrive in (iris, 2026-10-21).
accented_id <- paste0("NEON.PLA.", intToUtf8(233), "03.001")
identity_fixture <- data.frame(
  individualID = c("NEON.PLA.Z10.001", "NEON.PLA.A02.001",
                   "NEON.PLA.Z10.001", accented_id),
  scientificName = c("Species first", "Species alpha",
                     "Species corrected", "Species accented"),
  growthForm = c("tree", "shrub", "forb", "graminoid"),
  taxonRank = rep("species", 4L),
  nativeStatusCode = c("N", "N", "I", "N"),
  plotID = c("PLOT-Z", "PLOT-A", "PLOT-Z2", "PLOT-E"),
  decimalLatitude = c(40, 41, 40.5, 42),
  decimalLongitude = c(-70, -71, -70.5, -72),
  editedDate = as.POSIXct(c("2019-01-05 10:00:00", "2019-01-05 10:00:00",
                            "2021-03-02 08:00:00", "2019-01-05 10:00:00"), tz = "UTC"),
  date = as.Date(rep("2016-04-01", 4L)),
  uid = c("u-3", "u-2", "u-1", "u-4"),
  ignoredRawColumn = 1:4,
  stringsAsFactors = FALSE
)
identity_rows <- first_phenology_identity_rows(identity_fixture, "TEST")
check(
  identical(identity_rows$individualID,
            enc2utf8(c("NEON.PLA.A02.001", "NEON.PLA.Z10.001", accented_id))),
  "identity dedup returns one row per plant in radix individualID order with UTF-8 keys"
)
check(
  nrow(identity_rows) == 3L &&
    identity_rows$scientificName[[2L]] == "Species corrected" &&
    identity_rows$plotID[[2L]] == "PLOT-Z2" &&
    identity_rows$decimalLatitude[[2L]] == 40.5,
  "identity dedup keeps the complete latest-edited row when metadata conflicts"
)
# ties: the same editedDate falls to the newest date, then to the smallest uid
identity_ties <- identity_fixture[c(1L, 3L), ]
identity_ties$editedDate <- identity_ties$editedDate[[1L]]
identity_ties$date <- as.Date(c("2017-05-01", "2016-04-01"))
tie_by_date <- first_phenology_identity_rows(identity_ties, "TEST")
identity_ties$date <- identity_ties$date[[1L]]
tie_by_uid <- first_phenology_identity_rows(identity_ties, "TEST")
check(
  tie_by_date$scientificName == "Species first" && tie_by_uid$scientificName == "Species corrected",
  "identity ties fall to the newest date, then to the smallest uid"
)
# the same raw rows in any order keep the same identity rows and the same bytes
shuffled_rows <- first_phenology_identity_rows(identity_fixture[c(4L, 3L, 1L, 2L), ], "TEST")
shuffle_paths <- c(tempfile(fileext = ".rds"), tempfile(fileext = ".rds"))
saveRDS(identity_rows, shuffle_paths[[1L]], compress = "xz")
saveRDS(shuffled_rows, shuffle_paths[[2L]], compress = "xz")
check(
  identical(shuffled_rows, identity_rows) &&
    identical(unname(tools::md5sum(shuffle_paths[[1L]])), unname(tools::md5sum(shuffle_paths[[2L]]))),
  "shuffled identity input keeps the same rows and serializes to identical bytes"
)
unlink(shuffle_paths)
check(
  errors_with(first_phenology_identity_rows(identity_fixture[, setdiff(names(identity_fixture), "editedDate")], "TEST"),
              "missing required columns: editedDate"),
  "identity helper fails closed when an ordering column (editedDate) is absent"
)
check(
  identical(names(identity_rows), c(
    "individualID", "scientificName", "growthForm", "taxonRank",
    "nativeStatusCode", "plotID", "decimalLatitude", "decimalLongitude"
  )) && inherits(identity_rows, "data.frame") && !inherits(identity_rows, "tbl_df"),
  "identity helper returns only the eight required columns as a base data frame"
)

# Optional identity metadata are optional at the value level, not the shape
# level. Preserve honest unknowns as full-length typed NA values.
identity_optional <- identity_fixture
identity_optional$nativeStatusCode <- rep(NA_character_, nrow(identity_optional))
identity_optional$decimalLatitude <- rep(NA_real_, nrow(identity_optional))
optional_rows <- first_phenology_identity_rows(identity_optional, "TEST")
check(
  nrow(optional_rows) == 3L &&
    identical(optional_rows$nativeStatusCode, rep(NA_character_, 3L)) &&
    identical(optional_rows$decimalLatitude, rep(NA_real_, 3L)),
  "identity helper preserves full-length typed NA optional values"
)

# The fetch boundary must produce a self-contained RDS even if the loader hands
# it package-backed ALTREP columns. The helper allocates ordinary base vectors,
# preserves attributes/all-NA fields, and permits length zero only for zero-row
# metadata tables.
status_fixture <- data.frame(
  individualID = c("NEON.PLA.Z10.001", "NEON.PLA.A02.001"),
  plotID = c("PLOT-Z", "PLOT-A"),
  date = as.Date(c("2026-04-01", "2026-04-02")),
  dayOfYear = c(91L, 92L),
  phenophaseName = factor(c("Leaves", "Open flowers")),
  phenophaseStatus = c("yes", "no"),
  phenophaseIntensity = rep(NA_character_, 2L),
  stringsAsFactors = FALSE
)
raw_fixture <- list(
  phe_perindividual = identity_optional,
  phe_statusintensity = status_fixture,
  optional_empty_table = data.frame(
    note = character(), when = as.Date(character()), stringsAsFactors = FALSE
  )
)
portable_raw <- materialize_phenology_raw_result(raw_fixture, "TEST")
check(
  identical(portable_raw$phe_perindividual$nativeStatusCode,
            rep(NA_character_, 4L)) &&
    inherits(portable_raw$phe_statusintensity$date, "Date") &&
    is.factor(portable_raw$phe_statusintensity$phenophaseName) &&
    nrow(portable_raw$optional_empty_table) == 0L &&
    all(vapply(portable_raw$optional_empty_table, length, integer(1)) == 0L),
  "raw materializer preserves types, optional NAs, and legitimate zero-row tables"
)

# `neonUtilities` returns data.table containers in the fetch job. Character `i`
# has join semantics for `[.data.table`, so the raw boundary must inspect columns
# one name at a time with `[[` rather than base-data-frame column subsetting.
# Preserve the container class and every column value/attribute while replacing
# package-backed column storage with newly allocated base vectors.
data_table_raw <- list(
  phe_perindividual = data.table::as.data.table(identity_optional),
  phe_statusintensity = data.table::as.data.table(status_fixture),
  optional_empty_table = data.table::as.data.table(
    raw_fixture$optional_empty_table
  )
)
attr(data_table_raw$phe_statusintensity$dayOfYear, "unit") <- "day-of-year"
data_table_expected <- lapply(data_table_raw, data.table::copy)
data_table_portable <- materialize_phenology_raw_result(
  lapply(data_table_raw, data.table::copy), "DATA_TABLE"
)
same_data_table_columns <- all(vapply(names(data_table_expected), function(table) {
  expected <- data_table_expected[[table]]
  actual <- data_table_portable[[table]]
  identical(names(actual), names(expected)) &&
    all(vapply(names(expected), function(column) {
      identical(actual[[column]], expected[[column]])
    }, logical(1)))
}, logical(1)))
rectangular_data_tables <- all(vapply(data_table_portable, function(table) {
  !is.data.frame(table) || all(vapply(names(table), function(column) {
    length(table[[column]]) == nrow(table)
  }, logical(1)))
}, logical(1)))
check(
  all(vapply(data_table_portable, inherits, logical(1), "data.table")) &&
    same_data_table_columns && rectangular_data_tables,
  paste0(
    "raw materializer handles data.table producers without join dispatch and ",
    "preserves column values, attributes, and rectangularity"
  )
)

local({
  roundtrip_path <- tempfile(fileext = ".rds")
  on.exit(unlink(roundtrip_path), add = TRUE)
  saveRDS(portable_raw, roundtrip_path)
  roundtrip <- readRDS(roundtrip_path)
  validate_phenology_raw_result(roundtrip, "TEST")
  check(
    identical(roundtrip$phe_perindividual$individualID,
              identity_optional$individualID) &&
      identical(roundtrip$phe_statusintensity$phenophaseIntensity,
                rep(NA_character_, 2L)),
    "materialized raw result survives a dependency-free RDS round trip"
  )
})

identity_missing <- identity_fixture[, setdiff(names(identity_fixture), "plotID")]
check(
  errors_with(first_phenology_identity_rows(identity_missing, "TEST"),
              "missing required columns: plotID"),
  "identity helper fails closed when a required column is absent"
)
identity_na <- identity_fixture
identity_na$individualID[[2L]] <- NA_character_
check(
  errors_with(first_phenology_identity_rows(identity_na, "TEST"),
              "missing or blank individualID"),
  "identity helper fails closed on an NA individualID"
)
identity_blank <- identity_fixture
identity_blank$individualID[[2L]] <- "  \t"
check(
  errors_with(first_phenology_identity_rows(identity_blank, "TEST"),
              "missing or blank individualID"),
  "identity helper fails closed on a whitespace-only individualID"
)

# Reproduce run 30819294736: readRDS() without the producer's Arrow namespace
# retained 244 data-frame rows but substituted length-zero vectors. Detect that
# corrupt shape before assignment instead of emitting `$<-.data.frame`.
broken_columns <- as.list(identity_fixture)
broken_columns$individualID <- character()
identity_zero_length <- structure(
  broken_columns, class = "data.frame",
  row.names = .set_row_names(nrow(identity_fixture))
)
raw_zero_length <- raw_fixture
raw_zero_length$phe_perindividual <- identity_zero_length
check(
  errors_with(
    validate_phenology_raw_result(raw_zero_length, "TEST"),
    paste0(
      "raw table phe_perindividual for TEST is not rectangular: ",
      "individualID (length 0; expected 4)"
    )
  ),
  "raw consumer fails closed on a nonempty length-zero key column"
)

# ---- deterministic bundle bytes ---------------------------------------------
# The same observations must serialize to the same bytes whatever order the raw
# fetch or a join delivered them in, and exact duplicate rows must not survive.
obs_fixture <- data.frame(
  individualID = c("NEON.PLA.B", "NEON.PLA.A", "NEON.PLA.B", "NEON.PLA.A",
                   "NEON.PLA.A", "NEON.PLA.C"),
  year = c(2020L, 2020L, 2020L, 2019L, 2020L, NA),
  date = as.Date(c("2020-04-02", "2020-04-01", "2020-04-02", "2019-05-01",
                   "2020-04-01", NA)),
  phenophaseName = factor(c("Leaves", "Breaking leaf buds", "Leaves", "Leaves",
                            "Breaking leaf buds", "Leaves")),
  status = factor(c("yes", "no", "yes", "uncertain", "no", NA),
                  levels = c("no", "uncertain", "yes")),
  is_species = c(TRUE, TRUE, TRUE, TRUE, TRUE, NA),
  stringsAsFactors = FALSE
)
shuffled <- obs_fixture[c(6L, 3L, 1L, 5L, 2L, 4L), , drop = FALSE]
canon_a <- canonical_obs(obs_fixture)
canon_b <- canonical_obs(shuffled)
check(identical(canon_a, canon_b),
      "canonical_obs gives an identical table for a row-shuffled copy")
check(nrow(canon_a) == 4L && !anyDuplicated(canon_a) &&
        identical(canon_a$individualID,
                  c("NEON.PLA.A", "NEON.PLA.A", "NEON.PLA.B", "NEON.PLA.C")) &&
        identical(canon_a$year, c(2019L, 2020L, 2020L, NA)),
      "canonical_obs drops exact duplicates and orders by every column, NA last")
check(is.factor(canon_a$status) &&
        identical(levels(canon_a$status), c("no", "uncertain", "yes")) &&
        inherits(canon_a$date, "Date") && is.integer(canon_a$year) &&
        is.logical(canon_a$is_species) &&
        identical(attr(canon_a, "row.names"), 1:4) &&
        identical(class(canon_a), class(obs_fixture)),
      "canonical_obs keeps column types, factor levels, class and resets row names")
check(identical(canonical_obs(canon_a), canon_a),
      "canonical_obs is idempotent")
labels_fixture <- data.frame(
  phenophaseName = factor(c("Leaves", "Breaking leaf buds"),
                          levels = c("Leaves", "Breaking leaf buds")),
  stringsAsFactors = FALSE
)
check(identical(as.character(canonical_obs(labels_fixture)$phenophaseName),
                c("Breaking leaf buds", "Leaves")),
      "canonical_obs orders factor columns by label, not by level code")
local({
  path_a <- tempfile(fileext = ".rds")
  path_b <- tempfile(fileext = ".rds")
  on.exit(unlink(c(path_a, path_b)), add = TRUE)
  saveRDS(canon_a, path_a, compress = "xz")
  saveRDS(canon_b, path_b, compress = "xz")
  check(identical(unname(tools::md5sum(path_a)), unname(tools::md5sum(path_b))),
        "canonical obs from shuffled inputs serialize to identical md5")
})
# Committed bundles store obs as a tibble; the canonical form must stay one.
if (requireNamespace("tibble", quietly = TRUE)) {
  tbl_a <- canonical_obs(tibble::as_tibble(obs_fixture))
  tbl_b <- canonical_obs(tibble::as_tibble(shuffled))
  check(inherits(tbl_a, "tbl_df") && identical(tbl_a, tbl_b) &&
          identical(as.data.frame(tbl_a), canon_a),
        "canonical_obs keeps a tibble a tibble with the same rows")
}
check(errors_with(canonical_obs(list(a = 1)), "obs is not a data frame"),
      "canonical_obs fails closed on a non-data-frame")

inds_fixture <- data.frame(
  individualID = c("NEON.PLA.B", "NEON.PLA.C", "NEON.PLA.A"),
  scientificName = c("Beta", "Gamma", "Alpha"),
  stringsAsFactors = FALSE
)
bundle_fixture <- list(
  obs = obs_fixture,
  inds = inds_fixture,
  meta = list(site = "TEST"),
  ind_summary = inds_fixture[c(2L, 1L, 3L), , drop = FALSE],
  trend = data.frame(scientificName = c("Beta", "Alpha", "Alpha"),
                     year = c(2020L, 2021L, 2020L), onset = c(100, 101, 99),
                     n = c(3L, 3L, 4L), stringsAsFactors = FALSE)
)
bundle_reordered <- bundle_fixture
bundle_reordered$obs <- shuffled
bundle_reordered$inds <- inds_fixture[c(3L, 1L, 2L), , drop = FALSE]
bundle_reordered$trend <- bundle_fixture$trend[c(3L, 1L, 2L), , drop = FALSE]
canon_bundle <- canonical_bundle(bundle_fixture)
check(identical(canon_bundle, canonical_bundle(bundle_reordered)) &&
        identical(names(canon_bundle), names(bundle_fixture)) &&
        identical(canon_bundle$inds$individualID,
                  c("NEON.PLA.A", "NEON.PLA.B", "NEON.PLA.C")) &&
        identical(canon_bundle$ind_summary$individualID,
                  c("NEON.PLA.A", "NEON.PLA.B", "NEON.PLA.C")) &&
        identical(canon_bundle$trend$year, c(2020L, 2021L, 2020L)) &&
        identical(canon_bundle$trend$scientificName, c("Alpha", "Alpha", "Beta")),
      "canonical_bundle orders obs, inds, ind_summary and trend and keeps member order")
null_trend <- bundle_fixture
null_trend["trend"] <- list(NULL)
canon_null <- canonical_bundle(null_trend)
check("trend" %in% names(canon_null) && is.null(canon_null$trend) &&
        identical(names(canon_null), names(bundle_fixture)),
      "canonical_bundle keeps a NULL trend as a named NULL member")
no_key <- bundle_fixture
no_key$inds$individualID <- NULL
check(errors_with(canonical_bundle(no_key),
                  "Bundle table inds is missing sort columns: individualID"),
      "canonical_bundle fails closed when a sort key is absent")

local({
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  first <- write_rds_if_changed(canon_bundle, path)
  # Push the mtime into the past so an unwanted rewrite is detectable at any
  # file-system timestamp resolution.
  Sys.setFileTime(path, as.POSIXct("2001-01-01 00:00:00", tz = "UTC"))
  before <- file.info(path)$mtime
  second <- write_rds_if_changed(canonical_bundle(bundle_reordered), path)
  after <- file.info(path)$mtime
  check(isTRUE(first) && identical(second, FALSE) && identical(before, after),
        "write_rds_if_changed writes once and skips an identical rewrite without touching mtime")
  changed <- canon_bundle
  changed$meta$site <- "OTHER"
  check(isTRUE(write_rds_if_changed(changed, path)) &&
          identical(readRDS(path)$meta$site, "OTHER"),
        "write_rds_if_changed rewrites when the content changes")
})

cat(sprintf("All %d bundle-identity fixtures passed.\n", passed))
