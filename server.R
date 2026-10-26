# ===========================================================================
# NEON Plant Phenology Explorer — server.R
# ===========================================================================
server <- function(input, output, session) {
  is_dark <- function() identical(input$colorMode, "dark")
  plotly_theme <- function(p, legend = TRUE) {
    dark <- is_dark(); ink <- if (dark) "#e8eef2" else "#1f2a30"
    grid <- if (dark) "rgba(220,230,240,0.10)" else "rgba(31,42,48,0.08)"; zero <- if (dark) "rgba(220,230,240,0.22)" else "rgba(31,42,48,0.15)"
    lin <- if (dark) "#3a4759" else "#d6ddd4"; legc <- if (dark) "#c3cedd" else "#344049"
    p %>% plotly::layout(paper_bgcolor = "rgba(0,0,0,0)", plot_bgcolor = "rgba(0,0,0,0)",
      font = list(color = ink, family = "Rubik"),
      xaxis = list(gridcolor = grid, zerolinecolor = zero, linecolor = lin),
      yaxis = list(gridcolor = grid, zerolinecolor = zero, linecolor = lin),
      legend = list(bgcolor = "rgba(0,0,0,0)", orientation = "h", y = -0.2, font = list(color = legc)),
      margin = list(l = 55, r = 30, t = 48, b = 44),
      hoverlabel = list(bgcolor = "rgba(20,83,42,0.96)", bordercolor = "#d98014", font = list(color = "#fff", family = "Rubik", size = 13))) %>%
      plotly::config(displayModeBar = FALSE, responsive = TRUE)
  }
  note_plot <- function(msg, icon = "\U0001F33F") plotly::plot_ly(type="scatter", mode="markers") %>%
    plotly::layout(paper_bgcolor="rgba(0,0,0,0)", plot_bgcolor="rgba(0,0,0,0)", xaxis=list(visible=FALSE), yaxis=list(visible=FALSE),
      annotations=list(list(text=paste0(icon,"<br>",msg), showarrow=FALSE, font=list(color=if(is_dark())"#9fb0c4" else "#6b7a85", size=15), align="center"))) %>%
    plotly::config(displayModeBar = FALSE)

  rv <- reactiveValues(obs=NULL, inds=NULL, ind_summary=NULL, trend=NULL, la_trend=NULL, label=NULL, site=NULL, ind=NULL, ctx=NULL, is_demo=FALSE, pendingSite=NULL)

  # ---- green-up coverage badge (the desert biome-conditional honesty) ------
  # When < ~half of a site's plants ever resolve a green-up onset, the
  # median green-up is a thin, biased subsample (warm deserts log most plants
  # straight into "Leaves"). Surface a small CLICKABLE badge — clean by default,
  # the why behind a tap (a bslib popover, the app's existing disclosure chrome).
  GU_COVERAGE_FLOOR <- 0.5
  # a site whose median in-season visit interval exceeds this is "coarse cadence":
  # onset is interval-censored to the visit gap, so its onset carries wide censoring
  # uncertainty and it is greyed + dropped from the cross-site fit. 10 days is about
  # 1.5x the usual 7-day median gap (NEON visits 2 or 3 times a week while plants
  # change fast, about weekly otherwise); bundled sites run 3-15d (one site at 15).
  CADENCE_COARSE <- 10
  gu_badge <- function(share, where = "here") {
    if (!is.finite(share) || share >= GU_COVERAGE_FLOOR) return(NULL)
    pct <- round(share * 100)
    bslib::popover(
      tags$span(class = "gu-cov-badge", role = "button", tabindex = "0",
        bsicons::bs_icon("exclamation-triangle-fill"),
        sprintf(" green-up scored for %d%% of plants %s", pct, where)),
      title = "Thin green-up coverage",
      p(HTML(sprintf("Only <b>%d%%</b> of the tagged plants %s have a green-up onset in a fully visited year (“Breaking leaf buds” or “Initial growth”, or for drought-deciduous shrubs their first “Young leaves” of the calendar year).", pct, where))),
      p(HTML("Shrubs that drop their leaves in drought have no bud-break stage in NEON's protocol, so their green-up is the year's first new 'Young leaves'; evergreen shrubs, cacti and annuals that sprout with autumn rain have no calendar-year green-up and are read by leaf-active days.")),
      p(class = "caveat", bsicons::bs_icon("arrow-right-circle"),
        HTML(" So <b>leaf-active</b> (days carrying leaves) is shown <b>by default</b> here, because it survives where green-up collapses. You can switch back to green-up on the Map, the trend, and Across sites.")),
      placement = "bottom")
  }

  # ---- site-level green-up estimand (status-aware) --------------------------
  # Reads the loaded site's site_table row: greenup_status is point, range,
  # upper_bound, short_record or none (see greenup_bounds / greenup_label in
  # R/phe_helpers.R). Only a point or range carries a numeric median_greenup.
  site_gu <- function(site) {
    row <- if (!is.null(site) && nzchar(site %||% "")) site_table[site_table$site == site, , drop = FALSE] else site_table[0, ]
    num <- function(col) if (nrow(row) && col %in% names(row)) suppressWarnings(as.numeric(row[[col]][1])) else NA_real_
    chr <- function(col) if (nrow(row) && col %in% names(row)) as.character(row[[col]][1]) else NA_character_
    status <- chr("greenup_status")
    list(found = nrow(row) > 0 && !is.na(status), status = if (is.na(status)) "none" else status,
         hi = num("greenup_hi"), lo = num("greenup_lo"), med = num("median_greenup"),
         la = num("median_leaf_active"), n_seasons = num("n_years_watched"),
         la_hi = num("leaf_active_hi"), la_status = { s <- chr("leaf_active_status"); if (is.na(s)) "none" else s },
         la_edge = num("leaf_edge_share"), uncertain = num("uncertain_share"),
         forms = chr("greenup_autumn_forms"), carry_forms = chr("greenup_carry_forms"),
         fallback = num("greenup_fallback_share"))
  }
  # site leaf-active label: "N days" or "at least N days" (leaf_label); a site
  # index without leaf_active_status reads as a point
  site_la_lab <- function(g) {
    if (!is.finite(g$la)) return(NA_character_)
    leaf_label(g$la, if (g$la_status %in% c("point", "lower_bound")) g$la_status else "point")
  }
  # the uncertain-records disclosure (iris), NULL under UNCERTAIN_DISCLOSE
  uncertain_txt <- function(g) {
    if (!is.finite(g$uncertain) || g$uncertain < UNCERTAIN_DISCLOSE) return(NULL)
    sprintf("%d%% of scored records here were marked uncertain and are left out of every rate and onset.",
            as.integer(round(g$uncertain * 100)))
  }
  # per-plant labels (ind_summary rows): green-up reads "day N or earlier" when at
  # least half its supported years were left-censored (the median has no lower
  # bound); leaf-active reads "at least N days" when the plant's span is a lower bound
  plant_gu_lab <- function(r, none = "n/a") {
    v <- suppressWarnings(as.numeric(r$greenup))
    lc <- if ("greenup_lc_years" %in% names(r)) suppressWarnings(as.numeric(r$greenup_lc_years)) else rep(NA_real_, length(v))
    ny <- if ("greenup_n_years" %in% names(r)) suppressWarnings(as.numeric(r$greenup_n_years)) else rep(NA_real_, length(v))
    ub <- is.finite(lc) & is.finite(ny) & ny > 0 & 2 * lc >= ny
    ifelse(!is.finite(v), none, ifelse(ub, sprintf("day %d or earlier", as.integer(round(v))), sprintf("day %d", as.integer(round(v)))))
  }
  plant_gu_ub <- function(r) {
    lc <- if ("greenup_lc_years" %in% names(r)) suppressWarnings(as.numeric(r$greenup_lc_years)) else rep(NA_real_, nrow(r))
    ny <- if ("greenup_n_years" %in% names(r)) suppressWarnings(as.numeric(r$greenup_n_years)) else rep(NA_real_, nrow(r))
    is.finite(lc) & is.finite(ny) & ny > 0 & 2 * lc >= ny
  }
  plant_la_lb <- function(r) if ("leaf_active_lower_bound" %in% names(r)) r$leaf_active_lower_bound %in% TRUE else rep(FALSE, NROW(r))
  plant_la_lab <- function(r, none = "n/a", unit = "days") {
    v <- suppressWarnings(as.numeric(r$leaf_active)); lb <- plant_la_lb(r)
    ifelse(!is.finite(v), none, sprintf("%s%d %s", ifelse(lb, "at least ", ""), as.integer(round(v)), unit))
  }
  # "N season(s)" for the short-record sentence
  seasons_txt <- function(n) if (is.finite(n)) sprintf("%d season%s", as.integer(n), if (n == 1) "" else "s") else "too few seasons"
  short_record_txt <- function(n) sprintf("Green-up and leaf-active days are unavailable here: %s monitored, too few to check the visit schedule.", seasons_txt(n))

  # ---- NEON release provenance (PHE_RELEASE + the search index's data-through date)
  # Guarded: a missing PHE_RELEASE field or SEARCH_INDEX$built drops that part
  # instead of printing NA.
  rel_field <- function(k) { v <- if (exists("PHE_RELEASE")) PHE_RELEASE[[k]] else NULL
    if (is.null(v) || !length(v) || is.na(v[1]) || !nzchar(v[1])) NULL else as.character(v[1]) }
  data_through <- function(fmt) {
    b <- if (!is.null(SEARCH_INDEX)) SEARCH_INDEX$built else NULL
    d <- tryCatch(as.Date(b), error = function(e) NA)
    if (!length(d) || is.na(d[1])) NULL else format(d[1], fmt)
  }
  release_sentence <- function() {
    prod <- rel_field("product"); nm <- rel_field("product_name"); tag <- rel_field("tag"); thr <- data_through("%B %Y")
    if (is.null(prod) || is.null(tag)) return(NULL)
    if (is.null(thr)) sprintf("NEON %s %s (%s).", prod, nm %||% "", tag)
    else sprintf("NEON %s %s (%s), observations through %s.", prod, nm %||% "", tag, thr)
  }
  release_short <- function() {
    tag <- rel_field("tag"); thr <- data_through("%b %Y")
    if (is.null(tag)) return(NULL)
    if (is.null(thr)) sprintf("NEON %s", tag) else sprintf("NEON %s · data through %s", tag, thr)
  }

  # Open on DEFAULT_SITE's state (SRER, Arizona) when that site is bundled;
  # otherwise keep the earlier Massachusetts default.
  default_state <- if (DEFAULT_SITE %in% site_table$site) site_table$state[match(DEFAULT_SITE, site_table$site)] else NA_character_
  observe({ ch <- phe_state_choices()
    sel <- if (!is.na(default_state) && default_state %in% ch) default_state else if ("MA" %in% ch) "MA" else NULL
    updateSelectInput(session, "stateSel", choices = ch, selected = sel) })
  # When the state changes, refill the site dropdown. If a map/browse pick is
  # pending, keep THAT site selected (so the sidebar mirrors the dot the user
  # tapped); otherwise DEFAULT_SITE when it is in this state, else the first
  # site in the state.
  observeEvent(input$stateSel, {
    sites <- phe_sites_in_state(input$stateSel)
    sel <- if (!is.null(rv$pendingSite) && rv$pendingSite %in% sites) rv$pendingSite
           else if (DEFAULT_SITE %in% sites) DEFAULT_SITE
           else if (length(sites)) sites[[1]] else NULL
    rv$pendingSite <- NULL
    updateSelectInput(session, "site", choices = sites, selected = sel)
  }, ignoreInit = FALSE)
  output$siteBio <- renderUI({ req(input$site); b <- site_bio(input$site); if (is.null(b)) return(NULL); div(class="site-bio", bs_icon("info-circle-fill"), span(b)) })
  shinyjs::hide("mainTabsWrap")

  ingest <- function(b, label, is_demo = FALSE) {
    if (is.null(b) || is.null(b$obs) || !nrow(b$obs)) { session$sendCustomMessage("loadDone", list()); showNotification("No phenology data for that site.", type="warning"); return(invisible()) }
    rv$obs <- b$obs; rv$inds <- b$inds
    # prefer the bundle's precomputed summaries (saves ~430ms/load); fall back
    # for older bundles that predate the precompute.
    rv$ind_summary <- b$ind_summary %||% individual_summary(b$obs, b$inds)
    rv$trend <- b$trend %||% onset_trend(b$obs)
    rv$support <- site_year_support(normalize_doy(b$obs))   # which years were visited on the usual schedule
    rv$la_trend <- leaf_active_trend(b$obs, support = rv$support)   # desert-safe year-trend; works where green-up is too thin
    # SMART DEFAULT: at thin-green-up (desert) sites, default every metric toggle to
    # leaf-active — the read that survives where green-up collapses. One app-wide
    # threshold: green-up scored for < GU_COVERAGE_FLOOR (50%) of the roster. Users
    # can still switch back; the Onset Lab already auto-leads leaf-active by this gate.
    gu_cov <- greenup_coverage(rv$ind_summary)
    def_metric <- if (is.finite(gu_cov) && gu_cov < GU_COVERAGE_FLOOR) "leaf_active" else "greenup"
    updateSelectInput(session, "mapMetric",   selected = def_metric)
    updateSelectInput(session, "trendMetric", selected = def_metric)
    updateSelectInput(session, "xsMetric",    selected = def_metric)
    rv$label <- label; rv$site <- b$meta$site; rv$is_demo <- is_demo; rv$ind <- NULL
    yrs <- range(b$obs$year, na.rm=TRUE); rv$ctx <- paste0(b$meta$site, " · ", if (yrs[1]==yrs[2]) yrs[1] else paste0(yrs[1],"–",yrs[2]))
    # close any picker popup left open on the national map before the splash hides,
    # so it is not still open when the user comes back via "change site"
    leaflet::leafletProxy("nationalMap", session) %>% leaflet::clearPopups()
    shinyjs::show("mainTabsWrap"); shinyjs::show("spPickerWrap"); shinyjs::hide("splash")
    # plant picker (one row per tagged individual)
    is_ <- rv$ind_summary
    ch <- if (!is.null(is_) && nrow(is_)) setNames(is_$individualID,
      sprintf("%s · %s (%s)", is_$scientificName, short_ind(is_$individualID), short_plot(is_$plotID))) else character(0)
    updateSelectizeInput(session, "indSel", choices = c("Pick a tagged plant…"="", ch), selected = "", server = TRUE)
    # species choices for the clock; DEFAULT to the most-monitored species so the
    # first paint is a clean single-calendar ring (not the "All species" view the
    # caption itself warns mixes evergreen/deciduous/forb calendars).
    sp <- sort(unique(species_level_only(b$obs)$scientificName)); sp <- sp[!is.na(sp)]
    top_sp <- names(sort(table(species_level_only(b$inds)$scientificName), decreasing = TRUE))
    top_sp <- top_sp[!is.na(top_sp) & nzchar(top_sp)]
    sel_sp <- if (length(top_sp) && top_sp[1] %in% sp) top_sp[1] else ""
    updateSelectInput(session, "clockSp", choices = c("All species" = "", setNames(sp, sp)), selected = sel_sp)
    session$sendCustomMessage("pheSite", list(site = b$meta$site))   # for export filenames
    nav_select("tabs", "overview"); session$sendCustomMessage("countUp", list()); session$sendCustomMessage("loadDone", list())
    invisible(TRUE)
  }
  load_site <- function(site, push = TRUE){ if (is.null(site)||identical(site, "")) { session$sendCustomMessage("loadDone", list()); return() }
    # allowlist: only a bundled site code goes on to the bundle loader
    not_bundled <- function() { session$sendCustomMessage("loadDone", list()); showNotification("That site isn't bundled in this demo.", type="error"); invisible() }
    if (!is.character(site) || length(site) != 1L || !(site %in% site_table$site)) return(not_bundled())
    b <- load_site_bundle(site); if (is.null(b)) return(not_bundled())
    row <- site_table[site_table$site==site,]
    ok <- ingest(b, sprintf("%s · %s", site, if (nrow(row)) row$name else site))
    # the loaded site goes into the URL, so Back returns to the picker and a
    # shared link reopens this site
    if (isTRUE(ok) && push) updateQueryString(paste0("?site=", site), mode = "push", session = session)
    invisible(ok) }
  # The map popup, the browse list, and the site-search all pick a site OFF the
  # sidebar. Route them through here so the sidebar's state + site dropdowns end
  # up reading the site that was picked (not the previous one) before the load.
  load_site_full <- function(code, push = TRUE){ if (is.null(code) || code=="") return()
    m <- neon_sites[neon_sites$site == code, ]
    if (nrow(m)) {
      rv$pendingSite <- code
      if (identical(input$stateSel, m$state[1])) {
        # same state already selected — the stateSel cascade won't re-fire, so set
        # the site dropdown directly and clear the pending flag ourselves.
        rv$pendingSite <- NULL
        updateSelectInput(session, "site", selected = code)
      } else {
        # different state — change it; the stateSel observer refills the site
        # dropdown honouring rv$pendingSite, landing on this site.
        updateSelectInput(session, "stateSel", selected = m$state[1])
      }
    }
    load_site(code, push = push) }
  observeEvent(input$loadBtn, load_site(input$site)); observeEvent(input$pickSite, { removeModal(); load_site_full(input$pickSite) })
  # The URL follows the loaded site: ?site=CODE at start or after Back/Forward
  # opens that site (when it is bundled); a URL with no site while a site is
  # loaded (Back from a site) returns to the picker. Shiny updates url_search on
  # pushState and popstate, so our own pushes land here too and are no-ops.
  observeEvent(session$clientData$url_search, {
    q <- tryCatch(parseQueryString(session$clientData$url_search %||% "")$site, error = function(e) NULL)
    if (is.character(q) && length(q) == 1L && q %in% site_table$site) {
      if (!identical(q, rv$site)) {
        session$sendCustomMessage("smtLoadStart", list(label = q))
        load_site_full(q, push = FALSE)   # the URL already names this site
      }
    } else if (!is.null(rv$site)) {
      show_picker(push = FALSE)
    }
  }, ignoreNULL = TRUE)
  # v2 flow: the Harvard Forest demo path is gone — users pick a real site on
  # the map, the Browse-all-sites list, or the by-name select panel. The demoBtn
  # / demoBtn2 inputs and their observers were removed with the demo CTAs.

  # "Change site" (in the hero band) -> back to the picker-map landing.
  show_picker <- function(push = TRUE) {
    rv$obs <- NULL; rv$inds <- NULL; rv$ind_summary <- NULL; rv$trend <- NULL; rv$la_trend <- NULL
    rv$label <- NULL; rv$site <- NULL; rv$ind <- NULL; rv$ctx <- NULL; rv$is_demo <- FALSE
    rv$support <- NULL
    shinyjs::hide("mainTabsWrap"); shinyjs::hide("spPickerWrap"); shinyjs::show("splash")
    if (push) updateQueryString("?", mode = "push", session = session)
    # the picker map was hidden while a site was loaded; nudge it across several
    # frames to re-measure now that it's visible again, so it never paints blank
    # / half-width on return (page_fillable settles its width a beat late).
    session$sendCustomMessage("kickMaps", list())
  }
  observeEvent(input$changeSite, show_picker(push = TRUE))

  # ---- national site-picker map (the splash landing) --------------------
  # STATIC leafletOutput in ui (never inside renderUI — avoids the re-bind race).
  output$nationalMap <- leaflet::renderLeaflet({
    st <- site_table[is.finite(site_table$lat) & is.finite(site_table$lng), , drop=FALSE]
    if (!nrow(st)) return(leaflet::leaflet() %>% add_suite_basemap("CartoDB.Positron") %>% leaflet::setView(-96, 38, 3))
    gv <- if ("median_greenup" %in% names(st)) suppressWarnings(as.numeric(st$median_greenup)) else rep(NA_real_, nrow(st))
    gs0 <- if ("gu_share" %in% names(st)) suppressWarnings(as.numeric(st$gu_share)) else rep(NA_real_, nrow(st))
    # robust [p5,p95] colour domain from WELL-COVERED sites only, then clamp every
    # site's value to it — so KONA (day 226, 3% coverage) / LAJA (day 5) pin to the
    # late/early endpoint instead of stretching the ramp flat (suite colour standard).
    pal <- greenup_pal(gv, gu_share = gs0)
    gv_col <- gp_clamp(pal, gv)
    mx <- max(st$n_individuals, 1, na.rm=TRUE); st$radius <- 6 + 12 * sqrt(pmax(st$n_individuals, 1)) / sqrt(mx)
    elev <- ifelse(is.finite(st$elevation_m), paste0(st$elevation_m, " m"), "n/a")
    # NEON-sourced strings go into popup HTML, so escape them first
    esc <- function(x) htmltools::htmlEscape(ifelse(is.na(x), "", as.character(x)))
    st_state <- ifelse(is.na(state_names[st$state]), st$state, state_names[st$state])
    # green-up text follows the site's estimand status: a point keeps its day and
    # date; a range, an upper bound or a short record uses greenup_label() wording.
    gstat <- if ("greenup_status" %in% names(st)) as.character(st$greenup_status) else rep(NA_character_, nrow(st))
    ghi <- if ("greenup_hi" %in% names(st)) suppressWarnings(as.numeric(st$greenup_hi)) else rep(NA_real_, nrow(st))
    glo <- if ("greenup_lo" %in% names(st)) suppressWarnings(as.numeric(st$greenup_lo)) else rep(NA_real_, nrow(st))
    gtxt <- vapply(seq_len(nrow(st)), function(i) {
      s_i <- gstat[i]
      if (identical(s_i, "point") && is.finite(gv[i]))
        return(paste0(" · green-up ", greenup_label(gv[i], glo[i], ghi[i], "point"), " (", doy_to_month(gv[i]), ")"))
      if (identical(s_i, "range") && is.finite(ghi[i]) && is.finite(glo[i]))
        return(paste0(" · green-up ", greenup_label(gv[i], glo[i], ghi[i], "range")))
      if (identical(s_i, "upper_bound") && is.finite(ghi[i]))
        return(paste0(" · green-up ", greenup_label(gv[i], glo[i], ghi[i], "upper_bound")))
      if (identical(s_i, "short_record")) return(" · green-up unavailable, too few seasons")
      if (is.finite(gv[i])) paste0(" · green-up day ", gv[i], " (", doy_to_month(gv[i]), ")") else ""
    }, character(1))
    # green-up COVERAGE share per site (gu_share). Sites where green-up is scored
    # for < ~half the roster (warm deserts) carry a biased median_greenup, so they
    # READ as thin — a muted, hollow marker (no always-on text), with the why in the
    # click-popup + hover label only. 0.5 mirrors gu_badge's GU_COVERAGE_FLOOR.
    gs <- if ("gu_share" %in% names(st)) suppressWarnings(as.numeric(st$gu_share)) else rep(NA_real_, nrow(st))
    thin <- is.finite(gs) & gs < 0.5
    mk_stroke <- ifelse(thin, "#9b8f74", "#fff")            # muted vs crisp ring
    mk_opacity <- ifelse(thin, 0.45, 0.9)                   # thin sites recede
    covtxt <- ifelse(thin, sprintf("<div class='sp-cov-thin'>&#9888; green-up scored for %d%% of plants here. Read leaf-active.</div>", round(gs * 100)), "")
    pop <- sprintf(paste0(
      "<div class='site-pop'><div class='pm-pop-t'>%s <span class='sp-code'>%s</span></div>",
      "<div class='pm-pop-s'>%s · NEON %s · %s</div><div class='sp-bio'>%s</div>",
      "<div class='sp-years'>%s plants · %s species%s</div>%s",
      "<div class='sp-actions'>",
      "<button class='sp-btn sp-go' onclick=\"smtLoadStart('%s');Shiny.setInputValue('pickSite','%s',{priority:'event'});return false;\">Explore this site &rarr;</button>",
      "<button class='sp-btn sp-info' onclick=\"Shiny.setInputValue('siteInfo','%s',{priority:'event'});return false;\">About this site</button>",
      "</div></div>"),
      esc(st$name), st$site, esc(st_state), esc(st$domain), elev, esc(st$bio),
      st$n_individuals, st$n_species, gtxt, covtxt, esc(gsub("['\"\\\\]", "", st$name)), st$site, st$site)
    lab <- sprintf("<b>%s</b> · %s<br>%s plants%s · tap for details", st$site, esc(st$name), st$n_individuals,
      ifelse(thin, " · thin green-up coverage", ""))
    leaflet::leaflet(st) %>% add_suite_basemap("CartoDB.Positron") %>%
      leaflet::addCircleMarkers(lng=~lng, lat=~lat, radius=~radius, layerId=~site,
        fillColor=pal(gv_col), color=mk_stroke, weight=1, fillOpacity=mk_opacity,
        label=lapply(lab, htmltools::HTML), popup=pop,
        popupOptions=leaflet::popupOptions(className="pm-pop-card", keepInView=FALSE)) %>%
      leaflet::addLegend("bottomright", pal=pal, values=gp_clamp(pal, gv[is.finite(gv)]), title="median green-up DOY", na.label="n/a")
  })
  observe({ updateSelectizeInput(session, "siteSearch", server=TRUE, selected="",
    choices = c("Jump to a site…" = "", stats::setNames(site_table$site,
      sprintf("%s · %s (%s)", site_table$site, site_table$name, site_table$state)))) })
  observeEvent(input$siteSearch, if (nzchar(input$siteSearch %||% "")) {
    session$sendCustomMessage("smtLoadStart", list(label = input$siteSearch)); load_site_full(input$siteSearch) }, ignoreInit=TRUE)

  # ---- "About this site" -> instant info card (no bundle load) -------------
  # The popup's About button sets input$siteInfo. Show a small details card
  # (where it is, what's been recorded) with an Explore footer that hands off to
  # the SAME load path the popup's Explore button uses.
  site_info_modal <- function(code) {
    m   <- neon_sites[neon_sites$site == code, ]
    row <- site_table[site_table$site == code, ]
    if (!nrow(m))
      return(modalDialog(title = "Site info", easyClose = TRUE, footer = modalButton("Close"),
                         p("No details are available for this site.")))
    dash <- function(x) if (length(x) == 0 || is.na(x) || !nzchar(as.character(x))) "n/a" else as.character(x)
    coords <- if (!is.na(m$lat[1]) && !is.na(m$lng[1])) sprintf("%.3f, %.3f", m$lat[1], m$lng[1]) else "n/a"
    n_pl <- if (nrow(row)) suppressWarnings(as.integer(row$n_individuals[1])) else NA_integer_
    n_sp <- if (nrow(row)) suppressWarnings(as.integer(row$n_species[1])) else NA_integer_
    # the green-up stat follows the site's status (a range or a bound is text)
    sg <- site_gu(code)
    gv <- if (sg$found && sg$status %in% c("point", "range", "upper_bound"))
            sub("^day ", "", greenup_label(sg$med, sg$lo, sg$hi, sg$status)) %||% NA else NA
    if (identical(gv, "NA") || length(gv) != 1L) gv <- NA
    stat <- function(v, lab) div(class = "si-stat",
      div(class = "si-stat-n", if (length(v) == 0 || is.na(v)) "n/a" else format(v, big.mark = ",")),
      div(class = "si-stat-l", lab))
    modalDialog(
      title = HTML(sprintf("\U0001F33F %s <span class='si-code'>(%s)</span>", htmltools::htmlEscape(dash(m$name[1])), code)),
      easyClose = TRUE, size = "m",
      footer = tagList(
        modalButton("Close"),
        tags$button(type = "button", class = "btn btn-primary",
          onclick = sprintf("smtLoadStart('%s');Shiny.setInputValue('pickSite','%s',{priority:'event'});",
                            gsub("['\"\\\\<>]", "", dash(m$name[1])), code),
          HTML("Explore this site &rarr;"))),
      div(class = "site-info",
        div(class = "si-sec",
          div(class = "si-h", "Where"),
          div(class = "si-row", dash(m$state[1]), sprintf(" · NEON %s", dash(m$domain[1]))),
          if (!is.na(m$bio[1])) div(class = "si-row si-bio", m$bio[1]),
          div(class = "si-coords", "\U0001F4CD ", coords,
              if (!is.na(m$elevation_m[1])) sprintf(" · %s m", m$elevation_m[1]) else NULL)),
        div(class = "si-sec",
          div(class = "si-h", "What's been recorded"),
          div(class = "si-stats",
            stat(n_pl, "tagged plants"),
            stat(n_sp, "species"),
            stat(gv, "median green-up (day-of-year)")))))
  }
  observeEvent(input$siteInfo, if (nzchar(input$siteInfo %||% "")) showModal(site_info_modal(input$siteInfo)))

  pick_individual <- function(id, navigate=FALSE){ if (is.null(id)||is.na(id)||id=="") return()
    if (is.null(rv$ind_summary) || !(id %in% rv$ind_summary$individualID)) return()
    rv$ind <- id; if (!identical(input$indSel, id)) updateSelectizeInput(session, "indSel", selected=id); if (navigate) nav_select("tabs","profile") }
  observeEvent(input$indSel, if (nzchar(input$indSel %||% "")) pick_individual(input$indSel, navigate=TRUE), ignoreInit=TRUE)
  observeEvent(input$qcCardRequest, if (nzchar(input$qcCardRequest %||% "")) pick_individual(input$qcCardRequest, navigate=TRUE), ignoreInit=TRUE)
  observeEvent(input$surpriseBtn, { req(rv$ind_summary); pick_individual(sample(rv$ind_summary$individualID, 1), navigate=TRUE) })
  observeEvent(input$goClock, nav_select("tabs","clock")); observeEvent(input$goOnset, nav_select("tabs","onset"))
  # route the default pick through pick_individual() so the "Open a plant's
  # profile" picker shows the plant that opens, not its placeholder
  observeEvent(input$goProfile, {
    if (is.null(rv$ind) && !is.null(rv$ind_summary) && nrow(rv$ind_summary)) pick_individual(rv$ind_summary$individualID[1], navigate=TRUE)
    else nav_select("tabs","profile") })
  observeEvent(input$goMap, nav_select("tabs","map"))

  # ---- hero ----
  output$heroStats <- renderUI({
    inds <- rv$inds; req(inds)
    n_sp <- dplyr::n_distinct(species_level_only(inds)$scientificName)
    n_pl <- dplyr::n_distinct(inds$plotID)
    gu <- suppressWarnings(stats::median(rv$ind_summary$greenup, na.rm=TRUE))
    gu_share <- greenup_coverage(rv$ind_summary)
    # static = text shown as-is (no count-up), for a green-up range, bound or n/a
    hero <- function(v,l,suf="",icon,tone,ttl=NULL,static=NULL) div(class=paste0("hero-stat hero-",tone), title=ttl,
      div(class="hs-icon", bs_icon(icon)),
      div(if (!is.null(static)) div(class="hs-v hs-v-static", static)
          else div(class="hs-v count-up", `data-target`=v, `data-suffix`=suf, "0"),
          div(class="hs-l", l)))
    cov <- gu_badge(gu_share, where = "here")
    g <- site_gu(rv$site)
    gu_ttl <- "Typical day-of-year the average plant first breaks leaf, a within-site timing signal pooled across years."
    # thin green-up coverage (same gate as the metric defaults in ingest): the
    # gold tile leads with median leaf-active days; green-up stays in the story
    # with its coverage clause
    thin_gu <- is.finite(gu_share) && gu_share < GU_COVERAGE_FLOOR
    la_lb <- identical(g$la_status, "lower_bound")
    gu_tile <- if (thin_gu && is.finite(g$la)) {
      la_ttl <- sprintf("Median days a plant carries leaves per year, in years visited on the usual schedule. Shown first here because green-up is scored for only %d%% of plants.", round(gu_share * 100))
      if (la_lb) hero(NA, "days carrying leaves (median, lower bound)", icon="sun", tone="gold", ttl=la_ttl,
                      static=sprintf("at least %d", round(g$la)))
      else hero(round(g$la), "days carrying leaves (median)", icon="sun", tone="gold", ttl=la_ttl)
    } else if (!g$found || identical(g$status, "point")) {
      v <- if (g$found && is.finite(g$med)) g$med else gu
      if (is.finite(v)) hero(round(v), "median green-up (day-of-year)", icon="clock-history", tone="gold", ttl=gu_ttl)
      else hero(NA, "median green-up", icon="clock-history", tone="gold", ttl=gu_ttl, static="n/a")
    } else if (identical(g$status, "range") && is.finite(g$lo) && is.finite(g$hi)) {
      hero(NA, "median green-up (day-of-year range)", icon="clock-history", tone="gold", ttl=gu_ttl,
           static=sprintf("%d to %d", round(g$lo), round(g$hi)))
    } else if (identical(g$status, "upper_bound") && is.finite(g$hi)) {
      hero(NA, "median green-up (day-of-year, upper bound)", icon="clock-history", tone="gold", ttl=gu_ttl,
           static=sprintf("%d or earlier", round(g$hi)))
    } else hero(NA, "median green-up", icon="clock-history", tone="gold", ttl=gu_ttl, static="n/a")
    gu_note <- if (!g$found) NULL else switch(g$status,
      range = if (is.finite(g$lo) && is.finite(g$hi)) sprintf("The median lies between day %d and day %d. Each plant's green-up is known only to lie between its last 'no' and first 'yes' visit; onsets underway at the first visit could be earlier. This is not a confidence interval.", round(g$lo), round(g$hi)),
      upper_bound = if (is.finite(g$hi)) sprintf("Most plants were already greening at the first visit, so the true median is day %d or earlier and no single day is shown.", round(g$hi)),
      short_record = short_record_txt(g$n_seasons),
      NULL)
    # the leaf tile leads at thin coverage: when it is a lower bound, say why beside it
    if (thin_gu && is.finite(g$la) && la_lb)
      gu_note <- paste(c(gu_note, sprintf("Many leaf spans here run into the year's first or last visit, so the leaf-active median is %s, not the full leaf period.",
                                         site_la_lab(g))), collapse = " ")
    div(class="hero-band",
      div(class="hero-title",
        bs_icon("flower3"), tags$b(rv$label),
        span(class = "scope-chip scope-site", bs_icon("geo-alt"), rv$site),
        actionLink("changeSite", tagList(bs_icon("arrow-left-circle"), " change site"),
                   class = "hero-change"),
        downloadLink("reportPdf", tagList(bs_icon("file-earmark-pdf"), " report (PDF)"),
                     class = "hero-report"),
        downloadLink("reportCard", tagList(bs_icon("filetype-csv"), " site summary (CSV)"),
                     class = "hero-report")),
      div(class="hero-grid",
        hero(nrow(inds), "tagged plants", icon="flower1", tone="pine"),
        hero(n_sp, "species", icon="tree", tone="navy"),
        hero(n_pl, if (n_pl == 1) "phenology plot" else "phenology plots", icon="geo", tone="terra"),
        gu_tile),
      if (!is.null(cov) || !is.null(gu_note)) div(class="hero-cov-row", cov,
        if (!is.null(gu_note)) tags$p(class="hero-gu-note", gu_note)),
      { rs <- release_short(); if (!is.null(rs)) tags$p(class="hero-release", rs) })
  })
  # #heroStats:empty is display:none (saves phone space before a site loads),
  # and Shiny suspends hidden outputs, so render it while hidden or it would
  # never fill (and never unhide).
  outputOptions(output, "heroStats", suspendWhenHidden = FALSE)


  # ---- Overview ----
  output$formBar <- renderPlotly({
    inds <- rv$inds; req(inds); cb <- comp_by(inds, "growthForm"); cb <- cb[!is.na(cb$growthForm),]
    cb$lab <- factor(cb$growthForm, levels = rev(cb$growthForm))
    plot_ly(cb, x=~n, y=~lab, type="bar", orientation="h", marker=list(color=DDL$green),
      hovertemplate="%{y}<br>%{x} plants<extra></extra>") %>%
      plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE, xaxis=list(title="Tagged plants"), yaxis=list(title=""), margin=list(l=200))
  })
  output$overviewInsight <- renderUI({
    inds <- rv$inds; req(inds); cb <- comp_by(inds, "growthForm"); cb <- cb[!is.na(cb$growthForm),]
    dom <- cb$growthForm[1]; n_sp <- dplyr::n_distinct(species_level_only(inds)$scientificName)
    insight_banner("flower3", tone="pine", HTML(sprintf("This site watches <span class='ci-hero'>%d</span> tagged plants across <b>%d</b> species; the dominant growth form is <b>%s</b> (%d plants).",
      nrow(inds), n_sp, tolower(dom), cb$n[1])))
  })
  output$siteInsights <- renderUI({
    inds <- rv$inds; obs <- rv$obs; req(inds, obs)
    gu <- suppressWarnings(stats::median(rv$ind_summary$greenup, na.rm=TRUE))
    la <- suppressWarnings(stats::median(rv$ind_summary$leaf_active, na.rm=TRUE))
    yrs <- sort(unique(obs$year))
    pts <- c(sprintf("Over <b>%d</b> years (%s), observers logged <b>%s</b> phenophase records on <b>%d</b> tagged plants.",
      length(yrs), paste0(min(yrs),"–",max(yrs)), format(nrow(obs), big.mark=","), nrow(inds)))
    g <- site_gu(rv$site)
    if (g$found) la <- g$la   # the site index median (supported years); NA for a short record
    la_lb <- g$found && identical(g$la_status, "lower_bound")
    # leaf-active phrase via leaf_label(): "about N days" or "at least N days"
    la_words <- if (!is.finite(la)) NULL else if (la_lb) sprintf("at least <b>%d</b> days", round(la)) else sprintf("about <b>%d</b> days", round(la))
    la_txt <- if (!is.null(la_words)) sprintf(" and carries leaves %s a year", la_words) else ""
    # the green-up date phrase for the site's estimand status (NULL when none)
    gu_phrase <- if (!g$found) {
      if (is.finite(gu)) sprintf("around <b>%s</b> (day %d)", doy_to_month(gu), round(gu))
    } else switch(g$status,
      point = if (is.finite(g$med)) sprintf("around <b>%s</b> (day %d)", doy_to_month(g$med), round(g$med)),
      range = if (is.finite(g$lo) && is.finite(g$hi)) sprintf("between <b>%s</b> and <b>%s</b> (day %d to %d)",
        doy_to_month(g$lo), doy_to_month(g$hi), round(g$lo), round(g$hi)),
      upper_bound = if (is.finite(g$hi)) sprintf("by <b>%s</b> or earlier (day %d or earlier)", doy_to_month(g$hi), round(g$hi)),
      NULL)
    # thin green-up coverage: lead with leaf-active days, keep green-up with its
    # coverage clause (same gate as the hero tile and the metric defaults)
    gu_share <- greenup_coverage(rv$ind_summary)
    thin_gu <- is.finite(gu_share) && gu_share < GU_COVERAGE_FLOOR
    gu_txt <- if (g$found && identical(g$status, "short_record")) short_record_txt(g$n_seasons)
      else if (thin_gu && is.finite(la)) {
        paste0(sprintf("The typical plant carries leaves %s a year.", la_words),
          if (!is.null(gu_phrase)) sprintf(" Green-up is scored for only <b>%d%%</b> of plants here; among those, the typical plant greens up %s.", round(gu_share * 100), gu_phrase)
          else sprintf(" Green-up is scored for only <b>%d%%</b> of plants here.", round(gu_share * 100)))
      } else if (!is.null(gu_phrase)) sprintf("The typical plant greens up %s%s.", gu_phrase, la_txt)
      else NULL
    if (!is.null(gu_txt)) pts <- c(pts, gu_txt)
    if (!is.null(gu_txt) && is.finite(la) && la_lb)
      pts <- c(pts, sprintf("Leaf-active days here are a lower bound: %s of leaf plant-years run into the year's first or last visit, and the visits allow up to %s days. Read %s as the shortest the leaf period could be, not its full length.",
        if (is.finite(g$la_edge)) sprintf("%d%%", round(g$la_edge * 100)) else "many",
        if (is.finite(g$la_hi)) round(g$la_hi) else "more", site_la_lab(g)))
    { ut <- uncertain_txt(g); if (!is.null(ut)) pts <- c(pts, ut) }
    # growth-form list as a plural phrase: Forb -> forbs, Graminoid -> graminoids,
    # anything else -> "<form> plants" (semi-evergreen broadleaf plants)
    forms_phrase <- function(x) {
      fm <- tolower(trimws(strsplit(x, ";", fixed = TRUE)[[1]])); fm <- fm[nzchar(fm)]
      fm <- ifelse(fm %in% c("forb", "graminoid"), paste0(fm, "s"), paste(fm, "plants"))
      if (length(fm) > 1) paste(paste(fm[-length(fm)], collapse = ", "), "and", fm[length(fm)]) else fm
    }
    if (g$found && !is.na(g$forms) && nzchar(g$forms))
      pts <- c(pts, sprintf("Here %s sprout with autumn rain, so they have no calendar-year green-up; read leaf-active days for them.", forms_phrase(g$forms)))
    if (g$found && !is.na(g$carry_forms) && nzchar(g$carry_forms))
      pts <- c(pts, sprintf("Here %s are still green at the turn of the year in most years, so they have no calendar-year green-up; read leaf-active days for them.", forms_phrase(g$carry_forms)))
    if (g$found && is.finite(g$fallback) && g$fallback > 0)
      pts <- c(pts, "Drought-deciduous shrubs count their first new 'Young leaves' of the year as green-up.")
    pts <- c(pts, "Phenology is recorded on a <b>fixed roster of tagged individuals</b> along transects. It captures <b>timing</b> (when each phenophase happens), not abundance. Open the Phenology Clock to see the year unfold.")
    # one span per item, so the bold runs stay inline instead of each becoming a flex column
    div(class="insight-list", lapply(pts, function(t) div(class="il-item", bs_icon("dot"), span(HTML(t)))))
  })

  # ---- Phenology Clock (flagship) ----
  # COVERAGE-CONDITIONAL EMPHASIS. At thin-coverage desert sites (gu_share <
  # GU_COVERAGE_FLOOR) the green-up petals (Breaking leaf buds / Initial growth)
  # rest on a small, non-random subset, so we visually DE-EMPHASIZE them (dashed,
  # thin, faint fill) and lead with the leaf-presence ring, which spans the whole
  # roster. Pure caption + emphasis over the existing weekly_yesrate output — NO
  # new computation, and every petal still draws (nothing is dropped).
  output$clockPlot <- renderPlotly({
    obs <- rv$obs; req(obs); sci <- if (nzchar(input$clockSp %||% "")) input$clockSp else NULL
    wk <- weekly_yesrate(obs, sci); if (is.null(wk) || !nrow(wk)) return(note_plot("No phenophase records for that selection"))
    leaf_lead <- { gs <- greenup_coverage(rv$ind_summary); is.finite(gs) && gs < GU_COVERAGE_FLOOR }
    phs <- names(sort(PHENO_RANK[intersect(names(PHENO_RANK), unique(wk$phenophaseName))]))
    phs <- c(phs, setdiff(unique(wk$phenophaseName), phs))   # any unranked appended
    full <- data.frame(week = 1:52)
    # map a week to the ANGLE of its CENTRE day-of-year, on the SAME /365 scale as
    # the month ticks below — otherwise petals (a /52 scale) drift 3-6 days off the
    # month labels (a /365 scale) by year's end. Centre = (w-1)*7 + 3.5.
    theta_of <- function(w) ((w - 1) * 7 + 3.5) / 365 * 360
    p <- plotly::plot_ly()
    for (pn in phs) {
      d <- wk[wk$phenophaseName == pn, c("week","rate","n")]
      m <- merge(full, d, by="week", all.x=TRUE); m$rate[is.na(m$rate)] <- 0; m$n[is.na(m$n)] <- 0
      m <- m[order(m$week),]
      th <- theta_of(m$week); r <- m$rate; nn <- m$n
      th <- c(th, th[1] + 360); r <- c(r, r[1]); nn <- c(nn, nn[1])   # close the ring at +360, not back to 0
      col <- COL_OF_PHENO(pn)
      # at thin coverage, mute the green-up petals (dashed/thin/faint) and bring the
      # leaf-presence ring forward (solid, bolder, brighter fill).
      is_gu   <- pn %in% GREENUP
      is_leaf <- identical(pn, "Leaves")
      if (leaf_lead && is_gu) { ln <- list(color = col, width = 1, dash = "dot"); fa <- 0.06; nm <- paste0(pn, " (thin coverage)") }
      else if (leaf_lead && is_leaf) { ln <- list(color = col, width = 3.4); fa <- 0.34; nm <- paste0(pn, ", desert-safe read") }
      else { ln <- list(color = col, width = 2); fa <- 0.22; nm <- pn }
      p <- p %>% plotly::add_trace(type="scatterpolar", mode="lines", name=nm,
        r = r, theta = th, fill = "toself",
        fillcolor = grDevices::adjustcolor(col, alpha.f = fa), line = ln,
        customdata = nn,
        hovertemplate = paste0(pn, "<br>%{r:.0f}% of scored plant-years 'yes'<br>%{customdata} plant-year opportunities<extra></extra>"))
    }
    ink <- if (is_dark()) "#e8eef2" else "#1f2a30"; grid <- if (is_dark()) "rgba(220,230,240,0.20)" else "rgba(31,42,48,0.12)"
    muted <- if (is_dark()) "#9fb0c4" else "#6b7a85"
    mo_theta <- (c(1,32,60,91,121,152,182,213,244,274,305,335) - 1)/365*360
    scope <- sprintf("%s · %% of scored plant-years 'yes', by week · typical-year pool%s",
      rv$ctx %||% "", if (is.null(sci)) " · all species (mixes evergreen, deciduous & forb leaf calendars; pick a species to read timing)" else paste0(" · ", sci))
    anns <- list(list(text = scope, x = 0, y = if (leaf_lead) 1.18 else 1.10, xref = "paper", yref = "paper",
        showarrow = FALSE, xanchor = "left", font = list(color = muted, size = 10.5)))
    if (leaf_lead) {
      gpct <- round(greenup_coverage(rv$ind_summary) * 100)
      anns <- c(anns, list(list(
        text = sprintf("green-up scored for %d%% of plants here; the bold leaf-presence ring is the desert-safe read", gpct),
        x = 0, y = 1.07, xref = "paper", yref = "paper", showarrow = FALSE, xanchor = "left",
        font = list(color = "#b5481f", size = 10.5))))
    }
    p %>% plotly::layout(
      font = list(color = ink, family = "Rubik"), paper_bgcolor="rgba(0,0,0,0)",
      polar = list(bgcolor = "rgba(0,0,0,0)",
        radialaxis = list(ticksuffix = "%", angle = 90, gridcolor = grid, tickfont = list(size = 9, color = ink), range = c(0, 100)),
        angularaxis = list(rotation = 90, direction = "clockwise", gridcolor = grid,
          tickmode = "array", tickvals = mo_theta, ticktext = month.abb, tickfont = list(size = 10, color = ink))),
      legend = list(orientation = "h", y = -0.12, font = list(color = ink)),
      annotations = anns,
      margin = list(l = 30, r = 30, t = if (leaf_lead) 78 else 42, b = 30)) %>%
      plotly::config(displayModeBar = FALSE, responsive = TRUE)
  })
  # clickable green-up-coverage disclosure beside the clock — reuses gu_badge, so
  # it is clean (absent) at forest sites and only appears at thin-coverage deserts.
  output$clockCoverage <- renderUI({
    req(rv$ind_summary); cov <- gu_badge(greenup_coverage(rv$ind_summary), where = "here")
    if (is.null(cov)) return(NULL)
    div(class = "map-cov-row", cov)
  })
  output$trendPlot <- renderPlotly({
    metric <- input$trendMetric %||% "greenup"
    tr <- if (metric == "leaf_active") rv$la_trend else rv$trend
    if (is.null(tr) || !nrow(tr)) return(note_plot(
      if (metric == "leaf_active") "Not enough plants per year for a leaf-active trend" else "Not enough plants per year for an onset trend"))
    lf <- metric == "leaf_active"
    yttl <- if (lf) "Leaf-active days per year" else "Green-up onset (day-of-year)"
    # hollow points (trend_hollow): a bound, not a value, so drawn open and left
    # out of the banner's fit; the hover says which bound and why (iris wording)
    tr$hollow <- trend_hollow(tr)
    tr$hov <- ifelse(tr$hollow,
      if (lf) sprintf("at least %d days: these spans run into the year's first or last visit; left out of the trend", as.integer(round(tr$onset)))
      else sprintf("day %d or earlier: most plants were already greening at the first visit; left out of the trend", as.integer(round(tr$onset))),
      if (lf) sprintf("%d leaf-active days", as.integer(round(tr$onset))) else sprintf("green-up day %d", as.integer(round(tr$onset))))
    n_all <- dplyr::n_distinct(tr$scientificName)
    top <- names(sort(table(tr$scientificName), decreasing=TRUE)); top <- head(top, 8)
    tr <- tr[tr$scientificName %in% top,]
    pal <- make_species_pal(tr); col_of <- function(s) pal[[s]] %||% OTHER_GREY
    p <- plotly::plot_ly()
    for (s in unique(tr$scientificName)) { d <- tr[tr$scientificName==s,]; d <- d[order(d$year),]
      p <- p %>% plotly::add_trace(data=d, x=~year, y=~onset, type="scatter", mode="lines+markers", name=s,
        text=~hov, line=list(color=col_of(s), width=2),
        marker=list(color=ifelse(d$hollow, "rgba(0,0,0,0)", col_of(s)), size=ifelse(d$hollow, 9, 7),
                    symbol=ifelse(d$hollow, "circle-open", "circle"), line=list(color=col_of(s), width=1.6)),
        hovertemplate=paste0("<b>",s,"</b><br>%{x}: %{text}<extra></extra>")) }
    note <- if (n_all > 8) list(list(text=sprintf("showing the 8 most-monitored of %d species (the banner above pools all %d)", n_all, n_all),
      x=0, y=1.06, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", font=list(size=10.5, color="#8a988f"))) else list()
    if (any(tr$hollow)) note <- c(note, list(list(
      text = if (lf) "open circles: at least that many days (spans run into the year's first or last visit); left out of the trend"
             else "open circles: that day or earlier (most plants already greening at the first visit); left out of the trend",
      x = 0, y = 1.06 + 0.06 * length(note), xref = "paper", yref = "paper", showarrow = FALSE, xanchor = "left",
      font = list(size = 10.5, color = "#8a988f"))))
    # name the reduced-visit years the trend leaves out (2020 COVID cut, partial
    # first years), so a gap in the line reads as missing effort, not biology
    sup_col <- if (metric == "leaf_active") "leaf_supported" else "greenup_supported"
    gone <- if (!is.null(rv$support) && sup_col %in% names(rv$support)) rv$support$year[!rv$support[[sup_col]]] else integer(0)
    if (length(gone)) note <- c(note, list(list(
      text = sprintf("left out, visited less than usual or started late after the %s was already underway: %s",
                     if (metric == "leaf_active") "leaf season" else "green-up", paste(gone, collapse = ", ")),
      x = 0, y = 1.06 + 0.06 * length(note), xref = "paper", yref = "paper", showarrow = FALSE, xanchor = "left",
      font = list(size = 10.5, color = "#8a988f"))))
    p %>% plotly_theme() %>% plotly::layout(xaxis=list(title="Year", dtick=1), yaxis=list(title=yttl),
      legend=list(font=list(size=9)), annotations=note,
      margin=list(l=55, r=30, t=max(48, 30 + 20 * length(note)), b=44))
  })
  output$trendInsight <- renderUI({
    metric <- input$trendMetric %||% "greenup"
    lf <- metric == "leaf_active"
    tr <- if (lf) rv$la_trend else rv$trend
    noun <- if (lf) "leaf-active days" else "green-up"
    sup <- rv$support
    if (!is.null(sup) && nrow(sup) && "greenup_reason" %in% names(sup) && all(sup$greenup_reason %in% "short_record"))
      return(insight_banner("hourglass-split", tone = "navy",
        "Too few seasons monitored here to check the visit schedule, so no trend is drawn."))
    # green-up too-thin nudge: when green-up has no/short series here but the
    # leaf-active trend does, point the desert user to the metric that works.
    if (!lf && (is.null(tr) || nrow(tr) < 3) && !is.null(rv$la_trend) && nrow(rv$la_trend) >= 3) {
      lay <- rv$la_trend %>% dplyr::group_by(.data$year) %>% dplyr::summarise(o = stats::median(.data$onset), .groups="drop")
      if (nrow(lay) >= TREND_MIN_YEARS) return(insight_banner("arrow-right-circle", tone = "gold",
        HTML("Green-up is scored for too few plants here to fit a trend. Switch <b>Show</b> to <b>Leaf-active days</b> for a longer, desert-safe series.")))
    }
    req(!is.null(tr) && nrow(tr) >= 3)
    # trend_verdict(): fit A over the solid points only (hollow points are bounds,
    # not values), checked against fit B over every point. Report days/YEAR with
    # fit A's 95% interval; never extrapolate to "per decade".
    v <- trend_verdict(tr)
    left_txt <- function(n) if (n > 0) sprintf(" %d species-year point%s %s left out as %s.", n, if (n == 1) "" else "s", if (n == 1) "is" else "are",
      if (lf) "lower bounds (spans that run into the year's first or last visit)" else "upper bounds (most plants already greening at the first visit)") else ""
    caveat <- if (lf) "<em>Descriptive and composition-sensitive: it is not a site-wide season-length estimate.</em>"
              else "<em>Descriptive and composition-sensitive: it is not a causal or site-wide population trend.</em>"
    if (identical(v$verdict, "too_short")) return(insight_banner("hourglass-split", tone = "navy",
      HTML(sprintf("Only <b>%d</b> year%s of %s have a solid annual median here. Too short to fit a trend: phenology shifts need about %d or more years before a slope means anything.%s",
        v$ny, if (v$ny == 1) "" else "s", noun, TREND_MIN_YEARS, left_txt(v$n_left_out)))))
    if (identical(v$verdict, "none")) return(insight_banner("dash-circle", tone = "navy",
      HTML(sprintf("Across <b>%d</b> annual medians, the monitored-species %s summary shows <b>no detectable linear shift</b> (%.1f days/yr, 95%% interval %.1f to %.1f, spans zero).%s The roster and species mix can change among years.",
        v$ny, noun, v$slope, v$lo, v$hi, left_txt(v$n_left_out)))))
    if (identical(v$verdict, "depends")) return(insight_banner("question-circle", tone = "navy",
      HTML(sprintf("The direction here depends on how the left-out points are treated. Without them the monitored-species %s summary changes %.1f days/yr (95%% interval %.1f to %.1f across <b>%d</b> annual medians); with every point as recorded the fit does not agree, so no direction is claimed.%s",
        noun, v$slope, v$lo, v$hi, v$ny, left_txt(v$n_left_out)))))
    up <- identical(v$verdict, "up")
    dir <- if (lf) (if (up) "longer" else "shorter") else (if (up) "later" else "earlier")
    good <- if (lf) up else !up
    insight_banner(if (up) "arrow-up-right" else "arrow-down-right", tone = if (good) "pine" else "gold",
      HTML(sprintf("Across <b>%d</b> annual medians, the monitored-species %s summary changed <b>%.1f days/year %s</b> (95%% interval %.1f to %.1f).%s %s",
        v$ny, if (lf) "leaf-active" else "green-up", abs(v$slope), dir, v$lo, v$hi, left_txt(v$n_left_out), caveat)))
  })

  # Onset Lab coverage note — when green-up is scored for few plants, the X axis
  # (green-up onset) places only a biased fifth of the roster; point users to the
  # Y axis (leaf-active days), which spans the whole roster. Clickable, clean by
  # default (absent at forest sites).
  output$onsetCoverage <- renderUI({
    req(rv$ind_summary); cov <- gu_badge(greenup_coverage(rv$ind_summary), where = "here")
    if (is.null(cov)) return(NULL)
    div(class = "map-cov-row", cov)   # guidance ("read leaf-active") lives in the badge popover — nothing always-on
  })

  # ---- Onset Lab (flagship pinnable board) ----
  # COVERAGE-CONDITIONAL X axis. Green-up onset is only scored for a fraction of a
  # warm-desert roster (SRER ~19%), so the old hard `is.finite(greenup) &
  # is.finite(leaf_active)` gate silently dropped ~80% of tagged plants and broke
  # the badge's "switch the metric on the Onset Lab" promise. When the site's
  # green-up coverage is thin (gu_share < GU_COVERAGE_FLOOR) we place every plant
  # with a finite leaf_active and put DAYS CARRYING LEAVES (leaf_active, already
  # computed by key_onsets — NOT a new estimator) on the X axis, so the whole
  # desert roster shows. Where green-up coverage is good (forests), the existing
  # green-up × leaf-active board is unchanged.
  output$onsetBoard <- renderPlotly({
    is_ <- rv$ind_summary; req(is_)
    gu_share <- greenup_coverage(is_)
    leaf_mode <- is.finite(gu_share) && gu_share < GU_COVERAGE_FLOOR
    if (leaf_mode) {
      d <- is_[is.finite(is_$leaf_active), , drop=FALSE]
      xcol <- "leaf_active"; xttl <- "Days carrying leaves per year · briefer ← → longer"
    } else {
      d <- is_[is.finite(is_$greenup) & is.finite(is_$leaf_active), , drop=FALSE]
      xcol <- "greenup"; xttl <- "Green-up onset (day-of-year) · earlier ← → later"
    }
    n_total <- nrow(is_); n_placed <- nrow(d)
    g <- site_gu(rv$site)
    if (!n_placed && identical(g$status, "short_record")) return(note_plot(sprintf(
      "Too few seasons monitored here (%s) to place plants.<br>The Phenology Clock and Plant Profile still show every record.",
      if (is.finite(g$n_seasons)) as.integer(g$n_seasons) else "under three")))
    if (!n_placed) return(note_plot(if (leaf_mode) "No plants yet have any leaf-active days recorded"
                                    else "No plants yet have both leaf-out and leaf-active days recorded"))
    # generic placement vars so all the downstream machinery (colour-by, pins,
    # quadrants, viewing diamond) is metric-agnostic. In leaf mode Y is years
    # watched (n_years, already computed), so the desert board still has a real
    # second axis instead of a single leaf-active column on a flat line.
    d$xv <- d[[xcol]]
    if (leaf_mode) { d$yv <- d$n_years; yttl <- "Years watched · fewer ↓ ↑ more" }
    else           { d$yv <- d$leaf_active; yttl <- "Days carrying leaves per year · briefer ↓ ↑ longer" }
    # Colour-by capped to the 8 most-monitored categories + an explicit grey
    # "Other" — interpolating Dark2 across ~20 species made muddy, look-alike
    # olives. Growth form (<=8 categories) is the default and is unaffected.
    cby <- input$onsetColor %||% "growthForm"
    lv <- ordered_levels(d, cby)
    d$grp <- cap_groups(d[[cby]], lv, cap = 8L)
    pal <- capped_pal(lv, cap = 8L)
    grps <- intersect(c(utils::head(lv, 8L), "Other"), unique(d$grp))   # keep frequency order; Other last
    gu_tip <- ifelse(is.finite(d$greenup), paste0("green-up ", plant_gu_lab(d), " (", vapply(d$greenup, doy_to_month, ""), ")"),
                     "<span style='color:#b5481f'>no green-up phase in a fully visited year</span>")
    # leaf-active label per plant: "N days" or "at least N days" (lower bound)
    d$la_lb <- plant_la_lb(d)
    la_tip <- paste0("carries leaves ", plant_la_lab(d, unit = "days/yr"))
    # NEON-sourced strings reach the pin card's innerHTML, so escape them
    esc <- function(x) htmltools::htmlEscape(ifelse(is.na(x), "", as.character(x)))
    d$tip <- paste0("<span class='smt-pin-emoji'>\U0001F33F</span> <b>", esc(d$scientificName), "</b><br/>",
      "<em>", esc(d$growthForm), " · plot ", esc(short_plot(d$plotID)), "</em><br/>",
      "<span class='smt-pin-stats'>", gu_tip, "<br/>",
      la_tip,
      ifelse(is.finite(d$flower), paste0(" · flowers day ", d$flower), ""), "<br/>",
      d$n_years, " yr watched (any metric)</span>",
      "<br/><span class='smt-open' role='button' tabindex='0' data-tag='", htmltools::htmlEscape(d$individualID, attribute = TRUE), "'>\U0001F50E Open plant profile &rarr;</span>",
      "<br/><em class='smt-pin-hint'>Tap the dot to pin this card</em>")
    qcol <- if (is_dark()) "#7e8da0" else "#9aa6b2"; muted <- if (is_dark()) "#9fb0c4" else "#6b7a85"
    # hover reads the same labels as the pin card (bounds stay bounds)
    d$hov <- if (leaf_mode) paste0(htmltools::htmlEscape(d$scientificName), "<br>", la_tip, " · ", d$n_years, " yr watched")
             else paste0(htmltools::htmlEscape(d$scientificName), "<br>green-up ", plant_gu_lab(d), " · ", la_tip)
    d$hov <- ifelse(d$la_lb, paste0(d$hov, "<br>open marker: leaf spans run into the year's first or last visit"), d$hov)
    htmpl <- "%{text}<extra></extra>"
    p <- plotly::plot_ly()
    for (g in grps) { sub <- d[d$grp==g,]
      p <- p %>% plotly::add_trace(data=sub, x=~xv, y=~yv, type="scatter", mode="markers", name=g,
        customdata=~tip, marker=list(color=ifelse(sub$la_lb, "rgba(0,0,0,0)", pal[[g]] %||% OTHER_GREY), size=11, opacity=0.82,
                                     symbol=ifelse(sub$la_lb, "circle-open", "circle"),
                                     line=list(color=ifelse(sub$la_lb, pal[[g]] %||% OTHER_GREY, "#fff"), width=ifelse(sub$la_lb, 1.8, 0.5))),
        text=~hov, hovertemplate=htmpl) }
    xr <- range(d$xv); yr <- range(d$yv)
    capt <- if (leaf_mode)
      sprintf("green-up scored for only %d%% of plants here, so this board places by DAYS CARRYING LEAVES · each dot is a plant · %d of %d plants placeable (any leaf-active days)", round(gu_share*100), n_placed, n_total)
    else
      sprintf("each dot is a plant · green-up onset × days carrying leaves · %d of %d plants placeable (both recorded)", n_placed, n_total)
    if (any(d$la_lb)) capt <- paste0(capt, " · open dots: at least that many leaf days")
    ann <- list(list(text=capt, x=0, y=1.07, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", font=list(color=muted, size=11)))
    shp <- list()
    # only draw quadrant labels + median crosshair when there are enough plants
    # AND real spread on both axes — otherwise a 1-3 plant site stacks all four
    # labels on one point and the crosshair is meaningless.
    if (n_placed >= 4 && diff(xr) > 0 && diff(yr) > 0) {
      mx <- stats::median(d$xv); my <- stats::median(d$yv)
      px <- diff(xr)*0.02; py <- diff(yr)*0.02
      qlab <- function(x,y,t,xa,ya) list(text=t, x=x, y=y, xref="x", yref="y", showarrow=FALSE, xanchor=xa, yanchor=ya, font=list(color=qcol, size=10.5))
      ql <- if (leaf_mode)
        list(tl="BRIEF, LONG-WATCHED", tr="LONG-LEAVED, LONG-WATCHED", bl="BRIEF, NEW", br="LONG-LEAVED, NEW")
      else
        list(tl="EARLY & LONG-LEAVED", tr="LATE RISER, LONG-LEAVED", bl="EARLY & BRIEF", br="LATE & BRIEF")
      ann <- c(ann, list(
        qlab(xr[1]+px, yr[2]-py, ql$tl, "left", "top"),
        qlab(xr[2]-px, yr[2]-py, ql$tr, "right", "top"),
        qlab(xr[1]+px, yr[1]+py, ql$bl, "left", "bottom"),
        qlab(xr[2]-px, yr[1]+py, ql$br, "right", "bottom")))
      shp <- list(list(type="line", xref="x", yref="paper", x0=mx, x1=mx, y0=0, y1=1, line=list(color=qcol, dash="dot", width=1)),
                  list(type="line", xref="paper", yref="y", x0=0, x1=1, y0=my, y1=my, line=list(color=qcol, dash="dot", width=1)))
    }
    if (!is.null(rv$ind)) { ir <- d[d$individualID == rv$ind, ]
      if (nrow(ir)==1) p <- p %>% plotly::add_trace(x=ir$xv, y=ir$yv, type="scatter", mode="markers", name="★ viewing", customdata=ir$tip, showlegend=TRUE,
        marker=list(symbol="diamond", size=18, color="#d98014", line=list(color="#fff", width=1.6)), hovertemplate=paste0("viewing ", ir$scientificName, "<extra></extra>")) }
    p %>% plotly_theme() %>% plotly::layout(xaxis=list(title=xttl), yaxis=list(title=yttl),
      shapes=shp, annotations=ann, hovermode="closest")
  })
  output$indCardSlot <- renderUI({
    if (is.null(rv$ind)) return(div(class="qc-empty", div(class="qc-empty-icon","\U0001F33F"), h4("Tap a plant to see its card"),
      p("Tap a dot above and choose “Open plant profile”, or pick a plant from “Open a plant's profile” above the tabs.")))
    r <- rv$ind_summary[rv$ind_summary$individualID == rv$ind,]; if (!nrow(r)) return(NULL)
    div(class="lab-sel", span(class="ls-emoji","\U0001F50E"),
      div(class="ls-body", div(class="ls-id", tags$b(r$scientificName), sprintf(" · green-up %s · carries leaves %s",
        plant_gu_lab(r), plant_la_lab(r, unit = "d/yr"))),
        div(class="ls-dom", em(sprintf("%s · plot %s", r$growthForm, short_plot(r$plotID))))),
      actionButton("goProfFromCard", tagList(bs_icon("arrows-fullscreen"), " Open full profile"), class="btn-outline-dark btn-sm"))
  })
  observeEvent(input$goProfFromCard, nav_select("tabs","profile"))

  # ---- Plant Profile (downloadable career card) ----
  output$phenoSpark <- renderPlotly({
    id <- rv$ind; req(id); h <- indiv_history(rv$obs, id); if (is.null(h)) return(note_plot("No records for this plant"))
    yes <- h[h$status == "yes" & is.finite(h$dayOfYear),]; if (!nrow(yes)) return(note_plot("No phenophase recorded 'yes' yet"))
    phs <- names(sort(PHENO_RANK[intersect(names(PHENO_RANK), unique(yes$phenophaseName))], decreasing=TRUE))
    phs <- c(setdiff(unique(yes$phenophaseName), phs), phs)
    yes$phenophaseName <- factor(yes$phenophaseName, levels = phs)
    p <- plotly::plot_ly()
    for (pn in levels(yes$phenophaseName)) { sub <- yes[yes$phenophaseName==pn,]; if (!nrow(sub)) next
      p <- p %>% plotly::add_trace(data=sub, x=~dayOfYear, y=~phenophaseName, type="scatter", mode="markers", name=pn,
        marker=list(color=COL_OF_PHENO(pn), size=9, opacity=0.7, line=list(color="#fff", width=0.5)),
        text=~paste0(year), hovertemplate=paste0(pn, "<br>%{text} · day %{x}<extra></extra>"), showlegend=FALSE) }
    mo_doy <- c(1,32,60,91,121,152,182,213,244,274,305,335)
    p %>% plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE,
      xaxis=list(title="Day of year", range=c(0,366), tickmode="array", tickvals=mo_doy, ticktext=month.abb, tickfont=list(size=9)),
      yaxis=list(title=""), margin=list(l=140,r=15,t=10,b=36))
  })
  output$plantProfile <- renderUI({
    if (is.null(rv$ind)) return(div(class="qc-empty", div(class="qc-empty-icon","\U0001F33F"), h4("Pick a plant to open its profile"),
      p("Use the Onset Lab (tap a dot → “Open plant profile”) or the “Open a plant's profile” picker above the tabs.")))
    r <- rv$ind_summary[rv$ind_summary$individualID == rv$ind,]; req(nrow(r)==1)
    h <- indiv_history(rv$obs, rv$ind); q <- pheno_qc_flags(h, r$growthForm); flags <- q$flags
    n_ph <- if (!is.null(h)) dplyr::n_distinct(h$phenophaseName[h$status=="yes"]) else 0
    n_yr <- if (!is.null(h)) dplyr::n_distinct(h$year) else 0
    tile <- function(v,l) div(class="qc-tile", div(class="qc-tile-v", v), div(class="qc-tile-l", l))
    # day-of-year tile that shows the calendar date in its label (no bare DOY)
    gtile <- function(v,l) tile(ifelse(is.finite(v), v, "n/a"), if (is.finite(v)) paste0(l, " · ", doy_to_month(v)) else l)
    # only flags whose offending rows were actually found are clickable; a 0-row
    # flag (e.g. the "no yes recorded" info note) is shown but not a link.
    has_problem <- any(vapply(flags, function(f) f$level %in% c("high","warn") && f$n > 0, logical(1)))
    qc_icon <- function(lvl) switch(lvl, high="exclamation-octagon-fill", warn="exclamation-triangle-fill", "info-circle-fill")
    flag_items <- lapply(flags, function(f) {
      clickable <- isTRUE(f$n > 0) && f$key %in% names(q$sets)
      div(class = paste0("qc-flag qc-flag-", f$level, if (clickable) " qc-flag-click" else ""),
        role = if (clickable) "button" else NULL, tabindex = if (clickable) "0" else NULL,
        `aria-label` = if (clickable) f$title else NULL,
        onclick = if (clickable) sprintf("Shiny.setInputValue('pheQcInspect','%s',{priority:'event'})", f$key) else NULL,
        bs_icon(qc_icon(f$level)),
        div(class="qcf-body",
          div(class="qcf-title", f$title, if (clickable) tags$span(class="qcf-n", f$n)),
          div(class="qcf-detail", HTML(f$text))),
        if (clickable) tags$span(class="qcf-go", bs_icon("chevron-right")))
    })
    flag_ui <- if (!has_problem) c(list(div(class="qc-flag qc-flag-ok", bs_icon("check-circle-fill"),
      div(class="qcf-body", div(class="qcf-title","No phenophase-ordering issues detected for this plant"),
        div(class="qcf-detail","Leaf-stage order, green-up consistency, and censoring all look fine, nothing to verify.")))), flag_items) else flag_items
    body <- div(id="qcCardNode", class="qc-card", `data-short`=gsub("[^A-Za-z]","",substr(r$scientificName,1,20)),
      div(class="qc-head", span(class="qc-emoji","\U0001F33F"),
        div(div(class="qc-id", r$scientificName), div(class="qc-sci", em(sprintf("%s · %s · plot %s",
          r$growthForm, switch(as.character(r$nativeStatusCode), "N"="native", "I"="introduced", "NI"="native & introduced", as.character(r$nativeStatusCode) %||% "n/a"), short_plot(r$plotID))))),
        div(class="qc-head-badges", glow_badge(paste0(short_ind(r$individualID)), DDL$green))),
      div(class="qc-tiles",
        { gub <- plant_gu_ub(r)
          tile(if (is.finite(r$greenup)) (if (gub) sprintf("day %d or earlier", as.integer(r$greenup)) else r$greenup) else "n/a",
               if (is.finite(r$greenup)) paste0("green-up · ", doy_to_month(r$greenup), if (gub) " or earlier" else "") else "green-up") },
        gtile(r$flower, "first flower"),
        gtile(r$leaf_off, "last leaf-week"),
        tile(if (!is.finite(r$leaf_active)) "n/a" else if (plant_la_lb(r)) sprintf("at least %dd", as.integer(r$leaf_active)) else paste0(r$leaf_active, "d"),
             "days carrying leaves"),
        tile(n_yr, "years watched"), tile(n_ph, "phenophases")),
      div(class="qc-section-h", bs_icon("calendar3-range"), " Phenophase calendar · when each phase happens"),
      plotlyOutput("phenoSpark", height="240px"),
      div(class="qc-section-h", bs_icon("clipboard-check"), " Quality checks ",
        tags$span(class="qcf-sub", "· verify, not errors")),
      div(class="qc-flags", flag_ui),
      if (has_problem) div(class="qcf-hint", bs_icon("hand-index-thumb"), " tap a flag to list the exact records behind it"),
      if (is.finite(r$greenup) && plant_gu_ub(r))
        p(class="qc-cap-note", style="margin-top:8px", bs_icon("info-circle"),
          sprintf(" In at least half of this plant's years it was already greening at the first visit, so its green-up is day %d or earlier, not a single day.", as.integer(r$greenup))),
      if (is.finite(r$leaf_active) && plant_la_lb(r))
        p(class="qc-cap-note", style="margin-top:8px", bs_icon("info-circle"),
          sprintf(" This plant's leaf spans run into the year's first or last visit, so %d days is the shortest its leaf period could be, not its full length.", as.integer(r$leaf_active))),
      if (identical(as.character(r$growthForm), "Drought deciduous broadleaf"))
        p(class="qc-cap-note", style="margin-top:8px", bs_icon("info-circle"),
          " This shrub's green-up is its first 'Young leaves' after a 'no' this year, a slightly later stage than tree bud-break; leaves carried over from December are not a new green-up."),
      p(class="qc-cap-note", style="margin-top:8px", bs_icon("info-circle"),
        HTML(" Onset dates are interval-censored to the midpoint between the last 'no' and first 'yes' observation, then taken as the median across monitored years. <b>Last leaf-week</b> is the last week leaves were recorded, not measured senescence (a plant that flushes twice a year carries no single leaf-off date), so read <b>days carrying leaves</b> for growing extent: they are summed over each run of leafy visits, midpoint to midpoint, in fully visited years.")))
    div(div(class="plot-profile-wrap", body), div(class="qc-toolbar",
      tags$button(class="smt-snap-btn", type="button", onclick="smtSaveQcCard()", bsicons::bs_icon("download"), " Save plant card (PNG)"),
      downloadButton("indCsv", "Download history (CSV)", class="smt-clear-btn"),
      if (length(q$sets)) downloadButton("qcReportCsv", "Download QC report (CSV)", class="smt-clear-btn")),
      uiOutput("pheQcInspector"))
  })

  # ---- clickable QC inspector: the exact rows behind a tapped flag --------
  pheQc <- reactive({ req(rv$ind); h <- indiv_history(rv$obs, rv$ind)
    r <- rv$ind_summary[rv$ind_summary$individualID == rv$ind, ]
    gf <- if (nrow(r)) r$growthForm[1] else NULL
    list(hist = h, gf = gf, q = pheno_qc_flags(h, gf)) })
  output$pheQcInspector <- renderUI({
    key <- input$pheQcInspect; pq <- pheQc(); q <- pq$q
    req(!is.null(key), key %in% names(q$sets))
    st <- q$sets[[key]]; req(!is.null(st), nrow(st))
    f <- Filter(function(x) identical(x$key, key), q$flags)[[1]]
    show <- intersect(c("date","year","dayOfYear","phenophaseName","status","intensity","flag"), names(st))
    head_n <- min(nrow(st), 200L); sv <- st[seq_len(head_n), show, drop=FALSE]
    div(class="qc-inspector",
      div(class="qci-head", bs_icon(switch(f$level, high="exclamation-octagon-fill", warn="exclamation-triangle-fill", "info-circle-fill")),
        tags$b(sprintf(" %s · %d record%s", f$title, f$n, if (f$n==1) "" else "s")),
        downloadButton("pheQcSubsetCsv", "Download these", class="btn-outline-dark btn-sm qci-dl")),
      div(class="qc-cap-scroll", tags$table(class="inspect-tbl",
        tags$thead(tags$tr(lapply(show, tags$th))),
        tags$tbody(lapply(seq_len(nrow(sv)), function(i)
          tags$tr(lapply(show, function(cc) tags$td(format(sv[[cc]][i])))))))),
      if (nrow(st) > head_n) p(class="qc-cap-note", sprintf("Showing first %d of %d. Download for the full list.", head_n, nrow(st))))
  })
  output$pheQcSubsetCsv <- downloadHandler(
    filename = function() sprintf("NEON-Phenology_QC-%s_%s_%s.csv", input$pheQcInspect %||% "flag",
      gsub("[^A-Za-z0-9]","",short_ind(rv$ind %||% "plant")), format(Sys.Date(),"%Y%m%d")),
    content = function(file){ q <- pheQc()$q; st <- q$sets[[input$pheQcInspect]]; req(!is.null(st))
      st <- cbind(site = rv$site %||% NA_character_, individualID = rv$ind %||% NA_character_, st)
      utils::write.csv(st, file, row.names=FALSE, na="") }, contentType="text/csv")
  output$qcReportCsv <- downloadHandler(
    filename = function() sprintf("NEON-Phenology_QC-report_%s_%s_%s.csv", rv$site %||% "site",
      gsub("[^A-Za-z0-9]","",short_ind(rv$ind %||% "plant")), format(Sys.Date(),"%Y%m%d")),
    content = function(file){ pq <- pheQc(); rep <- phe_qc_report(pq$hist, pq$gf)
      if (is.null(rep)) rep <- data.frame(note="No data-quality flags for this plant.")
      rep <- cbind(site = rv$site %||% NA_character_, individualID = rv$ind %||% NA_character_, rep)
      utils::write.csv(rep, file, row.names=FALSE, na="") }, contentType="text/csv")
  # ---- site report PDF (hero band downloadLink) ----------------------------
  # Three-page vector PDF (R/report_pdf.R): headline tiles with the green-up
  # status and coverage, composition, season bands, trends with the years left
  # out, caveats and the CAN / CANNOT claims, NEON citation on every page.
  output$reportPdf <- downloadHandler(
    filename = function() sprintf("NEON-Phenology_Report_%s_%s.pdf",
      rv$site %||% "site", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      req(rv$obs, rv$inds, rv$site)
      phe_report_pdf(file, site = rv$site, label = rv$label, inds = rv$inds, obs = rv$obs,
        ind_summary = rv$ind_summary, site_row = site_table[site_table$site == rv$site, , drop = FALSE],
        release = if (exists("PHE_RELEASE")) PHE_RELEASE else NULL,
        data_through = if (!is.null(SEARCH_INDEX)) SEARCH_INDEX$built else NULL,
        app_version = APP_VERSION)
    }, contentType = "application/pdf")

  # ---- site summary CSV (hero band downloadLink) ----------------------------
  # A tidy site-summary CSV beside the PDF: one block of headline metrics for
  # the loaded site (with the green-up status and its bounds), plus a
  # growth-form roster, generated from the same reactives the rest of the app
  # reads. Self-describing filename so a folder of them stays legible.
  output$reportCard <- downloadHandler(
    filename = function() sprintf("NEON-Phenology_ReportCard_%s_%s.csv",
      rv$site %||% "site", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      inds <- rv$inds; obs <- rv$obs; req(inds, obs)
      yrs <- range(obs$year, na.rm = TRUE)
      n_sp <- dplyr::n_distinct(species_level_only(inds)$scientificName)
      n_pl <- dplyr::n_distinct(inds$plotID)
      # the same status-aware numbers the hero shows (site index), never a bare
      # median where the green-up is only an upper bound or the record too short
      sg   <- site_gu(rv$site)
      gu   <- sg$med
      la   <- sg$la
      gu_share <- greenup_coverage(rv$ind_summary)
      cb <- comp_by(inds, "growthForm"); cb <- cb[!is.na(cb$growthForm), , drop = FALSE]
      hdr <- data.frame(
        metric = c("site", "site_name", "label", "year_first", "year_last",
                   "tagged_plants", "species", "phenology_plots",
                   "median_greenup_doy", "greenup_lower_bound_doy", "greenup_upper_doy", "greenup_status",
                   "greenup_label", "median_leaf_active_days", "leaf_active_status",
                   "leaf_active_hi_days", "leaf_edge_share", "leaf_active_label",
                   "greenup_coverage_share", "uncertain_share", "phenophase_records",
                   "data_product", "generated", "app_version", "source"),
        value = c(rv$site %||% "", { r <- site_table[site_table$site == (rv$site %||% ""), ]
                    if (nrow(r)) r$name[1] else "" }, rv$label %||% "",
                  yrs[1], yrs[2], nrow(inds), n_sp, n_pl,
                  if (is.finite(gu)) round(gu) else NA,
                  if (is.finite(sg$lo)) round(sg$lo) else NA, if (is.finite(sg$hi)) round(sg$hi) else NA,
                  sg$status, greenup_label(sg$med, sg$lo, sg$hi, sg$status, sg$n_seasons) %||% NA,
                  if (is.finite(la)) round(la) else NA, sg$la_status,
                  if (is.finite(sg$la_hi)) round(sg$la_hi) else NA,
                  if (is.finite(sg$la_edge)) round(sg$la_edge, 3) else NA,
                  site_la_lab(sg),
                  if (is.finite(gu_share)) round(gu_share, 3) else NA,
                  if (is.finite(sg$uncertain)) round(sg$uncertain, 4) else NA,
                  nrow(obs), NEON_DPID, as.character(Sys.Date()), APP_VERSION,
                  "Desert Data Labs · not affiliated with NEON/Battelle/NSF"),
        stringsAsFactors = FALSE)
      roster <- if (nrow(cb)) data.frame(metric = paste0("growth_form: ", cb$growthForm),
                                         value = paste0(cb$n, " plants"), stringsAsFactors = FALSE) else NULL
      out <- rbind(hdr, roster)
      utils::write.csv(out, file, row.names = FALSE, na = "")
    },
    contentType = "text/csv")

  output$indCsv <- downloadHandler(
    filename = function() sprintf("NEON-Phenology_%s_%s.csv", gsub("[^A-Za-z0-9]","",short_ind(rv$ind %||% "plant")), format(Sys.Date(),"%Y%m%d")),
    content = function(file){ id <- rv$ind; req(id); h <- indiv_history(rv$obs, id); req(!is.null(h))
      utils::write.csv(h, file, row.names=FALSE, na="") },
    contentType="text/csv")

  # standalone codebook (the same table the analysis zip ships)
  output$codebookCsv <- downloadHandler(
    filename = function() sprintf("NEON-Phenology_codebook_%s_%s.csv", rv$site %||% "all-sites", format(Sys.Date(), "%Y%m%d")),
    content = function(file) utils::write.csv(phe_codebook_csv(site = rv$site, app_version = APP_VERSION), file, row.names = FALSE, na = ""),
    contentType = "text/csv")

  # ---- analysis-ready data bundle: tidy CSVs + a shipped codebook (zip) ----
  output$siteBundle <- downloadHandler(
    filename = function() sprintf("NEON-phe_%s_%s.zip", rv$site %||% "site", format(Sys.Date(), "%Y%m%d")),
    content = function(file) {
      req(rv$obs)
      td <- tempfile("phebundle"); dir.create(td)
      obs <- as.data.frame(rv$obs)
      # re-attach nativeStatusCode (kept on inds, not obs, to save memory)
      obs$nativeStatusCode <- rv$inds$nativeStatusCode[match(obs$individualID, rv$inds$individualID)]
      ko <- key_onsets(rv$obs)
      if (!is.null(ko)) {
        sp <- as.data.frame(rv$inds)[, c("individualID","scientificName","growthForm")]
        ko <- dplyr::left_join(ko, sp, by = "individualID")
        ko <- ko[, intersect(c("individualID","year","scientificName","growthForm",
                               "greenup","greenup_lo","greenup_hi","greenup_source","left_censored","carryover","flower","leaf_off",
                               "leaf_active","leaf_active_hi","leaf_edge_start","leaf_edge_end","leaf_weeks",
                               "greenup_supported", "leaf_supported"), names(ko)), drop=FALSE]
      }
      clk <- weekly_yesrate(rv$obs, NULL)
      # individual_summary: the codebook documents taxonRank/is_species + the three
      # *_n_years companion columns. A bundle built before those columns existed
      # lacks them, which would make the export drift from the codebook — so
      # backfill from a fresh individual_summary() (re-derives all five) when any
      # are missing. A rebuilt bundle already carries them and this is a no-op.
      ind_s <- as.data.frame(rv$ind_summary)
      need <- c("taxonRank","is_species","greenup_source","greenup_n_years","flower_n_years",
                "leaf_active_n_years","greenup_lc_years","n_years_watched",
                "leaf_active_hi","leaf_edge_years","leaf_active_lower_bound")
      if (!all(need %in% names(ind_s))) {
        fresh <- individual_summary(rv$obs, rv$inds)
        if (!is.null(fresh)) ind_s <- as.data.frame(fresh)
      }
      w <- function(df, nm) if (!is.null(df) && nrow(df)) utils::write.csv(df, file.path(td, nm), row.names=FALSE, na="")
      w(obs, "obs_long.csv"); w(ko, "onsets_by_individual_year.csv")
      w(ind_s, "individual_summary.csv")
      w(as.data.frame(site_year_support(normalize_doy(rv$obs))), "site_year_support.csv")
      w(clk, "phenology_clock_weekly.csv"); w(as.data.frame(rv$trend), "onset_trend_by_species_year.csv")
      w(phe_codebook_csv(site = rv$site, app_version = APP_VERSION), "codebook.csv")
      writeLines(c(
        sprintf("NEON Plant Phenology Explorer · analysis-ready export for site %s", rv$site %||% ""),
        sprintf("Generated %s · Desert Data Labs · app %s", Sys.Date(), APP_VERSION),
        "Data product: NEON DP1.10055.001 (data.neonscience.org). Not affiliated with NEON/Battelle/NSF.", "",
        "FILES:",
        "  obs_long.csv                     one row per individual x visit x phenophase (tidy long)",
        "  onsets_by_individual_year.csv    per individual-year green-up (+ greenup_lo = last 'no', greenup_hi = first 'yes', greenup_source, left_censored, carryover), flower, leaf-off, leaf-active (+ leaf_active_hi = longest span the visits allow, leaf_edge_start / leaf_edge_end = span runs into the year's first / last visit, leaf_weeks QC), greenup_supported, leaf_supported",
        "  individual_summary.csv           one row per tagged plant (medians across SUPPORTED years; *_n_years are the n behind each median; leaf_active_hi, leaf_edge_years, and leaf_active_lower_bound = TRUE when leaf_active is a lower bound: read it as 'at least N days', not the full leaf period)",
        "  site_year_support.csv            per year: median visited weeks per plant, first visit day, and whether the year passed the support gate",
        "  phenology_clock_weekly.csv       % of scored plant-years 'yes' per phenophase/week (typical-year pool; n>=5)",
        "  onset_trend_by_species_year.csv  median bud-break green-up per species per supported year (n>=3 individuals); lc_share = share of its plant-years already greening at the first visit (at 0.5 or more the median is 'day N or earlier' and the app leaves it out of the trend fit)",
        "  codebook.csv                     every column's type/units/definition + _phenophase_decode + _provenance", "",
        "Unit of analysis: tagged plant individual (repeated measures); plotID = spatial block.",
        "TIMING, not abundance. Onset is interval-censored between greenup_lo and greenup_hi; that bracket bounds visit spacing and censoring, not sampling error. The clock pools plant-year opportunities; repeat visits collapse within year and years stay separate.",
        "leaf_off is the last leaf-week, NOT senescence (meaningless for multi-flush plants). Read leaf_active.",
        "See codebook.csv for the full contract."),
        file.path(td, "README.txt"))
      fs <- list.files(td)
      if (requireNamespace("zip", quietly = TRUE)) zip::zip(file, files = fs, root = td)
      else utils::zip(file, file.path(td, fs), flags = "-j")
    },
    contentType = "application/zip")

  # ---- Map (plots) ----
  output$map <- leaflet::renderLeaflet({
    ps <- plot_summary_phe(rv$obs, rv$inds, rv$ind_summary); req(ps); ps <- ps[is.finite(ps$lat) & is.finite(ps$lng),]
    req(nrow(ps) > 0)
    metric <- input$mapMetric %||% "greenup"
    val <- ps[[metric]]; has <- is.finite(val)         # NA stays NA — never median-filled (honest gaps)
    if (metric == "greenup") {
      pal <- greenup_pal(val[has], gu_share = ps$gu_share[has])   # robust domain from well-covered plots, clamp outliers
      val <- gp_clamp(pal, val)
      legtitle <- "median green-up DOY (earlier = green)"; nalab <- "no green-up scored" }
    else if (metric == "leaf_active") {
      dom <- if (sum(has) && diff(range(val[has])) > 0) range(val[has]) else c(0, max(val[has], 1))
      pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2"); legtitle <- "median leaf-active days/yr"; nalab <- "no leaf record" }
    else { dom <- if (sum(has) && diff(range(val[has])) > 0) range(val[has]) else c(0, max(val[has], 1))
           pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2"); legtitle <- "plants tagged"; nalab <- "n/a" }
    mx <- max(ps$n_ind, 1); ps$radius <- 8 + 13 * sqrt(pmax(ps$n_ind, 1)) / sqrt(mx)   # area ∝ plants
    # The popup LEADS WITH the selected metric, so it matches the dot colour (at
    # desert sites green-up is scored for ~0-19% of plants, so leaf-active is the
    # honest lead). Each stat is rendered once; the off-metric stat is a secondary line.
    thin    <- is.finite(ps$gu_share) & ps$gu_share < GU_COVERAGE_FLOOR
    gu_str  <- ifelse(is.finite(ps$greenup),
                 paste0("day ", ps$greenup, " (", doy_to_month(ps$greenup), ")"), "not yet scored")
    # leaf_label wording per plot: "N d/yr" or "at least N d/yr" (lower bound)
    la_lb_p <- if ("leaf_active_lower_bound" %in% names(ps)) ps$leaf_active_lower_bound %in% TRUE else rep(FALSE, nrow(ps))
    la_str  <- ifelse(is.finite(ps$leaf_active), paste0(ifelse(la_lb_p, "at least ", ""), ps$leaf_active, " d/yr"), "not yet recorded")
    # per-plot green-up coverage caveat — only shown when green-up actually leads
    # or is the secondary line, so a 1/5-of-plants plot can't read like a whole-plot number.
    gp_pct  <- round(ps$gu_share * 100)
    # at a 0%-coverage desert plot, "scored for 0% of plants" reads like a broken
    # zero — say "not scored at this plot" instead, and always point to leaf-active.
    covtxt <- ifelse(thin, ifelse(gp_pct <= 0,
        "<br><span style='color:#b5481f'>green-up not scored at this plot; read leaf-active.</span>",
        sprintf("<br><span style='color:#b5481f'>green-up scored for %d%% of plants here; read leaf-active.</span>", gp_pct)), "")
    lead_la <- sprintf("<b>leaf-active %s</b><br><span class='pm-pop-sub'>green-up %s</span>%s", la_str, gu_str, covtxt)
    lead_gu <- sprintf("<b>green-up %s</b>%s<br><span class='pm-pop-sub'>carries leaves %s</span>", gu_str, covtxt, la_str)
    lead_n  <- sprintf("<span class='pm-pop-sub'>green-up %s%s · leaf-active %s</span>", gu_str,
                 ifelse(thin & gp_pct > 0, sprintf(" (%d%% of plants)", gp_pct), ""), la_str)
    metric_line <- if (metric == "leaf_active") lead_la else if (metric == "greenup") lead_gu else lead_n
    lab <- sprintf("<b>%s</b> · %d plants<br>%s", htmltools::htmlEscape(short_plot(ps$plotID)), ps$n_ind, metric_line)
    leaflet::leaflet(ps) %>% add_suite_basemap(input$view %||% "CartoDB.Positron") %>%
      leaflet::addCircleMarkers(lng = ~lng, lat = ~lat, radius = ~radius, fillColor = pal(val), color = "#fff", weight = 1, fillOpacity = 0.85,
        label = lapply(lab, htmltools::HTML), popup = lapply(lab, htmltools::HTML)) %>%
      leaflet::addLegend("bottomright", pal = pal, values = val[has], title = legtitle, na.label = nalab)
  })
  # site-level green-up coverage badge above the Map — clickable disclosure, only
  # appears when coverage is thin (clean by default at forest sites).
  output$mapCoverage <- renderUI({
    req(rv$ind_summary); cov <- gu_badge(greenup_coverage(rv$ind_summary), where = "at this site")
    if (is.null(cov)) return(NULL)
    div(class = "map-cov-row", cov)   # guidance ("switch to leaf-active") lives in the badge popover — nothing always-on
  })

  # ---- Across sites (the national gradient the 46-site data unlocks) ------
  # site-aware note: at a thin-green-up (desert) entry site we auto-DEFAULT this
  # network view to leaf-active (see ingest); this banner explains that default,
  # or — if the user has switched back to green-up here — points them to it.
  output$xsNudge <- renderUI({
    is_ <- rv$ind_summary; if (is.null(is_)) return(NULL)
    share <- greenup_coverage(is_)
    if (!is.finite(share) || share >= GU_COVERAGE_FLOOR) return(NULL)
    where <- rv$label %||% rv$site %||% "this site"; pct <- round(share * 100)
    if (identical(input$xsMetric %||% "greenup", "leaf_active"))
      div(class = "xs-nudge", style = "margin:4px 0 2px",
        insight_banner("info-circle", tone = "pine", HTML(sprintf(
          "Showing <b>leaf-active days</b> by default: green-up is scored for only <b>%d%%</b> of plants at <b>%s</b>, so leaf-active is the steadier read here.", pct, htmltools::htmlEscape(where)))))
    else
      div(class = "xs-nudge", style = "margin:4px 0 2px",
        insight_banner("arrow-right-circle", tone = "gold", HTML(sprintf(
          "<b>%s</b> scores green-up for only <b>%d%%</b> of its plants. Switch <b>Show</b> to <b>Leaf-active days</b> for the steadier read.", htmltools::htmlEscape(where), pct))))
  })
  output$gradientPlot <- renderPlotly({
    metric <- input$xsMetric %||% "greenup"
    st <- site_table
    # ---- leaf-active mode: markers-only vs latitude, ALL sites, no fit line ----
    # leaf-active is season LENGTH (temperature + water), so the network slope
    # pools biomes and species mixes; the within-species fit (WS_LEAF, global.R)
    # is the controlled read and lives in the banner. No fit line here. The
    # green-up coverage/cadence grey-out gates do NOT apply: leaf-active never
    # uses the green-up phenophase, so greying SRER (the desert site leaf-active
    # exists to rescue) would invert its purpose. Lower-bound sites (spans that
    # run into the year's first or last visit) are drawn open and left out of
    # the banner slope.
    if (metric == "leaf_active") {
      if (!("median_leaf_active" %in% names(st))) return(note_plot("Rebuild the data bundle to enable leaf-active views", "\U0001F30E"))
      d <- st[is.finite(suppressWarnings(as.numeric(st$median_leaf_active))) & is.finite(st$lat) &
                suppressWarnings(as.numeric(st$n_individuals)) >= 5, , drop=FALSE]
      if (nrow(d) < 4) return(note_plot("Need more bundled sites for a leaf-active view", "\U0001F30E"))
      d$la <- suppressWarnings(as.numeric(d$median_leaf_active))
      d$n_species <- if ("n_species" %in% names(d)) d$n_species else NA_integer_
      d$lb <- if ("leaf_active_status" %in% names(d)) d$leaf_active_status %in% "lower_bound" else rep(FALSE, nrow(d))
      dom <- range(d$la, na.rm=TRUE); if (!all(is.finite(dom)) || diff(dom) == 0) dom <- c(min(d$la,na.rm=TRUE)-1, max(d$la,na.rm=TRUE)+1)
      pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2")
      rim <- if (is_dark()) "#16261d" else "#ffffff"; muted <- if (is_dark()) "#9fb0c4" else "#8a988f"
      d$hov <- paste0("<b>", d$site, " · ", htmltools::htmlEscape(d$name), "</b><br>lat ", sprintf("%.1f", d$lat), "°N · ",
        vapply(seq_len(nrow(d)), function(i) leaf_label(d$la[i], if (d$lb[i]) "lower_bound" else "point"), ""),
        " a year (", d$n_species, " species)",
        ifelse(d$lb, "<br>open marker: spans run into the year's first or last visit; left out of the slope", ""))
      p <- plotly::plot_ly(d, x=~lat, y=~la, type="scatter", mode="markers", text=~hov,
        marker=list(size=11, color=ifelse(d$lb, "rgba(0,0,0,0)", pal(d$la)), symbol=ifelse(d$lb, "circle-open", "circle"),
                    line=list(color=ifelse(d$lb, pal(d$la), rim), width=ifelse(d$lb, 2, 0.8))),
        hovertemplate="%{text}<extra></extra>")
      n_off <- nrow(st) - nrow(d)
      shown <- if (n_off > 0) sprintf("%d of %d sites shown; the other %d have no leaf-active median (fewer than three seasons or under five plants)", nrow(d), nrow(st), n_off)
               else sprintf("all %d sites shown, none excluded", nrow(st))
      lb_txt <- if (any(d$lb)) sprintf(" · open markers: %d site%s where the median is a lower bound (at least that many days)", sum(d$lb), if (sum(d$lb) == 1) "" else "s") else ""
      ann <- list(list(text=paste0("markers only, no latitude fit: leaf-active is season length (temperature + water), so it sorts by biome, not a clean poleward law · ", shown, lb_txt),
        x=0, y=1.06, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", align="left", font=list(size=10.5, color=muted)))
      return(p %>% plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE, annotations=ann,
        xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median leaf-active days per year")))
    }
    if (!("median_greenup" %in% names(st))) return(note_plot("Rebuild the data bundle to enable cross-site views", "\U0001F30E"))
    d <- st[is.finite(st$median_greenup) & is.finite(st$lat), , drop=FALSE]
    if (nrow(d) < 4) return(note_plot("Need more bundled sites for a latitude gradient", "\U0001F30E"))
    # green-up coverage gate: a site whose green-up median rests on < half its
    # roster (warm deserts) is biased, so it is GREYED and EXCLUDED from the fit —
    # the latitude line is estimated on well-covered sites only.
    d$gu_share <- if ("gu_share" %in% names(d)) suppressWarnings(as.numeric(d$gu_share)) else rep(NA_real_, nrow(d))
    # coarse-cadence gate: onset is interval-censored to the visit gap, so a site
    # visited far apart carries wide censoring uncertainty on its onset. Sites with
    # a median visit interval > CADENCE_COARSE days are greyed + excluded from the
    # fit alongside thin-coverage sites (both bias the cross-site onset read).
    d$mvi <- if ("median_visit_interval" %in% names(d)) suppressWarnings(as.numeric(d$median_visit_interval)) else rep(NA_real_, nrow(d))
    cov_ok  <- !is.finite(d$gu_share) | d$gu_share >= 0.5
    cad_ok  <- !is.finite(d$mvi) | d$mvi <= CADENCE_COARSE
    d$well <- cov_ok & cad_ok
    pal <- greenup_pal(d$median_greenup, gu_share = d$gu_share)
    cols <- ifelse(d$well, pal(gp_clamp(pal, d$median_greenup)), "#c4c0b2")   # thin/coarse sites greyed
    d$n_species <- if ("n_species" %in% names(d)) d$n_species else NA_integer_
    cov_lab <- ifelse(!cov_ok, " · thin green-up coverage", "")
    cad_lab <- ifelse(!cad_ok, sprintf(" · coarse visit cadence (~%.0fd)", d$mvi), "")
    excl_lab <- ifelse(d$well, "", paste0(cov_lab, cad_lab, " (excluded from fit)"))
    p <- plotly::plot_ly(d, x=~lat, y=~median_greenup, type="scatter", mode="markers",
      text=paste0(d$site, " · ", d$name, excl_lab), customdata=~n_species,
      marker=list(size=11, color=cols, line=list(color="#fff", width=0.8)),
      hovertemplate="<b>%{text}</b><br>lat %{x:.1f}°N · green-up day %{y} (%{customdata} species)<extra></extra>")
    well <- d[d$well, , drop=FALSE]
    if (nrow(well) >= 4 && diff(range(well$lat)) > 0) {
      fit <- stats::lm(median_greenup ~ lat, data=well)
      xs <- range(well$lat); ys <- as.numeric(stats::predict(fit, newdata=data.frame(lat=xs)))
      p <- p %>% plotly::add_trace(x=xs, y=ys, type="scatter", mode="lines", inherit=FALSE,
        line=list(color="#b5481f", width=2, dash="dash"), hoverinfo="skip", showlegend=FALSE)
    }
    n_grey <- sum(!d$well)
    ann <- if (n_grey > 0) list(list(text=sprintf("grey = thin green-up coverage (<50%% of plants) or coarse visit cadence (>%dd); %d site%s excluded from the fit", CADENCE_COARSE, n_grey, if (n_grey==1) "" else "s"),
      x=0, y=1.05, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", font=list(size=10.5, color="#8a988f"))) else list()
    # sites with no green-up day at all (upper bound or short record) are not drawn;
    # say how many, so a missing dot reads as withheld, not lost
    n_np <- if ("greenup_status" %in% names(st)) sum(st$greenup_status %in% c("upper_bound", "short_record", "none")) else 0L
    if (n_np > 0) ann <- c(ann, list(list(
      text=sprintf("not plotted: %d site%s (most plants already greening at the first visit, or fewer than three seasons)", n_np, if (n_np == 1) "" else "s"),
      x=0, y=if (length(ann)) 1.10 else 1.05, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", font=list(size=10.5, color="#8a988f"))))
    p %>% plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE, annotations=ann,
      xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median green-up (day-of-year)"))
  })
  # within-species fit wording, shared by both gradient metrics. rho's interval
  # is a real sampling interval (Fisher z), unlike the visit brackets.
  rho_txt <- function(ws) {
    if (is.null(ws) || !is.finite(ws$rho %||% NA)) return("")
    if (is.finite(ws$rho_lo %||% NA) && is.finite(ws$rho_hi %||% NA))
      sprintf(", Spearman rho %.2f (95%% interval %.2f to %.2f)", ws$rho, ws$rho_lo, ws$rho_hi)
    else sprintf(", Spearman rho %.2f", ws$rho)
  }
  excl_txt <- function(ws) {
    ex <- ws$excluded_sites %||% character(0)
    if (!length(ex)) return("")
    sprintf("; %s left out, fewer than three seasons behind %s value", paste(ex, collapse = ", "), if (length(ex) == 1) "its" else "their")
  }
  ws_sentence <- function(ws, slope_fmt) {
    if (is.null(ws)) return("")
    sprintf(paste0(": held within one species (<em>%s</em>, %d sites) ", slope_fmt, " (95%% interval %.1f to %.1f, R&sup2;=%.2f)%s%s%s"),
      sub("^([A-Z][a-z]+ [a-z\\-]+).*$", "\\1", ws$species), ws$n_sites, ws$slope, ws$lo, ws$hi, ws$r2,
      rho_txt(ws), excl_txt(ws), if (ws$lo < 0 && ws$hi > 0) ", not distinguishable from zero" else "")
  }
  output$gradientInsight <- renderUI({
    metric <- input$xsMetric %||% "greenup"
    st <- site_table
    if (metric == "leaf_active") {
      if (!("median_leaf_active" %in% names(st))) return(NULL)
      # every number below is computed from the shipped site_index and
      # national_onsets (WS_LEAF, fit once in global.R), never typed in, so a
      # rebuild cannot leave stale copy
      la_all <- st[is.finite(st$median_leaf_active) & is.finite(st$lat), , drop = FALSE]
      # lower-bound sites (spans that run into the year's first or last visit)
      # are left out of the network slope: their value is only a floor
      lb <- if ("leaf_active_status" %in% names(la_all)) la_all$leaf_active_status %in% "lower_bound" else rep(FALSE, nrow(la_all))
      la_d <- la_all[!lb, , drop = FALSE]
      if (nrow(la_d) < 4) return(NULL)
      la_slope <- unname(stats::coef(stats::lm(median_leaf_active ~ lat, data = la_d))[2])
      lb_txt <- if (any(lb)) sprintf(" (%d of %d sites left out: their median is a lower bound, at least that many days)", sum(lb), nrow(la_all)) else ""
      ws_txt <- ws_sentence(WS_LEAF, "the latitude slope is %.1f days per degree")
      srer <- la_all$median_leaf_active[la_all$site == "SRER"]
      srer_lb <- any(lb[la_all$site == "SRER"])
      srer_txt <- if (length(srer) && is.finite(srer)) sprintf(", and the Sonoran desert at SRER reads %s <b>%d days</b> a year because most of its tagged shrubs are scored in leaf on nearly every visit",
        if (srer_lb) "at least" else "about", round(srer)) else ""
      return(insight_banner("rulers", tone="pine", HTML(sprintf(paste0(
        "<b>Leaf-active days</b> measure season <b>length</b>: how long a plant carries leaves, summed over each run of leafy visits, in years visited on the site's usual schedule. ",
        "They are driven by temperature <em>and</em> water and sorted by biome; this is <b>not</b> Hopkins' bioclimatic law (that governs green-up <em>onset</em>). ",
        "Across %d sites%s leaf-active changes about <b>%.1f days per degree north</b>. That network slope is a biome-sorting echo, not a controlled gradient%s%s. ",
        "Read it as season length, never as abundance or productivity."),
        nrow(la_d), lb_txt, la_slope, ws_txt, srer_txt))))
    }
    if (!("median_greenup" %in% names(st))) return(NULL)
    d <- st[is.finite(st$median_greenup) & is.finite(st$lat), , drop=FALSE]
    if (nrow(d) < 4) return(NULL)
    # net slope is fit on WELL-COVERED + ADEQUATE-CADENCE sites only (same gate as
    # the plot), so the banner number matches the line drawn and isn't dragged by
    # thin-coverage or coarse-cadence sites.
    gs <- if ("gu_share" %in% names(d)) suppressWarnings(as.numeric(d$gu_share)) else rep(NA_real_, nrow(d))
    mvi <- if ("median_visit_interval" %in% names(d)) suppressWarnings(as.numeric(d$median_visit_interval)) else rep(NA_real_, nrow(d))
    well <- d[(!is.finite(gs) | gs >= 0.5) & (!is.finite(mvi) | mvi <= CADENCE_COARSE), , drop=FALSE]
    if (nrow(well) < 4) well <- d
    co <- summary(stats::lm(median_greenup ~ lat, data=well))$coefficients; net_slope <- co[2,1]
    # cadence badge: the typical visit interval across the bundled sites + the
    # coarse-cadence count, so the reader knows the gradient's censoring resolution.
    med_cad <- suppressWarnings(stats::median(mvi, na.rm=TRUE)); n_coarse <- sum(mvi > CADENCE_COARSE, na.rm=TRUE)
    cad_badge <- if (is.finite(med_cad)) div(class="cadence-badge",
      bs_icon("calendar-week"),
      HTML(sprintf(" sites are visited about every <b>%.0f days</b> on average%s. Onset is interval-censored to that gap, so cross-site onset gaps are approximate.",
        med_cad, if (n_coarse > 0) sprintf("; %d coarse-cadence site%s (&gt;%dd) are greyed out below", n_coarse, if (n_coarse==1) "" else "s", CADENCE_COARSE) else ""))) else NULL
    # LEAD with the within-species slope (the confound-controlled read the app
    # already computes in the secondary panel); demote the network slope to the
    # coarse echo it is. Falls back to the network read if no species spans enough
    # sites yet (older/partial bundles).
    ws <- WS_GREENUP   # fit once in global.R; NULL when no species spans enough sites
    if (!is.null(ws)) {
      sp_short <- sub("^([A-Z][a-z]+ [a-z\\-]+).*$", "\\1", ws$species)
      return(tagList(insight_banner(if (ws$slope >= 0) "graph-up-arrow" else "graph-down-arrow", tone="pine", HTML(sprintf(
        "Holding the species constant, <b><em>%s</em></b> greens up <b>%.1f days %s per °N</b> across <b>%d</b> sites (95%% interval %.1f to %.1f, R²=%.2f)%s%s. This removes the between-species mix but remains an observational space-for-time pattern. <em>The all-species network slope (about %.0f d/°N) is shown only as a coarser, composition-confounded comparison; neither slope alone identifies a temperature effect.</em>",
        sp_short, abs(ws$slope), if (ws$slope >= 0) "later" else "earlier", ws$n_sites, ws$lo, ws$hi, ws$r2,
        rho_txt(ws), excl_txt(ws), abs(net_slope)))), cad_badge))
    }
    tagList(insight_banner(if (net_slope >= 0) "graph-up-arrow" else "graph-down-arrow", tone="pine", HTML(sprintf(
      "Across <b>%d</b> sites, median green-up differs by roughly <b>%.0f days %s per degree of latitude north</b>. <em>Each point mixes species and visit schedules (n as few as 4), so this is a descriptive space-for-time gradient, not a controlled comparison or a temperature effect.</em>",
      nrow(d), abs(net_slope), if (net_slope >= 0) "later" else "earlier"))), cad_badge)
  })
  observe({ if (is.null(NATIONAL_ONSETS) || !nrow(NATIONAL_ONSETS)) {
      updateSelectInput(session, "xsSpecies", choices = c("(rebuild data bundle)" = "")); return() }
    tab <- sort(table(NATIONAL_ONSETS$scientificName), decreasing=TRUE); multi <- names(tab)[tab >= 2]
    updateSelectInput(session, "xsSpecies",
      choices = if (length(multi)) stats::setNames(multi, multi) else c("(no species spans ≥2 sites yet)" = ""),
      selected = if (length(multi)) multi[1] else "") })
  output$speciesAcrossPlot <- renderPlotly({
    no <- NATIONAL_ONSETS; if (is.null(no) || !nrow(no)) return(note_plot("Rebuild the data bundle to enable this view", "\U0001F33F"))
    sp <- input$xsSpecies %||% ""; if (!nzchar(sp)) return(note_plot("Pick a species monitored at several sites", "\U0001F33F"))
    metric <- input$xsMetric %||% "greenup"
    rim <- if (is_dark()) "#16261d" else "#ffffff"
    # leaf-active mode: species held constant, markers only. A site whose value
    # rests on fewer than three seasons is greyed (the within-species fit drops it);
    # a lower-bound value (spans that run into the year's first or last visit) is
    # drawn open.
    if (metric == "leaf_active") {
      d <- no[no$scientificName == sp & is.finite(suppressWarnings(as.numeric(no$leaf_active))), , drop=FALSE]
      if (nrow(d) < 2) return(note_plot("This species has leaf-active recorded at only one site", "\U0001F33F"))
      d <- d[order(d$lat),]; d$la <- suppressWarnings(as.numeric(d$leaf_active))
      d$short <- if ("leaf_n_years" %in% names(d)) { ny <- suppressWarnings(as.numeric(d$leaf_n_years)); is.finite(ny) & ny < SUPPORT_MIN_YEARS } else rep(FALSE, nrow(d))
      if (!is.null(WS_LEAF) && identical(WS_LEAF$species, sp)) d$short <- d$short | d$site %in% (WS_LEAF$excluded_sites %||% character(0))
      d$lb <- if ("leaf_active_lower_bound" %in% names(d)) d$leaf_active_lower_bound %in% TRUE else rep(FALSE, nrow(d))
      dom <- range(d$la, na.rm=TRUE); if (!all(is.finite(dom)) || diff(dom) == 0) dom <- c(min(d$la,na.rm=TRUE)-1, max(d$la,na.rm=TRUE)+1)
      pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2")
      base <- ifelse(d$short, "#c4c0b2", pal(d$la))
      d$hov <- paste0("<b>", sp, "</b> @ ", d$site, "<br>lat ", sprintf("%.1f", d$lat), "°N · ",
        ifelse(d$lb, sprintf("at least %d days", as.integer(round(d$la))), sprintf("%d days", as.integer(round(d$la)))),
        " a year (n=", d$n_ind, " plants)",
        ifelse(d$lb, "<br>open marker: spans run into the year's first or last visit", ""),
        ifelse(d$short, "<br>grey: fewer than three seasons behind this value; left out of the within-species fit", ""))
      return(plotly::plot_ly(d, x=~lat, y=~la, type="scatter", mode="markers", text=~hov,
        marker=list(size=12, color=ifelse(d$lb, "rgba(0,0,0,0)", base), symbol=ifelse(d$lb, "circle-open", "circle"),
                    line=list(color=ifelse(d$lb, base, rim), width=ifelse(d$lb, 2, 1))),
        hovertemplate="%{text}<extra></extra>") %>%
        plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE,
          xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median leaf-active days per year")))
    }
    d <- no[no$scientificName == sp & is.finite(no$greenup), , drop=FALSE]
    if (nrow(d) < 2) return(note_plot("This species is bundled at only one site", "\U0001F33F"))
    d <- d[order(d$lat),]
    # grey a site whose value rests on fewer than three seasons (the within-species
    # fit, WS_GREENUP, drops it); a range reads "day lo to hi" in the hover
    d$short <- if ("n_years" %in% names(d)) { ny <- suppressWarnings(as.numeric(d$n_years)); is.finite(ny) & ny < SUPPORT_MIN_YEARS } else rep(FALSE, nrow(d))
    if (!is.null(WS_GREENUP) && identical(WS_GREENUP$species, sp)) d$short <- d$short | d$site %in% (WS_GREENUP$excluded_sites %||% character(0))
    gst <- if ("greenup_status" %in% names(d)) as.character(d$greenup_status) else rep("point", nrow(d))
    d$hov <- paste0("<b>", sp, "</b> @ ", d$site, "<br>lat ", sprintf("%.1f", d$lat), "°N · green-up ",
      vapply(seq_len(nrow(d)), function(i) greenup_label(d$greenup[i], d$greenup_lo[i] %||% NA, d$greenup_hi[i] %||% NA,
                                                         if (gst[i] %in% c("point", "range")) gst[i] else "point") %||% "", ""),
      ifelse(gst %in% "range", sprintf(" (median day %d)", as.integer(round(d$greenup))), ""),
      " (n=", d$n_ind, " plants)",
      ifelse(d$short, "<br>grey: fewer than three seasons behind this value; left out of the within-species fit", ""))
    # markers only: a line through discrete sites would fabricate a continuous
    # latitudinal path that was never estimated.
    plotly::plot_ly(d, x=~lat, y=~greenup, type="scatter", mode="markers", text=~hov,
      marker=list(size=12, color=ifelse(d$short, "#c4c0b2", "#1f7a3f"), line=list(color="#fff", width=1)),
      hovertemplate="%{text}<extra></extra>") %>%
      plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE,
        xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median green-up (day-of-year)"))
  })

  output$aboutPanel <- renderUI({
    # visit cadence: the loaded site's median gap between visits (site index),
    # else the typical gap across the bundled sites
    mvi_all <- if ("median_visit_interval" %in% names(site_table)) suppressWarnings(as.numeric(site_table$median_visit_interval)) else numeric(0)
    mvi_site <- if (!is.null(rv$site) && length(mvi_all)) mvi_all[match(rv$site, site_table$site)] else NA_real_
    cadence_txt <- if (length(mvi_site) == 1L && is.finite(mvi_site))
      sprintf(" At %s the median gap between visits is about %d days, so a date is only as precise as that gap.", rv$site, as.integer(round(mvi_site)))
      else if (any(is.finite(mvi_all)))
        sprintf(" Across the bundled sites the median gap between visits is about %d days (%d to %d), so a date is only as precise as that gap.",
          as.integer(round(stats::median(mvi_all, na.rm = TRUE))), as.integer(min(mvi_all, na.rm = TRUE)), as.integer(max(mvi_all, na.rm = TRUE)))
      else " A date is only as precise as the gap between visits."
    # the loaded site's uncertain-records share, disclosed at UNCERTAIN_DISCLOSE (iris)
    unc_txt <- if (!is.null(rv$site)) uncertain_txt(site_gu(rv$site)) else NULL
    if (!is.null(unc_txt)) unc_txt <- paste0(" ", unc_txt)
    rel <- release_sentence(); doi <- rel_field("doi")
    div(class="about-wrap",
      div(class="about-card", h4("\U0001F33F What this is"),
        p("An (unofficial) explorer for NEON's ", tags$b("Plant phenology observations"), " (", tags$code("DP1.10055.001"), "). A fixed roster of tagged plants along transects is checked ", tags$b("2 or 3 times a week while plants are changing fast, about weekly the rest of the year"), "; for each, observers record which ", tags$b("phenophases"), " are active: breaking leaf buds, leaves, open flowers, colored leaves, falling leaves.")),
      div(class="about-card", h4(bs_icon("clock-history"), " Timing, not abundance"),
        p("Phenology is a ", tags$b("timing signal"), ": when a plant wakes, blooms, and senesces. Because the roster is fixed, it is not a measure of how common a species is. It tracks the ", tags$b("calendar of the canopy"), ", and how that calendar shifts year to year."),
        p("Onset is ", tags$b("interval-censored"), ": the true first-leaf day lies between the last 'no' and first 'yes' visit, so we use the midpoint.", cadence_txt, unc_txt)),
      div(class="about-card", h4(bs_icon("flower1"), " Green-up, carefully"),
        p(tags$b("Green-up"), " is a plant's first ", tags$b("bud-break"), " of the year. Drought-deciduous shrubs have no bud-break stage in NEON's protocol, so for them it is the first new ", tags$b("Young leaves"), "."),
        p("A 'yes' that was already 'yes' at the plant's last December visit is leaves carried over from last year, not a new green-up."),
        p("When some plants were already greening at the first visit of the year, the median is shown as a ", tags$b("range"), " or as ", tags$b("\"day N or earlier\""), ", because the true onset came before anyone looked."),
        p("Years visited less than usual (such as 2020) and sites with fewer than three seasons are left out of medians and trends."),
        p(tags$b("This app cannot:")),
        tags$ul(
          tags$li("give a calendar-year green-up for evergreens, cacti or annuals that sprout with autumn rain;"),
          tags$li("treat a Young-leaves green-up as the same day-for-day event as bud-break;"),
          tags$li("read a green-up range as a confidence interval: it bounds visit spacing and censoring, not sampling error;"),
          tags$li("give a green-up where most plants were already greening at the first visit, or from fewer than three seasons;"),
          tags$li("read \"at least N days\" of leaf-active as the full leaf period: those spans run into the year's first or last visit, so the true period is longer;"),
          tags$li("give a trend direction that flips depending on how the censoring-heavy points are treated (those read \"depends\" and no direction is claimed);"),
          tags$li("fit a leaf-active slope through lower-bound sites: they are drawn open and left out."))),
      div(class="about-card", h4(bs_icon("graph-down-arrow"), " Why it matters"),
        p("Green-up and bloom timing can respond to climate and can alter overlap with pollinators or migrating birds. This app exposes timing and support; it does not estimate those drivers, causal effects, or species mismatches."),
        p(bs_icon("envelope"), " ", tags$a(href="mailto:desertdatalabs@gmail.com","desertdatalabs@gmail.com"), " · ",
          tags$a(href="https://data.neonscience.org/data-products/DP1.10055.001", target="_blank", "NEON data product"))),
      div(class="about-card", h4(bs_icon("award"), " Data attribution & license"),
        p(class="caveat",
          "Built with data from the National Ecological Observatory Network (NEON), a U.S. National Science Foundation program operated by Battelle. NEON data are provided under a Creative Commons Attribution 4.0 International (CC BY 4.0) license (",
          tags$a(href="https://creativecommons.org/licenses/by/4.0/", target="_blank", "creativecommons.org/licenses/by/4.0"),
          "). This app aggregates and derives summary metrics from the raw NEON data products; the underlying measurements are unaltered. It is an independent, unofficial tool and is not endorsed by NEON, Battelle, or the NSF."),
        if (!is.null(rel)) p(class="about-release", rel,
          if (!is.null(doi)) tagList(" ", tags$a(href=doi, target="_blank", rel="noopener", doi)))),
      div(class="about-card", h4(bs_icon("journal-text"), " Codebook"),
        p("Every exported column with its type, units and definition, plus the phenophase decode and the provenance of this build. It is also inside the analysis zip."),
        downloadButton("codebookCsv", "Download the codebook (CSV)", class="btn-outline-dark btn-sm")),
      div(class="about-card", h4(bs_icon("grid-3x3-gap-fill"), " The NEON series"),
        p("This is one of a family of explorers, each built on a different NEON data product, that share the same look and state what each number can and cannot support."),
        series_block(footer = FALSE)))
  })
  observeEvent(input$help, showModal(modalDialog(easyClose=TRUE, title=tagList(bs_icon("question-circle"), " How it works"),
    tags$ul(
      tags$li(HTML("Pick a <b>site</b> on the map, or by name in the panel below it.")),
      tags$li(HTML("<b>Phenology Clock</b> · the typical year, week by week; switch species to compare.")),
      tags$li(HTML("<b>Onset Lab</b> · every plant by green-up onset × season length; <b>tap one</b> to pin its card, then “Open plant profile”.")),
      tags$li(HTML("<b>Plant Profile</b> · a plant's phenophase calendar, onset dates, quality checks, and downloads.")),
      tags$li(HTML("Phenology is a <b>timing</b> signal on a fixed roster, not a measure of abundance."))),
    footer=modalButton("Got it"))))

  # =========================================================================
  # SEARCH THE NETWORK — instant in-memory search over the bundled index.
  # Reads SEARCH_TAXA / SEARCH_SITES loaded once at boot in global.R (no fetch).
  # Both result tables carry a "Go to site" button that routes through the SAME
  # pickSite -> load_site_full() path the picker-map popup uses, so the jump is
  # instant (loads from the bundle) and lands the user on the Overview tab.
  # =========================================================================
  doy_lab <- function(d) ifelse(is.finite(d), sprintf("%s (%s)", d, doy_to_month(d)), "n/a")
  # leaf_active is a COUNT of days a plant carries leaves per year (distinct
  # leaf-weeks x 7), NOT a day-of-year. It must read as a duration ("110 days"),
  # never as a calendar date (doy_to_month would turn 110 into a fake "Apr 20").
  days_lab <- function(d) ifelse(is.finite(d), sprintf("%s days", round(d)), "n/a")
  # a per-row "Go to site →" button: sets input$searchGo to the site code.
  go_btn <- function(codes) vapply(codes, function(cd) as.character(
    tags$button(class = "sp-btn sp-go search-go-btn", type = "button",
      onclick = sprintf("smtLoadStart('%s');Shiny.setInputValue('searchGo','%s',{priority:'event'});return false;", cd, cd),
      HTML(paste0("Go to ", cd, " &rarr;")))), character(1))

  # one selectize fed from the boot-time species roster (server-side so 499
  # options never bloat the page); placeholder seeds a desert example.
  observe({
    updateSelectizeInput(session, "searchTaxon", server = TRUE,
      choices = c("" , stats::setNames(SEARCH_SPECIES, SEARCH_SPECIES)), selected = "")
  })

  # the wired jump: identical behaviour to the map popup's Explore button.
  observeEvent(input$searchGo, if (nzchar(input$searchGo %||% "")) {
    session$sendCustomMessage("smtLoadStart", list(label = input$searchGo))
    load_site_full(input$searchGo)
  }, ignoreInit = TRUE)

  # ---- (a) FIND A TAXON ---------------------------------------------------
  taxon_rows <- reactive({
    sp <- input$searchTaxon %||% ""
    if (!nzchar(sp) || is.null(SEARCH_TAXA)) return(SEARCH_TAXA[0, , drop = FALSE])
    d <- SEARCH_TAXA[SEARCH_TAXA$scientificName == sp, , drop = FALSE]
    d[order(d$greenup, d$site, na.last = TRUE), , drop = FALSE]
  })
  output$searchTaxonCaption <- renderUI({
    sp <- input$searchTaxon %||% ""
    if (!nzchar(sp)) return(div(class = "search-cap muted",
      bs_icon("arrow-up"), " Pick a species to see every site that monitors it."))
    d <- taxon_rows(); n <- nrow(d)
    if (!n) return(div(class = "search-cap muted", bs_icon("emoji-frown"),
      sprintf(" No bundled site monitors %s yet.", sp)))
    ng <- sum(is.finite(d$greenup))
    div(class = "search-cap",
      glow_badge(sprintf("%d %s", n, if (n == 1) "site" else "sites"), DDL$primary),
      tags$em(sprintf(" monitor %s%s ", sp, if (grepl("[.]$", sp)) "" else ".")),
      tags$span(class = "muted", if (ng == n)
        "Green-up day shown for every site."
        else sprintf("%s fewer than three plants of this species have a green-up in fully visited years, most were already greening at the first visit, or the species has no calendar-year green-up (evergreen shrubs, cacti, annuals that sprout with autumn rain).",
          if (ng == 0) "No green-up day here:" else sprintf("Green-up day shown for %d. At the others", ng))))
  })
  output$searchTaxonTbl <- DT::renderDT({
    d <- taxon_rows(); if (!nrow(d)) return(NULL)
    out <- data.frame(
      Site = sprintf("<b>%s</b> · %s", d$site, htmltools::htmlEscape(d$name %||% d$site)),
      State = d$state,
      `Green-up day` = vapply(d$greenup, doy_lab, character(1)),
      `Days carrying leaves` = ifelse(if ("leaf_active_lower_bound" %in% names(d)) d$leaf_active_lower_bound %in% TRUE else FALSE,
        ifelse(is.finite(d$leaf_active), sprintf("at least %d days", as.integer(round(d$leaf_active))), "n/a"),
        vapply(d$leaf_active, days_lab, character(1))),
      Plants = d$n_ind,
      Years = ifelse(is.na(d$year_min), "n/a", ifelse(d$year_min == d$year_max,
        as.character(d$year_min), sprintf("%s–%s", d$year_min, d$year_max))),
      ` ` = go_btn(d$site),
      check.names = FALSE, stringsAsFactors = FALSE)
    DT::datatable(out, escape = FALSE, rownames = FALSE, selection = "none",
      options = list(pageLength = 12, dom = "tip", autoWidth = FALSE,
        columnDefs = list(list(orderable = FALSE, targets = ncol(out) - 1))),
      class = "compact stripe hover")
  }, server = FALSE)

  # ---- (b) THRESHOLD QUERY (sites by median green-up day) ------------------
  output$thrDayLabel <- renderUI({
    dir <- input$thrDir %||% "before"
    if (dir %in% c("earliest", "latest")) return(NULL)
    div(class = "thr-day-readout", bs_icon("calendar-event"),
      sprintf(" day %d = %s", input$thrDay %||% 120, doy_to_month(input$thrDay %||% 120)))
  })
  threshold_rows <- reactive({
    if (is.null(SEARCH_SITES)) return(NULL)
    d <- SEARCH_SITES; dir <- input$thrDir %||% "before"; day <- input$thrDay %||% 120
    if (dir == "before")        d <- d[d$median_greenup <  day, , drop = FALSE]
    else if (dir == "after")    d <- d[d$median_greenup >= day, , drop = FALSE]
    if (dir == "latest") d <- d[order(-d$median_greenup), , drop = FALSE]
    else                 d <- d[order(d$median_greenup), , drop = FALSE]
    d
  })
  output$searchThresholdCaption <- renderUI({
    d <- threshold_rows(); tot <- if (!is.null(SEARCH_SITES)) nrow(SEARCH_SITES) else 0
    dir <- input$thrDir %||% "before"; day <- input$thrDay %||% 120
    if (is.null(d) || !nrow(d)) return(div(class = "search-cap muted", bs_icon("emoji-frown"),
      " No bundled site matches. Try a later day."))
    phrase <- switch(dir,
      before   = sprintf("green up before day %d (%s)", day, doy_to_month(day)),
      after    = sprintf("green up on or after day %d (%s)", day, doy_to_month(day)),
      earliest = "ranked earliest green-up first",
      latest   = "ranked latest green-up first")
    div(class = "search-cap",
      glow_badge(sprintf("%d of %d sites", nrow(d), tot), DDL$primary),
      tags$em(sprintf(" %s.", phrase)))
  })
  output$searchThresholdTbl <- DT::renderDT({
    d <- threshold_rows(); if (is.null(d) || !nrow(d)) return(NULL)
    out <- data.frame(
      Site = sprintf("<b>%s</b> · %s", d$site, htmltools::htmlEscape(d$name %||% d$site)),
      State = d$state,
      `Median green-up day` = ifelse(
        if ("greenup_status" %in% names(d)) d$greenup_status %in% "range" & is.finite(d$greenup_lo) else FALSE,
        sprintf("day %d to %d", as.integer(round(d$greenup_lo)),
                as.integer(round(if ("greenup_hi" %in% names(d)) d$greenup_hi else d$median_greenup))),
        vapply(d$median_greenup, doy_lab, character(1))),
      Species = d$n_species,
      Plants = d$n_individuals,
      Years = ifelse(is.na(d$year_min), "n/a", sprintf("%s–%s", d$year_min, d$year_max)),
      ` ` = go_btn(d$site),
      check.names = FALSE, stringsAsFactors = FALSE)
    DT::datatable(out, escape = FALSE, rownames = FALSE, selection = "none",
      options = list(pageLength = 15, dom = "tip", autoWidth = FALSE,
        columnDefs = list(list(orderable = FALSE, targets = ncol(out) - 1))),
      class = "compact stripe hover")
  }, server = FALSE)
}
