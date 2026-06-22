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
# A categorical palette that NEVER interpolates Dark2 past its 8 discrete hues
# (interpolating across ~20 categories produces muddy, indistinguishable olives).
# Returns up to `cap` distinct Dark2 colours; an explicit grey "Other" bucket
# catches everything past the cap. `groups` should already be ordered so the most
# important (e.g. most-monitored) categories take the distinct colours.
OTHER_GREY <- "#9aa6b2"
capped_pal <- function(groups, cap = 8L) {
  g <- groups[!is.na(groups) & nzchar(groups)]
  if (!length(g)) return(stats::setNames(character(0), character(0)))
  keep <- utils::head(g, cap)
  cols <- RColorBrewer::brewer.pal(max(3L, min(8L, length(keep))), "Dark2")[seq_along(keep)]
  pal <- stats::setNames(cols, keep)
  c(pal, stats::setNames(OTHER_GREY, "Other"))
}
# ordered category vector for a frame `d` on column `col`, most-frequent first
# (so capped_pal hands the distinct hues to the categories that matter most).
ordered_levels <- function(d, col) {
  v <- as.character(d[[col]]); v <- v[!is.na(v) & nzchar(v)]
  if (!length(v)) return(character(0))
  names(sort(table(v), decreasing = TRUE))
}
# bucket a category vector to the cap: anything past the top `cap` -> "Other".
cap_groups <- function(x, levels_ordered, cap = 8L) {
  keep <- utils::head(levels_ordered, cap)
  x <- as.character(x); x[is.na(x) | !nzchar(x)] <- "Other"
  ifelse(x %in% keep, x, "Other")
}
make_species_pal <- function(d){ capped_pal(ordered_levels(d, "scientificName"), cap = 8L) }

# ordered phenophase sequence (for the clock rings + out-of-order QC). Higher rank
# = later in the season. Growth-form-specific phenophases share this ordering.
PHENO_RANK <- c("Breaking leaf buds"=1, "Emerging needles"=1, "Breaking needle buds"=1,
                "Initial growth"=1, "Young needles"=2, "Increasing leaf size"=2, "Young leaves"=2,
                "Leaves"=3, "Open flowers"=4, "Open pollen cones"=4, "Colored leaves"=5,
                "Falling leaves"=6, "Fruits"=4)
GREENUP <- c("Breaking leaf buds","Initial growth","Emerging needles","Breaking needle buds")
SENESCE <- c("Colored leaves","Falling leaves")
# Each phenophase gets a DISTINCT colour (no duplicate hexes — overlapping petals
# must stay separable). The leaf stages ramp green but shift HUE as well as
# lightness (yellow-green onset -> blue-green full leaves) so they don't collapse
# into one band under colour-vision deficiency; the reproductive + senescence
# phenophases escape the green band entirely onto CVD-safe distinct hues —
# flowers magenta, pollen cones steel-blue, fruits violet, colored leaves warm
# orange, falling leaves rust — so the senescence/reproductive phenophases never
# read as leaf-green under protan/deutan (the failure the prior ramp had). Every
# pair clears dE>=14 under deutan AND protan (CVD-tuned + verified, chart review).
pheno_palette <- c(
  "Breaking leaf buds"  = "#cfe8a0", "Initial growth"      = "#b3db7a",
  "Breaking needle buds"= "#c2e08c", "Emerging needles"    = "#97cf6a",
  "Increasing leaf size"= "#69b33f", "Young leaves"        = "#7abf4a",
  "Young needles"       = "#52a23a", "Leaves"              = "#147a4a",
  "Open flowers"        = "#c8417a", "Open pollen cones"   = "#3f7faf",
  "Fruits"              = "#6a3fa0", "Colored leaves"      = "#d9701a",
  "Falling leaves"      = "#a83c14")

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
      # left-censored = a 'yes' with NO preceding 'no', so true onset is earlier
      # than recorded (the first visit already caught the phenophase active).
      left_censored = {
        yes <- .data$dayOfYear[.data$status == "yes"]; no <- .data$dayOfYear[.data$status == "no"]
        if (!length(yes)) NA else !length(no[no < min(yes)]) },
      first_yes = if (any(.data$status=="yes")) min(.data$dayOfYear[.data$status=="yes"]) else NA_real_,
      .groups = "drop") %>%
    dplyr::filter(is.finite(.data$onset_doy))
}

# green-up / flowering / leaf-off / leaf-active per individual per year.
# leaf_off = last day "Leaves" was recorded 'yes'. We do NOT use first 'Colored
# leaves' as senescence: NEON records it for a few early-stressed leaves (e.g.
# day 163 in June), which makes first-coloration a wildly early marker.
# leaf_active = distinct weeks with leaves present x 7 ≈ days the plant actually
# carries leaves. This is the honest growing-extent metric for EVERY growth form:
# greenup→leaf_off would span ~300 days for a drought-deciduous desert plant that
# flushes and drops several times a year, whereas leaf_active sums only the weeks
# leaves are really present (~110 days). So the Onset Lab uses leaf_active, not a
# green-up-to-leaf-off span.
# Defensive at the 46-site scale: a site may lack green-up, flowering, or leaf
# records entirely — each branch falls back to an empty keyed tibble so a missing
# phenophase never crashes the join (it just yields NA columns).
key_onsets <- function(obs) {
  ek <- tibble::tibble(individualID = character(), year = integer())
  lv <- obs[obs$phenophaseName == "Leaves" & obs$status == "yes" & is.finite(obs$dayOfYear), , drop=FALSE]
  guo <- onset(obs, GREENUP)
  gu <- if (!is.null(guo) && nrow(guo))
      guo %>% dplyr::group_by(.data$individualID, .data$year) %>%
        dplyr::summarise(greenup = min(.data$onset_doy),
                         left_censored = .data$left_censored[which.min(.data$onset_doy)], .groups="drop")
    else dplyr::mutate(ek, greenup = numeric(), left_censored = logical())
  flo <- onset(obs, "Open flowers")
  fl <- if (!is.null(flo) && nrow(flo)) flo %>% dplyr::transmute(individualID, year, flower = .data$onset_doy)
        else dplyr::mutate(ek, flower = numeric())
  lo <- if (nrow(lv)) lv %>% dplyr::group_by(.data$individualID, .data$year) %>%
          dplyr::summarise(leaf_off = max(.data$dayOfYear), .groups="drop")
        else dplyr::mutate(ek, leaf_off = numeric())
  la <- if (nrow(lv)) lv %>% dplyr::mutate(wk = (.data$dayOfYear - 1L) %/% 7L + 1L) %>%
          dplyr::group_by(.data$individualID, .data$year) %>%
          dplyr::summarise(leaf_active = dplyr::n_distinct(.data$wk) * 7L, .groups="drop")
        else dplyr::mutate(ek, leaf_active = integer())
  out <- Reduce(function(a,b) dplyr::full_join(a,b,by=c("individualID","year")), list(gu, fl, lo, la))
  if (is.null(out) || !nrow(out)) return(NULL)
  out
}

# green-up COVERAGE share: fraction of tagged plants that ever resolve a finite
# green-up onset. In warm deserts the green-up *phenophase* ("Breaking leaf buds"
# / "Initial growth") is rarely scored — drought-deciduous / cactus / evergreen
# plants are logged straight into "Leaves" — so a desert median_greenup rests on a
# small, non-random subsample (SRER 19%, JORN 54%) while leaf_active survives.
# This is the number behind the coverage badge; computed at runtime from the
# per-plant summary so it needs no bundle rebuild.
greenup_coverage <- function(ind_s) {
  if (is.null(ind_s) || !nrow(ind_s) || !("greenup" %in% names(ind_s))) return(NA_real_)
  n <- nrow(ind_s); if (!n) return(NA_real_)
  sum(is.finite(ind_s$greenup)) / n
}

# one row per individual: median green-up / leaf-active etc. (Onset Lab + picker)
individual_summary <- function(obs, inds) {
  ko <- key_onsets(obs); if (is.null(ko) || !nrow(ko)) return(NULL)
  agg <- ko %>% dplyr::group_by(.data$individualID) %>%
    dplyr::summarise(greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
                     flower = round(stats::median(.data$flower, na.rm=TRUE)),
                     leaf_off = round(stats::median(.data$leaf_off, na.rm=TRUE)),
                     leaf_active = round(stats::median(.data$leaf_active, na.rm=TRUE)),
                     # per-metric companion n: how many years actually contributed
                     # to EACH median, so a NA can be read as "never scored that
                     # phenophase" (structural, n=0) vs "scored, just not this plant".
                     # A green-up NA at a desert evergreen is structural; pairing the
                     # median with its own n separates that from a missing record.
                     greenup_n_years     = sum(is.finite(.data$greenup)),
                     flower_n_years      = sum(is.finite(.data$flower)),
                     leaf_active_n_years = sum(is.finite(.data$leaf_active)),
                     # count a year if ANY key metric is finite, so leaf-only
                     # evergreens (no green-up/flower onset) aren't undercounted to 0
                     n_years = dplyr::n_distinct(.data$year[is.finite(.data$greenup) | is.finite(.data$flower) |
                                                            is.finite(.data$leaf_off) | is.finite(.data$leaf_active)]),
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
  # PLANT-weighted, not visit-weighted: a plant visited twice in a week must count
  # ONCE, or the "% of plants" label is false (it would be "% of observations").
  # Collapse to one row per individual x phenophase x week first; the plant counts
  # 'yes' if ANY visit that week was 'yes' (the phenophase was active that week).
  d <- d %>% dplyr::group_by(.data$individualID, .data$phenophaseName, .data$week) %>%
    dplyr::summarise(plant_yes = any(.data$status == "yes"), .groups = "drop")
  d %>% dplyr::group_by(.data$phenophaseName, .data$week) %>%
    dplyr::summarise(yes = sum(.data$plant_yes), n = dplyr::n(), .groups="drop") %>%
    dplyr::mutate(rate = round(100 * .data$yes / .data$n, 1)) %>%
    dplyr::filter(.data$n >= 5)   # suppress sub-threshold weeks: a 100%-of-3 ring must not look as solid as 100%-of-1000 (n is now distinct plants/week)
}

# onset trend per species x year (the climate-shift signal — NOT pooled).
# Collapse to each individual's EARLIEST green-up per year FIRST (the same
# min-across-green-up-phenophases that key_onsets/individual_summary use), so a
# plant that records two green-up phenophases in a year (e.g. "Breaking leaf
# buds" + "Initial growth", or a conifer's needle pair) isn't pseudo-replicated
# into the species-year median and the trend matches the per-plant green-up.
onset_trend <- function(obs, phenophases = GREENUP) {
  o <- onset(obs, phenophases); if (is.null(o) || !nrow(o)) return(NULL)
  o <- o %>% dplyr::group_by(.data$individualID, .data$scientificName, .data$year) %>%
    dplyr::summarise(onset_doy = min(.data$onset_doy), .groups = "drop")
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
# Returns list(flags = list(level,text,key,n), sets = named list of the exact
# offending rows behind each flag). The UI lists each flag clickable -> a DT
# inspector of its `sets[[key]]` + a per-flag CSV downloadHandler, and
# phe_qc_report() rolls every set into one ranked report CSV. Flagged rows are
# always RETAINED, never dropped. (Ported to the suite QC-inspector standard;
# see docs/neonize-playbook.md, memory neonize-qc-flag-pattern.)
QC_COLS <- c("date","year","dayOfYear","phenophaseName","status","intensity")
pheno_qc_flags <- function(hist, growth_form = NULL) {
  out <- list(flags = list(), sets = list())
  if (is.null(hist) || !nrow(hist)) return(out)
  cols <- intersect(QC_COLS, names(hist))
  tidy <- function(rows, label) { rows <- rows[!is.na(rows)]; if (!length(rows)) return(NULL)
    x <- hist[rows, cols, drop=FALSE]; if (!nrow(x)) return(NULL); x$flag <- label; x[order(x$year, x$dayOfYear), , drop=FALSE] }
  # add a flag ONLY when it has offending rows (a 0-row check is a no-op, never a
  # phantom flag); allow_empty=TRUE keeps a genuine no-row note (e.g. "no yes yet").
  add <- function(level, title, key, rows, text, allow_empty = FALSE) {
    rows <- unique(rows[!is.na(rows)]); n <- length(rows)
    if (!n && !allow_empty) return(invisible())
    out$flags[[length(out$flags)+1L]] <<- list(level=level, title=title, key=key, n=n, text=text)
    if (n) out$sets[[key]] <<- tidy(rows, title) }

  yes_idx <- which(hist$status == "yes")
  if (!length(yes_idx)) { add("info", "No phenophase recorded 'yes' yet", "noyes", integer(0),
    "No phenophase has been recorded 'yes' yet for this plant.", allow_empty = TRUE); return(out) }

  # (1) out-of-order VEGETATIVE phenophases within a year (single-cycle plants only).
  single_cycle <- is.null(growth_form) || grepl("^Deciduous|conifer|^Pine", growth_form)
  oo_rows <- integer(0); oo_years <- integer(0)
  if (single_cycle) for (y in unique(hist$year[yes_idx])) {
    yidx <- which(hist$status == "yes" & hist$year == y & hist$phenophaseName %in% names(VEG_SEQ) & is.finite(hist$dayOfYear))
    if (!length(yidx)) next
    fr <- tapply(hist$dayOfYear[yidx], as.character(hist$phenophaseName[yidx]), min)
    rk <- VEG_SEQ[names(fr)]; ok <- is.finite(rk) & is.finite(fr); fr <- fr[ok]; rk <- rk[ok]
    if (length(fr) >= 2) { o <- order(fr)
      if (any(diff(rk[o]) < 0)) { oo_rows <- c(oo_rows, yidx); oo_years <- c(oo_years, y) } }
  }
  add("high", "Leaf phenophases out of sequence", "outoforder", oo_rows,
    sprintf("In %s, leaf phenophases were recorded out of sequence (a later leaf stage before an earlier one, e.g. falling/colored leaves before leaf-out). Worth checking the records for %s.",
      paste(sort(unique(oo_years)), collapse=", "), if (length(unique(oo_years))==1) "that year" else "those years"))

  # (2) green-up year-outlier: a year >45 d from this plant's own median.
  gy_idx <- which(hist$status == "yes" & hist$phenophaseName %in% GREENUP & is.finite(hist$dayOfYear))
  if (length(gy_idx)) {
    gyy <- hist$year[gy_idx]; gyd <- hist$dayOfYear[gy_idx]
    per_yr <- tapply(gyd, gyy, min); per_yr <- per_yr[is.finite(per_yr)]
    if (length(per_yr) >= 3) { med <- stats::median(per_yr); off <- per_yr - med
      i <- which.max(abs(off))
      if (length(i)==1 && is.finite(off[i]) && abs(off[i]) > 45) {
        oy <- names(per_yr)[i]
        out_rows <- gy_idx[as.character(gyy) == oy]
        add("warn", "Green-up year well off the plant's norm", "outlier", out_rows,
          sprintf("In %s this plant broke leaf around day %d, %d days %s than its usual day-%d. Could be a real shift, or a date to verify.",
            oy, round(per_yr[i]), round(abs(off[i])), if (off[i] < 0) "earlier" else "later", round(med)))
      }
    }
  }

  # (3) left-censored onset: a year whose earliest visit was already 'yes' for a
  # leaf-out phenophase, so true onset is earlier than recorded.
  if (length(gy_idx)) {
    lc_rows <- integer(0)
    for (y in unique(hist$year[gy_idx])) {
      gall <- which(hist$year == y & hist$phenophaseName %in% GREENUP & hist$status %in% c("yes","no") & is.finite(hist$dayOfYear))
      if (!length(gall)) next
      yd <- hist$dayOfYear[gall][hist$status[gall] == "yes"]; nd <- hist$dayOfYear[gall][hist$status[gall] == "no"]
      if (length(yd) && (!length(nd) || min(yd) <= min(nd)))
        lc_rows <- c(lc_rows, gall[hist$status[gall] == "yes" & hist$dayOfYear[gall] == min(yd)])
    }
    add("info", "Leaf-out already underway at first visit", "leftcensored", lc_rows,
      "Some years' leaf-out was already underway at the first visit, so the true onset may be a little earlier than shown.")
  }

  # (4) sparse: only one year of monitoring
  if (dplyr::n_distinct(hist$year) == 1L)
    add("info", "Watched in a single year so far", "single_year", yes_idx,
      "Watched in a single year so far. Onset dates can't be compared across years yet.")
  out
}
# roll every flag's offending rows into one ranked report data.frame for CSV
# download (high -> warn -> info), or NULL if the plant is clean.
phe_qc_report <- function(hist, growth_form = NULL) {
  q <- pheno_qc_flags(hist, growth_form); if (!length(q$sets)) return(NULL)
  lvl <- vapply(q$flags, function(f) f$level, ""); names(lvl) <- vapply(q$flags, function(f) f$key, "")
  ord <- c("high"=1,"warn"=2,"info"=3)
  keys <- names(q$sets)[order(ord[lvl[names(q$sets)]])]
  do.call(rbind, c(lapply(keys, function(k) { x <- q$sets[[k]]; x$level <- lvl[[k]]; x }), list(make.row.names = FALSE)))
}

# growth-form / species composition (Overview)
comp_by <- function(inds, by = c("growthForm","scientificName")) {
  by <- match.arg(by); inds %>% dplyr::count(.data[[by]], name="n") %>% dplyr::arrange(dplyr::desc(.data$n)) }

# per-plot summary for the map (n individuals + median green-up onset). Accepts a
# precomputed individual_summary so the Map tab needn't recompute it (perf).
# Also carries gu_share (fraction of the plot's plants that resolve a green-up
# onset) so the map can flag plots where green-up rests on a thin subsample, and
# leaf_active (median days carrying leaves) for the biome-conditional metric
# switch — leaf_active survives where green-up collapses in warm deserts.
plot_summary_phe <- function(obs, inds, ind_s = NULL) {
  if (is.null(ind_s)) ind_s <- individual_summary(obs, inds)
  if (is.null(ind_s)) return(NULL)
  ind_s %>% dplyr::group_by(.data$plotID) %>%
    dplyr::summarise(n_ind = dplyr::n(), greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
                     gu_share = sum(is.finite(.data$greenup)) / dplyr::n(),
                     leaf_active = round(stats::median(.data$leaf_active, na.rm=TRUE)),
                     lat = stats::median(.data$lat, na.rm=TRUE), lng = stats::median(.data$lng, na.rm=TRUE), .groups="drop")
}

# ---------------------------------------------------------------------------
# Cross-site / national layer (precomputed at bundle time; the app reads the
# rolled-up tables, never every bundle). green-up DOY → colour ramp shared by
# the single-site and national maps so "earlier" reads the same on both:
# early green-up = fresh green, late = senescence amber (on-theme + intuitive).
# ---------------------------------------------------------------------------
GREENUP_RAMP <- c("#15502f","#3f8f3a","#9ccf6a","#e0b341","#d98014")
# Robust green-up colour domain: a handful of THIN-COVERAGE sites carry wild
# median_greenup values (KONA day 226 at gu_share 0.03; LAJA day 5) that, on a raw
# range(), wash every well-covered site into one flat mid-band. So clamp the colour
# domain to the 5th/95th percentile of the WELL-COVERED sites (gu_share >= floor)
# and PIN out-of-range values to the endpoints. Pass gu_share to use the coverage
# filter; omit it (legacy callers / per-plot maps) to fall back to robust quantiles
# of the values themselves. Returns a palette FUNCTION that clamps before mapping,
# so an outlier reads as "off the deep/late end", never as a fabricated NA gap.
# The robust [p5,p95] colour domain for green-up DOY, computed from well-covered
# sites only (gu_share >= floor) when a coverage vector is supplied. Returned so
# the legend, the markers, and the value-clamp all share ONE domain.
greenup_domain <- function(domain, gu_share = NULL, floor = 0.5) {
  v <- suppressWarnings(as.numeric(domain))
  base <- if (!is.null(gu_share)) {
    gs <- suppressWarnings(as.numeric(gu_share))
    well <- v[is.finite(v) & is.finite(gs) & gs >= floor]
    if (length(well) >= 3) well else v[is.finite(v)]
  } else v[is.finite(v)]
  d <- if (length(base)) stats::quantile(base, c(.05, .95), names = FALSE, na.rm = TRUE) else c(100, 200)
  if (!all(is.finite(d)) || diff(d) == 0) { m <- if (length(base)) stats::median(base, na.rm = TRUE) else 150; d <- c(m - 1, m + 1) }
  d
}
# Green-up palette on the ROBUST domain (p5/p95 of well-covered sites). A handful
# of THIN-COVERAGE sites carry wild median_greenup values (KONA day 226 at
# gu_share 0.03; LAJA day 5) that on a raw range() wash every well-covered site
# into one flat mid-band. Build the palette on the robust domain instead; callers
# clamp the values they map with gp_clamp() so an outlier pins to the deep/late
# endpoint rather than reading as a fabricated NA gap. Returns a leaflet
# colorNumeric object so addLegend() still draws a continuous legend.
greenup_pal <- function(domain, gu_share = NULL, floor = 0.5) {
  d <- greenup_domain(domain, gu_share = gu_share, floor = floor)
  pal <- leaflet::colorNumeric(GREENUP_RAMP, domain = d, na.color = "#c4c0b2")
  attr(pal, "gp_domain") <- d   # so callers can clamp values + legend ticks to it
  pal
}
# clamp a value vector to a palette's robust domain (so out-of-range outliers pin
# to the endpoint colour instead of falling outside the leaflet domain -> NA).
gp_clamp <- function(pal, x) {
  d <- attr(pal, "gp_domain"); x <- suppressWarnings(as.numeric(x))
  if (is.null(d)) return(x)
  pmin(pmax(x, d[1]), d[2])
}

# Effective VISIT CADENCE: the median gap (in days) between consecutive distinct
# visit dates within a growing season, per plant, pooled across the site. Onset is
# interval-censored to the gap between visits, so a site visited every ~7 days
# resolves onset far more tightly than one visited monthly — part of a cross-site
# onset difference can be censoring geometry, not biology (the phenology analog of
# detection probability). This is the number behind the cadence badge + the
# coarse-cadence grey on the gradient. Restricted to in-season gaps (<= 60 d) so a
# winter dormancy gap between seasons doesn't inflate it. Returns NA if a site has
# too few visits to estimate a gap.
visit_interval_days <- function(obs) {
  d <- obs[!is.na(obs$date) & is.finite(obs$year), c("individualID","year","date"), drop=FALSE]
  if (!nrow(d)) return(NA_real_)
  d <- d[!duplicated(d[c("individualID","year","date")]), , drop=FALSE]
  d <- d[order(d$individualID, d$year, d$date), , drop=FALSE]
  key <- paste(d$individualID, d$year)
  gap <- as.numeric(diff(as.Date(d$date)))
  same <- key[-1] == key[-length(key)]                 # only gaps within one plant-year
  g <- gap[same & is.finite(gap) & gap > 0 & gap <= 60] # in-season gaps only
  if (length(g) < 5) return(NA_real_)
  round(stats::median(g), 1)
}

# one row per site: the picker-map + cross-site numbers (computed in the bundler)
site_phe_summary <- function(obs, inds, meta, ind_s = NULL) {
  if (is.null(ind_s)) ind_s <- individual_summary(obs, inds)
  sp <- species_level_only(inds)
  safe_med <- function(x) { v <- suppressWarnings(stats::median(x, na.rm=TRUE)); if (is.finite(v)) round(v) else NA_real_ }
  tibble::tibble(
    site = meta$site, n_individuals = nrow(inds),
    n_species = dplyr::n_distinct(sp$scientificName[!is.na(sp$scientificName)]),
    n_obs = nrow(obs), n_plots = dplyr::n_distinct(inds$plotID),
    dominant_form = mode_chr(inds$growthForm),
    median_greenup = if (!is.null(ind_s)) safe_med(ind_s$greenup) else NA_real_,
    median_leaf_active = if (!is.null(ind_s)) safe_med(ind_s$leaf_active) else NA_real_,
    # green-up COVERAGE share (fraction of plants resolving a green-up onset). In
    # warm deserts the green-up phenophase is scored for ~1/5 of plants, so this
    # flags when median_greenup rests on a biased subsample. Carried to
    # site_index for the national-map coverage badge (next bundle rebuild).
    gu_share = if (!is.null(ind_s)) round(greenup_coverage(ind_s), 3) else NA_real_,
    # median in-season visit interval (days). Cross-site onset comparisons aren't
    # cadence-controlled, so a coarse-cadence site's onset carries wide censoring
    # uncertainty; carried to site_index for the cadence badge + gradient footnote.
    median_visit_interval = visit_interval_days(obs),
    year_min = suppressWarnings(min(obs$year, na.rm=TRUE)),
    year_max = suppressWarnings(max(obs$year, na.rm=TRUE)),
    lat = meta$lat, lng = meta$lng)
}

# within-species latitude gradient — the CONFOUND-CONTROLLED read of the cross-
# site gradient. The network slope (median_greenup ~ lat) pools different species
# mixes at every site; holding ONE widespread species constant removes that
# confound (red maple alone ~ +4.4 d/°N, R² 0.78 vs the network's +2.5, R² 0.41).
# Picks the species spanning the most sites (>= min_sites), fits greenup ~ lat,
# and returns the slope + its 95% CI + R² so the banner can LEAD with it. Reads
# the precomputed national_onsets table (one row per site×species); NULL if none
# qualifies. Pure base lm, no extra deps.
within_species_gradient <- function(national_onsets, min_sites = 4) {
  no <- national_onsets
  if (is.null(no) || !nrow(no) || !all(c("scientificName","greenup","lat") %in% names(no))) return(NULL)
  no <- no[is.finite(no$greenup) & is.finite(no$lat), , drop=FALSE]
  if (!nrow(no)) return(NULL)
  tab <- sort(table(no$scientificName), decreasing = TRUE)
  cand <- names(tab)[tab >= min_sites]
  if (!length(cand)) return(NULL)
  sp <- cand[1]                       # the most widely-monitored species
  d <- no[no$scientificName == sp, , drop=FALSE]
  if (nrow(d) < 3 || diff(range(d$lat)) == 0) return(NULL)
  fit <- stats::lm(greenup ~ lat, data = d); co <- summary(fit)$coefficients
  if (nrow(co) < 2) return(NULL)
  slope <- co[2,1]; se <- co[2,2]; df <- nrow(d) - 2
  tcrit <- stats::qt(0.975, df = df)
  list(species = sp, n_sites = nrow(d), slope = slope,
       lo = slope - tcrit*se, hi = slope + tcrit*se,
       r2 = summary(fit)$r.squared, p = co[2,4])
}

# one row per (site × species-level taxon) with ≥3 individuals: feeds the
# same-species-across-sites cross-site comparison (computed in the bundler).
site_species_onsets <- function(obs, inds, meta) {
  ko <- key_onsets(obs); if (is.null(ko)) return(NULL)
  spmap <- inds[, c("individualID","scientificName","growthForm","is_species"), drop=FALSE]
  d <- dplyr::left_join(ko, spmap, by = "individualID")
  d <- d[d$is_species %in% TRUE & !is.na(d$scientificName) & is.finite(d$greenup), , drop=FALSE]
  if (!nrow(d)) return(NULL)
  d %>% dplyr::group_by(.data$scientificName, .data$growthForm) %>%
    dplyr::summarise(n_ind = dplyr::n_distinct(.data$individualID),
                     greenup = round(stats::median(.data$greenup, na.rm=TRUE)),
                     flower = round(stats::median(.data$flower, na.rm=TRUE)),
                     leaf_active = round(stats::median(.data$leaf_active, na.rm=TRUE)),
                     .groups = "drop") %>%
    dplyr::filter(.data$n_ind >= 3) %>%
    dplyr::mutate(site = meta$site, lat = meta$lat, lng = meta$lng)
}
