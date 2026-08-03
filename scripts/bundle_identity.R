# Stable, fail-closed raw-table and identity extraction for the phenology bundler.
#
# Keep this helper dependency-free: it runs at the raw-data boundary before the
# fetcher serializes its staging artifact and before the bundler converts the
# result to a tibble. In particular, do not route the individualID key through
# vctrs hashing here or leave package-backed ALTREP vectors in the raw RDS files.

.phenology_site_label <- function(site) {
  if (length(site) == 1L && !is.na(site) && nzchar(as.character(site))) {
    as.character(site)
  } else {
    "<unknown>"
  }
}

.validate_phenology_frame <- function(x, table, site = "<unknown>",
                                      required = character(), nonempty = FALSE) {
  site_label <- .phenology_site_label(site)
  if (!is.data.frame(x)) {
    stop(sprintf("Phenology raw table %s for %s is not a data frame.",
                 table, site_label), call. = FALSE)
  }

  duplicate_names <- unique(names(x)[duplicated(names(x))])
  if (length(duplicate_names)) {
    stop(sprintf(
      "Phenology raw table %s for %s has duplicate columns: %s.",
      table, site_label, paste(duplicate_names, collapse = ", ")
    ), call. = FALSE)
  }

  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf(
      "Phenology raw table %s for %s is missing required columns: %s.",
      table, site_label, paste(missing, collapse = ", ")
    ), call. = FALSE)
  }

  expected <- nrow(x)
  ordered_names <- c(intersect(required, names(x)), setdiff(names(x), required))
  lengths <- vapply(
    ordered_names,
    function(column) length(x[[column]]),
    integer(1),
    USE.NAMES = TRUE
  )
  bad <- which(lengths != expected)
  if (length(bad)) {
    shown <- utils::head(bad, 10L)
    detail <- paste(sprintf(
      "%s (length %d; expected %d)", names(lengths)[shown], lengths[shown], expected
    ), collapse = ", ")
    if (length(bad) > length(shown)) {
      detail <- paste0(detail, sprintf(", and %d more", length(bad) - length(shown)))
    }
    stop(sprintf(
      paste0(
        "Phenology raw table %s for %s is not rectangular: %s. ",
        "Optional values must be represented by full-length typed NA values; ",
        "a zero-length column is valid only in a zero-row table."
      ),
      table, site_label, detail
    ), call. = FALSE)
  }

  if (isTRUE(nonempty) && expected == 0L) {
    stop(sprintf("Phenology raw table %s for %s has no rows.", table, site_label),
         call. = FALSE)
  }
  invisible(x)
}

# Allocate a new ordinary base vector and copy values into it. `as.vector()` and
# `x[]` can retain a package-backed ALTREP representation, so neither is a safe
# serialization boundary. Attributes retain Date, factor, and integer64 semantics.
.materialize_base_vector <- function(x, table, column, site = "<unknown>") {
  if (!is.atomic(x) && !is.list(x)) {
    stop(sprintf(
      "Phenology raw table %s for %s has unsupported %s column type %s.",
      table, .phenology_site_label(site), column, typeof(x)
    ), call. = FALSE)
  }
  out <- vector(typeof(x), length(x))
  if (length(x)) out[] <- x
  attributes(out) <- attributes(x)
  out
}

validate_phenology_raw_result <- function(x, site = "<unknown>") {
  if (!is.list(x)) {
    stop(sprintf("Phenology raw result for %s is not a list.",
                 .phenology_site_label(site)), call. = FALSE)
  }

  duplicate_tables <- unique(names(x)[duplicated(names(x))])
  if (length(duplicate_tables)) {
    stop(sprintf(
      "Phenology raw result for %s has duplicate tables: %s.",
      .phenology_site_label(site), paste(duplicate_tables, collapse = ", ")
    ), call. = FALSE)
  }

  required <- list(
    phe_perindividual = c(
      "individualID", "scientificName", "growthForm", "taxonRank",
      "nativeStatusCode", "plotID", "decimalLatitude", "decimalLongitude"
    ),
    phe_statusintensity = c(
      "individualID", "plotID", "date", "dayOfYear", "phenophaseName",
      "phenophaseStatus", "phenophaseIntensity"
    )
  )
  missing_tables <- setdiff(names(required), names(x))
  if (length(missing_tables)) {
    stop(sprintf(
      "Phenology raw result for %s is missing required tables: %s.",
      .phenology_site_label(site), paste(missing_tables, collapse = ", ")
    ), call. = FALSE)
  }

  tables <- c(intersect(names(required), names(x)),
              setdiff(names(x), names(required)))
  for (table in tables) {
    if (!is.data.frame(x[[table]]) && !(table %in% names(required))) next
    .validate_phenology_frame(
      x[[table]], table, site,
      required = if (table %in% names(required)) required[[table]] else character(),
      nonempty = table %in% names(required)
    )
  }
  invisible(x)
}

# `neonUtilities` can return Arrow-backed ALTREP columns when Arrow is available
# in the fetch process. Such columns are not portable to the intentionally lean,
# Arrow-free build job: readRDS() otherwise warns and substitutes length-zero
# vectors. Materialize every raw table column before saveRDS(), while preserving
# schema names, classes, attributes, and honest all-NA optional values.
materialize_phenology_raw_result <- function(x, site = "<unknown>") {
  validate_phenology_raw_result(x, site)
  for (table in names(x)) {
    if (!is.data.frame(x[[table]])) next
    for (column in names(x[[table]])) {
      x[[table]][[column]] <- .materialize_base_vector(
        x[[table]][[column]], table, column, site
      )
    }
  }
  validate_phenology_raw_result(x, site)
  x
}

first_phenology_identity_rows <- function(x, site = "<unknown>") {
  required <- c(
    "individualID", "scientificName", "growthForm", "taxonRank",
    "nativeStatusCode", "plotID", "decimalLatitude", "decimalLongitude"
  )
  site_label <- .phenology_site_label(site)
  .validate_phenology_frame(
    x, "phe_perindividual", site, required = required, nonempty = TRUE
  )

  out <- as.data.frame(x, stringsAsFactors = FALSE)
  out <- out[, required, drop = FALSE]
  ids <- enc2utf8(as.character(out$individualID))
  invalid <- is.na(ids) | !nzchar(trimws(ids))
  if (any(invalid)) {
    bad_rows <- paste(utils::head(which(invalid), 10L), collapse = ", ")
    stop(sprintf(
      "Phenology identity table for %s has missing or blank individualID at row(s): %s.",
      site_label, bad_rows
    ), call. = FALSE)
  }

  out$individualID <- ids
  out <- out[!duplicated(out$individualID), , drop = FALSE]
  rownames(out) <- NULL
  out
}
