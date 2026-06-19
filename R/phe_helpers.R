# ===========================================================================
# NEON Plant Phenology Explorer — phe_helpers.R
# The unit is a TAGGED plant individual with a weekly-resolution, multi-year
# phenophase career (a near-twin of the veg-structure tree career). Onset is
# interval-censored (weekly obs) -> midpoint between last 'no' and first 'yes'.
# The Phenology Clock pools years by design; onset trends must NOT pool (the
# never-pool rule). See docs/neonize-playbook.md.
# ===========================================================================
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
mode_chr <- function(x){ x<-x[!is.na(x)]; if(!length(x)) return(NA_character_); names(sort(table(x),decreasing=TRUE))[1] }
short_ind <- function(id) sub("^NEON\\.PLA\\.D[0-9]{2}\\.", "", as.character(id))
short_plot <- function(p) sub("^[A-Z]{4}_", "", as.character(p))

species_level_only <- function(d){ if (is.null(d)||!nrow(d)) return(d)
  if ("is_species" %in% names(d)) return(d[d$is_species %in% TRUE, , drop=FALSE])
  ok <- is.na(d$taxonRank)|d$taxonRank %in% c("species","subspecies","variety","speciesGroup"); d[ok,,drop=FALSE] }
make_species_pal <- function(d){ sp <- sort(unique(d$scientificName[!is.na(d$scientificName)])); if(!length(sp)) return(character(0))
  stats::setNames(grDevices::colorRampPalette(RColorBrewer::brewer.pal(8,"Dark2"))(length(sp)), sp) }

# ordered phenophase sequence (for the clock rings + out-of-order QC). Higher rank
# = later in the season. Growth-form-specific phenophases share this ordering.
PHENO_RANK <- c("Breaking leaf buds"=1, "Emerging needles"=1, "Breaking needle buds"=1,
                "Initial growth"=1, "Young needles"=2, "Increasing leaf size"=2, "Young leaves"=2,
                "Leaves"=3, "Open flowers"=4, "Open pollen cones"=4, "Colored leaves"=5,
                "Falling leaves"=6, "Fruits"=4)
GREENUP <- c("Breaking leaf buds","Initial growth","Emerging needles","Breaking needle buds")
SENESCE <- c("Colored leaves","Falling leaves")
pheno_palette <- c("Breaking leaf buds"="#9acd6b","Increasing leaf size"="#5fae3a","Leaves"="#1a7f37",
                   "Open flowers"="#d6336c","Fruits"="#9c6644","Colored leaves"="#e0962e","Falling leaves"="#b5651d",
                   "Initial growth"="#9acd6b","Young leaves"="#5fae3a","Emerging needles"="#7fbf7f",
                   "Young needles"="#5fae3a","Open pollen cones"="#caa84a","Breaking needle buds"="#9acd6b")

COL_OF_PHENO <- function(p) unname(ifelse(p %in% names(pheno_palette), pheno_palette[p], "#9aa6b2"))

# ---------------------------------------------------------------------------
# onset(): first 'yes' day-of-year per individual x phenophase x year, interval-
# censored to the midpoint between the last preceding 'no' and the first 'yes'.
# Returns one row per (individualID, phenophaseName, year).
# ---------------------------------------------------------------------------
onset <- function(obs, phenophases = NULL) {
  d <- obs[obs$status %in% c("yes","no") & !is.na(obs$dayOfYear), , drop=FALSE]
  if (!is.null(phenophases)) d <- d[d$phenophaseName %in% phenophases, , drop=FALSE]
  if (!nrow(d)) return(NULL)
  d %>% dplyr::group_by(.data$individualID, .data$scientificName, .data$growthForm, .data$phenophaseName, .data$year) %>%
    dplyr::summarise(onset_doy = {
        yes <- .data$dayOfYear[.data$status == "yes"]; no <- .data$dayOfYear[.data$status == "no"]
        if (!length(yes)) NA_real_ else { f <- min(yes); pno <- no[no < f]
          if (length(pno)) (max(pno) + f) / 2 else f } },   # midpoint of the interval (or left-censored = first yes)
      first_yes = if (any(.data$status=="yes")) min(.data$dayOfYear[.data$status=="yes"]) else NA_real_,
      .groups = "drop") %>%
    dplyr::filter(is.finite(.data$onset_doy))
}

# green-up / flowering / leaf-off per individual per year.
# leaf_off = last day "Leaves" was recorded 'yes' (the canopy-duration end). We do
# NOT use first 'Colored leaves' as a senescence proxy: NEON records 'Colored
# leaves: yes' for even a few early-stressed leaves (e.g. day 163 in June), which
# makes first-coloration a wildly early, misleading end-of-season marker. Last
# leaf-present day is the robust, ecologically meaningful growing-season end.
key_onsets <- function(obs) {
  gu <- onset(obs, GREENUP) %>% dplyr::group_by(.data$individualID, .data$year) %>%
    dplyr::summarise(greenup = min(.data$onset_doy), .groups="drop")
  fl <- onset(obs, "Open flowers") %>% dplyr::transmute(individualID, year, flower = .data$onset_doy)
  lo <- obs[obs$phenophaseName == "Leaves" & obs$status == "yes" & is.finite(obs$dayOfYear), , drop=FALSE] %>%
    dplyr::group_by(.data$individualID, .data$year) %>%
    dplyr::summarise(leaf_off = max(.data$dayOfYear), .groups="drop")
  out <- Reduce(function(a,b) dplyr::full_join(a,b,by=c("individualID","year")), list(gu, fl, lo))
  out$season <- ifelse(is.finite(out$greenup) & is.finite(out$leaf_off), out$leaf_off - out$greenup, NA_real_)
  out
}

# one row per individual: median green-up / season length etc. (Onset Lab + picker)
individual_summary <- function(obs, inds) {
  ko <- key_onsets(obs); if (is.null(ko) || !nrow(ko)) return(NULL)
  agg <- ko %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
                     flower = round(stats::median(.data$flower, na.rm=TRUE)),
                     leaf_off = round(stats::median(.data$leaf_off, na.rm=TRUE)),
                     season = round(stats::median(.data$season, na.rm=TRUE)),
                     n_years = dplyr::n_distinct(.data$year[is.finite(.data$greenup) | is.finite(.data$flower)]),
                     .groups="drop")
  dplyr::left_join(inds, agg, by = "individualID")
}

# ---------------------------------------------------------------------------
# Phenology Clock data: % of individuals 'yes' per phenophase per week-of-year,
# for one species (or all). Pools years BY DESIGN (caption it). Restricted to the
# phenophases that species' growth form actually records.
# ---------------------------------------------------------------------------
weekly_yesrate <- function(obs, sci = NULL) {
  d <- species_level_only(obs); d <- d[d$status %in% c("yes","no") & is.finite(d$dayOfYear), , drop=FALSE]
  if (!is.null(sci)) d <- d[d$scientificName %in% sci, , drop=FALSE]
  if (!nrow(d)) return(NULL)
  d$week <- pmin(52L, ((d$dayOfYear - 1L) %/% 7L) + 1L)
  d %>% dplyr::group_by(.data$phenophaseName, .data$week) %>%
    dplyr::summarise(yes = sum(.data$status=="yes"), n = dplyr::n(), .groups="drop") %>%
    dplyr::mutate(rate = round(100 * .data$yes / .data$n, 1)) %>%
    dplyr::filter(.data$n >= 1)
}

# onset trend per species x year (the climate-shift signal — NOT pooled)
onset_trend <- function(obs, phenophases = GREENUP) {
  o <- onset(obs, phenophases); if (is.null(o) || !nrow(o)) return(NULL)
  o %>% dplyr::group_by(.data$scientificName, .data$year) %>%
    dplyr::summarise(onset = round(stats::median(.data$onset_doy)), n = dplyr::n_distinct(.data$individualID), .groups="drop") %>%
    dplyr::filter(.data$n >= 3)   # >=3 individuals/species/year before a point is shown
}

# one individual's full phenophase record (the career timeline + card)
indiv_history <- function(obs, id) {
  if (is.null(obs) || is.null(id)) return(NULL)
  h <- obs[obs$individualID == id & !is.na(obs$date), , drop=FALSE]; if (!nrow(h)) return(NULL)
  h[order(h$date), c("date","year","dayOfYear","phenophaseName","status","intensity")]
}

# vegetative-only sequence for the ordering check. Reproductive phenophases
# (Open flowers, Fruits, pollen cones) are EXCLUDED — many trees flower before
# leaf-out (e.g. red maple), so flower-before-leaf is not an error.
VEG_SEQ <- c("Breaking leaf buds"=1, "Initial growth"=1, "Emerging needles"=1, "Breaking needle buds"=1,
             "Increasing leaf size"=2, "Young leaves"=2, "Young needles"=2,
             "Leaves"=3, "Colored leaves"=4, "Falling leaves"=5)

# per-individual QC flags (ported from veg tree_qc_flags). Low-noise by design:
# "verify, not wrong" — only flag things a human should actually look at.
# growth_form gates the ordering check: drought-deciduous / forb / semi-evergreen
# plants legitimately flush and drop leaves MULTIPLE times a year (rain-driven),
# so leaf-stage "out of order" within a year is normal for them, not an error.
pheno_qc_flags <- function(hist, growth_form = NULL) {
  flags <- list(); add <- function(level,text) flags[[length(flags)+1L]] <<- list(level=level,text=text)
  if (is.null(hist) || !nrow(hist)) return(flags)
  yes <- hist[hist$status == "yes", , drop=FALSE]
  if (!nrow(yes)) { add("info","No phenophase has been recorded 'yes' yet for this plant."); return(flags) }

  # (1) out-of-order VEGETATIVE phenophases within a year: leaf-out → leaves →
  # colored → falling should be monotonic. Falling/colored leaves before leaf-out
  # is biologically impossible for a SINGLE-CYCLE plant and points to a data issue.
  # Only applied to growth forms with one orderly leaf cycle per year.
  single_cycle <- is.null(growth_form) || grepl("^Deciduous|conifer|^Pine", growth_form)
  if (single_cycle) for (y in unique(yes$year)) {
    yy <- yes[yes$year == y & yes$phenophaseName %in% names(VEG_SEQ), ]
    if (!nrow(yy)) next
    fr <- tapply(yy$dayOfYear, yy$phenophaseName, min)
    rk <- VEG_SEQ[names(fr)]; ok <- is.finite(rk) & is.finite(fr); fr <- fr[ok]; rk <- rk[ok]
    if (length(fr) >= 2) { o <- order(fr)
      if (any(diff(rk[o]) < 0)) { add("high", sprintf("In %s, leaf phenophases were recorded out of sequence (a later leaf stage before an earlier one — e.g. falling/colored leaves before leaf-out). Worth checking the records for that year.", y)); break } }
  }

  # (2) green-up year-outlier: a year whose first leaf-out is >45 days from this
  # plant's own median across years — a real climate shift, or a slipped date.
  # (45d, not 30d: desert drought-deciduous green-up legitimately swings ~6 weeks
  # year to year with the rains, so a tighter bar would cry wolf at sites like SRER.)
  gy <- yes[yes$phenophaseName %in% GREENUP & is.finite(yes$dayOfYear), ]
  if (nrow(gy)) {
    per_yr <- tapply(gy$dayOfYear, gy$year, min); per_yr <- per_yr[is.finite(per_yr)]
    if (length(per_yr) >= 3) { med <- stats::median(per_yr); off <- per_yr - med
      i <- which.max(abs(off))
      if (length(i) == 1 && is.finite(off[i]) && abs(off[i]) > 45) add("warn", sprintf("In %s this plant broke leaf around day %d — %d days %s than its usual day-%d. Could be a real shift, or a date to verify.",
        names(per_yr)[i], round(per_yr[i]), round(abs(off[i])), if (off[i] < 0) "earlier" else "later", round(med))) }
  }

  # (3) left-censored onset: in some year the earliest visit was already 'yes' for
  # a leaf-out phenophase, so true onset is earlier than recorded.
  if (nrow(gy)) {
    lc <- FALSE
    for (y in unique(gy$year)) {
      gall <- hist[hist$year == y & hist$phenophaseName %in% GREENUP & hist$status %in% c("yes","no") & is.finite(hist$dayOfYear), ]
      yd <- gall$dayOfYear[gall$status == "yes"]; nd <- gall$dayOfYear[gall$status == "no"]
      if (length(yd) && (!length(nd) || min(yd) <= min(nd))) { lc <- TRUE; break }
    }
    if (lc) add("info", "Some years' leaf-out was already underway at the first visit, so the true onset may be a little earlier than shown.")
  }

  # (4) sparse: only one year of monitoring
  if (dplyr::n_distinct(hist$year) == 1L) add("info", "Watched in a single year so far — onset dates can't be compared across years yet.")
  flags
}

# growth-form / species composition (Overview)
comp_by <- function(inds, by = c("growthForm","scientificName")) {
  by <- match.arg(by); inds %>% dplyr::count(.data[[by]], name="n") %>% dplyr::arrange(dplyr::desc(.data$n)) }

# per-plot summary for the map (n individuals + median green-up onset)
plot_summary_phe <- function(obs, inds) {
  ind_s <- individual_summary(obs, inds); if (is.null(ind_s)) return(NULL)
  ind_s %>% dplyr::group_by(.data$plotID) %>%
    dplyr::summarise(n_ind = dplyr::n(), greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
                     lat = stats::median(.data$lat, na.rm=TRUE), lng = stats::median(.data$lng, na.rm=TRUE), .groups="drop")
}
