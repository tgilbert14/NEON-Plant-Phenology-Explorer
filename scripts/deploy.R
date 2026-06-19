# Optional shinyapps.io deploy (legacy fallback). The PRIMARY home is Posit
# Connect Cloud, which deploys straight from this git repo via manifest.json
# (scripts/write_manifest.R) and auto-republishes on every push — no token needed.
# Use this only if you also want a shinyapps.io mirror.
#   Rscript scripts/deploy.R   (after rsconnect::setAccountInfo(...))
# NOTE: shinyapps.io retires 2026-12-31 — prefer Connect Cloud.
suppressMessages(library(rsconnect))
files <- c("global.R", "ui.R", "server.R",
           list.files("R", pattern = "\\.R$", full.names = TRUE),
           list.files("www", recursive = TRUE, full.names = TRUE),
           list.files("data-sample", pattern = "\\.rds$", full.names = TRUE),
           Sys.glob("data/*.rds"),                                  # indexes + national_onsets
           list.files("data/sites", pattern = "\\.rds$", full.names = TRUE))
files <- unique(files[file.exists(files)])
cat("Bundling", length(files), "files (",
    length(list.files("data/sites", pattern = "\\.rds$")), "bundled sites )\n")
deployApp(appDir = ".", appFiles = files,
          appName = "NEONPlantPhenology", account = "t-lama", server = "shinyapps.io",
          forceUpdate = TRUE, launch.browser = FALSE, logLevel = "normal")
cat("\nDEPLOY_DONE\n")
