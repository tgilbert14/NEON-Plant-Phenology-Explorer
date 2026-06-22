# Local-dev convenience only: hop to the repo root if run from elsewhere (e.g.
# RStudio). Skipped where the path doesn't exist (CI / another machine), where the
# relative paths below already resolve from the repo root.
.root <- "C:/Users/tsgil/OneDrive/Documents/VGS - R/NEON-Plant-Phenology"
if (dir.exists(.root)) setwd(.root)
suppressPackageStartupMessages({ library(dplyr); library(tidyr) })
source("R/site_metadata.R"); source("R/phe_helpers.R")
b <- readRDS("data/sites/HARV.rds"); obs <- b$obs; inds <- b$inds
ok <- function(lbl, x) cat(sprintf("%-34s %s\n", lbl, x))

t <- system.time({ is_ <- individual_summary(obs, inds) })
ok("individual_summary rows", nrow(is_)); ok("  cols", paste(names(is_), collapse=","))
ok("  placeable (greenup&leaf_active)", sum(is.finite(is_$greenup) & is.finite(is_$leaf_active)))
ok("  median greenup", round(median(is_$greenup, na.rm=TRUE)))
ok("  median leaf_off", round(median(is_$leaf_off, na.rm=TRUE)))
ok("  median leaf_active", round(median(is_$leaf_active, na.rm=TRUE)))
ok("individual_summary time(s)", round(t[["elapsed"]],2))

wk_all <- weekly_yesrate(obs); ok("weekly_yesrate(all) rows", nrow(wk_all))
ok("  phenophases", paste(unique(wk_all$phenophaseName), collapse=" | "))
ok("  max rate", max(wk_all$rate))
wk_sp <- weekly_yesrate(obs, "Acer rubrum L."); ok("weekly_yesrate(Acer) rows", nrow(wk_sp))

tr <- onset_trend(obs); ok("onset_trend rows", if (is.null(tr)) 0 else nrow(tr))
if (!is.null(tr)) ok("  species-years", paste(head(sort(unique(tr$scientificName)),3), collapse=", "))

id <- is_$individualID[which(is.finite(is_$greenup) & is.finite(is_$leaf_active))[1]]
h <- indiv_history(obs, id); ok("indiv_history rows", nrow(h)); ok("  for", id)
q <- pheno_qc_flags(h); fl <- q$flags; ok("qc flags", length(fl)); ok("  qc sets (with rows)", length(q$sets))
if (length(fl)) for (f in fl) ok(paste0("  [",f$level,"] n=",f$n), substr(f$text,1,55))
rep <- phe_qc_report(h); ok("phe_qc_report rows", if (is.null(rep)) 0 else nrow(rep))

ps <- plot_summary_phe(obs, inds); ok("plot_summary_phe rows", nrow(ps))
ok("  cols", paste(names(ps), collapse=","))
ok("doy_to_month(120)", { dm <- format(as.Date(119, origin="2021-01-01"), "%b %d"); dm })

cat("\nALL HELPERS OK\n")
