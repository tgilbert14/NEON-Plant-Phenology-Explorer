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

# One identity row per tagged plant. When NEON lists a plant more than once (a
# later re-identification or plot correction), the latest record wins, as NEON's
# phenology tutorial does for phe_perindividual: the newest editedDate, then the
# newest date, then the smallest uid, so the same raw table always keeps the same
# row whatever order it arrives in (iris, 2026-10-21). The three ordering columns
# are required, and a raw table without them fails closed. Rows come back ordered
# by individualID (radix).
IDENTITY_ORDER_KEYS <- c("editedDate", "date", "uid")
first_phenology_identity_rows <- function(x, site = "<unknown>") {
  required <- c(
    "individualID", "scientificName", "growthForm", "taxonRank",
    "nativeStatusCode", "plotID", "decimalLatitude", "decimalLongitude"
  )
  site_label <- .phenology_site_label(site)
  .validate_phenology_frame(
    x, "phe_perindividual", site, required = c(required, IDENTITY_ORDER_KEYS),
    nonempty = TRUE
  )

  out <- as.data.frame(x, stringsAsFactors = FALSE)
  ids <- enc2utf8(as.character(out$individualID))
  invalid <- is.na(ids) | !nzchar(trimws(ids))
  if (any(invalid)) {
    bad_rows <- paste(utils::head(which(invalid), 10L), collapse = ", ")
    stop(sprintf(
      "Phenology identity table for %s has missing or blank individualID at row(s): %s.",
      site_label, bad_rows
    ), call. = FALSE)
  }

  sort_key <- function(v) if (is.factor(v)) as.character(v) else v
  ord <- order(ids, sort_key(out$editedDate), sort_key(out$date), sort_key(out$uid),
               decreasing = c(FALSE, TRUE, TRUE, FALSE), method = "radix", na.last = TRUE)
  out <- out[ord, required, drop = FALSE]
  out$individualID <- ids[ord]
  out <- out[!duplicated(out$individualID), , drop = FALSE]
  rownames(out) <- NULL
  out
}

# ---- deterministic bundle bytes --------------------------------------------
# A bundle rebuilt from the same observations must serialize to the same bytes,
# so a refresh that changes nothing produces no diff and a manifest checksum
# moves only when content moves. Row order from the raw fetch, from dplyr joins
# and from group-wise summaries is not promised, so every stored table is put in
# one canonical order here. Character keys sort with method = "radix", which
# compares bytes (C locale) and so cannot drift with the build machine's locale.

# Sort key for one column: factors compare by their labels (not their codes, so
# a different level set cannot reorder rows), dates by their numeric value.
.canonical_key <- function(x, column) {
  if (is.factor(x)) return(enc2utf8(as.character(x)))
  if (is.list(x) || is.complex(x) || is.raw(x)) {
    stop(sprintf("Cannot canonicalize column %s of type %s.", column, typeof(x)),
         call. = FALSE)
  }
  if (is.character(x)) return(enc2utf8(as.vector(x)))
  out <- unclass(x)
  attributes(out) <- NULL
  out
}

# Reindex rows of a data frame while keeping its class, every column's type,
# factor levels and attributes, and compact row names.
.reindex_frame <- function(x, idx) {
  out <- x[idx, , drop = FALSE]
  for (column in names(x)) {
    value <- x[[column]][idx]
    kept <- attributes(x[[column]])
    kept$names <- NULL
    attributes(value) <- kept
    out[[column]] <- value
  }
  attr(out, "row.names") <- .set_row_names(length(idx))
  out
}

.require_frame_columns <- function(x, table, columns) {
  if (!is.data.frame(x)) {
    stop(sprintf("Bundle table %s is not a data frame.", table), call. = FALSE)
  }
  missing <- setdiff(columns, names(x))
  if (length(missing)) {
    stop(sprintf("Bundle table %s is missing sort columns: %s.",
                 table, paste(missing, collapse = ", ")), call. = FALSE)
  }
  invisible(x)
}

.order_frame_by <- function(x, table, columns) {
  .require_frame_columns(x, table, columns)
  if (nrow(x) < 2L) return(.reindex_frame(x, seq_len(nrow(x))))
  keys <- lapply(columns, function(column) .canonical_key(x[[column]], column))
  idx <- do.call(order, c(unname(keys), list(na.last = TRUE, method = "radix")))
  .reindex_frame(x, idx)
}

# Drop exact duplicate rows (every column equal, NA equal to NA), then order the
# rows by every column in the table's column order. Sorting first makes the
# duplicate test a vectorized comparison of adjacent rows.
canonical_obs <- function(obs) {
  if (!is.data.frame(obs)) {
    stop("Bundle table obs is not a data frame.", call. = FALSE)
  }
  columns <- names(obs)
  if (anyDuplicated(columns)) {
    stop(sprintf("Bundle table obs has duplicate columns: %s.",
                 paste(unique(columns[duplicated(columns)]), collapse = ", ")),
         call. = FALSE)
  }
  n <- nrow(obs)
  if (n < 2L || !length(columns)) return(.reindex_frame(obs, seq_len(n)))
  keys <- lapply(columns, function(column) .canonical_key(obs[[column]], column))
  ord <- do.call(order, c(unname(keys), list(na.last = TRUE, method = "radix")))
  same <- rep(TRUE, n - 1L)
  for (key in keys) {
    sorted <- key[ord]
    a <- sorted[-1L]
    b <- sorted[-n]
    a_na <- is.na(a)
    b_na <- is.na(b)
    equal <- (a_na & b_na) | (!a_na & !b_na & a == b)
    equal[is.na(equal)] <- FALSE
    same <- same & equal
  }
  .reindex_frame(obs, ord[!c(FALSE, same)])
}

# Put every stored table of a site bundle in canonical order. Member names and
# order are kept; a NULL trend stays a named NULL member.
canonical_bundle <- function(b) {
  if (!is.list(b) || is.data.frame(b)) {
    stop("A phenology bundle must be a list.", call. = FALSE)
  }
  required <- c("obs", "inds", "ind_summary", "trend")
  missing <- setdiff(required, names(b))
  if (length(missing)) {
    stop(sprintf("Phenology bundle is missing members: %s.",
                 paste(missing, collapse = ", ")), call. = FALSE)
  }
  b[["obs"]] <- canonical_obs(b[["obs"]])
  b[["inds"]] <- .order_frame_by(b[["inds"]], "inds", "individualID")
  b[["ind_summary"]] <- .order_frame_by(b[["ind_summary"]], "ind_summary", "individualID")
  if (!is.null(b[["trend"]])) {
    b["trend"] <- list(.order_frame_by(b[["trend"]], "trend", c("scientificName", "year")))
  }
  b
}

# Content-keyed write: leave the file (and its mtime) alone when it already holds
# an identical object, so an unchanged rebuild touches nothing. Returns TRUE when
# the file was written.
write_rds_if_changed <- function(x, path) {
  if (file.exists(path)) {
    current <- tryCatch(readRDS(path), error = function(e) e)
    if (!inherits(current, "error") && identical(current, x)) return(invisible(FALSE))
  }
  saveRDS(x, path, compress = "xz")
  invisible(TRUE)
}
