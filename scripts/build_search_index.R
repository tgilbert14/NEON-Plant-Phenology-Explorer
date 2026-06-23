# ===========================================================================
# build_search_index.R — build the small, bundled "Search the network" index
# from the COMMITTED bundles, with NO live NEON fetch. Reads:
#   data/national_onsets.rds  — one row per (species × site): median green-up
#                               DOY (the app's honest within-site measure),
#                               flower / leaf_active medians, n_ind, growthForm.
#   data/sites/*.rds          — for the per-(species × site) year span
#                               (year_min / year_max), pulled from obs.
#   data/site_index.rds       — the site-level metrics (median_greenup, years)
#                               reused unchanged for the THRESHOLD query.
# Writes data/search_index.rds = list(taxa, sites, built):
#   $taxa  — tidy (species × site) occurrence rows: scientificName, growthForm,
#            site, state, lat, lng, elevation_m, n_ind, greenup (median DOY),
#            flower, leaf_active, year_min, year_max.
#   $sites — the site-level table for the threshold query (one row/site),
#            site, name, state, median_greenup, year_min, year_max, n_species,
#            n_individuals, gu_share.
# Loaded once at app boot (like site_index); searches filter it in memory, so
# the network search is instant and keeps the fast bundled load.
#
# Run:  Rscript scripts/build_search_index.R
# (skip_download-safe: reads only committed bundles, never NEON.)
# ===========================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(tibble) }))
if (dir.exists("C:/Users/tsgil/OneDrive/Documents/VGS - R/NEON-Plant-Phenology"))
  setwd("C:/Users/tsgil/OneDrive/Documents/VGS - R/NEON-Plant-Phenology")
source("R/site_metadata.R")     # neon_sites (name/state)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

NO  <- readRDS("data/national_onsets.rds")          # species × site onsets
SI  <- readRDS("data/site_index.rds")               # one row / site
if (is.null(NO) || !nrow(NO)) stop("national_onsets.rds is empty — run scripts/bundle_phe_data.R / rebuild_indexes.R first.")

# ---- per-(species × site) year span from the committed bundles -------------
# Cheap: obs already carries year + scientificName. One pass per bundle; only
# species-rank rows (is_species) so it lines up with national_onsets' roster.
span_rows <- list()
files <- list.files("data/sites", pattern = "\\.rds$", full.names = TRUE)
for (f in files) {
  b <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(b) || is.null(b$obs) || !nrow(b$obs)) next
  o <- b$obs
  sci <- as.character(o$scientificName)
  isp <- if ("is_species" %in% names(o)) o$is_species %in% TRUE else !is.na(sci)
  keep <- isp & !is.na(sci) & !is.na(o$year)
  if (!any(keep)) next
  sp <- tibble::tibble(site = b$meta$site, scientificName = sci[keep], year = as.integer(o$year[keep]))
  span_rows[[b$meta$site]] <- sp %>% dplyr::group_by(site, scientificName) %>%
    dplyr::summarise(year_min = min(year), year_max = max(year), .groups = "drop")
}
spans <- if (length(span_rows)) dplyr::bind_rows(span_rows) else
  tibble::tibble(site = character(), scientificName = character(), year_min = integer(), year_max = integer())

# ---- $taxa: tidy species × site occurrence rows ----------------------------
taxa <- NO %>%
  dplyr::transmute(scientificName = as.character(scientificName),
                   growthForm = as.character(growthForm),
                   site = as.character(site),
                   state = as.character(state),
                   lat = as.numeric(lat), lng = as.numeric(lng),
                   elevation_m = suppressWarnings(as.integer(elevation_m)),
                   n_ind = as.integer(n_ind),
                   greenup = suppressWarnings(as.numeric(greenup)),
                   flower = suppressWarnings(as.numeric(flower)),
                   leaf_active = suppressWarnings(as.numeric(leaf_active))) %>%
  dplyr::left_join(spans, by = c("site", "scientificName"))
# attach the human site name for display (state already on the row)
taxa$name <- neon_sites$name[match(taxa$site, neon_sites$site)]
taxa <- taxa %>% dplyr::arrange(scientificName, greenup, site)

# ---- $sites: site-level table for the threshold query ----------------------
sites <- SI %>%
  dplyr::transmute(site = as.character(site),
                   median_greenup = suppressWarnings(as.numeric(median_greenup)),
                   median_leaf_active = suppressWarnings(as.numeric(median_leaf_active)),
                   n_species = as.integer(n_species),
                   n_individuals = as.integer(n_individuals),
                   gu_share = suppressWarnings(as.numeric(gu_share)),
                   year_min = suppressWarnings(as.integer(year_min)),
                   year_max = suppressWarnings(as.integer(year_max)))
sites$name  <- neon_sites$name[match(sites$site, neon_sites$site)]
sites$state <- neon_sites$state[match(sites$site, neon_sites$site)]
sites$lat   <- neon_sites$lat[match(sites$site, neon_sites$site)] %||% NA_real_
sites$lng   <- neon_sites$lng[match(sites$site, neon_sites$site)] %||% NA_real_
sites <- sites %>% dplyr::filter(!is.na(median_greenup)) %>% dplyr::arrange(median_greenup)

search_index <- list(taxa = taxa, sites = sites, built = as.character(Sys.Date()))
saveRDS(search_index, "data/search_index.rds", compress = "xz")

cat(sprintf("search_index: %d taxon-site rows, %d distinct species, %d sites (taxa) | %d sites (threshold)\n",
            nrow(taxa), dplyr::n_distinct(taxa$scientificName), dplyr::n_distinct(taxa$site), nrow(sites)))
cat(sprintf("file size: %s bytes\n", format(file.size("data/search_index.rds"), big.mark = ",")))
cat("DONE\n")
