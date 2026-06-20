# ===========================================================================
# Bundle NEON Plant phenology observations (DP1.10055.001) into per-site .rds.
# Reads raw ../phe-data-fetch/<SITE>_raw.rds (scripts/fetch_all_phe.R).
# Each bundle = list(obs, inds, meta, ind_summary, trend):
#   obs  — trimmed phe_statusintensity joined to identity: individualID, plotID,
#          scientificName, growthForm, year, date, dayOfYear, phenophaseName,
#          status (yes/no/uncertain), intensity, is_species. Low-cardinality
#          columns (phenophaseName/status/intensity/growthForm) are FACTORS to
#          cut RAM ~40%. nativeStatusCode is NOT carried on obs (read from inds;
#          re-joined only at export). status == "missed" dropped.
#   inds — one row per tagged plant: individualID, scientificName, growthForm,
#          plotID, lat, lng, nativeStatusCode, taxonRank, is_species.
#   meta — site, lat, lng, years.
#   ind_summary / trend — precomputed (individual_summary / onset_trend) so the
#          app needn't recompute ~430ms on every site load.
# Also writes data/site_index.rds (one row/site, picker + national map) and
# data/national_onsets.rds (one row/site×species, the cross-site layer).
# ===========================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(tibble) }))
source("R/site_metadata.R")     # neon_sites (name/state/domain/elevation_m)
source("R/phe_helpers.R")       # individual_summary / onset_trend / site_phe_summary / site_species_onsets

RAW <- "../phe-data-fetch"; DEMO <- "HARV"
# bundle every raw site present (resumable national build); CLI args = subset
SITES <- sub("_raw\\.rds$", "", list.files(RAW, pattern = "_raw\\.rds$"))
if (length(commandArgs(trailingOnly = TRUE))) SITES <- commandArgs(trailingOnly = TRUE)
if (!length(SITES)) stop("No <SITE>_raw.rds in ", RAW, " — run scripts/fetch_all_phe.R first.")
is_species_rank <- function(rank, sci){ ok <- is.na(rank)|rank %in% c("species","subspecies","variety","speciesGroup")
  amb <- grepl("\\bsp\\.?$", ifelse(is.na(sci),"",sci))|grepl("/",ifelse(is.na(sci),"",sci),fixed=TRUE); ok & !amb }

build_site <- function(site) {
  f <- file.path(RAW, paste0(site,"_raw.rds")); if(!file.exists(f)){cat("  MISSING",f,"\n"); return(NULL)}
  r <- readRDS(f)
  pind <- tibble::as_tibble(r$phe_perindividual); si <- tibble::as_tibble(r$phe_statusintensity)
  num <- function(x) suppressWarnings(as.numeric(x))
  ident <- pind %>% dplyr::distinct(.data$individualID, .keep_all = TRUE) %>%
    dplyr::transmute(individualID, scientificName, growthForm, taxonRank, nativeStatusCode,
                     plotID, lat = num(decimalLatitude), lng = num(decimalLongitude)) %>%
    dplyr::mutate(is_species = is_species_rank(.data$taxonRank, .data$scientificName))
  obs <- si %>%
    dplyr::filter(.data$phenophaseStatus %in% c("yes","no","uncertain"), !is.na(.data$phenophaseName)) %>%
    dplyr::transmute(individualID, plotID,
                     year = as.integer(substr(as.character(date),1,4)), date = as.Date(date),
                     dayOfYear = as.integer(dayOfYear), phenophaseName, status = phenophaseStatus,
                     intensity = phenophaseIntensity) %>%
    dplyr::filter(!is.na(.data$year)) %>%
    # scientificName/growthForm/is_species denormalized onto obs for the analysis
    # layer; nativeStatusCode intentionally NOT carried (lives on inds — re-joined
    # only at CSV export) to save memory at the 46-site scale.
    dplyr::left_join(dplyr::select(ident, "individualID","scientificName","growthForm","is_species"), by = "individualID")
  # factor-encode the low-cardinality, high-repetition columns (RAM ~40% lower;
  # all helper comparisons are by value so behaviour is unchanged). Join/group
  # keys (individualID/plotID/scientificName) stay character to avoid factor-join
  # type clashes with inds.
  for (cc in c("phenophaseName","status","intensity","growthForm"))
    if (cc %in% names(obs)) obs[[cc]] <- as.factor(obs[[cc]])
  # identity may be drawn from obs plots; keep ident rows that actually have obs
  inds <- ident %>% dplyr::semi_join(obs, by = "individualID")
  if (!nrow(inds)) inds <- ident
  meta <- list(site = site, lat = stats::median(inds$lat, na.rm=TRUE), lng = stats::median(inds$lng, na.rm=TRUE),
               years = sort(unique(obs$year)))
  # helpers read status/phenophaseName as character — coerce a working copy so
  # factor columns don't surprise the summarisers (cheap; per-site).
  obs_chr <- obs; for (cc in c("phenophaseName","status","intensity","growthForm"))
    if (cc %in% names(obs_chr)) obs_chr[[cc]] <- as.character(obs_chr[[cc]])
  ind_summary <- individual_summary(obs_chr, inds)
  trend <- onset_trend(obs_chr)
  list(obs = obs, inds = inds, meta = meta, ind_summary = ind_summary, trend = trend,
       .summary = site_phe_summary(obs_chr, inds, meta, ind_summary),
       .species = site_species_onsets(obs_chr, inds, meta))
}

dir.create("data/sites", showWarnings=FALSE, recursive=TRUE); dir.create("data-sample", showWarnings=FALSE)
summ <- list(); nat <- list()
for (s in SITES) {
  cat("=== bundling", s, "===\n"); b <- build_site(s); if (is.null(b)) next
  ssum <- b$.summary; sp_onsets <- b$.species; b$.summary <- NULL; b$.species <- NULL
  saveRDS(b, file.path("data/sites", paste0(s,".rds")), compress="xz")
  if (identical(s, DEMO)) saveRDS(b, file.path("data-sample","demo.rds"), compress="xz")
  summ[[s]] <- ssum
  if (!is.null(sp_onsets)) nat[[s]] <- sp_onsets
  cat(sprintf("  %s: %d individuals, %d species, %s obs, mostly %s | greenup %s | size %s\n",
      s, ssum$n_individuals, ssum$n_species, format(ssum$n_obs, big.mark=","), ssum$dominant_form,
      ssum$median_greenup,
      format(file.size(file.path("data/sites", paste0(s,".rds"))), big.mark=",")))
}

# ---- site_index: one row per site (picker + national map) -----------------
site_index <- dplyr::bind_rows(summ)
# attach elevation (and confirm name/state come from neon_sites in the app)
site_index$elevation_m <- neon_sites$elevation_m[match(site_index$site, neon_sites$site)]
# gu_share = green-up COVERAGE share per site (greenup_coverage(); site_phe_summary
# emits it). PERSIST it so the national map can mute thin-coverage sites without a
# bundle reload. Backfill NA if an older summary in `summ` predates the column, so
# the column always exists and the app read never errors.
if (!("gu_share" %in% names(site_index))) site_index$gu_share <- NA_real_
saveRDS(site_index, "data/site_index.rds", compress="xz")

# ---- national_onsets: one row per (site × species) for the cross-site tab --
national_onsets <- dplyr::bind_rows(nat)
if (nrow(national_onsets)) {
  national_onsets$state <- neon_sites$state[match(national_onsets$site, neon_sites$site)]
  national_onsets$elevation_m <- neon_sites$elevation_m[match(national_onsets$site, neon_sites$site)]
}
saveRDS(national_onsets, "data/national_onsets.rds", compress="xz")

cat("\nsite_index:\n"); print(as.data.frame(site_index)); cat("\n")
cat(sprintf("national_onsets: %d site×species rows, %d species, %d sites\n",
    nrow(national_onsets), dplyr::n_distinct(national_onsets$scientificName), length(summ)))
cat("DONE\n")
