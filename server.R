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

  rv <- reactiveValues(obs=NULL, inds=NULL, ind_summary=NULL, trend=NULL, label=NULL, site=NULL, ind=NULL, ctx=NULL, is_demo=FALSE, pendingSite=NULL)

  # ---- green-up coverage badge (the desert biome-conditional honesty) ------
  # When < ~half of a site's plants ever resolve a green-up onset, the
  # median green-up is a thin, biased subsample (warm deserts log most plants
  # straight into "Leaves"). Surface a small CLICKABLE badge — clean by default,
  # the why behind a tap (a bslib popover, the app's existing disclosure chrome).
  GU_COVERAGE_FLOOR <- 0.5
  # a site whose median in-season visit interval exceeds this is "coarse cadence":
  # onset is interval-censored to the visit gap, so its onset carries wide censoring
  # uncertainty and it is greyed + dropped from the cross-site fit. 10 days ≈ 1.5x
  # the ~7-day twice-weekly target; bundled sites run 3-15d (one site at 15).
  CADENCE_COARSE <- 10
  gu_badge <- function(share, where = "here") {
    if (!is.finite(share) || share >= GU_COVERAGE_FLOOR) return(NULL)
    pct <- round(share * 100)
    bslib::popover(
      tags$span(class = "gu-cov-badge", role = "button", tabindex = "0",
        bsicons::bs_icon("exclamation-triangle-fill"),
        sprintf(" green-up scored for %d%% of plants %s", pct, where)),
      title = "Thin green-up coverage",
      p(HTML(sprintf("Only <b>%d%%</b> of the tagged plants %s ever record a green-up <em>phenophase</em> (“Breaking leaf buds” / “Initial growth”).", pct, where))),
      p(HTML("In warm deserts, drought-deciduous, cactus and evergreen plants are scored straight into “Leaves”, so this green-up median rests on a <b>small, non-random subset</b>, not a noisy whole-site number.")),
      p(class = "caveat", bsicons::bs_icon("arrow-right-circle"),
        HTML(" Read <b>leaf-active</b> (days carrying leaves) instead. It survives where green-up collapses. Switch the metric on the Map and Onset Lab.")),
      placement = "bottom")
  }

  observe({ ch <- phe_state_choices(); updateSelectInput(session, "stateSel", choices = ch, selected = if ("MA" %in% ch) "MA" else NULL) })
  # When the state changes, refill the site dropdown. If a map/browse pick is
  # pending, keep THAT site selected (so the sidebar mirrors the dot the user
  # tapped); otherwise fall back to the first site in the state.
  observeEvent(input$stateSel, {
    sites <- phe_sites_in_state(input$stateSel)
    sel <- if (!is.null(rv$pendingSite) && rv$pendingSite %in% sites) rv$pendingSite
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
    rv$label <- label; rv$site <- b$meta$site; rv$is_demo <- is_demo; rv$ind <- NULL
    yrs <- range(b$obs$year, na.rm=TRUE); rv$ctx <- paste0(b$meta$site, " · ", if (yrs[1]==yrs[2]) yrs[1] else paste0(yrs[1],"–",yrs[2]))
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
  load_site <- function(site){ if (is.null(site)||site=="") { session$sendCustomMessage("loadDone", list()); return() }
    b <- load_site_bundle(site); if (is.null(b)) { session$sendCustomMessage("loadDone", list()); showNotification("That site isn't bundled in this demo.", type="error"); return() }
    row <- site_table[site_table$site==site,]; ingest(b, sprintf("%s · %s", site, if (nrow(row)) row$name else site)) }
  # The map popup, the browse list, and the site-search all pick a site OFF the
  # sidebar. Route them through here so the sidebar's state + site dropdowns end
  # up reading the site that was picked (not the previous one) before the load.
  load_site_full <- function(code){ if (is.null(code) || code=="") return()
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
    load_site(code) }
  observeEvent(input$loadBtn, load_site(input$site)); observeEvent(input$pickSite, { removeModal(); load_site_full(input$pickSite) })
  # v2 flow: the Harvard Forest demo path is gone — users pick a real site on
  # the map, the Browse-all-sites list, or the by-name select panel. The demoBtn
  # / demoBtn2 inputs and their observers were removed with the demo CTAs.

  # "Change site" (in the hero band) -> back to the picker-map landing.
  observeEvent(input$changeSite, {
    rv$obs <- NULL; rv$inds <- NULL; rv$ind_summary <- NULL; rv$trend <- NULL
    rv$label <- NULL; rv$site <- NULL; rv$ind <- NULL; rv$ctx <- NULL; rv$is_demo <- FALSE
    shinyjs::hide("mainTabsWrap"); shinyjs::hide("spPickerWrap"); shinyjs::show("splash")
    # the picker map was hidden while a site was loaded; nudge it across several
    # frames to re-measure now that it's visible again, so it never paints blank
    # / half-width on return (page_fillable settles its width a beat late).
    session$sendCustomMessage("kickMaps", list())
  })

  # ---- national site-picker map (the splash landing) --------------------
  # STATIC leafletOutput in ui (never inside renderUI — avoids the re-bind race).
  output$nationalMap <- leaflet::renderLeaflet({
    st <- site_table[is.finite(site_table$lat) & is.finite(site_table$lng), , drop=FALSE]
    if (!nrow(st)) return(leaflet::leaflet() %>% leaflet::addProviderTiles("CartoDB.Positron") %>% leaflet::setView(-96, 38, 3))
    gv <- if ("median_greenup" %in% names(st)) suppressWarnings(as.numeric(st$median_greenup)) else rep(NA_real_, nrow(st))
    gs0 <- if ("gu_share" %in% names(st)) suppressWarnings(as.numeric(st$gu_share)) else rep(NA_real_, nrow(st))
    # robust [p5,p95] colour domain from WELL-COVERED sites only, then clamp every
    # site's value to it — so KONA (day 226, 3% coverage) / LAJA (day 5) pin to the
    # late/early endpoint instead of stretching the ramp flat (suite colour standard).
    pal <- greenup_pal(gv, gu_share = gs0)
    gv_col <- gp_clamp(pal, gv)
    mx <- max(st$n_individuals, 1, na.rm=TRUE); st$radius <- 6 + 12 * sqrt(pmax(st$n_individuals, 1)) / sqrt(mx)
    elev <- ifelse(is.finite(st$elevation_m), paste0(st$elevation_m, " m"), "—")
    gtxt <- ifelse(is.finite(gv), paste0(" · green-up day ", gv, " (", doy_to_month(gv), ")"), "")
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
      st$name, st$site, ifelse(is.na(state_names[st$state]), st$state, state_names[st$state]), st$domain, elev, st$bio,
      st$n_individuals, st$n_species, gtxt, covtxt, gsub("'", "", st$name), st$site, st$site)
    lab <- sprintf("<b>%s</b> · %s<br>%s plants%s · tap for details", st$site, st$name, st$n_individuals,
      ifelse(thin, " · thin green-up coverage", ""))
    leaflet::leaflet(st) %>% leaflet::addProviderTiles("CartoDB.Positron") %>%
      leaflet::addCircleMarkers(lng=~lng, lat=~lat, radius=~radius, layerId=~site,
        fillColor=pal(gv_col), color=mk_stroke, weight=1, fillOpacity=mk_opacity,
        label=lapply(lab, htmltools::HTML), popup=pop,
        popupOptions=leaflet::popupOptions(className="pm-pop-card")) %>%
      leaflet::addLegend("bottomright", pal=pal, values=gp_clamp(pal, gv[is.finite(gv)]), title="median green-up DOY", na.label="—")
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
    dash <- function(x) if (length(x) == 0 || is.na(x) || !nzchar(as.character(x))) "—" else as.character(x)
    coords <- if (!is.na(m$lat[1]) && !is.na(m$lng[1])) sprintf("%.3f, %.3f", m$lat[1], m$lng[1]) else "—"
    n_pl <- if (nrow(row)) suppressWarnings(as.integer(row$n_individuals[1])) else NA_integer_
    n_sp <- if (nrow(row)) suppressWarnings(as.integer(row$n_species[1])) else NA_integer_
    gv   <- if (nrow(row) && "median_greenup" %in% names(row)) suppressWarnings(as.numeric(row$median_greenup[1])) else NA_real_
    stat <- function(v, lab) div(class = "si-stat",
      div(class = "si-stat-n", if (length(v) == 0 || is.na(v)) "—" else format(v, big.mark = ",")),
      div(class = "si-stat-l", lab))
    modalDialog(
      title = HTML(sprintf("\U0001F33F %s <span class='si-code'>(%s)</span>", dash(m$name[1]), code)),
      easyClose = TRUE, size = "m",
      footer = tagList(
        modalButton("Close"),
        tags$button(type = "button", class = "btn btn-primary",
          onclick = sprintf("smtLoadStart('%s');Shiny.setInputValue('pickSite','%s',{priority:'event'});",
                            gsub("'", "", dash(m$name[1])), code),
          HTML("Explore this site &rarr;"))),
      div(class = "site-info",
        div(class = "si-sec",
          div(class = "si-h", "Where"),
          div(class = "si-row", dash(m$state[1]), HTML(sprintf(" · NEON %s", dash(m$domain[1])))),
          if (!is.na(m$bio[1])) div(class = "si-row si-bio", m$bio[1]),
          div(class = "si-coords", "\U0001F4CD ", coords,
              if (!is.na(m$elevation_m[1])) sprintf(" · %s m", m$elevation_m[1]) else NULL)),
        div(class = "si-sec",
          div(class = "si-h", "What's been recorded"),
          div(class = "si-stats",
            stat(n_pl, "tagged plants"),
            stat(n_sp, "species"),
            stat(if (is.finite(gv)) round(gv) else NA, "median green-up (day-of-year)")))))
  }
  observeEvent(input$siteInfo, if (nzchar(input$siteInfo %||% "")) showModal(site_info_modal(input$siteInfo)))

  pick_individual <- function(id, navigate=FALSE){ if (is.null(id)||is.na(id)||id=="") return()
    if (is.null(rv$ind_summary) || !(id %in% rv$ind_summary$individualID)) return()
    rv$ind <- id; if (!identical(input$indSel, id)) updateSelectizeInput(session, "indSel", selected=id); if (navigate) nav_select("tabs","profile") }
  observeEvent(input$indSel, if (nzchar(input$indSel %||% "")) pick_individual(input$indSel, navigate=TRUE), ignoreInit=TRUE)
  observeEvent(input$qcCardRequest, if (nzchar(input$qcCardRequest %||% "")) pick_individual(input$qcCardRequest, navigate=TRUE), ignoreInit=TRUE)
  observeEvent(input$surpriseBtn, { req(rv$ind_summary); pick_individual(sample(rv$ind_summary$individualID, 1), navigate=TRUE) })
  observeEvent(input$goClock, nav_select("tabs","clock")); observeEvent(input$goOnset, nav_select("tabs","onset"))
  observeEvent(input$goProfile, { if (is.null(rv$ind) && !is.null(rv$ind_summary)) rv$ind <- rv$ind_summary$individualID[1]; nav_select("tabs","profile") })
  observeEvent(input$goMap, nav_select("tabs","map"))

  # ---- hero ----
  output$heroStats <- renderUI({
    inds <- rv$inds; req(inds)
    n_sp <- dplyr::n_distinct(species_level_only(inds)$scientificName)
    n_pl <- dplyr::n_distinct(inds$plotID)
    gu <- suppressWarnings(stats::median(rv$ind_summary$greenup, na.rm=TRUE))
    gu_share <- greenup_coverage(rv$ind_summary)
    hero <- function(v,l,suf="",icon,tone,ttl=NULL) div(class=paste0("hero-stat hero-",tone), title=ttl,
      div(class="hs-icon", bs_icon(icon)), div(div(class="hs-v count-up", `data-target`=v, `data-suffix`=suf, "0"), div(class="hs-l", l)))
    cov <- gu_badge(gu_share, where = "here")
    div(class="hero-band",
      div(class="hero-title",
        bs_icon("flower3"), tags$b(rv$label),
        actionLink("changeSite", tagList(bs_icon("arrow-left-circle"), " change site"),
                   class = "hero-change"),
        downloadLink("reportCard", tagList(bs_icon("file-earmark-arrow-down"), " report card"),
                     class = "hero-report")),
      div(class="hero-grid",
        hero(nrow(inds), "tagged plants", icon="flower1", tone="pine"),
        hero(n_sp, "species", icon="tree", tone="navy"),
        hero(n_pl, "phenology plots", icon="geo", tone="terra"),
        hero(if (is.finite(gu)) round(gu) else 0, "median green-up (day-of-year)", icon="clock-history", tone="gold",
             ttl="Typical day-of-year the average plant first breaks leaf, a within-site timing signal pooled across years.")),
      if (!is.null(cov)) div(class="hero-cov-row", cov))
  })

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
    if (is.finite(gu)) pts <- c(pts, sprintf("The typical plant breaks leaf around <b>%s</b> (day %d)%s.",
      doy_to_month(gu), round(gu), if (is.finite(la)) sprintf(" and carries leaves about <b>%d</b> days a year", round(la)) else ""))
    pts <- c(pts, "Phenology is recorded on a <b>fixed roster of tagged individuals</b> along transects. It captures <b>timing</b> (when each phenophase happens), not abundance. Open the Phenology Clock to see the year unfold.")
    div(class="insight-list", lapply(pts, function(t) div(class="il-item", bs_icon("dot"), HTML(t))))
  })

  # ---- Phenology Clock (flagship) ----
  output$clockPlot <- renderPlotly({
    obs <- rv$obs; req(obs); sci <- if (nzchar(input$clockSp %||% "")) input$clockSp else NULL
    wk <- weekly_yesrate(obs, sci); if (is.null(wk) || !nrow(wk)) return(note_plot("No phenophase records for that selection"))
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
      p <- p %>% plotly::add_trace(type="scatterpolar", mode="lines", name=pn,
        r = r, theta = th, fill = "toself",
        fillcolor = grDevices::adjustcolor(col, alpha.f = 0.22), line = list(color = col, width = 2),
        customdata = nn,
        hovertemplate = paste0(pn, "<br>%{r:.0f}% of plants 'yes'<br>%{customdata} plants that week<extra></extra>"))
    }
    ink <- if (is_dark()) "#e8eef2" else "#1f2a30"; grid <- if (is_dark()) "rgba(220,230,240,0.20)" else "rgba(31,42,48,0.12)"
    muted <- if (is_dark()) "#9fb0c4" else "#6b7a85"
    mo_theta <- (c(1,32,60,91,121,152,182,213,244,274,305,335) - 1)/365*360
    scope <- sprintf("%s · %% of plants in each phenophase, by week · pooled across years%s",
      rv$ctx %||% "", if (is.null(sci)) " · all species (mixes evergreen, deciduous & forb leaf calendars; pick a species to read timing)" else paste0(" · ", sci))
    p %>% plotly::layout(
      font = list(color = ink, family = "Rubik"), paper_bgcolor="rgba(0,0,0,0)",
      polar = list(bgcolor = "rgba(0,0,0,0)",
        radialaxis = list(ticksuffix = "%", angle = 90, gridcolor = grid, tickfont = list(size = 9, color = ink), range = c(0, 100)),
        angularaxis = list(rotation = 90, direction = "clockwise", gridcolor = grid,
          tickmode = "array", tickvals = mo_theta, ticktext = month.abb, tickfont = list(size = 10, color = ink))),
      legend = list(orientation = "h", y = -0.12, font = list(color = ink)),
      annotations = list(list(text = scope, x = 0, y = 1.10, xref = "paper", yref = "paper",
        showarrow = FALSE, xanchor = "left", font = list(color = muted, size = 10.5))),
      margin = list(l = 30, r = 30, t = 42, b = 30)) %>%
      plotly::config(displayModeBar = FALSE, responsive = TRUE)
  })
  output$trendPlot <- renderPlotly({
    tr <- rv$trend; if (is.null(tr) || !nrow(tr)) return(note_plot("Not enough plants per year for an onset trend"))
    n_all <- dplyr::n_distinct(tr$scientificName)
    top <- names(sort(table(tr$scientificName), decreasing=TRUE)); top <- head(top, 8)
    tr <- tr[tr$scientificName %in% top,]
    pal <- make_species_pal(tr); col_of <- function(s) pal[[s]] %||% OTHER_GREY
    p <- plotly::plot_ly()
    for (s in unique(tr$scientificName)) { d <- tr[tr$scientificName==s,]; d <- d[order(d$year),]
      p <- p %>% plotly::add_trace(data=d, x=~year, y=~onset, type="scatter", mode="lines+markers", name=s,
        line=list(color=col_of(s), width=2), marker=list(color=col_of(s), size=7),
        hovertemplate=paste0("<b>",s,"</b><br>%{x}: green-up day %{y}<extra></extra>")) }
    note <- if (n_all > 8) list(list(text=sprintf("showing the 8 most-monitored of %d species (the banner above pools all %d)", n_all, n_all),
      x=0, y=1.06, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", font=list(size=10.5, color="#8a988f"))) else list()
    p %>% plotly_theme() %>% plotly::layout(xaxis=list(title="Year", dtick=1), yaxis=list(title="Green-up onset (day-of-year)"),
      legend=list(font=list(size=9)), annotations=note)
  })
  output$trendInsight <- renderUI({
    tr <- rv$trend; req(!is.null(tr) && nrow(tr) >= 3)
    site_yr <- tr %>% dplyr::group_by(.data$year) %>% dplyr::summarise(onset = stats::median(.data$onset), .groups="drop")
    ny <- nrow(site_yr)
    # never fit a trend to fewer than 5 annual points — and never extrapolate a
    # 3–7 year line to "per decade". Report days/YEAR with a 95% CI; if the CI
    # spans zero, say so instead of printing a directional verdict.
    if (ny < 5) return(insight_banner("hourglass-split", tone = "navy",
      HTML(sprintf("Only <b>%d</b> year%s of green-up are recorded here. Too short to fit a trend. Phenology shifts need ~5+ years before a slope means anything.", ny, if (ny==1) "" else "s"))))
    fit <- stats::lm(onset ~ year, data = site_yr); co <- summary(fit)$coefficients
    slope <- co[2,1]; se <- co[2,2]; tcrit <- stats::qt(0.975, df = ny - 2)
    lo <- slope - tcrit*se; hi <- slope + tcrit*se
    if (lo < 0 && hi > 0) return(insight_banner("dash-circle", tone = "navy",
      HTML(sprintf("Over <b>%d</b> years, green-up shows <b>no statistically detectable shift</b> (%.1f days/yr, 95%% CI %.1f to %.1f, spans zero). More years are needed to tell drift from noise.", ny, slope, lo, hi))))
    dir <- if (slope < 0) "earlier" else "later"
    insight_banner(if (slope < 0) "arrow-down-right" else "arrow-up-right", tone = if (slope < 0) "pine" else "gold",
      HTML(sprintf("Over <b>%d</b> years, site-wide green-up has shifted <b>%.1f days/year %s</b> (95%% CI %.1f to %.1f). <em>A short series, a signal, not a verdict; partly reflects which species were monitored each year.</em>",
        ny, abs(slope), dir, lo, hi)))
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
  output$onsetBoard <- renderPlotly({
    is_ <- rv$ind_summary; req(is_)
    d <- is_[is.finite(is_$greenup) & is.finite(is_$leaf_active), , drop=FALSE]
    n_total <- nrow(is_); n_placed <- nrow(d)
    if (!n_placed) return(note_plot("No plants yet have both leaf-out and leaf-active days recorded"))
    # Colour-by capped to the 8 most-monitored categories + an explicit grey
    # "Other" — interpolating Dark2 across ~20 species made muddy, look-alike
    # olives. Growth form (<=8 categories) is the default and is unaffected.
    cby <- input$onsetColor %||% "growthForm"
    lv <- ordered_levels(d, cby)
    d$grp <- cap_groups(d[[cby]], lv, cap = 8L)
    pal <- capped_pal(lv, cap = 8L)
    grps <- intersect(c(utils::head(lv, 8L), "Other"), unique(d$grp))   # keep frequency order; Other last
    d$tip <- paste0("<span class='smt-pin-emoji'>\U0001F33F</span> <b>", d$scientificName, "</b><br/>",
      "<em>", d$growthForm, " · plot ", short_plot(d$plotID), "</em><br/>",
      "<span class='smt-pin-stats'>green-up day ", d$greenup, " (", vapply(d$greenup, doy_to_month, ""), ")<br/>",
      "carries leaves ~", d$leaf_active, " days/yr",
      ifelse(is.finite(d$flower), paste0(" · flowers day ", d$flower), ""), "<br/>",
      d$n_years, " yr watched (any metric)</span>",
      "<br/><span class='smt-open' role='button' tabindex='0' data-tag='", d$individualID, "'>\U0001F50E Open plant profile &rarr;</span>",
      "<br/><em class='smt-pin-hint'>Tap the dot to pin this card</em>")
    qcol <- if (is_dark()) "#7e8da0" else "#9aa6b2"; muted <- if (is_dark()) "#9fb0c4" else "#6b7a85"
    p <- plotly::plot_ly()
    for (g in grps) { sub <- d[d$grp==g,]
      p <- p %>% plotly::add_trace(data=sub, x=~greenup, y=~leaf_active, type="scatter", mode="markers", name=g,
        customdata=~tip, marker=list(color=pal[[g]] %||% OTHER_GREY, size=11, opacity=0.82, line=list(color="#fff", width=0.5)),
        text=~scientificName, hovertemplate="%{text}<br>green-up day %{x} · leaf-active ~%{y} d/yr<extra></extra>") }
    xr <- range(d$greenup); yr <- range(d$leaf_active)
    capt <- sprintf("each dot is a plant · green-up onset × days carrying leaves · %d of %d plants placeable (both recorded)", n_placed, n_total)
    ann <- list(list(text=capt, x=0, y=1.07, xref="paper", yref="paper", showarrow=FALSE, xanchor="left", font=list(color=muted, size=11)))
    shp <- list()
    # only draw quadrant labels + median crosshair when there are enough plants
    # AND real spread on both axes — otherwise a 1-3 plant site stacks all four
    # labels on one point and the crosshair is meaningless.
    if (n_placed >= 4 && diff(xr) > 0 && diff(yr) > 0) {
      mx <- stats::median(d$greenup); my <- stats::median(d$leaf_active)
      px <- diff(xr)*0.02; py <- diff(yr)*0.02
      qlab <- function(x,y,t,xa,ya) list(text=t, x=x, y=y, xref="x", yref="y", showarrow=FALSE, xanchor=xa, yanchor=ya, font=list(color=qcol, size=10.5))
      ann <- c(ann, list(
        qlab(xr[1]+px, yr[2]-py, "EARLY & LONG-LEAVED", "left", "top"),
        qlab(xr[2]-px, yr[2]-py, "LATE RISER, LONG-LEAVED", "right", "top"),
        qlab(xr[1]+px, yr[1]+py, "EARLY & BRIEF", "left", "bottom"),
        qlab(xr[2]-px, yr[1]+py, "LATE & BRIEF", "right", "bottom")))
      shp <- list(list(type="line", xref="x", yref="paper", x0=mx, x1=mx, y0=0, y1=1, line=list(color=qcol, dash="dot", width=1)),
                  list(type="line", xref="paper", yref="y", x0=0, x1=1, y0=my, y1=my, line=list(color=qcol, dash="dot", width=1)))
    }
    if (!is.null(rv$ind)) { ir <- d[d$individualID == rv$ind, ]
      if (nrow(ir)==1) p <- p %>% plotly::add_trace(x=ir$greenup, y=ir$leaf_active, type="scatter", mode="markers", name="★ viewing", customdata=ir$tip, showlegend=TRUE,
        marker=list(symbol="diamond", size=18, color="#d98014", line=list(color="#fff", width=1.6)), hovertemplate=paste0("viewing ", ir$scientificName, "<extra></extra>")) }
    p %>% plotly_theme() %>% plotly::layout(xaxis=list(title="Green-up onset (day-of-year) · earlier ← → later"), yaxis=list(title="Days carrying leaves per year · briefer ↓ ↑ longer"),
      shapes=shp, annotations=ann, hovermode="closest")
  })
  output$indCardSlot <- renderUI({
    if (is.null(rv$ind)) return(div(class="qc-empty", div(class="qc-empty-icon","\U0001F33F"), h4("Tap a plant to see its card"),
      p("Tap a dot above and choose “Open plant profile”, or pick a plant from “Open a plant's profile” above the tabs.")))
    r <- rv$ind_summary[rv$ind_summary$individualID == rv$ind,]; if (!nrow(r)) return(NULL)
    div(class="lab-sel", span(class="ls-emoji","\U0001F50E"),
      div(class="ls-body", div(class="ls-id", tags$b(r$scientificName), sprintf(" · green-up day %s · carries leaves ~%s d/yr",
        ifelse(is.finite(r$greenup), r$greenup, "—"), ifelse(is.finite(r$leaf_active), r$leaf_active, "—"))),
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
    gtile <- function(v,l) tile(ifelse(is.finite(v), v, "—"), if (is.finite(v)) paste0(l, " · ", doy_to_month(v)) else l)
    # only flags whose offending rows were actually found are clickable; a 0-row
    # flag (e.g. the "no yes recorded" info note) is shown but not a link.
    has_problem <- any(vapply(flags, function(f) f$level %in% c("high","warn") && f$n > 0, logical(1)))
    qc_icon <- function(lvl) switch(lvl, high="exclamation-octagon-fill", warn="exclamation-triangle-fill", "info-circle-fill")
    flag_items <- lapply(flags, function(f) {
      clickable <- isTRUE(f$n > 0) && f$key %in% names(q$sets)
      div(class = paste0("qc-flag qc-flag-", f$level, if (clickable) " qc-flag-click" else ""),
        role = if (clickable) "button" else NULL, tabindex = if (clickable) "0" else NULL,
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
          r$growthForm, switch(as.character(r$nativeStatusCode), "N"="native", "I"="introduced", "NI"="native & introduced", as.character(r$nativeStatusCode) %||% "—"), short_plot(r$plotID))))),
        div(class="qc-head-badges", glow_badge(paste0(short_ind(r$individualID)), DDL$green))),
      div(class="qc-tiles",
        gtile(r$greenup, "green-up"),
        gtile(r$flower, "first flower"),
        gtile(r$leaf_off, "last leaf-week"),
        tile(ifelse(is.finite(r$leaf_active), paste0(r$leaf_active,"d"), "—"), "days carrying leaves"),
        tile(n_yr, "years watched"), tile(n_ph, "phenophases")),
      div(class="qc-section-h", bs_icon("calendar3-range"), " Phenophase calendar · when each phase happens"),
      plotlyOutput("phenoSpark", height="240px"),
      div(class="qc-section-h", bs_icon("clipboard-check"), " Quality checks ",
        tags$span(class="qcf-sub", "· verify, not errors")),
      div(class="qc-flags", flag_ui),
      if (has_problem) div(class="qcf-hint", bs_icon("hand-index-thumb"), " tap a flag to list the exact records behind it"),
      p(class="qc-cap-note", style="margin-top:8px", bs_icon("info-circle"),
        HTML(" Onset dates are interval-censored to the midpoint between the last 'no' and first 'yes' observation, then taken as the median across monitored years. <b>Last leaf-week</b> is the last week leaves were recorded, not measured senescence (a plant that flushes twice a year carries no single leaf-off date), so read <b>days carrying leaves</b> for growing extent.")))
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
  # ---- site report card (hero band downloadLink) --------------------------
  # Every v2 app ships a Report from the top bar / hero. This app has no PDF
  # render path, so the report is a tidy, well-formed site-summary CSV: one
  # block of headline metrics for the loaded site (and date span), plus a
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
      gu   <- suppressWarnings(stats::median(rv$ind_summary$greenup, na.rm = TRUE))
      la   <- suppressWarnings(stats::median(rv$ind_summary$leaf_active, na.rm = TRUE))
      gu_share <- greenup_coverage(rv$ind_summary)
      cb <- comp_by(inds, "growthForm"); cb <- cb[!is.na(cb$growthForm), , drop = FALSE]
      hdr <- data.frame(
        metric = c("site", "site_name", "label", "year_first", "year_last",
                   "tagged_plants", "species", "phenology_plots",
                   "median_greenup_doy", "median_leaf_active_days",
                   "greenup_coverage_share", "phenophase_records",
                   "data_product", "generated", "app_version", "source"),
        value = c(rv$site %||% "", { r <- site_table[site_table$site == (rv$site %||% ""), ]
                    if (nrow(r)) r$name[1] else "" }, rv$label %||% "",
                  yrs[1], yrs[2], nrow(inds), n_sp, n_pl,
                  if (is.finite(gu)) round(gu) else NA, if (is.finite(la)) round(la) else NA,
                  if (is.finite(gu_share)) round(gu_share, 3) else NA,
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
                               "greenup","flower","leaf_off","leaf_active","left_censored"), names(ko)), drop=FALSE]
      }
      clk <- weekly_yesrate(rv$obs, NULL)
      # individual_summary: the codebook documents taxonRank/is_species + the three
      # *_n_years companion columns. A bundle built before those columns existed
      # lacks them, which would make the export drift from the codebook — so
      # backfill from a fresh individual_summary() (re-derives all five) when any
      # are missing. A rebuilt bundle already carries them and this is a no-op.
      ind_s <- as.data.frame(rv$ind_summary)
      need <- c("taxonRank","is_species","greenup_n_years","flower_n_years","leaf_active_n_years")
      if (!all(need %in% names(ind_s))) {
        fresh <- individual_summary(rv$obs, rv$inds)
        if (!is.null(fresh)) ind_s <- as.data.frame(fresh)
      }
      w <- function(df, nm) if (!is.null(df) && nrow(df)) utils::write.csv(df, file.path(td, nm), row.names=FALSE, na="")
      w(obs, "obs_long.csv"); w(ko, "onsets_by_individual_year.csv")
      w(ind_s, "individual_summary.csv")
      w(clk, "phenology_clock_weekly.csv"); w(as.data.frame(rv$trend), "onset_trend_by_species_year.csv")
      w(phe_codebook_csv(site = rv$site, app_version = APP_VERSION), "codebook.csv")
      writeLines(c(
        sprintf("NEON Plant Phenology Explorer · analysis-ready export for site %s", rv$site %||% ""),
        sprintf("Generated %s · Desert Data Labs · app %s", Sys.Date(), APP_VERSION),
        "Data product: NEON DP1.10055.001 (data.neonscience.org). Not affiliated with NEON/Battelle/NSF.", "",
        "FILES:",
        "  obs_long.csv                     one row per individual x visit x phenophase (tidy long)",
        "  onsets_by_individual_year.csv    per individual-year green-up/flower/leaf-off/leaf-active + left_censored flag",
        "  individual_summary.csv           one row per tagged plant (medians across years)",
        "  phenology_clock_weekly.csv       % of plants 'yes' per phenophase per week (pooled years; n>=5)",
        "  onset_trend_by_species_year.csv  median green-up per species per year (n>=3 individuals)",
        "  codebook.csv                     every column's type/units/definition + _phenophase_decode + _provenance", "",
        "Unit of analysis: tagged plant individual (repeated measures); plotID = spatial block.",
        "TIMING, not abundance. Onset is interval-censored. The clock pools years by design.",
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
           pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2"); legtitle <- "plants tagged"; nalab <- "—" }
    mx <- max(ps$n_ind, 1); ps$radius <- 8 + 13 * sqrt(pmax(ps$n_ind, 1)) / sqrt(mx)   # area ∝ plants
    # The popup LEADS WITH the selected metric, so it matches the dot colour (at
    # desert sites green-up is scored for ~0-19% of plants, so leaf-active is the
    # honest lead). Each stat is rendered once; the off-metric stat is a secondary line.
    thin    <- is.finite(ps$gu_share) & ps$gu_share < GU_COVERAGE_FLOOR
    gu_str  <- ifelse(is.finite(ps$greenup),
                 paste0("day ", ps$greenup, " (", doy_to_month(ps$greenup), ")"), "not yet scored")
    la_str  <- ifelse(is.finite(ps$leaf_active), paste0("~", ps$leaf_active, " d/yr"), "not yet recorded")
    # per-plot green-up coverage caveat — only shown when green-up actually leads
    # or is the secondary line, so a 1/5-of-plants plot can't read like a whole-plot number.
    covtxt <- ifelse(thin,
      sprintf("<br><span style='color:#b5481f'>green-up scored for %d%% of plants here. Read leaf-active.</span>", round(ps$gu_share * 100)), "")
    lead_la <- sprintf("<b>leaf-active %s</b><br><span class='pm-pop-sub'>green-up %s</span>%s", la_str, gu_str, covtxt)
    lead_gu <- sprintf("<b>green-up %s</b>%s<br><span class='pm-pop-sub'>carries leaves %s</span>", gu_str, covtxt, la_str)
    lead_n  <- sprintf("<span class='pm-pop-sub'>green-up %s%s · leaf-active %s</span>", gu_str,
                 ifelse(thin, sprintf(" (scored for %d%% of plants)", round(ps$gu_share * 100)), ""), la_str)
    metric_line <- if (metric == "leaf_active") lead_la else if (metric == "greenup") lead_gu else lead_n
    lab <- sprintf("<b>%s</b> · %d plants<br>%s", short_plot(ps$plotID), ps$n_ind, metric_line)
    leaflet::leaflet(ps) %>% leaflet::addProviderTiles(input$view %||% "CartoDB.Positron") %>%
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
  output$gradientPlot <- renderPlotly({
    st <- site_table
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
    p %>% plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE, annotations=ann,
      xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median green-up (day-of-year)"))
  })
  output$gradientInsight <- renderUI({
    st <- site_table; if (!("median_greenup" %in% names(st))) return(NULL)
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
    ws <- within_species_gradient(NATIONAL_ONSETS, min_sites = 4)
    if (!is.null(ws)) {
      sp_short <- sub("^([A-Z][a-z]+ [a-z\\-]+).*$", "\\1", ws$species)
      return(tagList(insight_banner(if (ws$slope >= 0) "graph-up-arrow" else "graph-down-arrow", tone="pine", HTML(sprintf(
        "Holding the species constant, <b><em>%s</em></b> greens up <b>%.1f days %s per °N</b> across <b>%d</b> sites (95%% CI %.1f to %.1f, R²=%.2f), the spatial echo of Hopkins' bioclimatic law, with the species-mix confound removed. <em>The across-network slope (all species pooled, ~%.0f d/°N) is a coarser echo of the same temperature signal.</em>",
        sp_short, abs(ws$slope), if (ws$slope >= 0) "later" else "earlier", ws$n_sites, ws$lo, ws$hi, ws$r2, abs(net_slope)))), cad_badge))
    }
    tagList(insight_banner(if (net_slope >= 0) "graph-up-arrow" else "graph-down-arrow", tone="pine", HTML(sprintf(
      "Across <b>%d</b> sites, green-up shifts roughly <b>%.0f days %s per degree of latitude north</b>, the spatial echo of Hopkins' bioclimatic law. <em>Each point is a site's median across its species (different species mixes, n as few as 4), so read it as a coarse across-network gradient, not a controlled comparison.</em>",
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
    d <- no[no$scientificName == sp & is.finite(no$greenup), , drop=FALSE]
    if (nrow(d) < 2) return(note_plot("This species is bundled at only one site", "\U0001F33F"))
    d <- d[order(d$lat),]
    # markers only — a line through discrete sites would fabricate a continuous
    # latitudinal path that was never estimated.
    plotly::plot_ly(d, x=~lat, y=~greenup, type="scatter", mode="markers",
      text=~site, customdata=~n_ind, marker=list(size=12, color="#1f7a3f", line=list(color="#fff", width=1)),
      hovertemplate=paste0("<b>", sp, "</b> @ %{text}<br>lat %{x:.1f}°N · green-up day %{y} (n=%{customdata} plants)<extra></extra>")) %>%
      plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE,
        xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median green-up (day-of-year)"))
  })

  output$aboutPanel <- renderUI({
    div(class="about-wrap",
      div(class="about-card", h4("\U0001F33F What this is"),
        p("An (unofficial) explorer for NEON's ", tags$b("Plant phenology observations"), " (", tags$code("DP1.10055.001"), "). A fixed roster of tagged plants along transects is checked ", tags$b("up to twice a week"), " through the growing season; for each, observers record which ", tags$b("phenophases"), " are active: breaking leaf buds, leaves, open flowers, colored leaves, falling leaves.")),
      div(class="about-card", h4(bs_icon("clock-history"), " Timing, not abundance"),
        p("Phenology is a ", tags$b("timing signal"), ": when a plant wakes, blooms, and senesces. Because the roster is fixed, it is not a measure of how common a species is. It tracks the ", tags$b("calendar of the canopy"), ", and how that calendar shifts year to year."),
        p("Onset is ", tags$b("interval-censored"), ": the true first-leaf day lies between the last 'no' and first 'yes' visit, so we use the midpoint, honest about the twice-weekly resolution.")),
      div(class="about-card", h4(bs_icon("graph-down-arrow"), " Why it matters"),
        p("Shifts in green-up and bloom timing are among the clearest biological fingerprints of a changing climate, and drive mismatches with pollinators and migrating birds."),
        p(bs_icon("envelope"), " ", tags$a(href="mailto:desertdatalabs@gmail.com","desertdatalabs@gmail.com"), " · ",
          tags$a(href="https://data.neonscience.org/data-products/DP1.10055.001", target="_blank", "NEON data product"))),
      div(class="about-card", h4(bs_icon("grid-3x3-gap-fill"), " The NEON series"),
        p("This is one of a family of explorers, each built on a different NEON data product, that share the same look and the same honest-stats approach."),
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
  doy_lab <- function(d) ifelse(is.finite(d), sprintf("%s (%s)", d, doy_to_month(d)), "—")
  # leaf_active is a COUNT of days a plant carries leaves per year (distinct
  # leaf-weeks x 7), NOT a day-of-year. It must read as a duration ("110 days"),
  # never as a calendar date (doy_to_month would turn 110 into a fake "Apr 20").
  days_lab <- function(d) ifelse(is.finite(d), sprintf("%s days", round(d)), "—")
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
    d[order(d$greenup, d$site), , drop = FALSE]
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
      tags$em(sprintf(" monitor %s. ", sp)),
      tags$span(class = "muted", sprintf("Green-up day shown for %d; the rest are scored straight into leaves.", ng)))
  })
  output$searchTaxonTbl <- DT::renderDT({
    d <- taxon_rows(); if (!nrow(d)) return(NULL)
    out <- data.frame(
      Site = sprintf("<b>%s</b> · %s", d$site, d$name %||% d$site),
      State = d$state,
      `Green-up day` = vapply(d$greenup, doy_lab, character(1)),
      `Days carrying leaves` = vapply(d$leaf_active, days_lab, character(1)),
      Plants = d$n_ind,
      Years = ifelse(is.na(d$year_min), "—", ifelse(d$year_min == d$year_max,
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
      Site = sprintf("<b>%s</b> · %s", d$site, d$name %||% d$site),
      State = d$state,
      `Median green-up day` = vapply(d$median_greenup, doy_lab, character(1)),
      Species = d$n_species,
      Plants = d$n_individuals,
      Years = ifelse(is.na(d$year_min), "—", sprintf("%s–%s", d$year_min, d$year_max)),
      ` ` = go_btn(d$site),
      check.names = FALSE, stringsAsFactors = FALSE)
    DT::datatable(out, escape = FALSE, rownames = FALSE, selection = "none",
      options = list(pageLength = 15, dom = "tip", autoWidth = FALSE,
        columnDefs = list(list(orderable = FALSE, targets = ncol(out) - 1))),
      class = "compact stripe hover")
  }, server = FALSE)
}
