# ===========================================================================
# write_manifest.R — (re)generate manifest.json for a lean, bundle-only
# Posit Connect Cloud deploy (git-backed).
#
# Bundles ONLY what the running app needs: global/ui/server + R/ + www/ + the
# precomputed indexes (data/*.rds) + the per-site bundles (data/sites/*.rds) +
# the demo sample. It does NOT bundle scripts/, docs/, rsconnect/, or the README.
#
# neonUtilities is intentionally EXCLUDED — it's referenced dynamically in
# global.R (.NEON_PKG) so the dependency scanner never pins it, keeping the
# deploy lean (no wasm build; live-pull-on-cold-worker is a hang risk). The
# deployed app is bundle-only; the optional live-fetch still works in local dev.
#
# Run with an R that has the app's runtime packages (R 4.5.2 here has them all):
#   "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" scripts/write_manifest.R
# Re-run whenever runtime dependencies change, then commit manifest.json.
#
# HARD GATE: after writing, this parses manifest.json and stop()s with a non-zero
# error if neonUtilities / arrow / data.table leaked in as a package key. A leaked
# manifest pins a heavy (wasm-hostile) dependency the deployed bundle never needs,
# so it must NEVER commit silently — the gate fails the build instead.
# ===========================================================================
suppressMessages(library(rsconnect))

# Connect Cloud installs Linux package BINARIES from Posit Package Manager (RSPM)
# rather than compiling CRAN source. This is CRITICAL for the leaflet -> raster ->
# terra chain: terra's source build needs GDAL >= 3.5, but Connect's image ships
# GDAL 3.4.1, so a from-source terra fails to compile and aborts the whole publish.
# Pin the repo to the RSPM jammy (Ubuntu 22.04) BINARY mirror so a precompiled terra
# is installed instead. NOTE: the __linux__/jammy path is what makes RSPM serve
# binaries — the bare .../cran/latest URL still resolves to SOURCE on Linux. If a
# regen ever records a non-binary URL, swap it to this one before committing.
options(repos = c(RSPM = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))

appFiles <- c(
  "global.R", "ui.R", "server.R",
  list.files("R", pattern = "\\.R$", full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE),
  Sys.glob("data/*.rds"),                                       # site_index + national_onsets + search_index
  list.files("data/sites", pattern = "\\.rds$", full.names = TRUE),
  list.files("data-sample", pattern = "\\.rds$", full.names = TRUE)
)
appFiles <- unique(appFiles[file.exists(appFiles)])

cat(sprintf("Writing manifest for %d files (%d site bundles)...\n",
            length(appFiles), length(list.files("data/sites", pattern = "\\.rds$"))))
rsconnect::writeManifest(appDir = ".", appFiles = appFiles)

# ---- HARD GATE (CHECK-ONLY — never re-serialize the manifest) ----------------
# neonUtilities is kept out by the dynamic computed-name reference (the scanner
# never sees it); arrow is a live-fetch-only over-capture. writeManifest() does
# not capture either, so there is nothing to prune — we only VERIFY.
# CRITICAL: do NOT rewrite manifest.json here. rsconnect emits a canonical
# format (file checksums, metadata) that Connect Cloud validates; re-serializing
# it with jsonlite mangles that format and Connect rejects the deploy as
# "invalid manifest." data.table is a legitimate plotly hard dependency (Connect's
# base image lacks it) and MUST stay.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
BANNED <- c("neonUtilities", "arrow")
mj   <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
pkgs <- names(mj$packages %||% list())
cat(sprintf("manifest.json written: %d packages.\n", length(pkgs)))
leaked <- intersect(BANNED, pkgs)
if (length(leaked))
  stop(sprintf("MANIFEST GATE FAILED: banned package(s) present: %s. Investigate the computed-name dodge / appFiles scope and regenerate — do NOT hand-edit the manifest.",
               paste(leaked, collapse = ", ")), call. = FALSE)
if ("plotly" %in% pkgs && !"data.table" %in% pkgs)
  stop("data.table is MISSING while plotly is present. Connect's base image lacks data.table, so the deploy will fail. Regenerate with writeManifest; never prune data.table.", call. = FALSE)
cat("OK: lean manifest (no neonUtilities/arrow); data.table present for plotly.\n")
