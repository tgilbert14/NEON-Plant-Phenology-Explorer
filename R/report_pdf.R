# ===========================================================================
# report_pdf.R: server-side PDF site report for the NEON Plant Phenology Explorer.
#
# Ported from the Small Mammal Tracker's report_pdf.R (NEONize playbook 2e):
# a vector PDF drawn with base grid on grDevices::cairo_pdf, streamed by a
# Shiny downloadHandler. No LaTeX, no headless Chrome, no package beyond base
# grid/grDevices and the helpers already sourced from R/phe_helpers.R.
#
# Entry point (the server wires it into the hero "report card" link):
#   phe_report_pdf(file, site, label, inds, obs, ind_summary, site_row,
#                  release = NULL, data_through = NULL, app_version = NULL,
#                  generated = Sys.Date())
# Every name defined here carries an rp_ prefix so nothing in global.R or the
# helpers is shadowed.
# ===========================================================================
suppressPackageStartupMessages(library(grid))

# cairo_pdf renders system fonts and full Unicode; plain pdf() is the fallback.
rp_dev <- function() if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else grDevices::pdf

# Paper palette from the app's Field Notebook tokens (global.R DDL), with
# literal fallbacks so the file can be sourced on its own. The page is white
# paper; every text colour clears 4.5:1 on white.
rp_tok <- function(name, fallback) {
  if (exists("DDL", inherits = TRUE)) { v <- get("DDL", inherits = TRUE)[[name]]; if (!is.null(v)) return(v) }
  fallback
}
RP <- list(w = 8.5, h = 11, margin = 0.7, lineH = 0.17,
           primary = rp_tok("primary", "#1f6f3e"), primary2 = rp_tok("primary2", "#14532a"),
           leaf = rp_tok("leaf", "#1f7a3f"), greenup = rp_tok("greenup", "#9ccf6a"),
           amber = rp_tok("amber", "#d98014"), amber2 = rp_tok("amber2", "#9a5b0e"),
           terra = rp_tok("terra", "#b5481f"), ink = rp_tok("ink", "#24302a"),
           muted = rp_tok("muted", "#5f6f64"), line = rp_tok("line", "#e2ddcd"),
           paper = rp_tok("paper", "#fffdf7"), bg = rp_tok("bg", "#f6f3ea"))
RP$cw <- RP$w - 2 * RP$margin
RP$ch <- RP$h - 2 * RP$margin
RP$foot_h <- 0.62          # space reserved at the bottom of every page for the footer
RP$body_max <- RP$ch - RP$foot_h

# ---- text helpers ----------------------------------------------------------
# Map typographic glyphs to plain ones (no em dash may reach the PDF) and drop
# anything outside Latin-1 so a base pdf() fallback never prints boxes.
rp_txt <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  x <- gsub("\u2014|\u2013", "-", x)
  x <- gsub("\u00b7", "|", x)
  x <- gsub("\u2248", "~", x); x <- gsub("\u00b1", "+/-", x)
  x <- gsub("\u2265", ">=", x); x <- gsub("\u2264", "<=", x)
  x <- gsub("\u2192", "to", x)
  x <- gsub("[\u2018\u2019]", "'", x); x <- gsub("[\u201c\u201d]", "\"", x)
  enc2utf8(iconv(x, "UTF-8", "latin1", sub = ""))
}
rp_gy <- function(yTop) unit(1, "npc") - unit(yTop, "in")   # top-down cursor
rp_num <- function(x) { x <- suppressWarnings(as.numeric(x)); if (length(x) && is.finite(x[1])) x[1] else NA_real_ }
rp_int <- function(x) { x <- rp_num(x); if (is.na(x)) "n/a" else format(round(x), big.mark = ",", trim = TRUE) }
rp_pct <- function(x) { x <- rp_num(x); if (is.na(x)) "n/a" else sprintf("%d%%", round(100 * x)) }
rp_str <- function(x) { x <- as.character(x %||% NA_character_)[1]; if (is.na(x) || !nzchar(x)) NA_character_ else x }
rp_month <- function(doy) {
  doy <- rp_num(doy); if (is.na(doy)) return(NA_character_)
  format(as.Date(round(doy) - 1, origin = "2021-01-01"), "%b %d")
}
rp_plural <- function(n, one, many = paste0(one, "s")) if (isTRUE(rp_num(n) == 1)) one else many

# Measure-then-wrap; needs the device open (metrics are device-specific).
rp_wrap <- function(txt, fontsize, width_in, fontface = 1) {
  gp <- gpar(fontsize = fontsize, fontface = fontface)
  out <- character(0)
  for (para in strsplit(rp_txt(txt), "\n", fixed = TRUE)[[1]]) {
    words <- strsplit(para, " ", fixed = TRUE)[[1]]; words <- words[nzchar(words)]
    cur <- ""
    for (w in words) {
      test <- if (nzchar(cur)) paste(cur, w) else w
      if (convertWidth(grobWidth(textGrob(test, gp = gp)), "in", valueOnly = TRUE) > width_in && nzchar(cur)) {
        out <- c(out, cur); cur <- w
      } else cur <- test
    }
    out <- c(out, cur)
  }
  out
}
rp_width <- function(txt, fontsize, fontface = 1)
  convertWidth(grobWidth(textGrob(rp_txt(txt), gp = gpar(fontsize = fontsize, fontface = fontface))), "in", valueOnly = TRUE)
# largest font size (down to `min`) at which txt fits in width_in
rp_fit <- function(txt, fontsize, width_in, fontface = 1, min = 8) {
  while (fontsize > min && rp_width(txt, fontsize, fontface) > width_in) fontsize <- fontsize - 0.5
  fontsize
}

# ---- page state ------------------------------------------------------------
# One environment per render holds the page counter and the running header so a
# paragraph that would run into the footer can open a continuation page.
rp_footer <- function(st) {
  fl <- rp_wrap(st$footer, 7, RP$cw)
  grid.lines(x = unit(c(0, 1), "npc"), y = unit(length(fl) * 0.12 + 0.08, "in"),
             gp = gpar(col = RP$line, lwd = 0.8))
  for (k in seq_along(fl))
    grid.text(fl[k], x = unit(0, "npc"), y = unit((length(fl) - k) * 0.12 + 0.02, "in"),
              just = c("left", "bottom"), gp = gpar(fontsize = 7, col = RP$muted))
  grid.text(sprintf("page %d", st$page), x = unit(1, "npc"), y = unit(length(fl) * 0.12 + 0.12, "in"),
            just = c("right", "bottom"), gp = gpar(fontsize = 7, col = RP$muted))
}
rp_new_page <- function(st) {
  if (st$page > 0) popViewport()
  st$page <- st$page + 1
  grid.newpage()
  grid.rect(gp = gpar(fill = "white", col = NA))
  pushViewport(viewport(width = unit(RP$cw, "in"), height = unit(RP$ch, "in"), name = "content"))
  rp_footer(st)
  if (st$page > 1) {
    hl <- rp_txt(st$label)
    while (nchar(hl) > 20 && rp_width(hl, 10, 2) > RP$cw - 2.6) hl <- paste0(substr(hl, 1, nchar(hl) - 4), "...")
    grid.text(hl, x = unit(0, "npc"), y = rp_gy(0), just = c("left", "top"),
              gp = gpar(fontsize = 10, fontface = "bold", col = RP$primary2))
    grid.text("NEON Plant Phenology site report", x = unit(1, "npc"), y = rp_gy(0),
              just = c("right", "top"), gp = gpar(fontsize = 8.5, col = RP$muted))
    grid.lines(x = unit(c(0, 1), "npc"), y = rp_gy(0.24), gp = gpar(col = RP$line, lwd = 1))
    return(0.42)
  }
  0
}
rp_need <- function(st, y, h) if (y + h > RP$body_max) rp_new_page(st) else y

rp_para <- function(st, txt, y, fontsize = 9.5, col = RP$ink, fontface = 1, gap = 0.08,
                    indent = 0, width = RP$cw - indent) {
  lh <- RP$lineH * fontsize / 10
  for (ln in rp_wrap(txt, fontsize, width, fontface)) {
    y <- rp_need(st, y, lh)
    grid.text(ln, x = unit(indent, "in"), y = rp_gy(y), just = c("left", "top"),
              gp = gpar(fontsize = fontsize, col = col, fontface = fontface))
    y <- y + lh
  }
  y + gap
}
rp_h <- function(st, txt, y, need = 0.6) {
  y <- rp_need(st, y, need)
  grid.text(rp_txt(txt), x = unit(0, "npc"), y = rp_gy(y), just = c("left", "top"),
            gp = gpar(fontsize = 12, fontface = "bold", col = RP$primary2))
  grid.lines(x = unit(c(0, 1), "npc"), y = rp_gy(y + 0.24), gp = gpar(col = RP$line, lwd = 0.8))
  y + 0.34
}

# ---- headline tiles ---------------------------------------------------------
# cells: list(list(value, label, note)); laid out in `ncol` columns.
rp_tiles <- function(st, cells, y, ncol = 3, cellH = 0.98, gap = 0.1) {
  rows <- ceiling(length(cells) / ncol)
  y <- rp_need(st, y, rows * (cellH + gap))
  cw <- (RP$cw - (ncol - 1) * gap) / ncol
  for (i in seq_along(cells)) {
    r <- (i - 1) %/% ncol; cc <- (i - 1) %% ncol
    x0 <- cc * (cw + gap); yc <- y + r * (cellH + gap); cell <- cells[[i]]
    lead <- isTRUE(cell$lead)
    grid.rect(x = unit(x0, "in"), y = rp_gy(yc), width = unit(cw, "in"), height = unit(cellH, "in"),
              just = c("left", "top"), gp = gpar(fill = RP$bg, col = if (lead) RP$primary else RP$line,
                                                  lwd = if (lead) 1.4 else 0.8))
    grid.rect(x = unit(x0, "in"), y = rp_gy(yc), width = unit(0.05, "in"), height = unit(cellH, "in"),
              just = c("left", "top"), gp = gpar(fill = if (isTRUE(cell$muted)) RP$muted else RP$primary, col = NA))
    inner <- cw - 0.25
    fs <- rp_fit(cell$value, 17, inner, 2, min = 9)
    grid.text(rp_txt(cell$value), x = unit(x0 + 0.15, "in"), y = rp_gy(yc + 0.1), just = c("left", "top"),
              gp = gpar(fontsize = fs, fontface = "bold", col = if (isTRUE(cell$muted)) RP$muted else RP$primary2))
    lab <- rp_wrap(cell$label, 8.5, inner, 2)[1]
    grid.text(lab, x = unit(x0 + 0.15, "in"), y = rp_gy(yc + 0.42), just = c("left", "top"),
              gp = gpar(fontsize = 8.5, fontface = "bold", col = RP$ink))
    nl <- utils::head(rp_wrap(cell$note %||% "", 7.5, inner), 3)
    for (k in seq_along(nl))
      grid.text(nl[k], x = unit(x0 + 0.15, "in"), y = rp_gy(yc + 0.58 + (k - 1) * 0.125),
                just = c("left", "top"), gp = gpar(fontsize = 7.5, col = RP$muted))
  }
  y + rows * (cellH + gap) + 0.04
}

# ---- charts (pure grid) -----------------------------------------------------
rp_empty_box <- function(x0, yTop, w, h, msg) {
  grid.rect(x = unit(x0, "in"), y = rp_gy(yTop), width = unit(w, "in"), height = unit(h, "in"),
            just = c("left", "top"), gp = gpar(fill = RP$bg, col = RP$line, lty = 2))
  ml <- rp_wrap(msg, 8.5, w - 0.4)
  for (k in seq_along(ml))
    grid.text(ml[k], x = unit(x0 + w / 2, "in"),
              y = rp_gy(yTop + h / 2 - (length(ml) - 1) * 0.08 + (k - 1) * 0.16),
              gp = gpar(fontsize = 8.5, col = RP$muted))
}

# Horizontal bar chart of tagged plants per growth form.
rp_bar_chart <- function(st, comp, y, max_rows = 10) {
  if (is.null(comp) || !nrow(comp)) {
    y <- rp_need(st, y, 0.8); rp_empty_box(0, y, RP$cw, 0.7, "No growth-form records in this bundle."); return(y + 0.8)
  }
  comp <- comp[!is.na(comp[[1]]), , drop = FALSE]
  names(comp) <- c("form", "n")
  if (nrow(comp) > max_rows) {
    other <- sum(comp$n[max_rows:nrow(comp)])
    comp <- rbind(comp[seq_len(max_rows - 1), ], data.frame(form = "Other forms", n = other))
  }
  rowH <- 0.24; labW <- 2.5; numW <- 0.6
  h <- nrow(comp) * rowH
  y <- rp_need(st, y, h + 0.1)
  barW <- RP$cw - labW - numW; mx <- max(comp$n)
  for (i in seq_len(nrow(comp))) {
    yc <- y + (i - 1) * rowH
    lab <- rp_txt(comp$form[i]); fs <- rp_fit(lab, 9, labW - 0.1, 1, min = 7)
    grid.text(lab, x = unit(labW - 0.1, "in"), y = rp_gy(yc + rowH / 2), just = c("right", "centre"),
              gp = gpar(fontsize = fs, col = RP$ink))
    bw <- max(0.02, barW * comp$n[i] / mx)
    grid.rect(x = unit(labW, "in"), y = rp_gy(yc + 0.04), width = unit(bw, "in"), height = unit(rowH - 0.08, "in"),
              just = c("left", "top"), gp = gpar(fill = RP$primary, col = NA))
    grid.text(rp_int(comp$n[i]), x = unit(labW + bw + 0.06, "in"), y = rp_gy(yc + rowH / 2),
              just = c("left", "centre"), gp = gpar(fontsize = 8.5, col = RP$ink))
  }
  y + h + 0.08
}

# Season bands: one row per phenophase, one cell per week; dark where at least
# 50% of scored plant-years were 'yes', light where scored but under 50%, blank
# where fewer than 5 plant-years were scored that week.
rp_band_chart <- function(st, wy, y) {
  if (is.null(wy) || !nrow(wy)) {
    y <- rp_need(st, y, 0.8)
    rp_empty_box(0, y, RP$cw, 0.7, "No species-level phenophase scores with at least 5 plant-years in any week.")
    return(y + 0.8)
  }
  wy$phenophaseName <- as.character(wy$phenophaseName)
  ph <- unique(wy$phenophaseName)
  rk <- if (exists("PHENO_RANK", inherits = TRUE)) get("PHENO_RANK", inherits = TRUE)[ph] else rep(NA, length(ph))
  ph <- ph[order(ifelse(is.na(rk), 99, rk), ph)]
  labW <- 1.75; cntW <- 0.55; gridW <- RP$cw - labW - cntW; wkW <- gridW / 52; rowH <- 0.19
  h <- 0.22 + length(ph) * rowH + 0.42
  y <- rp_need(st, y, h)
  # month ticks along the top
  starts <- as.integer(format(as.Date(sprintf("2021-%02d-01", 1:12)), "%j"))
  for (m in 1:12) {
    xw <- labW + ((starts[m] - 1) %/% 7) * wkW
    grid.text(month.abb[m], x = unit(xw + 0.02, "in"), y = rp_gy(y), just = c("left", "top"),
              gp = gpar(fontsize = 7, col = RP$muted))
  }
  grid.text("weeks", x = unit(RP$cw, "in"), y = rp_gy(y), just = c("right", "top"),
            gp = gpar(fontsize = 7, col = RP$muted))
  y0 <- y + 0.18
  for (i in seq_along(ph)) {
    yc <- y0 + (i - 1) * rowH
    d <- wy[wy$phenophaseName == ph[i], , drop = FALSE]
    lab <- rp_txt(ph[i]); fs <- rp_fit(lab, 8.5, labW - 0.1, 1, min = 7)
    grid.text(lab, x = unit(labW - 0.08, "in"), y = rp_gy(yc + rowH / 2), just = c("right", "centre"),
              gp = gpar(fontsize = fs, col = RP$ink))
    grid.rect(x = unit(labW, "in"), y = rp_gy(yc + 0.03), width = unit(gridW, "in"), height = unit(rowH - 0.06, "in"),
              just = c("left", "top"), gp = gpar(fill = "white", col = RP$line, lwd = 0.5))
    for (k in seq_len(nrow(d))) {
      wk <- as.integer(d$week[k]); if (!is.finite(wk) || wk < 1 || wk > 52) next
      on <- is.finite(d$rate[k]) && d$rate[k] >= 50
      grid.rect(x = unit(labW + (wk - 1) * wkW, "in"), y = rp_gy(yc + 0.03),
                width = unit(wkW, "in"), height = unit(rowH - 0.06, "in"), just = c("left", "top"),
                gp = gpar(fill = if (on) RP$leaf else RP$line, col = NA))
    }
    n_on <- sum(is.finite(d$rate) & d$rate >= 50)
    grid.text(sprintf("%d", n_on), x = unit(RP$cw, "in"), y = rp_gy(yc + rowH / 2), just = c("right", "centre"),
              gp = gpar(fontsize = 8, col = RP$ink))
  }
  # legend
  ly <- y0 + length(ph) * rowH + 0.1
  sw <- function(x, fill, txt, border = NA) {
    grid.rect(x = unit(x, "in"), y = rp_gy(ly), width = unit(0.16, "in"), height = unit(0.12, "in"),
              just = c("left", "top"), gp = gpar(fill = fill, col = border, lwd = 0.5))
    grid.text(rp_txt(txt), x = unit(x + 0.22, "in"), y = rp_gy(ly - 0.005), just = c("left", "top"),
              gp = gpar(fontsize = 7.5, col = RP$ink))
  }
  sw(0, RP$leaf, "at least 50% of scored plant-years 'yes'")
  sw(2.55, RP$line, "scored, under 50% 'yes'")
  sw(4.35, "white", "fewer than 5 plant-years scored", border = RP$muted)
  y0 + length(ph) * rowH + 0.34
}

# Small line chart of site-year medians across species.
rp_line_chart <- function(x0, yTop, w, h, df, title, ylab, empty_msg, col = RP$primary) {
  grid.text(rp_txt(title), x = unit(x0, "in"), y = rp_gy(yTop), just = c("left", "top"),
            gp = gpar(fontsize = 9.5, fontface = "bold", col = RP$primary2))
  top <- yTop + 0.24; ph <- h - 0.24
  if (is.null(df) || !nrow(df)) { rp_empty_box(x0, top, w, ph, empty_msg); return(invisible()) }
  left <- 0.42; bottom <- 0.26
  pw <- w - left - 0.08; pph <- ph - bottom - 0.06
  yr <- df$year; v <- df$value
  xr <- range(yr) + c(-0.5, 0.5)
  yt <- pretty(range(v), n = 4); if (length(yt) < 2) yt <- c(floor(min(v)) - 5, ceiling(max(v)) + 5)
  yr_lim <- range(c(yt, v))
  px <- function(x) x0 + left + (x - xr[1]) / diff(xr) * pw
  py <- function(val) top + 0.06 + (1 - (val - yr_lim[1]) / diff(yr_lim)) * pph
  for (t in yt) {
    grid.lines(x = unit(c(px(xr[1]), px(xr[2])), "in"), y = rp_gy(c(py(t), py(t))),
               gp = gpar(col = RP$line, lwd = 0.6))
    grid.text(sprintf("%g", t), x = unit(x0 + left - 0.05, "in"), y = rp_gy(py(t)), just = c("right", "centre"),
              gp = gpar(fontsize = 7, col = RP$muted))
  }
  grid.text(rp_txt(ylab), x = unit(x0 + 0.02, "in"), y = rp_gy(top + 0.06 + pph / 2), rot = 90,
            just = c("centre", "top"), gp = gpar(fontsize = 7, col = RP$muted))
  ux <- sort(unique(yr)); step <- if (length(ux) > 8) 2 else 1
  for (i in seq_along(ux)) if ((i - 1) %% step == 0)
    grid.text(as.character(ux[i]), x = unit(px(ux[i]), "in"), y = rp_gy(top + 0.06 + pph + 0.05),
              just = c("centre", "top"), gp = gpar(fontsize = 7, col = RP$muted))
  # join consecutive years only, so a left-out year shows as a break, not a slope
  o <- order(yr); yo <- yr[o]; vo <- v[o]
  for (i in seq_len(length(yo) - 1)) if (yo[i + 1] - yo[i] == 1)
    grid.lines(x = unit(px(yo[i:(i + 1)]), "in"), y = rp_gy(py(vo[i:(i + 1)])), gp = gpar(col = col, lwd = 1.4))
  # a hollow year (every species point that year is a bound) is drawn open
  hol <- if ("hollow" %in% names(df)) df$hollow %in% TRUE else rep(FALSE, length(v))
  if (any(!hol)) grid.points(x = unit(px(yr[!hol]), "in"), y = rp_gy(py(v[!hol])), pch = 21, size = unit(5, "pt"),
              gp = gpar(fill = col, col = "white", lwd = 0.8))
  if (any(hol)) grid.points(x = unit(px(yr[hol]), "in"), y = rp_gy(py(v[hol])), pch = 21, size = unit(5, "pt"),
              gp = gpar(fill = "white", col = col, lwd = 1.2))
  invisible()
}

# site-year median across species of the species-year medians. Hollow species
# points (trend_hollow: a bound, not a value) are left out of the year's median
# when the year has a solid point, as in the app's trend fit; a year with only
# hollow points keeps their median and is drawn open.
rp_site_year <- function(tr) {
  if (is.null(tr) || !nrow(tr)) return(NULL)
  tr <- tr[is.finite(tr$onset), , drop = FALSE]; if (!nrow(tr)) return(NULL)
  tr$hollow <- if (exists("trend_hollow", inherits = TRUE)) trend_hollow(tr) else rep(FALSE, nrow(tr))
  out <- do.call(rbind, lapply(split(tr, tr$year), function(d) {
    solid <- d[!d$hollow, , drop = FALSE]; use <- if (nrow(solid)) solid else d
    data.frame(year = as.integer(d$year[1]), value = round(stats::median(use$onset)),
               n_species = length(unique(d$scientificName)), hollow = !nrow(solid)) }))
  out[order(out$year), , drop = FALSE]
}
# one-line verdict from trend_verdict() in the app's words
rp_verdict <- function(tr, leaf = FALSE) {
  if (is.null(tr) || !nrow(tr) || !exists("trend_verdict", inherits = TRUE)) return(NA_character_)
  v <- tryCatch(trend_verdict(tr), error = function(e) NULL); if (is.null(v)) return(NA_character_)
  left <- if (v$n_left_out > 0) sprintf(" %d species-year %s left out as %s.", v$n_left_out,
    if (v$n_left_out == 1) "point is" else "points are", if (leaf) "lower bounds" else "upper bounds") else ""
  switch(v$verdict,
    too_short = sprintf("Too short to fit a trend: %d %s with a solid median; about %d or more are needed.%s",
                        v$ny, rp_plural(v$ny, "year"), TREND_MIN_YEARS, left),
    none = sprintf("No detectable linear shift (%.1f days/yr, 95%% interval %.1f to %.1f).%s", v$slope, v$lo, v$hi, left),
    depends = sprintf("The direction depends on how the left-out points are treated, so none is claimed.%s", left),
    up = , down = sprintf("Changed %.1f days/yr %s (95%% interval %.1f to %.1f), descriptive only.%s", abs(v$slope),
                          if (leaf) (if (v$verdict == "up") "longer" else "shorter") else (if (v$verdict == "up") "later" else "earlier"),
                          v$lo, v$hi, left),
    NA_character_)
}

# ---- the composer -----------------------------------------------------------
phe_report_pdf <- function(file, site, label, inds, obs, ind_summary, site_row,
                           release = NULL, data_through = NULL, app_version = NULL,
                           generated = Sys.Date()) {
  sr <- if (is.null(site_row) || !NROW(site_row)) list() else as.list(as.data.frame(site_row)[1, , drop = FALSE])
  g <- function(nm) if (nm %in% names(sr)) sr[[nm]] else NULL
  rel <- release %||% (if (exists("PHE_RELEASE", inherits = TRUE)) get("PHE_RELEASE", inherits = TRUE) else list())
  rel_tag <- rp_str(rel$tag) %||% "release not recorded"; if (is.na(rel_tag)) rel_tag <- "release not recorded"
  rel_doi <- rp_str(rel$doi); prod <- rp_str(rel$product); if (is.na(prod)) prod <- "DP1.10055.001"
  prod_name <- rp_str(rel$product_name); if (is.na(prod_name)) prod_name <- "Plant phenology observations"
  lic <- rp_str(rel$license); if (is.na(lic)) lic <- "CC BY 4.0"
  label <- rp_str(label); if (is.na(label)) label <- as.character(site %||% "Site")

  obs <- if (is.null(obs)) NULL else as.data.frame(obs, stringsAsFactors = FALSE)
  if (!is.null(obs) && nrow(obs) && exists("normalize_doy", inherits = TRUE)) obs <- normalize_doy(obs)
  has_obs <- !is.null(obs) && nrow(obs) > 0
  inds <- if (is.null(inds)) data.frame() else as.data.frame(inds, stringsAsFactors = FALSE)

  dt <- data_through
  if (is.null(dt) || (length(dt) == 1 && is.na(dt))) {
    dt <- if (has_obs) {
      dd <- tryCatch(obs_dates(obs), error = function(e) as.Date(NA))
      if (any(!is.na(dd))) max(dd, na.rm = TRUE) else NA
    } else NA
  }
  dt_txt <- if (inherits(dt, "Date")) format(dt, "%Y-%m-%d") else if (is.na(dt[1])) "not recorded" else as.character(dt[1])
  gen_txt <- if (inherits(generated, "Date") || inherits(generated, "POSIXt")) format(generated, "%Y-%m-%d") else as.character(generated)
  ver_txt <- rp_str(app_version); if (is.na(ver_txt)) ver_txt <- "not recorded"

  # ---- numbers --------------------------------------------------------------
  n_ind <- rp_num(g("n_individuals")); if (is.na(n_ind)) n_ind <- length(unique(inds$individualID))
  n_sp <- rp_num(g("n_species"))
  if (is.na(n_sp) && nrow(inds)) n_sp <- length(unique(species_level_only(inds)$scientificName))
  n_plots <- rp_num(g("n_plots")); if (is.na(n_plots) && "plotID" %in% names(inds)) n_plots <- length(unique(inds$plotID))
  status <- rp_str(g("greenup_status")); if (is.na(status)) status <- "none"
  hi <- rp_num(g("greenup_hi")); lo <- rp_num(g("greenup_lo")); med <- rp_num(g("median_greenup"))
  n_watch <- rp_num(g("n_years_watched")); n_sup <- rp_num(g("n_supported_years"))
  cov <- rp_num(g("gu_share")); if (is.na(cov)) cov <- tryCatch(greenup_coverage(ind_summary), error = function(e) NA_real_)
  la <- rp_num(g("median_leaf_active")); cad <- rp_num(g("median_visit_interval"))
  la_hi <- rp_num(g("leaf_active_hi")); la_edge <- rp_num(g("leaf_edge_share")); unc <- rp_num(g("uncertain_share"))
  la_status <- rp_str(g("leaf_active_status")); if (is.na(la_status)) la_status <- if (is.na(la)) "none" else "point"
  lc_share <- rp_num(g("greenup_lc_share")); fb_share <- rp_num(g("greenup_fallback_share"))
  autumn_forms <- rp_str(g("greenup_autumn_forms")); carry_forms <- rp_str(g("greenup_carry_forms"))
  if (status %in% c("point", "range", "upper_bound") && is.na(hi)) status <- "none"
  if (status == "point" && is.na(med)) status <- "none"
  if (status == "range" && is.na(lo)) status <- "upper_bound"

  gu_lab <- tryCatch(greenup_label(med, lo, hi, status, n_watch), error = function(e) NA_character_)
  gu_value <- switch(status, point = , range = , upper_bound = gu_lab, short_record = "Unavailable", "None")
  gu_month <- switch(status,
    point = rp_month(med), range = sprintf("%s to %s", rp_month(lo), rp_month(hi)),
    upper_bound = sprintf("%s or earlier", rp_month(hi)), NA_character_)
  gu_note <- switch(status,
    point = sprintf("median day of year (%s); %s of supported onsets left-censored", gu_month, rp_pct(lc_share)),
    range = sprintf("median day %s lies in %s; %s of supported onsets left-censored", rp_int(med), gu_month, rp_pct(lc_share)),
    upper_bound = sprintf("latest possible median (%s); %s of supported onsets left-censored", gu_month, rp_pct(lc_share)),
    short_record = "too few seasons monitored to check the visit schedule",
    "no supported green-up onset at this site")
  gu_explain <- switch(status,
    point = sprintf("Green-up %s: the last 'no' and first 'yes' bounds are less than 14 days apart, so one day is shown.", gu_lab),
    range = sprintf(paste("Green-up %s (median day %s). Each plant's green-up is known only to lie between its last 'no'",
                          "and first 'yes' visit; onsets underway at the first visit could be earlier. This is not a confidence interval."),
                    gu_lab, rp_int(med)),
    upper_bound = sprintf(paste("Green-up %s: most plants were already greening at their first visit, so only",
                                "the latest possible median is known and no single day is given."), gu_lab),
    short_record = paste0("Green-up ", if (is.na(gu_lab)) "unavailable: too few seasons monitored" else gu_lab, ".",
                          if (is.na(la)) " Leaf-active days are withheld for the same reason." else ""),
    paste("Green-up unavailable: no plant here has a supported green-up onset (for example evergreens,",
          "cacti, autumn-sprouting annuals, or no scored bud-break)."))
  if (is.na(gu_lab) && status != "short_record") gu_lab <- "not available"
  cov_note <- if (is.na(cov)) "undefined without a supported season"
    else if (is.finite(fb_share) && fb_share > 0) sprintf("of tagged plants; %s of those onsets from first Young leaves", rp_pct(fb_share))
    else "of tagged plants with a supported green-up onset"
  la_lab <- if (is.na(la)) NA_character_ else leaf_label(la, if (la_status == "lower_bound") "lower_bound" else "point")
  la_note <- if (is.na(la)) {
    if (status == "short_record") "too few seasons monitored" else "no supported leaf-active span"
  } else if (la_status == "lower_bound") "lower bound: many spans run into the year's first or last visit"
  else "median days carrying leaves per plant-year, supported years only"
  # the leaf status in one line
  la_explain <- if (is.na(la)) NA_character_ else if (la_status == "lower_bound")
    sprintf(paste("Leaf-active %s: %s of leaf plant-years run into the year's first or last visit, and the visits allow up to",
                  "%s days, so %s is the shortest the leaf period could be, not its full length."),
            la_lab, rp_pct(la_edge), rp_int(la_hi), rp_int(la))
  else sprintf("Leaf-active %s: the spans the visits allow add less than 14 days, so the median is read as the leaf period.", la_lab)
  lead_leaf <- is.finite(cov) && cov < 0.5

  # ---- derived series ---------------------------------------------------------
  comp <- tryCatch(if (nrow(inds) && "growthForm" %in% names(inds)) as.data.frame(comp_by(inds, "growthForm")) else NULL,
                   error = function(e) NULL)
  wy <- if (has_obs) tryCatch(weekly_yesrate(obs), error = function(e) NULL) else NULL
  if (!is.null(wy)) wy <- as.data.frame(wy)
  gu_all <- if (has_obs) tryCatch(greenup_onsets(obs), error = function(e) NULL) else NULL
  sup <- if (has_obs) tryCatch(site_year_support(obs, gu = gu_all), error = function(e) NULL) else NULL
  tr_gu <- if (has_obs) tryCatch(onset_trend(obs), error = function(e) NULL) else NULL
  tr_la <- if (has_obs && !is.null(sup)) tryCatch(leaf_active_trend(obs, support = sup), error = function(e) NULL) else NULL
  sy_gu <- rp_site_year(tr_gu); sy_la <- rp_site_year(tr_la)

  reason_word <- c(low_effort = "reduced visits", late_start = "truncated start", short_record = "too few seasons")
  left_out <- function(col) {
    if (is.null(sup) || !nrow(sup) || !(col %in% names(sup))) return(character(0))
    s <- sup[sup[[col]] != "supported", , drop = FALSE]
    if (!nrow(s)) return(character(0))
    sprintf("%s (%s)", s$year, ifelse(s[[col]] %in% names(reason_word), reason_word[s[[col]]], s[[col]]))
  }
  out_gu <- left_out("greenup_reason"); out_la <- left_out("leaf_reason")

  footer <- paste0("Data: NEON (National Ecological Observatory Network). ", prod_name, " (", prod, "), ",
                   rel_tag, if (!is.na(rel_doi)) paste0(", ", rel_doi) else "", ". Licensed ", lic,
                   ". This report is unofficial, not endorsed by NEON, Battelle or the NSF. ",
                   "NEON Plant Phenology Explorer, Desert Data Labs.")

  st <- new.env(); st$page <- 0L; st$label <- label; st$footer <- footer
  dev <- rp_dev()
  dev(file, width = RP$w, height = RP$h, onefile = TRUE)
  on.exit({ grDevices::dev.off() }, add = TRUE)

  # ---------- PAGE 1: header, headline tiles, composition ----------
  y <- rp_new_page(st)
  grid.rect(x = unit(0, "npc"), y = rp_gy(0), width = unit(1, "npc"), height = unit(1.12, "in"),
            just = c("left", "top"), gp = gpar(fill = RP$primary, col = NA))
  grid.text("NEON Plant Phenology Explorer: site report", x = unit(0.16, "in"), y = rp_gy(0.16),
            just = c("left", "top"), gp = gpar(col = "white", fontsize = 16, fontface = "bold"))
  lab_fs <- rp_fit(label, 12, RP$cw - 0.32, 1, min = 8.5)
  grid.text(rp_txt(label), x = unit(0.16, "in"), y = rp_gy(0.5), just = c("left", "top"),
            gp = gpar(col = "white", fontsize = lab_fs))
  meta <- sprintf("Data through %s  |  Generated %s  |  App version %s", dt_txt, gen_txt, ver_txt)
  grid.text(rp_txt(meta), x = unit(0.16, "in"), y = rp_gy(0.8), just = c("left", "top"),
            gp = gpar(col = "white", fontsize = rp_fit(meta, 8.5, RP$cw - 0.32, 1, min = 7)))
  grid.lines(x = unit(c(0, 1), "npc"), y = rp_gy(1.12), gp = gpar(col = RP$amber, lwd = 3))
  y <- 1.26
  y <- rp_para(st, sprintf("Source: NEON %s (%s), %s%s. Licensed %s.", prod_name, prod, rel_tag,
                           if (!is.na(rel_doi)) paste0(", DOI ", rel_doi) else "", lic),
               y, fontsize = 8.5, col = RP$muted, gap = 0.1)
  watch_txt <- if (is.na(n_watch)) "" else sprintf(", scored over %s %s, %s of which %s the visit-schedule check",
    rp_int(n_watch), rp_plural(n_watch, "season"), if (is.na(n_sup)) "n/a" else rp_int(n_sup),
    if (isTRUE(n_sup == 1)) "passes" else "pass")
  y <- rp_para(st, sprintf("%s tagged %s of %s %s on %s phenology %s%s. Each number below describes when tagged plants were recorded in a phenophase, not how many plants there are.",
                           rp_int(n_ind), rp_plural(n_ind, "plant"), rp_int(n_sp), rp_plural(n_sp, "species", "species"),
                           rp_int(n_plots), rp_plural(n_plots, "plot"), watch_txt),
               y, fontsize = 10, gap = 0.14)

  t_gu <- list(value = gu_value, label = "Green-up (median onset)", note = gu_note,
               muted = !(status %in% c("point", "range", "upper_bound")))
  t_cov <- list(value = rp_pct(cov), label = "Green-up coverage", note = cov_note, muted = is.na(cov))
  t_la <- list(value = if (is.na(la)) "Unavailable" else la_lab,
               label = "Leaf-active (median)", note = la_note, muted = is.na(la), lead = lead_leaf)
  timing <- if (lead_leaf) list(t_la, t_gu, t_cov) else list(t_gu, t_cov, t_la)
  y <- rp_tiles(st, c(list(
    list(value = rp_int(n_ind), label = "Tagged plants", note = "individually tagged and revisited"),
    list(value = rp_int(n_sp), label = rp_plural(n_sp, "Species", "Species"), note = "identified to species or below"),
    list(value = rp_int(n_plots), label = rp_plural(n_plots, "Phenology plot", "Phenology plots"),
         note = "NEON phenology transect plots")), timing), y)
  if (lead_leaf)
    y <- rp_para(st, sprintf(paste("Leaf-active days lead here: only %s of tagged plants have a supported green-up",
                                   "onset, so the green-up median describes a minority of plants."), rp_pct(cov)),
                 y, fontsize = 9, fontface = 2, col = RP$amber2, gap = 0.06)
  y <- rp_para(st, gu_explain, y, fontsize = 9, gap = 0.06)
  if (!is.na(la_explain)) y <- rp_para(st, la_explain, y, fontsize = 9, gap = 0.06)
  if (is.finite(unc) && unc >= (if (exists("UNCERTAIN_DISCLOSE", inherits = TRUE)) get("UNCERTAIN_DISCLOSE", inherits = TRUE) else 0.10))
    y <- rp_para(st, sprintf("%d%% of scored records here were marked uncertain and are left out of every rate and onset.",
                             as.integer(round(unc * 100))), y, fontsize = 9, gap = 0.06)
  if (!is.na(autumn_forms))
    y <- rp_para(st, sprintf(paste("No calendar-year green-up for %s: these forms sprout with autumn rain, so their",
                                   "season spans two calendar years; read them by leaf-active days."), autumn_forms),
                 y, fontsize = 9, gap = 0.06)
  if (!is.na(carry_forms))
    y <- rp_para(st, sprintf(paste("No calendar-year green-up for %s: these forms stay green across the new year",
                                   "in most years, so the year's next flush is a different event from green-up."), carry_forms),
                 y, fontsize = 9, gap = 0.06)
  if (!is.na(cad))
    y <- rp_para(st, sprintf(paste("Visit cadence: plants were scored about every %s %s (median). An onset is known",
                                   "only to within the gap between the last 'no' and the first 'yes'."),
                             rp_int(cad), rp_plural(cad, "day")), y, fontsize = 9, gap = 0.1)

  y <- rp_h(st, "Composition: tagged plants by growth form", y + 0.06, need = 1.2)
  y <- rp_bar_chart(st, comp, y)
  y <- rp_para(st, "Counts are tagged plants chosen for phenology monitoring, not plant abundance or cover at the site.",
               y, fontsize = 8, col = RP$muted)

  # ---------- PAGE 2: season and trend ----------
  y <- rp_new_page(st)
  y <- rp_h(st, "Season: weeks when most plant-years were in each phenophase", y, need = 2)
  y <- rp_para(st, paste("All species. Each week counts one scored opportunity per plant, phenophase, year and week;",
                         "repeat visits in that week collapse to one. Years are pooled into a typical-year profile of",
                         "plant-year opportunities, not a population trend. The right column counts the weeks at or above 50%."),
               y, fontsize = 8.5, col = RP$muted, gap = 0.1)
  y <- rp_band_chart(st, wy, y)

  y <- rp_h(st, "Trend: site-year medians across species", y + 0.1, need = 3.2)
  y <- rp_para(st, paste("Each point is the median across species of the species-year medians; a species-year needs at",
                         "least 3 tagged plants. Each plant counts once per year. Unsupported site-years are left out.",
                         "Year-to-year change here is descriptive and is not attributed to climate."),
               y, fontsize = 8.5, col = RP$muted, gap = 0.1)
  y <- rp_need(st, y, 2.05)
  half <- (RP$cw - 0.3) / 2
  no_gu <- if (status == "short_record") "No trend: too few seasons monitored to check the visit schedule."
           else "No supported green-up trend: no species-year with 3 or more plants has a bud-break onset in a supported year."
  no_la <- if (status == "short_record") "No trend: too few seasons monitored to check the visit schedule."
           else "No supported leaf-active trend: no species-year with 3 or more plants in a supported year."
  rp_line_chart(0, y, half, 1.95, sy_gu, "Green-up onset (bud-break only)", "day of year", no_gu, RP$primary)
  rp_line_chart(half + 0.3, y, half, 1.95, sy_la, "Leaf-active days", "days in leaf", no_la, RP$amber2)
  y <- y + 2.05
  span_txt <- function(sy, what) if (is.null(sy)) sprintf("%s: no points.", what) else
    sprintf("%s: %d %s (%s to %s), %d to %d species per year.", what, nrow(sy), rp_plural(nrow(sy), "year"),
            min(sy$year), max(sy$year), min(sy$n_species), max(sy$n_species))
  vtxt <- function(tr, lf, what) { x <- rp_verdict(tr, lf); if (is.na(x)) "" else sprintf("%s trend: %s%s", what, tolower(substr(x, 1, 1)), substring(x, 2)) }
  y <- rp_para(st, paste(span_txt(sy_gu, "Green-up"), span_txt(sy_la, "Leaf-active"),
                         if (!is.null(sy_gu) || !is.null(sy_la)) "A gap in a line is a year left out." else "",
                         if (any(c(sy_gu$hollow, sy_la$hollow) %in% TRUE))
                           "An open point is a year whose every species point is a bound (green-up: most plants already greening at the first visit; leaf-active: spans that run into the year's first or last visit); bounds are left out of each year's median and of the trend fit." else "",
                         vtxt(tr_gu, FALSE, "Green-up"), vtxt(tr_la, TRUE, "Leaf-active"),
                         "The green-up trend uses bud-break onsets only:",
                         "forms read by first Young leaves flush with rain several times a year, so their first",
                         "flush is not a comparable annual onset."), y, fontsize = 8.5, gap = 0.06)
  lo_txt <- function(x) if (length(x)) paste(x, collapse = ", ") else "none"
  y <- rp_para(st, sprintf("Years left out of green-up: %s. Years left out of leaf-active: %s.",
                           lo_txt(out_gu), lo_txt(out_la)), y, fontsize = 9, gap = 0.04)
  why <- c(if (any(grepl("reduced visits", c(out_gu, out_la), fixed = TRUE)))
             "Reduced visits: that year's visited weeks fell below 75% of the site's usual count (for example the 2020-2021 COVID reduction).",
           if (any(grepl("truncated start", c(out_gu, out_la), fixed = TRUE)))
             "Truncated start: scoring began more than 30 days late and missed onsets or leaf-out already under way.",
           if (any(grepl("too few seasons", c(out_gu, out_la), fixed = TRUE)))
             "Too few seasons: with fewer than three seasons the visit schedule cannot be checked, so no year is used.")
  if (length(why)) y <- rp_para(st, paste(why, collapse = " "), y, fontsize = 8.5, col = RP$muted)

  # ---------- PAGE 3: caveats ----------
  y <- rp_new_page(st)
  y <- rp_h(st, "Caveats and claims", y)
  box_top <- y
  items <- list(
    list("Timing, not abundance.", "These are dates and durations recorded on tagged plants. They do not estimate abundance, cover, productivity, survival or the effect of climate."),
    list("Onsets are interval-censored.", "An onset lies between the last 'no' and the first 'yes' and is placed at their midpoint. A plant already 'yes' at its first visit of the year is left-censored; those onsets are kept and reported as a share, never dropped."),
    list("Visit cadence limits precision.", sprintf("Plants are scored on a schedule%s, so a day of year carries at least that much uncertainty. Site-years with reduced visits or a late start are excluded from medians and trends.",
                                                    if (is.na(cad)) "" else sprintf(" (about every %s %s here)", rp_int(cad), rp_plural(cad, "day")))),
    list("Pooling.", "The season chart pools years into one typical year of plant-year opportunities. Trends do not pool: each plant counts once per year before any median is taken.")
  )
  ix <- 0.18
  for (it in items) {
    y <- rp_para(st, it[[1]], y + 0.04, fontsize = 9.5, fontface = 2, col = RP$primary2, gap = 0.02, indent = ix, width = RP$cw - 2 * ix)
    y <- rp_para(st, it[[2]], y, fontsize = 9, gap = 0.06, indent = ix, width = RP$cw - 2 * ix)
  }
  y <- y + 0.04
  grid.rect(x = unit(0, "in"), y = rp_gy(box_top - 0.04), width = unit(RP$cw, "in"), height = unit(y - box_top + 0.04, "in"),
            just = c("left", "top"), gp = gpar(fill = NA, col = RP$line, lwd = 1))
  y <- y + 0.16

  y <- rp_h(st, "This report CAN", y)
  can <- c("Describe when tagged plants at this site were recorded in each phenophase across a typical year.",
           "Give a site green-up onset as one day, a censoring range, or an upper bound, with its coverage and censored share.",
           "Give leaf-active days per plant-year where green-up is sparse, as at warm-desert sites, as N days or, where spans run into the year's first or last visit, at least N days.",
           "Show site-year medians across species for supported years.")
  for (s in can) y <- rp_para(st, paste0("-  ", s), y, fontsize = 9, gap = 0.03, indent = 0.1)
  y <- rp_h(st, "This report CANNOT", y + 0.1)
  cannot <- c(
    "Give a calendar-year green-up for evergreens, cacti or autumn-sprouting annuals; read those by leaf-active days.",
    "Treat a Young-leaves green-up as the same day-for-day event as bud-break; it is the first new-leaf flush of drought-deciduous shrubs.",
    "Read a green-up range as a confidence interval; it bounds visit spacing and censoring, not sampling error.",
    "Give a green-up where most plants were already greening at their first visit (an upper bound only), or from fewer than three seasons.",
    "Read \"at least N days\" of leaf-active as the full leaf period; those spans run into the year's first or last visit.",
    "Give a trend direction that flips depending on how the censoring-heavy points are treated; those trends claim no direction.",
    "Fit a leaf-active slope through lower-bound sites or points; they are left out.",
    "Estimate plant abundance, productivity or demographic performance, or attribute a trend to climate.")
  for (s in cannot) y <- rp_para(st, paste0("-  ", s), y, fontsize = 9, gap = 0.03, indent = 0.1)

  y <- rp_h(st, "Source and citation", y + 0.1)
  y <- rp_para(st, sprintf(paste("NEON (National Ecological Observatory Network). %s (%s), %s.%s Data through %s.",
                                 "Licensed %s. Site %s."), prod_name, prod, rel_tag,
                           if (!is.na(rel_doi)) paste0(" ", rel_doi, ".") else "", dt_txt, lic, as.character(site %||% "")),
               y, fontsize = 9)
  y <- rp_para(st, sprintf("Generated %s by the NEON Plant Phenology Explorer, Desert Data Labs. App version: %s.",
                           gen_txt, ver_txt), y, fontsize = 9, col = RP$muted)

  popViewport()
  invisible(file)
}
