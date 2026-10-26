# ===========================================================================
# build_search_index.R — build the small, bundled "Search the network" index
# from the COMMITTED bundles, with NO live NEON fetch. Reads:
#   data/sites/*.rds          - the full species roster per site, built from
#                               ind_summary (joined to inds for any missing
#                               taxon fields): n_ind (distinct tagged plants)
#                               and the most common growthForm. Every
#                               species-rank taxon is kept, including ones with
#                               no scored green-up or fewer than three plants,
#                               so the "Find a plant" search can find them.
#                               The per-(species x site) year span
#                               (year_min / year_max) comes from obs. The
#                               days carrying leaves (leaf_active) and its bound
#                               flag come from the same per-plant rows.
#   data/national_onsets.rds  - the supported onset values: greenup, flower and
#                               leaf_active (medians over supported plant-years
#                               for species with at least three tagged plants
#                               carrying a green-up) and that plant count, which
#                               becomes n_greenup_ind. Roster rows without a
#                               national_onsets row keep these values NA, so the
#                               search agrees with every other green-up surface.
#   data/site_index.rds       — the site-level metrics (median_greenup, years)
#                               reused unchanged for the THRESHOLD query.
# Writes data/search_index.rds = list(taxa, sites, built):
#   $taxa  — tidy (species × site) occurrence rows: scientificName, growthForm,
#            site, state, lat, lng, elevation_m, n_ind, greenup (median DOY),
#            flower, leaf_active, leaf_active_lower_bound, year_min, year_max,
#            name, n_greenup_ind. leaf_active_lower_bound is TRUE when the
#            plants' median leaf_active_hi (the longest span the visits allow)
#            exceeds leaf_active by at least BOUND_POINT_TOL days, so the value
#            reads "at least"; NA when leaf_active is NA.
#   $sites — the site-level table for the threshold query (one row/site),
#            site, name, state, median_greenup, median_leaf_active, greenup_lo,
#            greenup_hi, greenup_status, year_min, year_max, n_species,
#            n_individuals, gu_share.
#   $built — deterministic data-through date: maximum observation date in the
#            committed bundles. It is deliberately NOT the wall-clock build date.
# Loaded once at app boot (like site_index); searches filter it in memory, so
# the network search is instant and keeps the fast bundled load.
#
# Run:  Rscript scripts/build_search_index.R
# (skip_download-safe: reads only committed bundles, never NEON.)
# ===========================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(tibble) }))
source("R/site_metadata.R")     # neon_sites (name/state)
source("scripts/bundle_identity.R") # write_rds_if_changed
# The bound tolerance is read from the helpers so the search flag and the app can
# never disagree on a second literal.
BOUND_POINT_TOL <- local({
  helpers <- new.env()
  sys.source("R/phe_helpers.R", envir = helpers)
  helpers$BOUND_POINT_TOL
})
if (!is.numeric(BOUND_POINT_TOL) || length(BOUND_POINT_TOL) != 1L || !is.finite(BOUND_POINT_TOL))
  stop("R/phe_helpers.R does not define a finite BOUND_POINT_TOL.")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

SI  <- readRDS("data/site_index.rds")               # one row / site
NO  <- readRDS("data/national_onsets.rds")          # supported species x site onsets
if (is.null(NO) || !nrow(NO)) stop("national_onsets.rds is empty. Run scripts/rebuild_indexes.R first.")

# ---- per-(species × site) year span from the committed bundles -------------
# Cheap: obs already carries year + scientificName. One pass per bundle; only
# species-rank rows (is_species) so it lines up with national_onsets' roster.
span_rows <- list()
roster_rows <- list()
source_dates <- as.Date(character())
files <- list.files("data/sites", pattern = "\\.rds$", full.names = TRUE)
for (f in files) {
  b <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(b) || is.null(b$obs) || !nrow(b$obs)) next
  o <- b$obs
  # ---- species roster for this site, from ind_summary (+ inds) ----
  ind <- b$ind_summary
  if (!is.null(ind) && nrow(ind)) {
    need <- setdiff(c("scientificName", "growthForm", "is_species"), names(ind))
    if (length(need) && !is.null(b$inds) && nrow(b$inds))
      ind <- dplyr::left_join(ind,
        dplyr::distinct(b$inds[, c("individualID", intersect(need, names(b$inds))), drop = FALSE],
                        individualID, .keep_all = TRUE),
        by = "individualID")
    if (!"growthForm" %in% names(ind)) ind$growthForm <- NA_character_
    if (all(c("scientificName", "is_species") %in% names(ind)))
      roster_rows[[b$meta$site]] <- ind %>%
        dplyr::filter(is_species %in% TRUE, !is.na(scientificName)) %>%
        dplyr::transmute(site = as.character(b$meta$site),
                         scientificName = as.character(scientificName),
                         individualID = as.character(individualID),
                         growthForm = as.character(growthForm),
                         leaf_active = if ("leaf_active" %in% names(ind)) suppressWarnings(as.numeric(leaf_active)) else NA_real_,
                         leaf_active_hi = if ("leaf_active_hi" %in% names(ind)) suppressWarnings(as.numeric(leaf_active_hi)) else NA_real_)
  }
  if ("date" %in% names(o)) {
    observed_dates <- suppressWarnings(as.Date(as.character(o$date)))
    source_dates <- c(source_dates, observed_dates[!is.na(observed_dates)])
  }
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
# One row per (site x species-rank taxon) present in the bundles. Green-up and
# flowering come only from national_onsets (the supported, at-least-three-plant
# medians, NA where the green-up is only an upper bound). Days carrying leaves
# come from the bundle's per-plant summary, so evergreens with no green-up (Larrea)
# still show a season length: the median across plants of each plant's median
# over supported years, where at least three plants carry a value. The same
# plants give leaf_active_hi; the gap between the two flags a lower bound.
mode_form <- function(x) { x <- x[!is.na(x) & nzchar(x)]; if (!length(x)) return(NA_character_)
  tb <- table(x); names(tb)[which.max(tb)] }   # table() sorts names, so ties break alphabetically
roster <- if (length(roster_rows)) dplyr::bind_rows(roster_rows) else
  tibble::tibble(site = character(), scientificName = character(), individualID = character(),
                 growthForm = character(), leaf_active = numeric(), leaf_active_hi = numeric())
# one national_onsets row per (site, species): if a species ever splits across
# growth forms, keep the row with the most green-up plants (then first form).
onsets <- NO %>%
  dplyr::transmute(site = as.character(site),
                   scientificName = as.character(scientificName),
                   form_key = as.character(growthForm),
                   n_greenup_ind = as.integer(n_ind),
                   greenup = suppressWarnings(as.numeric(greenup)),
                   flower = suppressWarnings(as.numeric(flower))) %>%
  dplyr::arrange(site, scientificName, dplyr::desc(n_greenup_ind), form_key) %>%
  dplyr::distinct(site, scientificName, .keep_all = TRUE) %>%
  dplyr::select(-form_key)
for (col in c("greenup", "flower"))
  onsets[[col]][is.nan(onsets[[col]])] <- NA_real_
taxa <- roster %>%
  dplyr::group_by(site, scientificName) %>%
  dplyr::summarise(growthForm = mode_form(growthForm),
                   n_ind = as.integer(dplyr::n_distinct(individualID)),
                   n_leaf = sum(is.finite(leaf_active)),
                   leaf_active_hi = if (n_leaf >= 3L && any(is.finite(leaf_active_hi[is.finite(leaf_active)])))
                     round(stats::median(leaf_active_hi[is.finite(leaf_active) & is.finite(leaf_active_hi)])) else NA_real_,
                   leaf_active = if (n_leaf >= 3L)
                     round(stats::median(leaf_active[is.finite(leaf_active)])) else NA_real_,
                   .groups = "drop") %>%
  dplyr::mutate(leaf_active_lower_bound = dplyr::if_else(
    is.finite(leaf_active), leaf_active_hi - leaf_active >= BOUND_POINT_TOL, NA)) %>%
  dplyr::select(-n_leaf, -leaf_active_hi) %>%
  dplyr::left_join(onsets, by = c("site", "scientificName")) %>%
  dplyr::left_join(spans, by = c("site", "scientificName"))
mi <- match(taxa$site, neon_sites$site)
taxa$state       <- as.character(neon_sites$state[mi])
taxa$lat         <- as.numeric(neon_sites$lat[mi])
taxa$lng         <- as.numeric(neon_sites$lng[mi])
taxa$elevation_m <- suppressWarnings(as.integer(neon_sites$elevation_m[mi]))
taxa$name        <- as.character(neon_sites$name[mi])
taxa <- taxa %>%
  dplyr::select(scientificName, growthForm, site, state, lat, lng, elevation_m, n_ind,
                greenup, flower, leaf_active, leaf_active_lower_bound, year_min, year_max,
                name, n_greenup_ind)
# stable order: species, then green-up (NA last), then site
taxa <- taxa[order(taxa$scientificName, taxa$greenup, taxa$site, na.last = TRUE, method = "radix"), , drop = FALSE]
rownames(taxa) <- NULL

# ---- $sites: site-level table for the threshold query ----------------------
sites <- SI %>%
  dplyr::transmute(site = as.character(site),
                   median_greenup = suppressWarnings(as.numeric(median_greenup)),
                   median_leaf_active = suppressWarnings(as.numeric(median_leaf_active)),
                   greenup_lo = if ("greenup_lo" %in% names(SI)) suppressWarnings(as.numeric(greenup_lo)) else NA_real_,
                   greenup_hi = if ("greenup_hi" %in% names(SI)) suppressWarnings(as.numeric(greenup_hi)) else NA_real_,
                   greenup_status = if ("greenup_status" %in% names(SI)) as.character(greenup_status) else NA_character_,
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

if (!length(source_dates)) stop("No finite observation date found in committed bundles.")
data_through <- as.character(max(source_dates))
search_index <- list(taxa = taxa, sites = sites, built = data_through)
write_rds_if_changed(search_index, "data/search_index.rds")

cat(sprintf("search_index: %d taxon-site rows, %d distinct species, %d sites (taxa) | %d sites (threshold)\n",
            nrow(taxa), dplyr::n_distinct(taxa$scientificName), dplyr::n_distinct(taxa$site), nrow(sites)))
cat(sprintf("file size: %s bytes\n", format(file.size("data/search_index.rds"), big.mark = ",")))
cat(sprintf("data through: %s (derived from committed observations)\n", data_through))
cat("DONE\n")
