#!/usr/bin/env Rscript

# Dependency-free fixtures for the raw per-individual identity boundary. Run
# from any working directory:
#   Rscript --vanilla scripts/test_bundle_identity.R

args <- commandArgs(trailingOnly = FALSE)
file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
root <- if (length(file_arg)) normalizePath(file.path(dirname(file_arg), "..")) else
  normalizePath(".")
source(file.path(root, "scripts", "bundle_identity.R"), chdir = TRUE)

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
# plant. Keep the first source row and ignore later conflicting metadata.
accented_id <- paste0("NEON.PLA.", intToUtf8(233), "03.001")
identity_fixture <- data.frame(
  individualID = c("NEON.PLA.Z10.001", "NEON.PLA.A02.001",
                   "NEON.PLA.Z10.001", accented_id),
  scientificName = c("Species first", "Species alpha",
                     "Species conflicting", "Species accented"),
  growthForm = c("tree", "shrub", "forb", "graminoid"),
  taxonRank = rep("species", 4L),
  nativeStatusCode = c("N", "N", "I", "N"),
  plotID = c("PLOT-Z", "PLOT-A", "PLOT-WRONG", "PLOT-E"),
  decimalLatitude = c(40, 41, 99, 42),
  decimalLongitude = c(-70, -71, 99, -72),
  ignoredRawColumn = 1:4,
  stringsAsFactors = FALSE
)
identity_rows <- first_phenology_identity_rows(identity_fixture, "TEST")
check(
  identical(identity_rows$individualID,
            enc2utf8(c("NEON.PLA.Z10.001", "NEON.PLA.A02.001", accented_id))),
  "identity dedup preserves nonalphabetic first-source order with UTF-8 keys"
)
check(
  nrow(identity_rows) == 3L &&
    identity_rows$scientificName[[1L]] == "Species first" &&
    identity_rows$plotID[[1L]] == "PLOT-Z" &&
    identity_rows$decimalLatitude[[1L]] == 40,
  "identity dedup keeps the complete first row when later metadata conflicts"
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

cat(sprintf("All %d bundle-identity fixtures passed.\n", passed))
