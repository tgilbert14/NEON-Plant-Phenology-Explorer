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
source("scripts/bundle_identity.R") # materialize portable raw-table vectors

tok <- Sys.getenv("NEON_TOKEN", "")
# Local runs may fall back to a token file; CI must use the NEON_TOKEN secret
# (the refresh gate probes it first), so the fallback never runs there.
if (!nzchar(tok) && !identical(Sys.getenv("CI"), "true"))
  for (f in c("../App-NEON-Small-Mammal-Tracker/.neon_token", ".neon_token"))
    if (file.exists(f)) { tok <- trimws(readLines(f, warn = FALSE))[1]; break }

outdir <- Sys.getenv("PHE_RAW_OUT_DIR", "../phe-data-fetch")
enddate <- Sys.getenv("PHE_ENDDATE", format(Sys.Date(), "%Y-%m"))
# Start of the bundled record. 2016-01 is deliberate: 2013-2015 seasons exist for
# 28 sites but were early, pre-operational years under an earlier protocol, and
# starting every site in 2016 keeps the site-year support gate comparable across
# the network. Set PHE_STARTDATE (YYYY-MM) to change it; re-bundle through the
# review-branch refresh when you do.
startdate <- Sys.getenv("PHE_STARTDATE", "2016-01")
if (!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", startdate))
  stop("PHE_STARTDATE must use YYYY-MM; got: ", startdate)
if (!grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", enddate))
  stop("PHE_ENDDATE must use YYYY-MM; got: ", enddate)
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

# site universe = the app's terrestrial site table
source("R/site_metadata.R")
sites <- neon_sites$site
args  <- commandArgs(trailingOnly = TRUE); if (length(args)) sites <- args

# One pinned NEON release, released data only (PHE_RELEASE in R/site_metadata.R).
release <- if (exists("PHE_RELEASE")) PHE_RELEASE$tag else stop("PHE_RELEASE is not defined in R/site_metadata.R")
cat(sprintf("Fetching %d sites %s to %s from %s (released data only) | token: %s | %s\n",
            length(sites), startdate, enddate, release, nzchar(tok), R.version.string)); flush.console()
ok <- character(0); empty <- character(0); failed <- character(0)
for (s in sites) {
  outf <- file.path(outdir, paste0(s, "_raw.rds"))
  if (file.exists(outf)) { cat("skip (have)  ", s, "\n"); ok <- c(ok, s); flush.console(); next }
  cat("=== fetching ", s, " ===\n"); flush.console()
  res <- tryCatch(
    loadByProduct(dpID = "DP1.10055.001", site = s,
                  startdate = startdate, enddate = enddate,
                  package = "basic", check.size = "FALSE",
                  release = release, include.provisional = FALSE,
                  token = if (nzchar(tok)) tok else NA),
    error = function(e) { cat("  ERROR:", conditionMessage(e), "\n"); failed <<- c(failed, s); NULL })
  if (s %in% failed) { flush.console(); next }
  if (is.null(res) || is.null(res$phe_statusintensity) || !nrow(res$phe_statusintensity)) {
    cat("  no phenology data for", s, "\n"); empty <- c(empty, s); flush.console(); next
  }
  res <- materialize_phenology_raw_result(res, s)
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
if (length(failed)) {
  message("::error title=NEON fetch failed::", paste(failed, collapse = " "))
  quit(status = 1)
}
cat("ALL DONE\n")
