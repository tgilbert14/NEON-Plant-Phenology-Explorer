# Stable, fail-closed identity extraction for the phenology bundler.
#
# Keep this helper dependency-free: it runs at the raw-data boundary before the
# bundler converts the result to a tibble.  In particular, do not route the
# individualID key through vctrs hashing here.

first_phenology_identity_rows <- function(x, site = "<unknown>") {
  required <- c(
    "individualID", "scientificName", "growthForm", "taxonRank",
    "nativeStatusCode", "plotID", "decimalLatitude", "decimalLongitude"
  )
  site_label <- if (length(site) == 1L && !is.na(site) && nzchar(as.character(site))) {
    as.character(site)
  } else {
    "<unknown>"
  }

  if (!is.data.frame(x)) {
    stop(sprintf("Phenology identity table for %s is not a data frame.", site_label),
         call. = FALSE)
  }

  missing <- setdiff(required, names(x))
  if (length(missing)) {
    stop(sprintf(
      "Phenology identity table for %s is missing required columns: %s.",
      site_label, paste(missing, collapse = ", ")
    ), call. = FALSE)
  }

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
