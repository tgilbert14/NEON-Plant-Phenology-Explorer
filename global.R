# ===========================================================================
# NEON Plant Phenology Explorer — global.R
# A NEONize sibling (Desert Data Labs) for Plant phenology observations
# (DP1.10055.001). Chrome + bundling spine + pin-card interaction ported from
# the prior siblings; the analysis layer is phenology-native (onset timing,
# the year-clock of phenophases, per-individual phenophase careers).
# ===========================================================================
suppressPackageStartupMessages({
  library(shiny); library(bslib); library(bsicons)
  library(dplyr); library(tidyr); library(stringr); library(tibble)
  library(plotly); library(leaflet); library(DT)
  library(shinyjs); library(shinycssloaders); library(RColorBrewer); library(htmltools)
})
source("R/site_metadata.R", local = FALSE)
source("R/phe_helpers.R", local = FALSE)
source("R/codebook.R", local = FALSE)

NEON_DPID <- "DP1.10055.001"   # Plant phenology observations
.NEON_PKG <- paste0("neon", "Utilities")
LIVE_FETCH <- (Sys.getenv("PHE_LIVE", "0") != "0") && requireNamespace(.NEON_PKG, quietly = TRUE)

SITE_DIR  <- "data/sites"
DEMO_PATH <- "data-sample/demo.rds"
DEMO_META <- list(site = "HARV", label = "HARV · Harvard Forest — demo")

read_bundle <- function(f) {
  if (!file.exists(f)) return(NULL)
  out <- tryCatch(readRDS(f), error = function(e) { warning(sprintf("read_bundle('%s'): %s", f, conditionMessage(e))); NULL })
  if (is.null(out)) return(NULL)
  if (is.data.frame(out)) return(out)
  if (is.null(out$obs) || !nrow(out$obs)) NULL else out
}
load_site_bundle <- function(site) read_bundle(file.path(SITE_DIR, paste0(site, ".rds")))
load_demo <- function() { b <- load_site_bundle(DEMO_META$site); if (!is.null(b)) b else read_bundle(DEMO_PATH) }

SITE_INDEX <- tryCatch(readRDS("data/site_index.rds"), error = function(e) NULL)
NATIONAL_ONSETS <- tryCatch(readRDS("data/national_onsets.rds"), error = function(e) NULL)
APP_VERSION <- "2.0 (Field Notebook)"
BUNDLED <- if (!is.null(SITE_INDEX)) SITE_INDEX$site else character(0)
site_table <- if (length(BUNDLED)) {
  m <- neon_sites[match(BUNDLED, neon_sites$site), ]
  want <- intersect(c("n_individuals","n_species","n_obs","dominant_form","median_greenup","median_leaf_active","n_plots","gu_share"), names(SITE_INDEX))
  cbind(m, SITE_INDEX[match(m$site, SITE_INDEX$site), want, drop = FALSE])
} else neon_sites[0, ]

# picker offers only the sites we actually bundled (honest UX)
phe_state_choices <- function() {
  st <- sort(unique(site_table$state)); if (!length(st)) return(NULL)
  setNames(st, sprintf("%s (%d)", state_names[st] %||% st, as.integer(table(site_table$state)[st])))
}
phe_sites_in_state <- function(stt) {
  rows <- site_table[site_table$state == stt, ]; rows <- rows[order(rows$name), ]
  if (!nrow(rows)) return(character(0))
  setNames(rows$site, sprintf("%s — %s", rows$site, rows$name))
}

# --- "Field Notebook" palette (Desert Data Labs) -------------------------
# A naturalist's seasonal journal: deep forest-canopy primary, terracotta
# secondary, senescence-amber accent/warning, on warm parchment. The brand
# accents ARE the phenophase ramp (see pheno_palette / styles.css :root), so
# chrome and charts speak ONE color language. Mirrors www/styles.css :root —
# keep the two in sync. Red is reserved for destructive only. Deliberately
# distinct from the Small Mammal Tracker's navy/cardinal/gold.
DDL <- list(
  primary = "#1f6f3e", primary2 = "#14532a",       # forest canopy
  terra   = "#b5481f", teal = "#2f8f87",           # secondary / info
  amber   = "#d98014", amber2 = "#9a5b0e",         # senescence accent + warning
  # phenophase ramp (mirror of pheno_palette / CSS tokens)
  greenup = "#9ccf6a", leaf = "#1f7a3f", bloom = "#c8417a", fruit = "#6a3fa0", senesce = "#d98014",
  ink = "#24302a", muted = "#5f6f64", bg = "#f6f3ea", paper = "#fffdf7", line = "#e2ddcd",
  # legacy aliases so older references keep resolving to the new palette
  navy = "#1f6f3e", navy2 = "#14532a", cardinal = "#AB0520",   # cardinal = destructive only
  gold = "#d98014", gold2 = "#9a5b0e", sky = "#2f8f87", green = "#1f7a3f", green2 = "#14532a")
app_theme <- bs_theme(version = 5, bg = "#f6f3ea", fg = DDL$ink,
  primary = DDL$primary, secondary = DDL$terra, success = DDL$leaf, info = DDL$teal,
  warning = DDL$amber, danger = DDL$cardinal,
  base_font = font_google("Rubik"), heading_font = font_google("Fraunces"), "border-radius" = "10px")

asset_url <- function(path) { f <- file.path("www", path)
  v <- if (file.exists(f)) as.integer(as.numeric(file.mtime(f))) else 0L; sprintf("%s?v=%s", path, v) }
spin <- function(x, img = NULL) shinycssloaders::withSpinner(x, color = DDL$green, type = 6)
info_pop <- function(title, ..., placement = "auto")
  bslib::popover(tags$span(class = "info-dot", bsicons::bs_icon("info-circle")), ..., title = title, placement = placement)
insight_banner <- function(icon, ..., tone = "navy")
  div(class = paste("chart-insight", paste0("ci-", tone)), bsicons::bs_icon(icon), div(class = "ci-text", ...))
glow_badge <- function(label, color = DDL$primary, glow = color)
  span(class = "glow-badge", style = sprintf("color:#fff; background:%s; border-color:%s;", color, color), label)
card_head <- function(icon, title, ...)
  bslib::card_header(class = "with-info", bsicons::bs_icon(icon), tags$span(class = "ch-title", " ", title), ...)
fmt_int <- function(x) format(round(as.numeric(x)), big.mark = ",", trim = TRUE)
doy_to_month <- function(d) format(as.Date(d - 1, origin = "2021-01-01"), "%b %d")

# The app mascot — a flat (no-gradient, no-id so it's safely reusable) cute
# leafy sprout in the Field Notebook canopy-green + senescence-amber. Used as
# the loading spinner, the splash guide, and the celebration hop. Parts are
# classed so the CSS can wiggle leaves / blink eyes.
MASCOT_CRITTER <- htmltools::HTML(paste0(
  '<svg class="mascot" viewBox="0 0 120 120" aria-hidden="true">',
  '<path d="M60,98 L60,64" stroke="#5a9a3a" stroke-width="4" stroke-linecap="round"/>',
  '<g class="mascot-ear-l"><path d="M52,40 C34,30 22,40 26,54 C42,54 52,48 52,40 Z" fill="#e6a92e"/></g>',
  '<g class="mascot-ear-r"><path d="M68,40 C86,30 98,40 94,54 C78,54 68,48 68,40 Z" fill="#e6a92e"/></g>',
  '<path d="M60,30 C48,30 44,46 52,58 L68,58 C76,46 72,30 60,30 Z" fill="#9bd24a"/>',
  '<ellipse cx="60" cy="68" rx="26" ry="26" fill="#8cbf52"/>',
  '<g class="mascot-eyes"><circle cx="51" cy="66" r="6" fill="#243a16"/><circle cx="69" cy="66" r="6" fill="#243a16"/>',
  '<circle cx="49" cy="63.5" r="2.2" fill="#ffffff"/><circle cx="67" cy="63.5" r="2.2" fill="#ffffff"/></g>',
  '</svg>'))
