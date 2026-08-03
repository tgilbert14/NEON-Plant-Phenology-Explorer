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

cat(sprintf("All %d bundle-identity fixtures passed.\n", passed))
