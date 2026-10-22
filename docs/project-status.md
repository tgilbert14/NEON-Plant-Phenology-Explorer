# Project status: NEON Plant Phenology Explorer

> The context file coordinators (`vgs`, `hk`, `neonize`) give every specialist so a
> cold-booted agent does not re-flag shipped or deliberately deferred work. Keep it
> current after every review or ship. Depth: `README.md`, `DEPLOY.md`,
> `docs/BUILD-TEST-HANDOFF.md`, `docs/DRIVER-KNOWLEDGE-PACKAGE.md`.

**Last updated:** 2026-10-22, on PR #14 (branch `fix/phenology-audit-12-13`), which
closes the 2026-10-18 suite audit findings for this repo. Not yet merged or deployed.

## Stage
- Live app and Pages cover are the pre-#14 release (`master`). PR #14 carries the
  corrected green-up and leaf-active estimand, the PDF report, deep links, the shell
  and copy fixes, provenance, and the pipeline signals. Tim merges; the post-merge
  refresh then reproduces the bundles from raw NEON on the review branch.

## Shipped in PR #14 (do not re-flag as missing)
- **Green-up:**
  - Bud-break onset, with a Young-leaves fallback for drought-deciduous shrubs.
  - A 31-day carry-over rule at the year boundary.
  - Autumn-sprouting and carry-over-dominated growth forms are excluded per site.
  - Two-stage site and species medians with a censoring lower bound (point, range,
    upper bound, short record).
- **Leaf-active:** the interval-censored span of each leafy run, with weeks x 7 kept
  as the `leaf_weeks` QC column.
- **Support:** separate green-up and leaf support flags (visit effort, late start
  judged per metric, at least 3 seasons).
- **Counts and dates:** n_years counted correctly; dayOfYear coalesced from date.
- **Gates:** `verify_bundle.R` checks that every stored summary reproduces from obs,
  and gates each audit defect.
- **Report and exports:** PDF site report (`R/report_pdf.R`, base grid); standalone
  codebook CSV in About.
- **Navigation:** `?site=CODE` deep links, with Back and Forward following the URL.
- **Runtime:** data: URL PNG export (Chrome, Edge, Safari); a full-roster plant
  search; title, lang, main landmark and skip link; keepInView off with a resize
  guard; SRER default; QC flags operable with Enter and Space.
- **Provenance:** NEON RELEASE-2026 pinned with released data only, DOI
  10.48443/p75s-7p48, "observations through December 2024" on the landing and in
  About, CC BY 4.0.
- **Pipeline:**
  - A refresh-ready issue for Tim, closed on deploy.
  - A NEON release and issue-log watch.
  - neonUtilities 4.0.1 pinned.
  - A build-fingerprint deploy smoke that also checks the title and lang.
  - The fetch fails loudly on any site error.

## Post-merge steps
1. Promote nothing by hand: the merge commit's CI must pass with the validator's
   manifest.
2. Dispatch `refresh-data.yml` with `skip_download=false` from `master`; review and
   merge the automation PR it opens (it should reproduce the bundles; the de-duplication
   and canonical sort change obs bytes once).
3. Set `CARTO_BASEMAP_KEY` on the Connect content and republish if the Light map
   still shows the Esri grey canvas.
4. Confirm Connect deploys the merge: the post-deploy smoke must see
   `plant-phenology-v1 build-<id>`.

## Deliberately deferred / non-goals
- **PUUM (Pu'u Maka'ala, Hawaii).** NEON has released plant phenology for PUUM, but it
  is not bundled. Adding it means a site row, a 47-site gate in `verify_bundle.R`
  and `refresh-data.yml`, and a token-holding fetch through the review branch, and
  it adds a tropical montane site to the latitude gradient. Owner decision: include
  it with the next full refresh, or record it as excluded.
- **2013 to 2015 seasons.** Released for 28 sites but not bundled: early,
  pre-operational years under an earlier protocol. `PHE_STARTDATE` makes a later
  change a one-line decision.
- **Season-anchored green-up** (a site-specific season start instead of the
  calendar year). This was held by iris because it changes the plant-year keys, and
  so the Driver calendar join and the trend axis. The autumn and carry-over form
  exclusions stand in for it.
- **A domain-borrowed visit-schedule reference** for short-record sites (would
  recover STEI 2017). Held by iris.
- **Cross-promo grid on the cover.** Settled by Living Poster V1: the cover carries
  one Atlas route, and the in-app About lists all ten explorers.
- **Live NEON API calls at runtime.** Avoided by design; the app boots from
  committed bundles.
- **Not a framework rewrite and not multi-tenant.** It is one public explorer.

## Owner decisions open
- PUUM: include or exclude (above).
- Branch protection on `master` (a ruleset requiring the `contracts` check).
- `CARTO_BASEMAP_KEY` on the Connect content.
