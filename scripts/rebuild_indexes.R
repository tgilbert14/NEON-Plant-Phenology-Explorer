# ===========================================================================
# rebuild_indexes.R — regenerate the DERIVED indexes from the COMMITTED per-site
# bundles, WITHOUT a NEON re-pull. This is the skip_download fast path: it reads
# data/sites/*.rds (already in the repo), recomputes data/site_index.rds +
# data/national_onsets.rds, and rewrites a lean manifest.json. No raw needed.
#
# Used by the refresh workflow when skip_download=true (a quick, deploy-safe
# rebuild + a self-test of the pipeline), and locally to refresh the indexes
# after a helper change that affects site_index/national_onsets columns.
#   Rscript scripts/rebuild_indexes.R
# ===========================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(tibble) }))
source("R/site_metadata.R")     # neon_sites
source("R/phe_helpers.R")       # site_phe_summary / site_species_onsets / individual_summary
source("scripts/bundle_identity.R") # canonical_obs / canonical_bundle / write_rds_if_changed

SITE_DIR <- "data/sites"
files <- list.files(SITE_DIR, pattern = "\\.rds$", full.names = TRUE)
if (!length(files)) stop("No committed site bundles in ", SITE_DIR, ": nothing to rebuild.")

DEMO <- "SRER"   # data-sample/demo.rds is this site's bundle, byte for byte
summ <- list(); nat <- list(); demo_bundle <- NULL
for (f in files) {
  b <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(b) || is.null(b$obs) || !nrow(b$obs)) { cat("  SKIP (empty)", basename(f), "\n"); next }
  s <- b$meta$site
  # Re-derive the per-plant summary and the species-year trend from obs on every
  # rebuild instead of reusing the stored tables: the stored ind_summary carried a
  # summarise-reassignment bug (every *_n_years capped at 1) and the estimand
  # changed (Young-leaves green-up fallback, site-year support gate), so a stored
  # table can only be trusted when it reproduces from the observations. The
  # refreshed tables are written back into the committed bundle so the app, the
  # export and the indexes read one definition. dayOfYear is coalesced from date
  # first (older bundles kept ~15k valid-date rows with a blank dayOfYear), and
  # obs is put in canonical order with exact duplicate rows dropped, so the same
  # observations always give the same bytes.
  obs_new <- canonical_obs(normalize_doy(b$obs))
  # obs columns are factors in the bundle; helpers compare by value, but coerce a
  # working copy so the summarisers see character (matches bundle_phe_data.R).
  obs_chr <- obs_new; for (cc in c("phenophaseName","status","intensity","growthForm"))
    if (cc %in% names(obs_chr)) obs_chr[[cc]] <- as.character(obs_chr[[cc]])
  ind_s <- individual_summary(obs_chr, b$inds)
  trend <- onset_trend(obs_chr)
  b$obs <- obs_new
  b$ind_summary <- ind_s
  b["trend"] <- list(trend)   # `$trend <- NULL` would delete the field
  b <- canonical_bundle(b)
  # Content-keyed write: an unchanged bundle keeps its bytes and its mtime.
  if (write_rds_if_changed(b, f)) cat("  rewrote", basename(f), "(canonical obs, ind_summary/trend re-derived)\n")
  if (identical(s, DEMO)) demo_bundle <- b
  summ[[s]] <- site_phe_summary(obs_chr, b$inds, b$meta, b$ind_summary)
  sp <- site_species_onsets(obs_chr, b$inds, b$meta)
  if (!is.null(sp)) nat[[s]] <- sp
  cat("  indexed", s, "\n")
}

# The demo is the SRER bundle exactly as committed above, rewritten only when it
# differs, whether or not SRER itself changed this run.
if (is.null(demo_bundle)) stop("Demo site ", DEMO, " has no usable committed bundle in ", SITE_DIR, ".")
dir.create("data-sample", showWarnings = FALSE)
if (write_rds_if_changed(demo_bundle, file.path("data-sample", "demo.rds")))
  cat("  rewrote data-sample/demo.rds (", DEMO, ")\n", sep = "")

site_index <- dplyr::bind_rows(summ)
site_index$elevation_m <- neon_sites$elevation_m[match(site_index$site, neon_sites$site)]
if (!("gu_share" %in% names(site_index))) site_index$gu_share <- NA_real_
if (!("median_visit_interval" %in% names(site_index))) site_index$median_visit_interval <- NA_real_
site_index <- site_index[order(as.character(site_index$site), method = "radix"), , drop = FALSE]
write_rds_if_changed(site_index, "data/site_index.rds")

national_onsets <- dplyr::bind_rows(nat)
if (nrow(national_onsets)) {
  national_onsets$state <- neon_sites$state[match(national_onsets$site, neon_sites$site)]
  national_onsets$elevation_m <- neon_sites$elevation_m[match(national_onsets$site, neon_sites$site)]
}
if (nrow(national_onsets))
  national_onsets <- national_onsets[order(as.character(national_onsets$site),
                                           as.character(national_onsets$scientificName),
                                           as.character(national_onsets$growthForm),
                                           na.last = TRUE, method = "radix"), , drop = FALSE]
write_rds_if_changed(national_onsets, "data/national_onsets.rds")

cat(sprintf("\nrebuilt site_index: %d sites | national_onsets: %d rows, %d species\n",
            nrow(site_index), nrow(national_onsets), dplyr::n_distinct(national_onsets$scientificName)))

# rebuild the "Search the network" index too — it derives from these same
# committed bundles + indexes, so it must stay in lockstep on every refresh.
if (file.exists("scripts/build_search_index.R")) {
  cat("Rebuilding search_index.rds...\n")
  source("scripts/build_search_index.R", local = new.env())
}

# refresh the lean manifest too (so a code/helper change deploys with the right
# package set). write_manifest.R hard-gates neonUtilities/arrow/data.table.
# Only when rsconnect is installed (it isn't in the slim refresh CI image); the
# data rebuild above is the deploy-relevant part, the manifest changes only on a
# dependency change, not a data refresh.
if (file.exists("scripts/write_manifest.R") && requireNamespace("rsconnect", quietly = TRUE)) {
  cat("Regenerating manifest.json...\n")
  source("scripts/write_manifest.R", local = new.env())
} else {
  cat("Skipping manifest regen (rsconnect not installed or no script); data indexes rebuilt.\n")
}
cat("DONE\n")
