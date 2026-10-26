# Independent oracle for the two headline site metrics (median green-up and median
# leaf-active days, with their bounds).
#
# Why this file exists: the release gate used to re-run the app's own helpers on the
# observations, so a bug in a helper reproduced itself and passed. This oracle is written
# from the signed-off written rules only (the scripts/headline_rules.md contract, sections 0 to 8b and 10) and does
# not call or copy anything in R/. Two separate implementations must agree for the gate to
# pass. Base R only, so it cannot inherit a package-level behaviour from the app either.
#
# Isolation: the file is meant to be loaded into an environment whose parent is base R
# only, so nothing from the app, a package or the global workspace can leak in. Every
# non-base function is called with its namespace (stats::median, stats::setNames), every
# constant is a literal in this file, and there is no library() or source() call.
#
# Loading and use (definitions only, no side effects):
#   oracle <- new.env(parent = baseenv())
#   sys.source("scripts/headline_oracle.R", envir = oracle)
#   oracle$headline_oracle_site(readRDS("data/sites/SRER.rds"))
#   paths <- list.files("data/sites", pattern = "[.]rds$", full.names = TRUE)
#   oracle$headline_oracle(paths)        # one row per site
#   oracle$headline_oracle_all(paths)    # list(site, species, plant_years, support)

ORACLE_BUDBREAK <- c("Breaking leaf buds", "Initial growth", "Emerging needles",
                     "Breaking needle buds")
ORACLE_FALLBACK <- "Young leaves"
ORACLE_DDB <- "Drought deciduous broadleaf"

# Year length, used by the leaf year-boundary bridge (section 7).
oracle_ylen <- function(y) {
  ifelse((y %% 4 == 0 & y %% 100 != 0) | y %% 400 == 0, 366, 365)
}

# Section 0. Plain vectors (factors compared by their character values), dayOfYear filled
# from the date where it is missing. The NEON dayOfYear is kept as recorded when present,
# even where it differs from the date's own day-of-year, because the rules define days as
# the dayOfYear column.
oracle_obs <- function(obs) {
  date <- as.Date(obs$date)
  doy <- as.numeric(obs$dayOfYear)
  fill <- is.na(doy) & !is.na(date)
  doy[fill] <- as.numeric(format(date[fill], "%j"))
  yr <- as.integer(obs$year)
  fill_yr <- is.na(yr) & !is.na(date)
  yr[fill_yr] <- as.integer(format(date[fill_yr], "%Y"))
  # Section 0: a missing or invalid date becomes Jan 1 of the row's year plus
  # (dayOfYear - 1), so the row still forms a visit for green-up.
  fill_dt <- is.na(date) & !is.na(doy) & !is.na(yr)
  date[fill_dt] <- as.Date(sprintf("%d-01-01", yr[fill_dt])) + (doy[fill_dt] - 1)
  data.frame(id = as.character(obs$individualID), year = yr, date = date, doy = doy,
             phase = as.character(obs$phenophaseName), status = as.character(obs$status),
             form = as.character(obs$growthForm), stringsAsFactors = FALSE)
}

# Section 0, last bullet: one growth form per plant (the first recorded value).
oracle_plant_forms <- function(o) {
  ok <- !is.na(o$form)
  f <- tapply(o$form[ok], o$id[ok], function(x) x[1])
  f
}

# Section 0: one scored status per plant x phase x visit date, 'yes' if any row is 'yes'.
# Dates group rows into visits; the day number carries every comparison downstream.
# 'uncertain' rows are dropped first so they never count as either.
oracle_scored_visits <- function(o, phases) {
  k <- o$phase %in% phases & o$status %in% c("yes", "no") & !is.na(o$date) &
    is.finite(o$doy)
  s <- o[k, c("id", "phase", "year", "date", "doy", "status")]
  s$yes <- s$status == "yes"
  key <- paste(s$id, s$phase, as.integer(s$date), sep = "\r")
  any_yes <- tapply(s$yes, key, any)
  min_day <- tapply(s$doy, key, min)
  s <- s[!duplicated(key), ]
  key <- paste(s$id, s$phase, as.integer(s$date), sep = "\r")
  s$yes <- as.vector(any_yes[key])
  # The visit's day number is the smallest dayOfYear among its rows (section 0).
  s$doy <- as.vector(min_day[key])
  s[order(s$id, s$phase, s$date), c("id", "phase", "year", "date", "doy", "yes")]
}

# Section 2. Onset of one phase for one plant, every calendar year it was scored. Input
# vectors are one visit per date, already sorted by date. Dates only pick the first visit
# and the previous year's last visit and measure the 31-day gap; every earlier or later
# comparison and all arithmetic use the visit day numbers, so lo <= hi holds even where
# NEON's dayOfYear disagrees with the date. Returns one row per scored year (onset NA where
# there is none) so section 4 can count plant-years without an onset.
oracle_phase_onsets <- function(dt, dy, yes, yr) {
  yrs <- sort(unique(yr))
  n <- length(yrs)
  onset <- lo <- hi <- rep(NA_real_, n)
  lc <- carry <- rep(FALSE, n)
  for (k in seq_len(n)) {
    y <- yrs[k]
    i <- which(yr == y)
    d <- dy[i]; s <- yes[i]
    if (!any(s)) next
    Y <- d[s]; N <- d[!s]
    f <- min(Y)
    # Standard onset s0; the boundary check below may replace it.
    before <- N[N < f]
    if (length(before)) {
      lo[k] <- max(before); s0 <- (lo[k] + f) / 2
    } else {
      s0 <- f; lc[k] <- TRUE
    }
    onset[k] <- s0; hi[k] <- f
    if (!s[1]) next
    j <- which(yr == y - 1)
    if (length(j) == 0) next
    pj <- j[length(j)]
    gap <- as.numeric(dt[i[1]] - dt[pj])
    if (gap > 31) next
    if (yes[pj]) {
      # Carried over from last year: the first visit is not an onset; look for the next
      # no-to-yes transition inside this year.
      carry[k] <- TRUE
      onset[k] <- lo[k] <- hi[k] <- NA_real_; lc[k] <- FALSE
      N1 <- N[N > d[1]]
      if (length(N1) == 0) next
      later <- Y[Y > min(N1)]
      if (length(later) == 0) next
      y2 <- min(later)
      lo[k] <- max(N[N < y2]); onset[k] <- (lo[k] + y2) / 2; hi[k] <- y2
    } else {
      # Bridged: last year's 'no' bounds the onset from below, in this year's day terms.
      p <- as.numeric(dt[pj] - as.Date(sprintf("%d-01-01", y))) + 1
      onset[k] <- max(1, (p + s0) / 2); lo[k] <- max(1, p); hi[k] <- f; lc[k] <- FALSE
    }
  }
  data.frame(year = yrs, onset = onset, lo = lo, hi = hi, left_censored = lc,
             carryover = carry)
}

# Section 2 applied to every plant x relevant phase.
oracle_all_onsets <- function(o) {
  v <- oracle_scored_visits(o, c(ORACLE_BUDBREAK, ORACLE_FALLBACK))
  if (nrow(v) == 0) {
    return(data.frame(id = character(), phase = character(), year = integer(),
                      onset = numeric(), lo = numeric(), hi = numeric(),
                      left_censored = logical(), carryover = logical()))
  }
  groups <- split(seq_len(nrow(v)), paste(v$id, v$phase, sep = "\r"))
  res <- lapply(groups, function(g) {
    r <- oracle_phase_onsets(v$date[g], v$doy[g], v$yes[g], v$year[g])
    cbind(data.frame(id = v$id[g[1]], phase = v$phase[g[1]], stringsAsFactors = FALSE), r)
  })
  out <- do.call(rbind, res)
  rownames(out) <- NULL
  out
}

# Section 3. Green-up per plant-year: earliest bud-break onset, else the Young leaves onset
# for drought deciduous broadleaf plants. Also returns the relevant-phase plant-years that
# section 4 needs for the carry-over share.
oracle_greenup <- function(ons, forms) {
  ons$form <- as.vector(forms[ons$id])
  is_ddb <- !is.na(ons$form) & ons$form == ORACLE_DDB
  relevant <- ons$phase %in% ORACLE_BUDBREAK | (ons$phase == ORACLE_FALLBACK & is_ddb)
  rel <- ons[relevant, ]
  py <- paste(rel$id, rel$year, sep = "\r")
  # Every plant-year with a scored relevant phase, with carry-over on any of them.
  scored <- data.frame(id = rel$id[!duplicated(py)], year = rel$year[!duplicated(py)],
                       stringsAsFactors = FALSE)
  carried <- tapply(rel$carryover, py, any)
  scored$carried <- as.vector(carried[paste(scored$id, scored$year, sep = "\r")])
  scored$form <- as.vector(forms[scored$id])

  pick <- function(sub, source) {
    sub <- sub[!is.na(sub$onset), ]
    sub <- sub[order(sub$id, sub$year, sub$onset), ]
    sub <- sub[!duplicated(paste(sub$id, sub$year, sep = "\r")), ]
    data.frame(id = sub$id, year = sub$year, greenup = sub$onset, lo = sub$lo, hi = sub$hi,
               left_censored = sub$left_censored, carryover = sub$carryover,
               source = rep(source, nrow(sub)), stringsAsFactors = FALSE)
  }
  bb <- pick(rel[rel$phase %in% ORACLE_BUDBREAK, ], "bud-break")
  yl <- pick(rel[rel$phase == ORACLE_FALLBACK, ], "young-leaves")
  yl <- yl[!(paste(yl$id, yl$year, sep = "\r") %in% paste(bb$id, bb$year, sep = "\r")), ]
  gu <- rbind(bb, yl)
  gu$form <- as.vector(forms[gu$id])
  list(greenup = gu[order(gu$id, gu$year), ], scored = scored)
}

# Section 4. Growth forms whose bud-break does not fall in the calendar year: autumn forms
# (onset mostly after day 274) and carry-over forms (already in leaf over the new year).
oracle_dropped_forms <- function(gu, scored) {
  autumn <- character()
  if (nrow(gu) > 0) {
    n <- tapply(gu$greenup, gu$form, length)
    s <- tapply(gu$greenup >= 274, gu$form, mean)
    autumn <- names(n)[n >= 10 & s >= 0.35]
  }
  carry <- character()
  if (nrow(scored) > 0) {
    n <- tapply(scored$carried, scored$form, length)
    s <- tapply(scored$carried, scored$form, mean)
    carry <- setdiff(names(n)[n >= 10 & s >= 0.35], autumn)
  }
  list(autumn = autumn, carry = carry)
}

# Section 5. Per-year support reasons for green-up and leaf, from visit effort, start date
# and truncation at the start of the record.
oracle_support <- function(o, gu, leaf_first) {
  r <- o[is.finite(o$doy) & !is.na(o$year), ]
  r$week <- (r$doy - 1) %/% 7 + 1
  pw <- unique(r[, c("id", "year", "week")])
  # Distinct weeks per plant-year, then the median over the plants visited that year.
  pykey <- paste(pw$id, pw$year, sep = "\r")
  wk <- tapply(pw$week, pykey, length)
  wk_year <- tapply(pw$year, pykey, function(x) x[1])
  med_weeks <- tapply(as.vector(wk), as.vector(wk_year), stats::median)
  n_plants <- tapply(as.vector(wk), as.vector(wk_year), length)
  first_doy <- tapply(r$doy, r$year, min)
  yrs <- as.integer(names(med_weeks))
  first_doy <- first_doy[as.character(yrs)]
  typical_weeks <- stats::median(med_weeks)
  typical_first <- stats::median(first_doy)
  low_effort <- !(med_weeks / typical_weeks >= 0.75)
  low_effort[is.na(low_effort)] <- TRUE
  late_date <- (first_doy - typical_first) > 30
  short <- length(yrs) < 3

  # Green-up truncation.
  lc <- cov <- stats::setNames(rep(NA_real_, length(yrs)), yrs)
  cov[] <- 0
  if (nrow(gu) > 0) {
    lcy <- tapply(gu$left_censored, gu$year, mean)
    npl <- tapply(gu$id, gu$year, function(x) length(unique(x)))
    lc[names(lcy)] <- lcy
    cov[names(npl)] <- npl / n_plants[names(npl)]
  }
  typical_cov <- stats::median(cov)
  cov_ratio <- if (isTRUE(typical_cov > 0)) cov / typical_cov else rep(NA_real_, length(yrs))
  late_gu <- late_date & (is.na(lc) | lc >= 0.5 | (is.finite(cov_ratio) & cov_ratio < 0.5))

  # Leaf truncation.
  lf <- stats::setNames(rep(NA_real_, length(yrs)), yrs)
  if (nrow(leaf_first) > 0) {
    lfy <- tapply(leaf_first$first_in_leaf, leaf_first$year, mean)
    lfy <- lfy[names(lfy) %in% names(lf)]
    lf[names(lfy)] <- lfy
  }
  late_leaf <- late_date & (is.na(lf) | lf >= 0.5)

  reason <- function(late) {
    x <- ifelse(late, "late_start", "supported")
    x[low_effort] <- "low_effort"
    if (short) x[] <- "short_record"
    x
  }
  data.frame(year = yrs, med_weeks = as.numeric(med_weeks), n_plants = as.numeric(n_plants),
             first_doy = as.numeric(first_doy), low_effort = as.logical(low_effort),
             late_date = as.logical(late_date), lc = as.numeric(lc), cov = as.numeric(cov),
             cov_ratio = as.numeric(cov_ratio), lf = as.numeric(lf),
             greenup_reason = reason(late_gu), leaf_reason = reason(late_leaf),
             stringsAsFactors = FALSE)
}

# Section 6 core, shared with the species summary (section 10): two-stage (plant, then
# group) green-up with interval bounds, from plant-year rows that are already supported.
oracle_greenup_bounds <- function(rows) {
  if (nrow(rows) == 0) {
    return(list(value = NA_real_, lo = NA_real_, hi = NA_real_, status = "none"))
  }
  lo_in <- ifelse(rows$left_censored, -Inf, rows$lo)
  mid <- round(tapply(rows$greenup, rows$id, stats::median))
  plo <- tapply(lo_in, rows$id, stats::median)
  plo <- ifelse(is.finite(plo), round(plo), plo)
  phi <- round(tapply(rows$hi, rows$id, stats::median))
  value <- round(stats::median(mid))
  hi <- round(stats::median(phi))
  lo <- stats::median(plo)
  if (is.finite(lo)) lo <- round(lo)
  status <- if (lo == -Inf) "upper_bound" else if (hi - lo < 14) "point" else "range"
  # Published values: the point value only for point and range; lo only when finite.
  list(value = if (status %in% c("point", "range")) value else NA_real_,
       lo = if (is.finite(lo)) lo else NA_real_, hi = hi, status = status)
}

# Section 6 for the site.
oracle_greenup_summary <- function(gu, sup) {
  if (nrow(sup) > 0 && all(sup$greenup_reason == "short_record")) {
    b <- list(value = NA_real_, lo = NA_real_, hi = NA_real_, status = "short_record")
  } else {
    b <- oracle_greenup_bounds(gu[gu$year %in% sup$year[sup$greenup_reason == "supported"], ])
  }
  data.frame(median_greenup = b$value, greenup_lo = b$lo, greenup_hi = b$hi,
             greenup_status = b$status, stringsAsFactors = FALSE)
}

# Section 7, one plant-year: summed 'yes' runs with midpoint edges, bridged across the
# year boundary from the neighbouring years' visits, plus the longest span the visits allow.
oracle_leaf_span <- function(d, s, y, prev, nxt) {
  n <- length(d)
  yl <- oracle_ylen(y)
  r <- rle(s)
  ends <- cumsum(r$lengths)
  starts <- ends - r$lengths + 1
  st <- starts[r$values]; en <- ends[r$values]
  a <- ifelse(st == 1, d[1], (d[pmax(st - 1, 1)] + d[st]) / 2)
  b <- ifelse(en == n, d[n], (d[en] + d[pmin(en + 1, n)]) / 2)
  edge_start <- FALSE; edge_end <- FALSE
  if (s[1]) {
    edge_start <- TRUE
    if (!is.null(prev)) {
      p_rel <- prev$day - oracle_ylen(y - 1)
      if (d[1] - p_rel <= 31) {
        a[1] <- if (prev$yes) 1 else max(1, (p_rel + d[1]) / 2)
        edge_start <- FALSE
      }
    }
  }
  if (s[n]) {
    edge_end <- TRUE
    if (!is.null(nxt)) {
      q_rel <- nxt$day + yl
      if (q_rel - d[n] <= 31) {
        b[length(b)] <- if (nxt$yes) yl + 1 else min(yl + 1, (d[n] + q_rel) / 2)
        edge_end <- FALSE
      }
    }
  }
  la <- sum(b - a)
  la_hi <- la + (d[1] - 1) * edge_start + (yl + 1 - d[n]) * edge_end
  c(leaf_active = la, leaf_active_hi = la_hi, edge_start = edge_start, edge_end = edge_end)
}

# Section 7 for every plant, plus the per plant-year first_in_leaf flag that section 5 uses.
oracle_leaf <- function(o) {
  k <- o$phase == "Leaves" & o$status %in% c("yes", "no") & is.finite(o$doy) & !is.na(o$year)
  v <- o[k, c("id", "year", "doy", "status")]
  empty <- list(spans = data.frame(id = character(), year = integer(), leaf_active = numeric(),
                                   leaf_active_hi = numeric(), edge_start = logical(),
                                   edge_end = logical()),
                first = data.frame(id = character(), year = integer(), first_in_leaf = logical()))
  if (nrow(v) == 0) return(empty)
  v$yes <- v$status == "yes"
  key <- paste(v$id, v$year, v$doy, sep = "\r")
  any_yes <- tapply(v$yes, key, any)
  v <- v[!duplicated(key), ]
  v$yes <- as.vector(any_yes[paste(v$id, v$year, v$doy, sep = "\r")])
  v <- v[order(v$id, v$year, v$doy), ]
  # One element per plant-year (id x year groups are contiguous after the sort above).
  py <- paste(v$id, v$year, sep = "\r")
  groups <- split(seq_len(nrow(v)), factor(py, levels = unique(py)))
  gid <- vapply(groups, function(g) v$id[g[1]], "")
  gyr <- vapply(groups, function(g) v$year[g[1]], 0L)
  first <- data.frame(id = gid, year = gyr,
                      first_in_leaf = vapply(groups, function(g) v$yes[g[1]], NA),
                      stringsAsFactors = FALSE)
  rownames(first) <- NULL
  # Neighbour plant-year index: the same plant in year - 1 and year + 1, if visited.
  lookup <- stats::setNames(seq_along(groups), names(groups))
  prev_k <- lookup[paste(gid, gyr - 1L, sep = "\r")]
  next_k <- lookup[paste(gid, gyr + 1L, sep = "\r")]
  m <- matrix(NA_real_, length(groups), 4)
  for (k in seq_along(groups)) {
    ii <- groups[[k]]
    if (!any(v$yes[ii])) next
    prev <- nxt <- NULL
    if (!is.na(prev_k[k])) {
      pj <- groups[[prev_k[k]]]; pj <- pj[length(pj)]
      prev <- list(day = v$doy[pj], yes = v$yes[pj])
    }
    if (!is.na(next_k[k])) {
      nj <- groups[[next_k[k]]][1]
      nxt <- list(day = v$doy[nj], yes = v$yes[nj])
    }
    m[k, ] <- oracle_leaf_span(v$doy[ii], v$yes[ii], gyr[k], prev, nxt)
  }
  has <- !is.na(m[, 1])
  sp <- data.frame(id = gid[has], year = gyr[has], leaf_active = m[has, 1],
                   leaf_active_hi = m[has, 2], edge_start = m[has, 3] == 1,
                   edge_end = m[has, 4] == 1, stringsAsFactors = FALSE)
  list(spans = sp, first = first)
}

# Section 8. Two-stage leaf-active summary, its upper bound and the edge share. `spans`
# arrives already limited to plants listed in inds. short_record is checked before none.
oracle_leaf_summary <- function(spans, sup) {
  na_out <- function(status) {
    data.frame(median_leaf_active = NA_real_, leaf_active_hi = NA_real_,
               leaf_active_status = status, leaf_edge_share = NA_real_,
               stringsAsFactors = FALSE)
  }
  if (nrow(sup) > 0 && all(sup$leaf_reason == "short_record")) return(na_out("short_record"))
  ok_years <- sup$year[sup$leaf_reason == "supported"]
  rows <- spans[spans$year %in% ok_years, ]
  if (nrow(rows) == 0) return(na_out("none"))
  pn <- round(tapply(rows$leaf_active, rows$id, stats::median))
  pm <- round(tapply(rows$leaf_active_hi, rows$id, stats::median))
  value <- round(stats::median(pn))
  hi <- round(stats::median(pm))
  data.frame(median_leaf_active = value, leaf_active_hi = hi,
             leaf_active_status = if (hi - value >= 14) "lower_bound" else "point",
             leaf_edge_share = round(mean(rows$edge_start | rows$edge_end), 3),
             stringsAsFactors = FALSE)
}

# Section 10. Species x growth form summary for one site, from the plants that `inds`
# marks as species with a name. Green-up uses the section 6 core on the group's supported
# plant-years; leaf takes each plant's unrounded median before the group median.
oracle_species <- function(site, gu, spans, sup, inds) {
  empty <- data.frame(site = character(), scientificName = character(),
                      growthForm = character(), n_ind = integer(), greenup = numeric(),
                      greenup_lo = numeric(), greenup_hi = numeric(),
                      greenup_status = character(), lc_share = numeric(),
                      leaf_active = numeric(), leaf_active_hi = numeric(),
                      leaf_active_lower_bound = logical(), leaf_edge_share = numeric(),
                      n_years = integer(), leaf_n_years = integer(),
                      stringsAsFactors = FALSE)
  if (is.null(inds) || nrow(inds) == 0) return(empty)
  sp_name <- as.character(inds$scientificName)
  keep <- !is.na(inds$is_species) & inds$is_species & !is.na(sp_name) & nzchar(sp_name)
  ind <- data.frame(id = as.character(inds$individualID)[keep], sci = sp_name[keep],
                    gf = as.character(inds$growthForm)[keep], stringsAsFactors = FALSE)
  ind <- ind[!duplicated(ind$id), ]
  gu_years <- sup$year[sup$greenup_reason == "supported"]
  leaf_years <- sup$year[sup$leaf_reason == "supported"]
  rows <- gu[gu$year %in% gu_years & gu$id %in% ind$id, ]
  if (nrow(rows) == 0) return(empty)
  m <- match(rows$id, ind$id)
  rows$sci <- ind$sci[m]; rows$gf <- ind$gf[m]
  lrows <- spans[spans$year %in% leaf_years, ]
  grp <- split(seq_len(nrow(rows)), paste(rows$sci, rows$gf, sep = "\r"))
  out <- lapply(grp, function(g) {
    r <- rows[g, ]
    plants <- unique(r$id)
    if (length(plants) < 3) return(NULL)
    b <- oracle_greenup_bounds(r)
    lr <- lrows[lrows$id %in% plants, ]
    if (nrow(lr) > 0) {
      la <- tapply(lr$leaf_active, lr$id, stats::median)
      la_hi <- tapply(lr$leaf_active_hi, lr$id, stats::median)
      la_v <- if (any(is.finite(la))) round(stats::median(la[is.finite(la)])) else NA_real_
      la_h <- if (any(is.finite(la_hi))) round(stats::median(la_hi[is.finite(la_hi)])) else NA_real_
      edge <- round(mean(lr$edge_start | lr$edge_end), 3)
    } else {
      la_v <- la_h <- edge <- NA_real_
    }
    data.frame(site = site, scientificName = r$sci[1], growthForm = r$gf[1],
               n_ind = length(plants), greenup = b$value, greenup_lo = b$lo,
               greenup_hi = b$hi, greenup_status = b$status,
               lc_share = round(mean(r$left_censored), 3), leaf_active = la_v,
               leaf_active_hi = la_h,
               leaf_active_lower_bound = if (is.na(la_v)) NA else la_h - la_v >= 14,
               leaf_edge_share = edge, n_years = length(unique(r$year)),
               leaf_n_years = length(unique(lr$year)), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, out)
  if (is.null(out)) return(empty)
  out <- out[order(out$scientificName, out$growthForm, method = "radix"), ]
  rownames(out) <- NULL
  out
}

# Sections 0 to 8 and 10 for one site: every intermediate table the outputs need.
oracle_compute <- function(bundle) {
  o <- oracle_obs(bundle$obs)
  forms <- oracle_plant_forms(o)
  ons <- oracle_all_onsets(o)
  g <- oracle_greenup(ons, forms)
  drop <- oracle_dropped_forms(g$greenup, g$scored)
  gu <- g$greenup[!(g$greenup$form %in% c(drop$autumn, drop$carry)), ]
  leaf <- oracle_leaf(o)
  sup <- oracle_support(o, gu, leaf$first)
  site <- as.character(bundle$meta$site)
  # Section 6 uses every plant in obs; section 8 only the plants listed in inds, because
  # the published leaf value is built on the inds-based per-plant summary.
  inds_ids <- if (is.null(bundle$inds)) character() else as.character(bundle$inds$individualID)
  # Section 8b counts.
  counts <- data.frame(n_years_watched = nrow(sup),
                       n_supported_years = sum(sup$greenup_reason == "supported"),
                       n_leaf_supported_years = sum(sup$leaf_reason == "supported"))
  row <- cbind(data.frame(site = site, stringsAsFactors = FALSE),
               oracle_greenup_summary(gu, sup),
               oracle_leaf_summary(leaf$spans[leaf$spans$id %in% inds_ids, ], sup), counts)
  list(site = site, row = row, onsets = ons, greenup = gu, dropped = drop, support = sup,
       leaf = leaf$spans, inds = bundle$inds)
}

# One site row. `detail = TRUE` also returns the intermediate tables, for debugging a
# disagreement with the app.
headline_oracle_site <- function(bundle, detail = FALSE) {
  x <- oracle_compute(bundle)
  if (detail) {
    return(list(summary = x$row, onsets = x$onsets, greenup = x$greenup,
                dropped = x$dropped, support = x$support, leaf = x$leaf))
  }
  x$row
}

# All site rows, ordered by site code.
headline_oracle <- function(paths) {
  out <- do.call(rbind, lapply(paths, function(p) headline_oracle_site(readRDS(p))))
  out <- out[order(out$site, method = "radix"), ]
  rownames(out) <- NULL
  out
}

# The four oracle tables for one site: site row, species x growth form rows, plant-years
# (with a green-up or a leaf row) and per-year support.
headline_oracle_tables <- function(bundle) {
  x <- oracle_compute(bundle)
  sup <- x$support
  gkey <- paste(x$greenup$id, x$greenup$year, sep = "\r")
  lkey <- paste(x$leaf$id, x$leaf$year, sep = "\r")
  keys <- unique(c(gkey, lkey))
  gi <- match(keys, gkey); li <- match(keys, lkey)
  id <- ifelse(is.na(gi), x$leaf$id[li], x$greenup$id[gi])
  yr <- ifelse(is.na(gi), x$leaf$year[li], x$greenup$year[gi])
  si <- match(yr, sup$year)
  py <- data.frame(site = rep(x$site, length(keys)), individualID = id, year = as.integer(yr),
                   greenup = x$greenup$greenup[gi], greenup_lo = x$greenup$lo[gi],
                   greenup_hi = x$greenup$hi[gi],
                   left_censored = x$greenup$left_censored[gi],
                   carryover = x$greenup$carryover[gi],
                   greenup_source = x$greenup$source[gi],
                   leaf_active = x$leaf$leaf_active[li],
                   leaf_active_hi = x$leaf$leaf_active_hi[li],
                   leaf_edge_start = x$leaf$edge_start[li],
                   leaf_edge_end = x$leaf$edge_end[li],
                   greenup_supported = sup$greenup_reason[si] %in% "supported",
                   leaf_supported = sup$leaf_reason[si] %in% "supported",
                   stringsAsFactors = FALSE)
  py <- py[order(py$individualID, py$year, method = "radix"), ]
  rownames(py) <- NULL
  support <- data.frame(site = rep(x$site, nrow(sup)), year = as.integer(sup$year),
                        greenup_reason = sup$greenup_reason, leaf_reason = sup$leaf_reason,
                        greenup_supported = sup$greenup_reason == "supported",
                        leaf_supported = sup$leaf_reason == "supported",
                        stringsAsFactors = FALSE)
  list(site = x$row,
       species = oracle_species(x$site, x$greenup, x$leaf, sup, x$inds),
       plant_years = py, support = support)
}

# The four tables bound over all bundles, sites in code order.
headline_oracle_all <- function(paths) {
  parts <- lapply(paths, function(p) headline_oracle_tables(readRDS(p)))
  ord <- order(vapply(parts, function(x) x$site$site, ""), method = "radix")
  parts <- parts[ord]
  bind <- function(name) {
    out <- do.call(rbind, lapply(parts, function(x) x[[name]]))
    rownames(out) <- NULL
    out
  }
  list(site = bind("site"), species = bind("species"), plant_years = bind("plant_years"),
       support = bind("support"))
}
