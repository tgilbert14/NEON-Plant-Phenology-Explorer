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
  observeEvent(input$demoBtn, ingest(load_demo(), DEMO_META$label, is_demo=TRUE)); observeEvent(input$demoBtn2, ingest(load_demo(), DEMO_META$label, is_demo=TRUE))

  # ---- national site-picker map (the splash landing) --------------------
  # STATIC leafletOutput in ui (never inside renderUI — avoids the re-bind race).
  output$nationalMap <- leaflet::renderLeaflet({
    st <- site_table[is.finite(site_table$lat) & is.finite(site_table$lng), , drop=FALSE]
    if (!nrow(st)) return(leaflet::leaflet() %>% leaflet::addProviderTiles("CartoDB.Positron") %>% leaflet::setView(-96, 38, 3))
    gv <- if ("median_greenup" %in% names(st)) suppressWarnings(as.numeric(st$median_greenup)) else rep(NA_real_, nrow(st))
    pal <- greenup_pal(gv)
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
        fillColor=pal(gv), color=mk_stroke, weight=1, fillOpacity=mk_opacity,
        label=lapply(lab, htmltools::HTML), popup=pop,
        popupOptions=leaflet::popupOptions(className="pm-pop-card")) %>%
      leaflet::addLegend("bottomright", pal=pal, values=gv[is.finite(gv)], title="median green-up DOY", na.label="—")
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
    div(class="hero-band", div(class="hero-title", bs_icon("flower3"), tags$b(rv$label)),
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
    pal <- make_species_pal(tr)
    p <- plotly::plot_ly()
    for (s in unique(tr$scientificName)) { d <- tr[tr$scientificName==s,]; d <- d[order(d$year),]
      p <- p %>% plotly::add_trace(data=d, x=~year, y=~onset, type="scatter", mode="lines+markers", name=s,
        line=list(color=pal[[s]], width=2), marker=list(color=pal[[s]], size=7),
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
    cby <- input$onsetColor %||% "growthForm"; d$grp <- as.character(d[[cby]]); d$grp[is.na(d$grp)] <- "—"
    grps <- sort(unique(d$grp)); pal <- stats::setNames(grDevices::colorRampPalette(RColorBrewer::brewer.pal(8,"Dark2"))(length(grps)), grps)
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
        customdata=~tip, marker=list(color=pal[[g]], size=11, opacity=0.82, line=list(color="#fff", width=0.5)),
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
      p("Tap a dot above and choose “Open plant profile”, or pick a plant in the sidebar.")))
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
      p("Use the Onset Lab (tap a dot → “Open plant profile”) or the sidebar picker.")))
    r <- rv$ind_summary[rv$ind_summary$individualID == rv$ind,]; req(nrow(r)==1)
    h <- indiv_history(rv$obs, rv$ind); flags <- pheno_qc_flags(h, r$growthForm)
    n_ph <- if (!is.null(h)) dplyr::n_distinct(h$phenophaseName[h$status=="yes"]) else 0
    n_yr <- if (!is.null(h)) dplyr::n_distinct(h$year) else 0
    tile <- function(v,l) div(class="qc-tile", div(class="qc-tile-v", v), div(class="qc-tile-l", l))
    # day-of-year tile that shows the calendar date in its label (no bare DOY)
    gtile <- function(v,l) tile(ifelse(is.finite(v), v, "—"), if (is.finite(v)) paste0(l, " · ", doy_to_month(v)) else l)
    has_problem <- any(vapply(flags, function(f) f$level %in% c("high","warn"), logical(1)))
    flag_items <- lapply(flags, function(f) div(class=paste0("qc-flag qc-flag-", f$level),
      bs_icon(switch(f$level, high="exclamation-octagon-fill", warn="exclamation-triangle-fill", "info-circle-fill")), span(HTML(f$text))))
    flag_ui <- if (!has_problem) c(list(div(class="qc-flag qc-flag-ok", bs_icon("check-circle-fill"),
      span("No phenophase-ordering issues detected for this plant."))), flag_items) else flag_items
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
      div(class="qc-section-h", bs_icon("clipboard-check"), " Quality checks"),
      div(class="qc-flags", flag_ui),
      p(class="qc-cap-note", style="margin-top:8px", bs_icon("info-circle"),
        HTML(" Onset dates are interval-censored to the midpoint between the last 'no' and first 'yes' observation, then taken as the median across monitored years. <b>Last leaf-week</b> is the last week leaves were recorded, not measured senescence (a plant that flushes twice a year carries no single leaf-off date), so read <b>days carrying leaves</b> for growing extent.")))
    div(div(class="plot-profile-wrap", body), div(class="qc-toolbar",
      tags$button(class="smt-snap-btn", type="button", onclick="smtSaveQcCard()", bsicons::bs_icon("download"), " Save plant card (PNG)"),
      downloadButton("indCsv", "Download history (CSV)", class="smt-clear-btn")))
  })
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
      w <- function(df, nm) if (!is.null(df) && nrow(df)) utils::write.csv(df, file.path(td, nm), row.names=FALSE, na="")
      w(obs, "obs_long.csv"); w(ko, "onsets_by_individual_year.csv")
      w(as.data.frame(rv$ind_summary), "individual_summary.csv")
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
    if (metric == "greenup") { pal <- greenup_pal(val[has]); legtitle <- "median green-up DOY (earlier = green)"; nalab <- "no green-up scored" }
    else if (metric == "leaf_active") {
      dom <- if (sum(has) && diff(range(val[has])) > 0) range(val[has]) else c(0, max(val[has], 1))
      pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2"); legtitle <- "median leaf-active days/yr"; nalab <- "no leaf record" }
    else { dom <- if (sum(has) && diff(range(val[has])) > 0) range(val[has]) else c(0, max(val[has], 1))
           pal <- leaflet::colorNumeric("YlGn", domain = dom, na.color = "#c4c0b2"); legtitle <- "plants tagged"; nalab <- "—" }
    mx <- max(ps$n_ind, 1); ps$radius <- 8 + 13 * sqrt(pmax(ps$n_ind, 1)) / sqrt(mx)   # area ∝ plants
    mon <- doy_to_month(ps$greenup)
    gtxt <- ifelse(is.finite(ps$greenup), paste0("day ", ps$greenup, " (", mon, ")"), "no green-up scored")
    # per-plot green-up coverage — say it on the marker where the number is thin,
    # so a 1/5-of-plants plot can't read like a whole-plot number.
    covtxt <- ifelse(is.finite(ps$gu_share) & ps$gu_share < GU_COVERAGE_FLOOR,
      sprintf("<br><span style='color:#b5481f'>green-up scored for %d%% of plants. Read leaf-active</span>", round(ps$gu_share * 100)), "")
    latxt <- ifelse(is.finite(ps$leaf_active), paste0(" · carries leaves ~", ps$leaf_active, " d/yr"), "")
    lab <- sprintf("<b>%s</b><br>%d plants · green-up %s%s%s", short_plot(ps$plotID), ps$n_ind, gtxt, latxt, covtxt)
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
    cols <- greenup_pal(d$median_greenup)(d$median_greenup)
    d$n_species <- if ("n_species" %in% names(d)) d$n_species else NA_integer_
    p <- plotly::plot_ly(d, x=~lat, y=~median_greenup, type="scatter", mode="markers",
      text=~paste0(site, " · ", name), customdata=~n_species,
      marker=list(size=11, color=cols, line=list(color="#fff", width=0.8)),
      hovertemplate="<b>%{text}</b><br>lat %{x:.1f}°N · green-up day %{y} (%{customdata} species)<extra></extra>")
    fit <- stats::lm(median_greenup ~ lat, data=d)
    xs <- range(d$lat); ys <- as.numeric(stats::predict(fit, newdata=data.frame(lat=xs)))
    p <- p %>% plotly::add_trace(x=xs, y=ys, type="scatter", mode="lines", inherit=FALSE,
      line=list(color="#b5481f", width=2, dash="dash"), hoverinfo="skip", showlegend=FALSE)
    p %>% plotly_theme(legend=FALSE) %>% plotly::layout(showlegend=FALSE,
      xaxis=list(title="Site latitude (°N)"), yaxis=list(title="Median green-up (day-of-year)"))
  })
  output$gradientInsight <- renderUI({
    st <- site_table; if (!("median_greenup" %in% names(st))) return(NULL)
    d <- st[is.finite(st$median_greenup) & is.finite(st$lat), , drop=FALSE]
    if (nrow(d) < 4) return(NULL)
    co <- summary(stats::lm(median_greenup ~ lat, data=d))$coefficients; net_slope <- co[2,1]
    # LEAD with the within-species slope (the confound-controlled read the app
    # already computes in the secondary panel); demote the network slope to the
    # coarse echo it is. Falls back to the network read if no species spans enough
    # sites yet (older/partial bundles).
    ws <- within_species_gradient(NATIONAL_ONSETS, min_sites = 4)
    if (!is.null(ws)) {
      sp_short <- sub("^([A-Z][a-z]+ [a-z\\-]+).*$", "\\1", ws$species)
      return(insight_banner(if (ws$slope >= 0) "graph-up-arrow" else "graph-down-arrow", tone="pine", HTML(sprintf(
        "Holding the species constant, <b><em>%s</em></b> greens up <b>%.1f days %s per °N</b> across <b>%d</b> sites (95%% CI %.1f to %.1f, R²=%.2f), the spatial echo of Hopkins' bioclimatic law, with the species-mix confound removed. <em>The across-network slope (all species pooled, ~%.0f d/°N) is a coarser echo of the same temperature signal.</em>",
        sp_short, abs(ws$slope), if (ws$slope >= 0) "later" else "earlier", ws$n_sites, ws$lo, ws$hi, ws$r2, abs(net_slope)))))
    }
    insight_banner(if (net_slope >= 0) "graph-up-arrow" else "graph-down-arrow", tone="pine", HTML(sprintf(
      "Across <b>%d</b> sites, green-up shifts roughly <b>%.0f days %s per degree of latitude north</b>, the spatial echo of Hopkins' bioclimatic law. <em>Each point is a site's median across its species (different species mixes, n as few as 4), so read it as a coarse across-network gradient, not a controlled comparison.</em>",
      nrow(d), abs(net_slope), if (net_slope >= 0) "later" else "earlier")))
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
          tags$a(href="https://data.neonscience.org/data-products/DP1.10055.001", target="_blank", "NEON data product"))))
  })
  observeEvent(input$help, showModal(modalDialog(easyClose=TRUE, title=tagList(bs_icon("question-circle"), " How it works"),
    tags$ul(
      tags$li(HTML("Pick a <b>site</b> (or open the Harvard Forest demo).")),
      tags$li(HTML("<b>Phenology Clock</b> · the typical year, week by week; switch species to compare.")),
      tags$li(HTML("<b>Onset Lab</b> · every plant by green-up onset × season length; <b>tap one</b> to pin its card, then “Open plant profile”.")),
      tags$li(HTML("<b>Plant Profile</b> · a plant's phenophase calendar, onset dates, quality checks, and downloads.")),
      tags$li(HTML("Phenology is a <b>timing</b> signal on a fixed roster, not a measure of abundance."))),
    footer=modalButton("Got it"))))
}
