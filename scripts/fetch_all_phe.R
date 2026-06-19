# ===========================================================================
# Fetch ALL NEON terrestrial Plant phenology observations (DP1.10055.001)
# raw bundles, in pieces. Resumable: skips any site whose <SITE>_raw.rds
# already exists in ../phe-data-fetch/, so it can be re-run / restarted safely.
#
# Run with an R build that has neonUtilities. Token via env NEON_TOKEN, else
# the sibling mammal repo's .neon_token (read, never printed).
#   Rscript scripts/fetch_all_phe.R              # all sites in R/site_metadata.R
#   Rscript scripts/fetch_all_phe.R BART SERC    # just these sites
# ===========================================================================
suppressPackageStartupMessages(library(neonUtilities))

tok <- Sys.getenv("NEON_TOKEN", "")
if (!nzchar(tok)) for (f in c("../App-NEON-Small-Mammal-Tracker/.neon_token", ".neon_token"))
  if (file.exists(f)) { tok <- trimws(readLines(f, warn = FALSE))[1]; break }

outdir <- "../phe-data-fetch"; dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# site universe = the app's terrestrial site table
source("R/site_metadata.R")
sites <- neon_sites$site
args  <- commandArgs(trailingOnly = TRUE); if (length(args)) sites <- args

cat(sprintf("Fetching %d sites | token: %s | %s\n", length(sites), nzchar(tok), R.version.string)); flush.console()
ok <- character(0); empty <- character(0); failed <- character(0)
for (s in sites) {
  outf <- file.path(outdir, paste0(s, "_raw.rds"))
  if (file.exists(outf)) { cat("skip (have)  ", s, "\n"); ok <- c(ok, s); flush.console(); next }
  cat("=== fetching ", s, " ===\n"); flush.console()
  res <- tryCatch(
    loadByProduct(dpID = "DP1.10055.001", site = s,
                  startdate = "2016-01", enddate = "2024-12",
                  package = "basic", check.size = "FALSE",
                  token = if (nzchar(tok)) tok else NA),
    error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); NULL })
  if (is.null(res) || is.null(res$phe_statusintensity) || !nrow(res$phe_statusintensity)) {
    cat("  no phenology data for", s, "\n"); empty <- c(empty, s); flush.console(); next
  }
  saveRDS(res, outf)
  cat(sprintf("  saved %s — status rows: %s, individuals: %s\n", s,
      format(nrow(res$phe_statusintensity), big.mark = ","),
      if (!is.null(res$phe_perindividual)) nrow(res$phe_perindividual) else NA)); flush.console()
  ok <- c(ok, s)
}
cat("\n==== FETCH SUMMARY ====\n")
cat("have/ok :", length(ok),    paste(ok, collapse = " "), "\n")
cat("empty   :", length(empty), paste(empty, collapse = " "), "\n")
cat("failed  :", length(failed),paste(failed, collapse = " "), "\n")
cat("ALL DONE\n")
