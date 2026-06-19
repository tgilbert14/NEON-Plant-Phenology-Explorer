# ===========================================================================
# Bundle NEON Plant phenology observations (DP1.10055.001) into per-site .rds.
# Reads raw ../phe-data-fetch/<SITE>_raw.rds (fetch_phe_demo.R, R-4.1.1).
# Each bundle = list(obs, inds, meta):
#   obs  — trimmed phe_statusintensity joined to identity: individualID, plotID,
#          scientificName, growthForm, nativeStatusCode, year, date, dayOfYear,
#          phenophaseName, status (yes/no/uncertain), intensity, is_species.
#          (status == "missed" dropped.) This is the phenophase career.
#   inds — one row per tagged plant: individualID, scientificName, growthForm,
#          plotID, lat, lng, nativeStatusCode, taxonRank, is_species.
#   meta — site, lat, lng, years.
# Onset / status-curves / season length are derived in-app from obs.
# ===========================================================================
suppressWarnings(suppressMessages({ library(dplyr) }))
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a
mode_chr <- function(x){ x<-x[!is.na(x)]; if(!length(x)) return(NA_character_); names(sort(table(x),decreasing=TRUE))[1] }
RAW <- "../phe-data-fetch"; SITES <- c("HARV", "SCBI", "SRER"); DEMO <- "HARV"
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
    dplyr::left_join(dplyr::select(ident, "individualID","scientificName","growthForm","nativeStatusCode","is_species"), by = "individualID")
  # identity may be drawn from obs plots; keep ident rows that actually have obs
  inds <- ident %>% dplyr::semi_join(obs, by = "individualID")
  if (!nrow(inds)) inds <- ident
  meta <- list(site = site, lat = stats::median(inds$lat, na.rm=TRUE), lng = stats::median(inds$lng, na.rm=TRUE),
               years = sort(unique(obs$year)))
  list(obs = obs, inds = inds, meta = meta)
}

dir.create("data/sites", showWarnings=FALSE, recursive=TRUE); dir.create("data-sample", showWarnings=FALSE)
idx <- list()
for (s in SITES) {
  cat("=== bundling", s, "===\n"); b <- build_site(s); if (is.null(b)) next
  saveRDS(b, file.path("data/sites", paste0(s,".rds")), compress="xz")
  if (identical(s, DEMO)) saveRDS(b, file.path("data-sample","demo.rds"), compress="xz")
  sp <- b$inds[b$inds$is_species, ]
  idx[[s]] <- data.frame(site = s, n_individuals = nrow(b$inds),
                         n_species = length(unique(sp$scientificName)),
                         n_obs = nrow(b$obs),
                         dominant_form = mode_chr(b$inds$growthForm),
                         lat = b$meta$lat, lng = b$meta$lng, stringsAsFactors = FALSE)
  cat(sprintf("  %s: %d individuals, %d species, %s obs, mostly %s | size %s\n",
      s, idx[[s]]$n_individuals, idx[[s]]$n_species, format(idx[[s]]$n_obs, big.mark=","), idx[[s]]$dominant_form,
      format(file.size(file.path("data/sites", paste0(s,".rds"))), big.mark=",")))
}
saveRDS(dplyr::bind_rows(idx), "data/site_index.rds", compress="xz")
cat("\nsite_index:\n"); print(dplyr::bind_rows(idx)); cat("DONE\n")
