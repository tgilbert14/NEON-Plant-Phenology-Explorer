# Project status: NEON Plant Phenology Explorer

> The context file coordinators (`vgs`, `hk`, `neonize`) give every specialist so a
> cold-booted agent does not re-flag shipped or deliberately deferred work. Keep it
> current after every review or ship. Depth: `README.md`, `DEPLOY.md`,
> `docs/BUILD-TEST-HANDOFF.md`, `docs/DRIVER-KNOWLEDGE-PACKAGE.md`.

**Last updated:** 2026-10-26, on PR #14 (branch `fix/phenology-audit-12-13`), which
closes the 2026-10-18 suite audit findings for this repo and carries hk's follow-ups.
Not yet merged or deployed.

## Stage
- Live app and Pages cover are the pre-#14 release (`master`). PR #14 carries the
  corrected and bracketed green-up and leaf-active estimand, the PDF report, deep
  links, the shell and copy fixes, provenance, the independent headline oracle,
  deterministic bundles and the pipeline signals. Tim merges; the post-merge
  refresh then reproduces the bundles from raw NEON on the review branch.

## Shipped in PR #14 (do not re-flag as missing)
- **Green-up:**
  - Bud-break onset, with a Young-leaves fallback for drought-deciduous shrubs.
  - A 31-day carry-over rule at the year boundary.
  - Autumn-sprouting and carry-over-dominated growth forms are excluded per site.
  - Two-stage site and species medians bracketed by the visit gap (lo = median
    last 'no', hi = median first 'yes'); point under 14 days, else range; upper
    bound; short record.
- **Leaf-active:** the interval-censored span of each leafy run with a 31-day
  year-boundary bridge; "at least N days" where unbridged edges could add 14 days or
  more; weeks x 7 kept as the `leaf_weeks` QC column.
- **Trends and gradient:** censoring-heavy points drawn open and left out of the fit;
  a direction needs 6 years and must agree with and without them ("depends"
  otherwise); the within-species gradient carries Spearman rho with an interval and
  needs 6 sites.
- **Support:** separate green-up and leaf support flags (visit effort, late start
  judged per metric, at least 3 seasons).
- **Counts and dates:** n_years counted correctly; dayOfYear coalesced from date;
  exact duplicate obs rows removed; uncertain records disclosed at 10% or more.
- **QC flags:** out-of-sequence redesigned (1,083 -> 135 plants); a same-visit yes/no
  conflict flag.
- **Gates:** `verify_bundle.R` checks that every stored summary reproduces from obs,
  gates each audit defect, and compares every headline exactly with the independent
  oracle (`scripts/headline_oracle.R`, from the signed `scripts/headline_rules.md`).
  Bundles are byte-identical on rebuild (`scripts/bundle_identity.R`).
- **Report and exports:** PDF site report (`R/report_pdf.R`, base grid); standalone
  codebook CSV in About.
- **Navigation:** `?site=CODE` deep links, with Back and Forward following the URL.
- **Runtime:** data: URL PNG export (Chrome, Edge, Safari); a full-roster plant
  search; title, lang, main landmark and skip link; keepInView off with a resize
  guard; SRER default; QC flags operable with Enter and Space.
- **Provenance:** NEON RELEASE-2026 pinned with released data only, DOI
  10.48443/p75s-7p48, "observations through December 2024" on the landing and in
  About, CC BY 4.0. About also names NEON's 2026 scope cut (phenology at core sites
  only from 2026; DELA closed on 2025-12-31).
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
   merge the automation PR it opens. It should reproduce the bundles; review its
   `inds` diff, because the identity-row rule (latest editedDate wins) first acts on
   raw data there.
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
- **Infraspecific keying of the within-species gradient.** Only nominate varieties
  (the epithet repeats the species, as in "Acer rubrum L. var. rubrum") should merge
  into their species, at the plant level; every other variety stays separate (iris).
  Red maple would gain GRSM. Needs a rebuild and a recheck of the gradient table.
- **NEON dayOfYear vs date.** At six sites one or two visit dates carry a dayOfYear
  that disagrees with the date (ABBY -8, DSNY -1, GRSM -4, LAJA +14, ONAQ -3,
  SRER -7 and -1). Kept as recorded: the estimand uses day numbers for arithmetic
  and dates only to form visits and measure the year-boundary gap.
- **Per-site "record ends 2025" labels.** From 2026 NEON observes phenology only at
  core sites (issue log 2026-01-28). No bundled year is affected (data end in
  December 2024); a per-site label needs a verified core and gradient site table
  and matters once a release covers 2026.
- **Cross-promo grid on the cover.** Settled by Living Poster V1: the cover carries
  one Atlas route, and the in-app About lists all ten explorers.
- **Live NEON API calls at runtime.** Avoided by design; the app boots from
  committed bundles.
- **Not a framework rewrite and not multi-tenant.** It is one public explorer.

## Owner decisions open
- PUUM: include or exclude (above).
- Branch protection on `master` (a ruleset requiring the `contracts` check).
- `CARTO_BASEMAP_KEY` on the Connect content.
- Deleting merged branches (`delete_branch_on_merge` is off; 6 of 7 non-default
  branches were merged at the audit).
