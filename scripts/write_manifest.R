#!/usr/bin/env Rscript

# Generate the lean, reproducible Posit Connect manifest for the bundle-only app.
# This script must run only in the pinned validator. It snapshots what is actually
# installed, prunes build/live-fetch-only dependencies by reachability, freezes
# ordinary packages to a dated RSPM lane, and verifies the exact source-built
# geospatial closure. Never hand-edit manifest.json.

suppressMessages({
  library(rsconnect)
  library(jsonlite)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

RSPM_SNAPSHOT <-
  "https://packagemanager.posit.co/cran/__linux__/jammy/2026-07-15"
R_PLATFORM_PIN <- "4.5.2"

GEO_PINS <- c(
  terra = "1.8-50", sf = "1.1-1", s2 = "1.1.11", units = "1.0-1",
  wk = "0.9.5", classInt = "0.4-11", raster = "3.6-32", sp = "2.2-1"
)
GEO_URLS <- c(
  terra = "https://cran.r-project.org/src/contrib/Archive/terra/terra_1.8-50.tar.gz",
  sf = "https://cran.r-project.org/src/contrib/sf_1.1-1.tar.gz",
  s2 = "https://cran.r-project.org/src/contrib/s2_1.1.11.tar.gz",
  units = "https://cran.r-project.org/src/contrib/units_1.0-1.tar.gz",
  wk = "https://cran.r-project.org/src/contrib/wk_0.9.5.tar.gz",
  classInt = "https://cran.r-project.org/src/contrib/classInt_0.4-11.tar.gz",
  raster = "https://cran.r-project.org/src/contrib/raster_3.6-32.tar.gz",
  sp = "https://cran.r-project.org/src/contrib/sp_2.2-1.tar.gz"
)

app_files <- c(
  "global.R", "ui.R", "server.R",
  list.files("R", pattern = "\\.R$", full.names = TRUE),
  list.files("www", recursive = TRUE, full.names = TRUE),
  Sys.glob("data/*.rds"),
  list.files("data/sites", pattern = "\\.rds$", full.names = TRUE),
  list.files("data-sample", pattern = "\\.rds$", full.names = TRUE)
)
app_files <- sort(unique(app_files[file.exists(app_files)]))

cat(sprintf("Writing manifest for %d files (%d site bundles)...\n",
            length(app_files),
            length(list.files("data/sites", pattern = "\\.rds$"))))
options(repos = c(CRAN = RSPM_SNAPSHOT))
rsconnect::writeManifest(appDir = ".", appFiles = app_files)

# The app's actual runtime roots. neonUtilities is deliberately referenced by a
# computed name and is fetch-only. rsconnect/jsonlite/cpp11 are build inputs.
RUNTIME_PKGS <- c(
  "shiny", "bslib", "bsicons", "dplyr", "tidyr", "stringr", "tibble",
  "plotly", "leaflet", "DT", "shinyjs", "shinycssloaders", "RColorBrewer",
  "htmltools", "zip"
)
DROP_PKGS <- c("neonUtilities", "arrow")

manifest <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
packages <- manifest$packages

dependency_names <- function(info) {
  desc <- info$description
  if (is.null(desc)) return(character(0))
  fields <- paste(c(desc$Imports, desc$Depends, desc$LinkingTo), collapse = ",")
  fields <- gsub("[\r\n]", " ", fields)
  tokens <- unlist(strsplit(fields, ","))
  tokens <- trimws(sub("[ (].*$", "", trimws(tokens)))
  tokens <- tokens[nzchar(tokens) & tokens != "R"]
  intersect(tokens, names(packages))
}

reachable <- character(0)
frontier <- setdiff(intersect(RUNTIME_PKGS, names(packages)), DROP_PKGS)
while (length(frontier)) {
  reachable <- union(reachable, frontier)
  next_frontier <- unique(unlist(lapply(frontier, function(pkg)
    dependency_names(packages[[pkg]]))))
  frontier <- setdiff(next_frontier, c(reachable, DROP_PKGS))
}

missing_roots <- setdiff(RUNTIME_PKGS, names(packages))
if (length(missing_roots))
  stop(sprintf("MANIFEST ROOT GATE FAILED: runtime package(s) were not captured: %s",
               paste(missing_roots, collapse = ", ")), call. = FALSE)

removed <- setdiff(names(packages), reachable)
if (length(removed)) {
  cat(sprintf("Pruning %d unreachable/build/live-fetch package(s): %s\n",
              length(removed), paste(sort(removed), collapse = ", ")))
  manifest$packages <- packages[reachable]
}

# Canonicalize ordinary repository provenance without changing package identity.
for (pkg in names(manifest$packages)) {
  if (!pkg %in% names(GEO_PINS)) {
    manifest$packages[[pkg]]$Source <- "CRAN"
    manifest$packages[[pkg]]$Repository <- RSPM_SNAPSHOT
  }
}

# Exact URL source installs retain their installation URL in RemotePkgRef. Connect
# needs the top-level CRAN lane and an absolute repository so it can resolve an
# archived release. Only DESCRIPTION's non-semantic source-build clock is removed.
for (pkg in names(GEO_PINS)) {
  if (is.null(manifest$packages[[pkg]])) next
  manifest$packages[[pkg]]$Source <- "CRAN"
  manifest$packages[[pkg]]$Repository <- "https://cran.r-project.org"
  if (!is.null(manifest$packages[[pkg]]$description))
    manifest$packages[[pkg]]$description$Built <- NULL
}

jsonlite::write_json(manifest, "manifest.json", auto_unbox = TRUE, pretty = TRUE,
                     null = "null")

# Hard provenance gate. Versions and exact refs must describe the packages the
# validator really compiled; this script never fabricates them.
check <- jsonlite::fromJSON("manifest.json", simplifyVector = FALSE)
bad <- character(0)
if (!identical(as.character(check$platform %||% ""), R_PLATFORM_PIN))
  bad <- c(bad, sprintf("platform=%s (want %s)",
                       as.character(check$platform %||% "<missing>"),
                       R_PLATFORM_PIN))

for (pkg in names(check$packages)) {
  info <- check$packages[[pkg]]
  version <- as.character(info$description$Version %||% "")
  declared <- as.character(info$description$Package %||% "")
  if (!identical(declared, pkg) || length(version) != 1L || !nzchar(version))
    bad <- c(bad, sprintf("%s has incomplete identity", pkg))
  if (!pkg %in% names(GEO_PINS) &&
      (!identical(as.character(info$Source %||% ""), "CRAN") ||
       !identical(as.character(info$Repository %||% ""), RSPM_SNAPSHOT)))
    bad <- c(bad, sprintf("%s ordinary repository is not the dated snapshot", pkg))
}

for (pkg in names(GEO_PINS)) {
  info <- check$packages[[pkg]]
  if (is.null(info)) {
    bad <- c(bad, sprintf("%s is missing", pkg))
    next
  }
  want_ref <- paste0("url::", unname(GEO_URLS[[pkg]]))
  got_version <- as.character(info$description$Version %||% "")
  got_ref <- as.character(info$description$RemotePkgRef %||% "")
  got_type <- as.character(info$description$RemoteType %||% "")
  got_built <- as.character(info$description$Built %||% "")
  if (!identical(got_version, unname(GEO_PINS[[pkg]])) ||
      !identical(as.character(info$Source %||% ""), "CRAN") ||
      !identical(as.character(info$Repository %||% ""),
                 "https://cran.r-project.org") ||
      !identical(got_type, "url") || !identical(got_ref, want_ref) ||
      nzchar(got_built))
    bad <- c(bad, sprintf("%s exact source provenance is invalid", pkg))
}

keys <- names(check$packages)
leaked <- intersect(DROP_PKGS, keys)
if (length(leaked))
  bad <- c(bad, sprintf("forbidden package(s): %s", paste(leaked, collapse = ",")))
if ("data.table" %in% keys && !"plotly" %in% keys)
  bad <- c(bad, "data.table has no runtime owner")

if (length(bad))
  stop(sprintf("MANIFEST PROVENANCE GATE FAILED: %s. Do not publish this candidate.",
               paste(bad, collapse = "; ")), call. = FALSE)

cat(sprintf("OK: pinned R %s manifest with %d runtime packages and exact geospatial closure.\n",
            R_PLATFORM_PIN, length(keys)))
