#!/usr/bin/env Rscript

# Normalize a historical bundle edge case without fetching or recomputing raw
# observations. Older onset_trend() returned a typed zero-row data frame when a
# site had observations but every species-year failed the n >= 3 support gate.
# The release contract requires NULL for that unavailable state.

paths <- c(
  list.files("data/sites", pattern = "[.]rds$", full.names = TRUE),
  list.files("data-sample", pattern = "[.]rds$", full.names = TRUE)
)
if (!length(paths)) stop("No committed phenology bundles found", call. = FALSE)

changed <- character(0)
for (path in sort(paths)) {
  bundle <- readRDS(path)
  if (!is.list(bundle) || !("trend" %in% names(bundle)))
    stop(sprintf("%s is not a phenology bundle with a trend field", path),
         call. = FALSE)

  if (is.data.frame(bundle$trend) && nrow(bundle$trend) == 0L) {
    bundle$trend <- NULL
    saveRDS(bundle, path, compress = "xz")
    changed <- c(changed, path)
  }
}

if (length(changed)) {
  cat(sprintf("Normalized %d empty trend container(s): %s\n",
              length(changed), paste(changed, collapse = ", ")))
} else {
  cat("No empty trend containers required normalization.\n")
}
