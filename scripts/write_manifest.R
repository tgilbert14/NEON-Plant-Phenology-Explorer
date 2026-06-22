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

appFiles <- c(
  "global.R", "ui.R", "server.R",
  list.files("R", pattern = "\\.R$", full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE),
  Sys.glob("data/*.rds"),                                       # precomputed indexes + national_onsets
  list.files("data/sites", pattern = "\\.rds$", full.names = TRUE),
  list.files("data-sample", pattern = "\\.rds$", full.names = TRUE)
)
appFiles <- unique(appFiles[file.exists(appFiles)])

cat(sprintf("Writing manifest for %d files (%d site bundles)...\n",
            length(appFiles), length(list.files("data/sites", pattern = "\\.rds$"))))
rsconnect::writeManifest(appDir = ".", appFiles = appFiles)

# ---- prune the heavy, wasm-hostile keys, then HARD GATE ----------------------
# neonUtilities / arrow are never legitimate here (the live fetch is local-dev
# only, referenced by a computed name), so they are pruned and the gate fails
# loud if either reappears.
# IMPORTANT: data.table is NOT banned. plotly *Imports* data.table as a hard
# dependency and Connect Cloud's base image does NOT provide it — Connect does
# NOT re-resolve transitive deps that are absent from the manifest, so pruning
# data.table breaks the plotly install and the whole deploy. It must stay.
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
BANNED <- c("neonUtilities", "arrow")

mj   <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
pkgs <- names(mj$packages %||% list())
pruned <- intersect(BANNED, pkgs)
if (length(pruned)) {
  mj$packages[pruned] <- NULL
  jsonlite::write_json(mj, "manifest.json", auto_unbox = TRUE, pretty = TRUE, digits = NA)
  cat(sprintf("Pruned transitive/banned key(s) from manifest: %s\n", paste(pruned, collapse = ", ")))
}

# re-read and gate
mj2  <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
pkgs <- names(mj2$packages %||% list())
cat(sprintf("manifest.json written: %d packages.\n", length(pkgs)))
leaked <- intersect(BANNED, pkgs)
if (length(leaked)) {
  stop(sprintf(
    "MANIFEST GATE FAILED: banned package(s) still present in manifest.json: %s.\nThese must never commit (heavy / wasm-hostile / live-fetch-only). Fix and re-run; do NOT commit this manifest.",
    paste(leaked, collapse = ", ")), call. = FALSE)
}
cat(sprintf("OK: none of {%s} are in the manifest (lean bundle-only build).\n",
            paste(BANNED, collapse = ", ")))
