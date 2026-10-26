# Plant Phenology Explorer build/test handoff

This is the durable cross-session record for the application, its scientific
contract, generated data, release state, and publication evidence. Read it before
work and re-read the latest entry immediately before appending or revising it.

## 2026-10-26 MST - [Claude, Opus 5.5] finish pass: hk follow-ups, PDF report, audit appendix P1 to P3

- Scope: Tim's 2026-10-22 finish instruction (`neon-audit-2026-10-18/reports/FINISH-LEDGER.md`):
  every Plant Phenology finding in the 2026-10-18 audit appendix (P1, then P2,
  then P3), the ledger's cross-cutting list and the PDF report, plus hk's three
  deferred PR #14 items and audit items a to l. The child session "Phenology hk
  follow-ups" did the estimand, pipeline and gate files under an agreed file split
  (branch `claude/silly-mirzakhani-e217cb`, tip `c27aaad`, merged here at `deedc1e`
  and `f85d09a`); this session did the app, report, workflow and doc files. All
  of it stays in PR #14: no stacked PR.
- Identities: PR #14, branch `fix/phenology-audit-12-13` from `master` `b6bc165`;
  code head `2a5f2bb`; watched branch `master`; Pages and Connect URLs as in the
  2026-10-21 entry. State at start: pushed head `895242b`, whose CI run
  `39730467992` failed only the committed-manifest gate; nothing merged.
- Model note: planned and reviewed on Opus 5.5 at max effort because the Fable
  limit was reached (fleet policy fallback, approved by Tim 2026-10-21); the PDF
  report and UI-wiring workers ran on Opus 5.5 at medium. iris signed off every
  estimand and QC rule (three reviews, including a line-by-line review of
  `scripts/headline_rules.md`); hk set the gradient statistics and the oracle design.
- Estimand (child, `R/phe_helpers.R`, every threshold a named constant):
  - green-up is bracketed by the visit gap: `greenup_lo` is the two-stage median of
    each plant-year's last 'no' (left-censored years count as -Inf), `greenup_hi`
    the median of the first 'yes', and the published value stays the midpoint
    median; point when hi - lo < 14 days (`BOUND_POINT_TOL` 7 -> 14), else range;
    an upper bound reads the first-'yes' median;
  - leaf spans bridge the new year when the nearest visit on the other side is at
    most 31 days away; an unbridged edge fills to the year boundary in
    `leaf_active_hi`, and a site reads "at least N days" (`leaf_active_status`
    lower_bound) when hi exceeds the value by 14 days or more;
  - trend points are hollow when `lc_share` >= 0.5 (green-up) or onset_hi - onset
    >= 14 (leaf); `trend_verdict()` needs 6 solid years (`TREND_MIN_YEARS`) and the
    fits with and without the hollow points to agree, else "depends";
  - `within_species_gradient()` adds Spearman rho with a Fisher z (Bonett-Wright)
    interval, a per species-site year floor and min_sites 6;
  - `uncertain_share` per site (disclosed in the app at 0.10 or more); exact
    duplicate obs rows removed; a same-visit yes/no conflict QC flag; the
    out-of-sequence flag redesigned; the latest-edited identity row wins;
  - deterministic bundles (`scripts/bundle_identity.R`: canonical row order and
    write-if-changed), the SRER demo, and an independent headline oracle
    (`scripts/headline_oracle.R`, written from the signed `scripts/headline_rules.md`)
    that `verify_bundle.R` compares exactly at site, site-year, plant-year and
    species level.
- App, report and pipeline (this session, `5012010` to `2a5f2bb`):
  - `R/report_pdf.R`: a three-page vector PDF site report (base grid and
    `cairo_pdf`, no new package) with headline tiles, green-up status and coverage,
    composition, season bands, trends with the years left out, caveats, CAN and
    CANNOT, and the NEON citation on every page; the CSV stays as "site summary".
  - `?site=CODE` deep links with Back and Forward; an allowlist before any bundle
    path; NEON strings HTML-escaped in pin cards, popups and tables.
  - Provenance: `PHE_RELEASE` (RELEASE-2026, DOI 10.48443/p75s-7p48, CC BY 4.0) in
    `R/site_metadata.R`; the hero, About and codebook name the release, DOI and
    "observations through December 2024"; About names NEON's 2026 scope cut (core
    sites only from 2026; DELA closed on 2025-12-31).
  - The bracketed estimand wired into every surface: greenup_label and
    leaf_label, iris's range note, the threshold table, hollow trend points and the
    verdict banner, "at least N days" (hero, insights, Onset Lab, plant card, plot
    map, search, gradient, species-across, report card, PDF), `WS_GREENUP` and
    `WS_LEAF` in `global.R`, the uncertain disclosure, bound columns in the export,
    and the About CANNOT list.
  - Shell, phone and copy: CTA within the 375 px fold, phone text sizes, 16 px
    selectize, 44 px targets, AA footer contrast, skip link, overlay Close button,
    scope chips, info-dot labels, ten-explorer registry with the NEON Cross-Product
    Response Atlas, no em dashes in visible copy (`check_cover.mjs` now fails on
    any), no sincerity labels (two "honest" codebook rows fixed in `8b8cb26`), the
    haptic tick only after a tap (`8c07db2`), and a pin-card close button with a
    type and an accessible name plus a legend-only picker hint (`2a5f2bb`).
  - Pipeline: build-fingerprint smoke (`plant-phenology-v1 build-<manifest md5[:12]>`
    plus title and lang); a refresh-ready issue opened by the publisher and closed
    by post-deploy; a release and issue-log watch; neonUtilities 4.0.1 pinned and
    asserted; the fetch pins RELEASE-2026 with `include.provisional = FALSE`, fails
    on any site error and never reads a token file in CI; the handler check scans R
    sources; `scripts/deploy.R` removed.
- Outcome. Before = `master` `b6bc165`; first estimand = `3c40912`; final = this head.

  | Site | Green-up master | 3c40912 | final | Leaf-active master | 3c40912 | final |
  |---|---|---|---|---|---|---|
  | SRER | day 33 | 77 to 88 | 73 to 91 (value 88) | 268 d | 350 d | 358 d |
  | ONAQ | day 66 | 46 or earlier | 49 or earlier | 77 d | 100 d | at least 100 d |
  | STER | day 186 | unavailable | unavailable (2 seasons) | 35 d | unavailable | unavailable |
  | LAJA | day 5 | 156 | 144 to 160 (value 156) | 258 d | 331 d | at least 336 d |
  | HARV | day 116 | 116 | 116 (bracket 114 to 118) | 147 d | 174 d | 174 d |

  Network: green-up 32 point, 5 range (CPER, LAJA, LENO, SOAP, SRER), 5 upper bound
  (BARR, NIWO, ONAQ, WOOD, YELL), 4 short record (DCFS, KONA, STEI, STER);
  leaf-active 15 point, 27 lower bound, 4 short record. national_onsets 710 rows
  (556 point, 55 range, 99 upper bound). obs 5,735,598 -> 5,705,266 rows (30,332
  exact duplicates; no estimate moves). Uncertain share at 0.10 or more: NIWO 0.254,
  RMNP 0.143. QC over 9,537 plants: out-of-sequence 1,083 -> 135, green-up outlier
  749 -> 73, same-visit conflict 573 plants (1,007 cells). Red maple within-species
  gradient (8 sites; SCBI's single season left out): green-up +4.33 d per degree N
  (1.91 to 6.76), rho 0.874 (0.310 to 0.983); leaf-active -8.25 (-11.99 to -4.51),
  rho -0.922 (-0.990 to -0.506). Trend verdicts over all 46 sites: green-up down 3
  (ABBY, JERC, SCBI), depends 1 (BLAN), none 25, too short 17; leaf-active down 1
  (OAES), depends 1 (CPER), none 20, too short 24. Search: 818 taxon-site rows,
  575 species. Data sha256 prefixes: `data/site_index.rds` 737f7b13,
  `data/national_onsets.rds` eb006c9a, `data/search_index.rds` b1b1412c,
  `data-sample/demo.rds` = `data/sites/SRER.rds` f7e84ff3.
- Commands (macOS 26.6.2, R 4.5.2, Node v24.20.0, actionlint 1.7.12), final tree:
  `Rscript --vanilla scripts/test_helpers.R` 46/46; `scripts/test_bundle_identity.R`
  27/27; `scripts/normalize_empty_trends.R` no-op; `scripts/rebuild_indexes.R`
  reproduces every committed `data/` and `data-sample/` byte, then stops at its
  manifest step on macOS as before (`manifest.json` untouched);
  `scripts/verify_bundle.R` passes every bundle, index and science gate with the
  oracle receipt "compared site 46, support 369, plant_years 34474, species 710
  rows; mismatches site 0, support 0, plant_years 0, species 0", and reports only
  the expected manifest notes (file set lacks `R/report_pdf.R`; checksums); offline
  source, the handler check (5 one-payload handlers, every sent type handled),
  `check_cover.mjs`, `bash -n` on the smoke and actionlint pass; `git diff --check`
  clean; no em dash on any added line. `phe_report_pdf()` for SRER, ONAQ and STER
  gives three US-letter pages each (`pdfinfo`), and the extracted text carries the
  table's headlines ("day 73 to 91", "358 days"; "day 49 or earlier", "at least 100
  days"; "Unavailable"), the release and DOI on every page, and no em dash. Suite lint
  (`neon-suite-lint.mjs --worktree --app phenology`): GREEN, 0 red, 0 yellow (the
  2026-10-22 baseline on `master` had 5 red, 14 yellow).
- Browser (in-app Chromium, local `runApp`), final tree: title, lang and one main
  landmark; `?site=` deep links for SRER, ONAQ, STER, LAJA and NIWO read as the
  table; NIWO discloses 25% uncertain records; the report PDF downloads (47,633
  bytes, `%PDF`); About shows the 2026 scope note; no horizontal overflow at 390 px;
  no server errors; no haptic call on a site load without a tap; an Onset Lab pin's
  close button has `type="button"` and the name "Close card" and closes the card. The hidden preview
  pane runs no requestAnimationFrame, so hero count-ups read 0 until a frame paints
  (a screenshot shows NIWO 201, 22, 2); the count-up code is unchanged from master.
  Not checked: Safari, Edge, a real phone, the deployed app.
- Release identities: pinned-validator run `40339102270` on code head `2a5f2bb`
  passed every validator step and failed only the committed-byte gate; its
  release-candidate artifact matched all 50 committed data files byte for byte.
  `efadd17` promotes that artifact's `manifest.json` unchanged (63 files, R 4.5.2,
  terra 1.8-50, no neonUtilities, `R/report_pdf.R` listed; md5 build id
  `5a1a0c2aefdf`, so the deploy marker is `plant-phenology-v1 build-5a1a0c2aefdf`),
  and `scripts/verify_bundle.R` passes against it. This records commit sits on top
  and changes no manifest-listed file; CI on the final PR head is in PR #14.
- Failed attempts and cleanup: two child workers stopped on the weekly usage limit
  (2026-10-21); their saved work was finished on 2026-10-26, and the signed rule
  sheet, lost from a cleared scratchpad, was restored into the repo. The local test
  rebuild was discarded (`git checkout -- data data-sample`) before merging the
  child's rebuild. CI runs on `5012010`, `fe9b475` and `9380306` were cancelled by
  newer pushes; the `895242b` run failed only the manifest gate and its artifacts
  expired before promotion. The hero once never filled because `#heroStats:empty`
  hid it and Shiny suspends hidden outputs; `outputOptions(suspendWhenHidden = FALSE)`
  fixed it (`04cc088`).
- Residual risks: obs bytes changed in all 46 bundles (duplicates removed,
  canonical order), and the Atlas refresh reads `data/sites` from this repo's HEAD
  without a PR gate (note for cass); the identity-row rule (latest editedDate wins)
  is unmeasured until the next raw refresh; 27 of 42 sites with a leaf value now read
  "at least N days", a large visible change; from 2026 NEON observes phenology only
  at core sites, so gradient sites will add no years after 2025.
- Next action: Tim merges PR #14; CI must pass on the merge; dispatch
  `refresh-data.yml` with `skip_download=false` from `master` and review the
  automation PR (it should reproduce the bundles; review the inds diff for the
  identity-row rule); confirm Connect serves `plant-phenology-v1 build-<id>` for the
  merged manifest.

## 2026-10-21 MST - [Claude, Opus 5.5] audit 2026-10-18 items 12 and 13 plus shell items

- Scope: the Wave 2 Plant Phenology items of the 2026-10-18 suite audit. Item 12
  (green-up definition, leaf-active effort confound, capped n_years, NA dayOfYear,
  calendar-year anchor and left-censoring artifacts) and item 13 (Onset Lab and QC
  card PNG export, "Find a plant" roster), plus this app's share of the suite
  shell items (page title and lang, one main landmark, picker-map keepInView and
  resize guard, SRER default, QC flags operable with Enter and Space).
- Identities: PR #14, source branch `fix/phenology-audit-12-13` from `master`
  `b6bc165cdf2b60a68eecc63249679d91914b88f0` (after the cron PR #13 merge);
  watched deployment branch `master`; Pages
  <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/>; Connect
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>.
  Test state at start: clean tree, last refresh runs skipped by the calendar gate.
- Model note: planned and reviewed on Opus 5.5 at max effort because the Fable
  limit was reached (fleet policy fallback, approved by Tim 2026-10-21). The
  estimand rules were set by the iris review (Opus, max), reviewed by hk (Opus,
  max, verdict SHIP WITH FIXES), and the two estimand amendments hk asked for
  were signed off by iris before the final rebuild.
- Estimand (R/phe_helpers.R, every threshold a named constant):
  - green-up is the earliest bud-break onset, with a per-plant-year Young-leaves
    fallback for Drought deciduous broadleaf only (`greenup_source`);
  - a 31-day carry-over rule at the year boundary (`carryover`);
  - growth forms dropped per site when >= 35% of >= 10 onsets fall on or after
    day 274 (SJER and SOAP forbs and graminoids) or >= 35% of >= 10 plant-years
    carry over the new year (LAJA graminoids and semi-evergreen broadleaf);
  - separate support flags (`greenup_supported`, `leaf_supported`): >= 3 watched
    seasons else `short_record`; median visit-weeks >= 0.75 of the site's typical;
    a first visit > 30 days after the site's typical counts as `late_start` only
    when that metric was truncated (green-up: >= half of the year's onsets
    left-censored, or coverage < half the site's typical; leaf: >= half of the
    plant-years already in leaf at the first visit);
  - two-stage site and species medians with a censoring lower bound
    (`greenup_status` point, range, upper_bound, short_record; the numeric median
    is withheld for upper_bound);
  - leaf-active as the interval-censored span of each run of Leaves = yes visits,
    with weeks x 7 kept as `leaf_weeks`; two-stage species flowering and
    leaf-active;
  - `*_n_years` counted before the summarise reassignment; dayOfYear coalesced
    from date in the bundler and in `rebuild_indexes.R`, which now re-derives
    `ind_summary` and `trend` from `obs` and rewrites a bundle only when they change.
- Network outcome: 33 point, 4 range (CPER, LENO, SOAP, SRER), 5 upper-bound
  (BARR, NIWO, ONAQ, WOOD, YELL) and 4 short-record sites (DCFS, KONA, STEI, STER).
  Of 369 watched site-years, 276 are supported for green-up (76 low effort, 36 of
  them in 2020; 11 late start; 6 short record) and 273 for the leaf metrics (14 late
  start). Supported finite-green-up site-years: 272 across 42 sites, 33 with >= 6
  (was 346 across 45, 39 with >= 6).

  | Site | Green-up before | Green-up after | Leaf-active before | Leaf-active after |
  |---|---|---|---|---|
  | SRER | day 33 (coverage 0.18) | day 77 to 88 (coverage 0.64) | 268 d | 350 d |
  | ONAQ | day 66 | day 46 or earlier (value withheld) | 77 d | 100 d |
  | STER | day 186 | unavailable, 2 seasons | 35 d | unavailable |
  | SJER | day 80 | day 64, woody plants only | 122 d | 140 d |
  | LAJA | day 5 | day 156 (coverage 0.19) | 258 d | 331 d |
  | TEAK | day 162 | day 154 | 119 d | 166 d |
  | HARV | day 116 | day 116 | 147 d | 174 d |

- Runtime and shell: PNG export renders through a data: URL (blob: URLs taint
  the canvas in Chromium and WebKit); the search roster lists every species-level
  plant (818 taxon-site rows, 575 species, SRER 20 species, was 723 / 499 / 7),
  with green-up from `national_onsets` and leaf-active from the per-plant summary
  (>= 3 plants); `<title>`, `lang="en"` and `<main id="main">`; picker popups
  `keepInView = FALSE` and `kickMaps` invalidates only maps with `clientWidth > 0`;
  SRER (Arizona) is the default site; one delegated keydown handler makes
  `.qc-flag-click` operable with Enter and Space; a stale Windows `setwd()` left
  `scripts/build_search_index.R` (suite lint L12).
- Commands (macOS 26.6.2, R 4.5.2, Node v24.20.0), final tree: `Rscript --vanilla
  scripts/test_helpers.R` (26/26 PASS; new fixtures for n_years, dayOfYear,
  fallback scope, carry-over, autumn and carry-over forms, bounds, short record,
  per-metric late start, coverage guard, leaf span); `scripts/test_bundle_identity.R`
  (11/11); `scripts/rebuild_indexes.R` (bundles re-derived, indexes rebuilt);
  `scripts/normalize_empty_trends.R` (no-op); `scripts/verify_bundle.R` (all
  bundle, index and science gates PASS; the only failure is the manifest checksum,
  which the pinned CI regenerates); handler and cover checks PASS; offline source
  PASS; `git diff --check` clean; no em dash on any added line. The new verify
  gates fire against master's bundles (n_years cap in 42 bundles, NA dayOfYear in
  8, 95 unfindable species, non-reproducing summaries, unsupported trend years).
  The Atlas v2 adapter's own `phenology_v2_validate_bundle` (sourced read-only
  from NEON-Driver-Cascade) passes 46/46 rebuilt bundles. The suite lint
  (`neon-suite-lint.mjs --app phenology --worktree`) clears L1, L2, L12 and L13 on
  the branch; L15 (refresh publish gate) remains a pipeline-lane item.
- CI evidence on the first PR head `27fab70`: run `39691847702` passed every step
  on the pinned validator (tests, the two-build deterministic index check,
  manifest regeneration, `verify_bundle.R`, offline source) and failed only the
  intentional committed-byte gate on `manifest.json`. Its release-candidate
  artifact matched all 50 local data files byte for byte, so macOS and Linux
  builds of the same code agree; only the manifest needs promotion.
- Browser (in-app Chromium pane, local `shiny::runApp`): title, lang and one main
  landmark present; SRER/AZ selected on first paint; the Onset Lab PNG (243 KB)
  and QC card PNG (1.3 MB) save, and a same-page control reproduces the
  tainted-canvas SecurityError with a blob: URL; Enter and Space open the QC flag
  inspector; SRER, ONAQ, STER, SJER and LAJA heroes and insights read as in the
  table; no horizontal overflow at 1280 and 390 px; the picker map returns at full
  width after "change site"; the analysis zip (731 KB) and the status-aware report
  card download. Not checked: Safari and Edge, a real phone, the deployed app.
- Failed attempts and cleanup: the first estimand review died on the Fable usage
  limit and was re-run on Opus. A first draft labelled every year of a site with
  its first year's support reason (`ifelse()` on a scalar); the label is fixed and
  tested. `rebuild_indexes.R` stops at the manifest step on macOS (rsconnect cannot
  bundle the local library); the tracked `manifest.json` was never hand-edited.
- hk follow-ups not in this PR: species-year trend points where most plants were
  left-censored are drawn and fitted like the others (11% of points); the bounds
  carry censoring but not the visit-interval width; leaf spans that touch the
  year's first or last visit are not labelled "at least N days" (54% of supported
  plant-years, most at year-round sites).
- Residual risks: leaf-active rises at most sites (span plus the support gate);
  nine sites no longer publish a single green-up day; the Atlas computes its own
  green-up (bud-break only, no carry-over) and weeks x 7 leaf-active from these
  bundles, so the same defects remain there until cass decides; the raw refresh
  path (`bundle_phe_data.R` from NEON) runs only in the refresh workflow.
- Next action: promote the manifest from the final head's validator artifact,
  require green CI on that exact head, Tim merges, then dispatch
  `refresh-data.yml` with `skip_download=false` from `master` so the review branch
  reproduces the bundles from raw, and verify Connect deploys the merge with the
  `plant-phenology-v1` marker.

## 2026-08-05 19:37:36 MST - [Codex] pinned release-byte promotion

- Draft PR #11 validated exact source head
  `3979175ae05868c46bdd6ff7593127abef422fd6` in run `31065668215`, job
  `92502746696`. Static, scientific-helper, idempotent normalization,
  deterministic-index, pinned-manifest, bundle/index/manifest, and offline-source
  gates passed. The run stopped only at the intentional committed-release-byte
  equality guard after uploading the validated candidate.
- Downloaded artifact `8953827399`,
  `plant-phenology-release-candidate-3979175ae05868c46bdd6ff7593127abef422fd6`,
  and verified its archive digest as
  `sha256:6e28bbb8b2de4f560f07de5187f05a5f15e1f9426d74fffadb86defe5c0ef7b9`.
  Extracted all five registered files directly without rebuilding or hand editing.
  The four RDS files reproduced the reviewed candidate bytes; only
  `manifest.json` changed, from SHA-256
  `512737700fdad555264737303439a1816eb189f5ec456e7420aa40dc9165d29b` to
  `77f4a43544cba60cf8a14df7eb7d3838000d29598c899dc20f261b05ea78bc1d`.
- This is release-byte promotion for the cover-only source change. It does not
  alter a bundle, index, estimator, scientific threshold, source family,
  ecological disposition, or Driver artifact. Next action: commit and push the
  promoted manifest, then require the complete validator to pass on that exact
  amended PR head before review or publication.

## 2026-08-05 19:23:15 MST - [Codex] visible art-label removal candidate

- Scope began from clean exact `origin/master`
  `30be615dc438b60e4fa6454973b3b42589b22234` on branch
  `agent/remove-cover-art-disclaimer`. The watched deployment branch remains
  `master`; Pages remains
  <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/> and Connect remains
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>
  (content ID `019ee118-bf17-1622-bd5d-e59cab3b36a7`). Nothing was pushed,
  merged, dispatched, or deployed in this local candidate pass.
- Pages and the in-app first-run poster no longer overlay the sentence
  “Editorial illustration—not a field photograph or data record.” The matching
  caption-only CSS was removed. Descriptive image alt text, the durable source/
  prompt/hash register in `docs/IMAGE-PROVENANCE.md`, the tagged-plant scope,
  `DP1.10055.001`, and the abundance/productivity/causal limits are unchanged.
  `scripts/check_cover.mjs` now fails if either poster restores that sentence or
  any visible `figcaption`.
- Local PASS on Node `v24.4.1` and R `4.5.3`: `node --check
  scripts/check_cover.mjs`; `node scripts/check_cover.mjs`; `node
  scripts/check_custom_message_handlers.mjs` (five handlers); parse of all app,
  helper, and script R sources; `bash -n scripts/post_deploy_smoke.sh`; and final
  `git diff --check`. The cover gate retained alt text, hook/promise/CTA, claim,
  source-product, accessibility, local-asset, dimension, and checksum assertions.
- Local scientific fixtures were attempted but stopped before assertions because
  this host library lacks `data.table` and `dplyr`. Manifest generation was also
  attempted with `Rscript --vanilla scripts/write_manifest.R` and stopped before
  writing because `rsconnect` is absent. The tracked manifest was not hand-edited.
  Exact runtime-file checksums and the full fixture/release contract therefore
  remain pending the pinned Ubuntu 22.04 / R 4.5.2 / Haswell / one-thread PR
  validator and promotion of its exact manifest candidate.
- Learning/Driver decision: `NONE / NO DRIVER BYTE CHANGE` (`cover-system` and
  `suite-platform`). This changes presentation only; no bundle, index, estimator,
  scientific threshold, source family, ecological disposition, or Driver artifact
  changed. No temporary repository artifact required cleanup.

Next action: push this local commit for review, promote only the exact green
validator-generated manifest if its committed-byte gate requests it, merge only a
green exact head, republish/sync the watched `master` revision in Connect if Last
deployed lags, and require workflow `Verify Phenology production after master
publication` to pass marker `ddl-app-ready=plant-phenology-v1` plus host-error
rejection before browser QA.

## 2026-08-04 15:13:38 EDT - [Codex] manifest dependency-drift repair candidate

- Scope began on branch `agent/suite-synthesis-phenology-governance` at exact
  PR #10 head `f4399dab6f4d2c7de0299e7be43cc07d92974edd`. The watched branch remains
  `master`; Pages remains
  <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/> and Connect remains
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>
  (content ID `019ee118-bf17-1622-bd5d-e59cab3b36a7`). No app, data, estimator,
  generated index, tracked `manifest.json`, Pages, Connect, or Driver byte was
  changed by this repair.
- Exact-head validation run `30940936808` / job `92098810379` passed the static,
  scientific-helper, trend-normalization, and first deterministic-index build
  work. Its second `scripts/rebuild_indexes.R` invocation correctly attempted
  manifest regeneration because `rsconnect` was installed, then failed closed in
  `rsconnect::createAppManifest()` before publication. The install resolver had
  moved the unversioned direct requests from the committed-manifest identities
  `bslib 0.11.0` and `zip 3.0.1` to source-built `bslib 0.12.0` and `zip 3.0.2`;
  those source installs had no reproducible reinstall location, so `rsconnect`
  rejected them. This was dependency-resolution/cache drift, not a scientific or
  index determinism failure.
- Both manifest-producing lanes now request exact `bslib@0.11.0` and
  `zip@3.0.1`, matching the committed manifest. The PR validator cache key moved
  from `plant-phenology-geo-closure-v1` to `-v2`, and the refresh validator key
  moved from `plant-phenology-refresh-geo-closure-v1` to `-v2`, so neither lane can
  restore the stale source-built closure. The dated RSPM lane, R 4.5.2, exact
  geospatial URLs, Haswell/one-thread contract, generator, and provenance gate
  remain unchanged.
- Local PASS: Ruby parsed all three workflow YAML files; R 4.5.3 parsed
  `scripts/write_manifest.R` and `scripts/rebuild_indexes.R`; Node parsed the cover
  and custom-message checkers; static assertions found both exact package pins and
  both `v2` cache keys in the only two workflows that invoke manifest generation;
  and `git diff --check` passed. A local macOS install is not equivalent to the
  pinned Ubuntu binary resolver, so exact manifest equality and the full release
  contract remain pending a fresh GitHub Actions run on the amended PR head.

Next action: commit and push this focused workflow/handoff repair, then require a
fresh exact-head PR validator to regenerate the byte-identical manifest and pass
all remaining gates before merge.

## 2026-08-04 14:49:56 EDT - [Codex] current-production governance closeout

- Scope was documentation-only suite synthesis from clean branch
  `agent/suite-synthesis-phenology-governance` at exact `origin/master`
  `7d0f29f7886cfae1c760a9ffc9e056184ec6fc68`. The watched branch remains
  `master`; Pages remains
  <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/> and Connect remains
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>
  (content ID `019ee118-bf17-1622-bd5d-e59cab3b36a7`). No runtime, data,
  estimator, manifest, workflow, Pages, Connect, or Driver artifact was changed.
- The former portability candidate is now closed by promoted production. Validated
  data candidate `3089dc8e527340245735efbc62c95aa2faee5b25` passed PR-head
  check `30841258764`; reviewer-authenticated PR #9 merged it as
  `7d0f29f7886cfae1c760a9ffc9e056184ec6fc68`. Merged validation
  `30842200764`, Pages `30842196863`, and exact production health
  `30842199076` passed. Current `manifest.json` SHA-256 is
  `512737700fdad555264737303439a1816eb189f5ec456e7420aa40dc9165d29b`.
- The measured suite audit ran from the Driver worktree with
  `Rscript --vanilla scripts/audit_suite_compatibility.R
  /Users/vgs/Documents/Codex/2026-07-22/we-have-been-working-through-updating/work/repos
  phenology`. It found 346 distinct app-supported finite-onset site-year keys
  across 45 sites; all 346/346 match Driver calendar keys, and 39 sites have at
  least six supported years. That is calendar compatibility for an app-supported
  result, not a registered Driver estimator, independent adapter, or vote receipt.
- Decision axes are now explicit: the current app scientific/release contract is
  `VERIFIED`; the ecological Driver disposition remains
  `HOLD / NO DRIVER BYTE CHANGE`. The existing temperature -> green-up vote is not
  re-authorized by the 346/346 key match. It still requires a registered
  temperature/onset analysis that preserves support and censoring, an independent
  current-source adapter, and old/new parity.
- Static documentation checks passed: `git diff --check`; a changed-path audit
  limited this closeout to `docs/BUILD-TEST-HANDOFF.md` and
  `docs/DRIVER-KNOWLEDGE-PACKAGE.md`; and exact-identity/disposition assertions
  found the promoted candidate, merge, four workflow receipts, measured join,
  explicit contract-trust axis, and no-byte authorization. Full R/app/browser and
  deployment gates are `N/A` because no release byte changed. No failed mutation,
  temporary repository artifact, or cleanup remained.

Next action: keep green-up `HOLD`; only a separately registered current-source
adapter and temperature/onset analysis with support, censoring, and parity can
request a Driver byte change.

## 2026-08-03 live-data.table producer-boundary follow-up candidate

- Audit time: `2026-08-03 12:21:41 EDT (-0400)`. This focused source-only
  follow-up began from exact current `origin/master` merge
  `849d4fb17824b21db0e1b0e9fd632e841e86b9b9` in isolated worktree
  `/Users/vgs/Documents/Codex/2026-07-22/we-have-been-working-through-updating/work/trees/NEON-Plant-Phenology-datatable-boundary-30831102602`,
  branch `codex/phenology-datatable-boundary-fix`. The watched branch remains
  `master`; Pages remains
  <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/> and Connect remains
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>
  (content ID `019ee118-bf17-1622-bd5d-e59cab3b36a7`).
- The first portability repair head
  `5414cef7d242066b17b35a4b4ffbbabf76e6f967` passed exact-head CI run
  `30828987483` / job `91737844063`; validated artifacts were release candidate
  ID `8862640658`, SHA-256
  `45d80c43b71086c9aaa049cc5084cdc8f7a2f4ed745ff9ad5483ac1ee773f0f1`,
  and manifest ID `8862639837`, SHA-256
  `df8dcaa7ddbb11563aaa80bdfafd2a651bcac82f965581ed1d214e7af01e0f23`.
  PR #7 merged as `849d4fb17824b21db0e1b0e9fd632e841e86b9b9`.
  Post-merge validator `30830610250`, semantic-production run `30830611272`,
  and Pages run `30830607424` all passed on that exact merge.
- The one authorized complete `skip_download=false` refresh, run `30831102602`,
  was bound to exact master `849d4fb17824b21db0e1b0e9fd632e841e86b9b9`.
  Gate job `91744959578` passed. Fetch job `91744990072` installed its pinned
  R 4.1.1 closure, downloaded and stacked first site HARV, then failed before
  serialization at `scripts/bundle_identity.R:42` with
  `Error in [.data.table(x, ordered_names)` and the data.table character-`i`
  join-contract message. Raw-artifact upload was skipped; build job `91745707628`
  and publisher job `91745707857` were skipped; the run has zero artifacts; no
  `automation/plant-phenology-data-refresh` ref exists; and no generated-data PR
  was opened. No candidate or production data byte changed.
- Root cause was a producer-container test gap, not NEON schema or value drift.
  `validate_phenology_raw_result()` correctly validated saved base data frames in
  local and pinned tests, but the live `neonUtilities` producer returns
  `data.table` containers. `x[ordered_names]` is base-data-frame column selection
  but invokes join semantics for `[.data.table`. The failure was therefore a
  deterministic code compatibility defect; retrying the unchanged workflow would
  not be meaningful.
- The repair computes each column length through subclass-neutral
  `x[[column]]`, retaining required-first ordering, duplicate/missing/nonempty
  checks, exact column names in diagnostics, and all existing fail-closed shape
  rules. The executable producer fixture uses real `data.table` containers and
  verifies Date, factor, typed-NA, custom-column attributes, legitimate zero-row
  metadata, container classes, exact values/attributes, and rectangularity. It
  would execute the failed join path against the old implementation.
- Local PASS on R 4.5.3/macOS arm64: all 11 raw-boundary fixtures and all 11
  scientific helper fixtures; parse of all 18 R sources; five one-payload Shiny
  handlers; Living Poster/cover contract; all three workflow YAML files; and
  `git diff --check`. An exact ABBY reproduction used the immutable raw file
  `824ded7ee13754951c93072c697bab7ddf242f9ef95d66ed4f6c3ac190fd2301`,
  Arrow 25.0.0, and data.table 1.18.4: all nine data-frame containers / 139
  columns remained value-and-attribute identical after materialization and
  rectangular; a second Arrow-free process read the staged RDS with zero warnings,
  244 identity rows, and 136,563 status rows. The first isolated local
  data.table source install was blocked by missing macOS `libintl.h`; the official
  R 4.5 macOS binary supplied the test-only dependency, and the failed compiler
  attempt is not counted as evidence.
- No estimator, threshold, grouping, label, generated RDS, demo, index,
  `manifest.json`, app runtime, workflow authority, token, publisher, Connect,
  Pages, or Driver artifact byte changed. Scientific disposition remains
  `HOLD / NO DRIVER BYTE CHANGE`. Residual gates: independent diff review, green
  exact-head CI on pinned Ubuntu/R 4.5.2/Haswell/one thread, guarded merge, then
  exactly one new complete refresh and review of its generated candidate. This
  local proof is not permission to merge a data candidate.

## 2026-08-03 raw-staging portability repair candidate

- Audit time: `2026-08-03 11:31:09 EDT (-0400)`. This source-only repair began
  from exact `origin/master` `19ba023a0bf957cb993be11639e5ee38a412beaa`
  in isolated worktree
  `/Users/vgs/Documents/Codex/2026-07-22/we-have-been-working-through-updating/work/trees/NEON-Plant-Phenology-identity-schema-30819294736`,
  branch `agent/phenology-identity-schema-30819294736`. The watched branch remains
  `master`; Pages remains
  <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/> and Connect remains
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>
  (content ID `019ee118-bf17-1622-bd5d-e59cab3b36a7`). This candidate has not
  been pushed, merged, dispatched, or deployed.
- Full-refresh run `30819294736` fetched all 46 sites successfully in job
  `91704881226`, then failed in build job `91719922015` while bundling first site
  ABBY. Publisher job `91724482179` was skipped. Its unexpired raw artifact is ID
  `8859906292`, name
  `plant-phenology-raw-19ba023a0bf957cb993be11639e5ee38a412beaa`,
  224,861,437 bytes, artifact SHA-256
  `8ebd712f36875077e42202912278ff6a94e0f3cc98b9f71dcf40a9d1c7416239`.
  Exact ABBY raw-file SHA-256 is
  `824ded7ee13754951c93072c697bab7ddf242f9ef95d66ed4f6c3ac190fd2301`.
- Root cause is storage-backend drift, not an upstream field-name or value-schema
  change. The producer's `neonUtilities` 2.4.3 result contained Arrow-backed
  ALTREP columns even though Arrow is not a declared `neonUtilities` import. With
  Arrow loaded, exact ABBY `phe_perindividual` is a rectangular 244-row,
  38-column table and all eight app identity fields are present and complete.
  Without Arrow, `readRDS()` retains the 244-row frame but warns that it cannot
  unserialize `arrow::array_*_vector` values and substitutes length-zero columns,
  producing the misleading `$<-.data.frame` replacement error. The complete
  artifact has one identity schema across all 46 sites, 10,176 raw identity rows,
  and 5,739,845 raw status rows; none of the eight identity fields is absent,
  NA, or blank. Optional metadata semantics are unchanged: unknown values are
  full-length typed `NA`; a length-zero column is valid only in a zero-row table.
- `scripts/fetch_all_phe.R` now materializes every raw data-frame column into a
  dependency-free base vector before `saveRDS()`, preserving names, classes,
  attributes, factors, dates, and typed all-NA values. The shared helper validates
  every table's rectangular shape before and after materialization.
  `scripts/bundle_phe_data.R` also validates required tables, fields, nonempty
  row sets, unique column names, and column lengths immediately after `readRDS()`.
  Corrupt legacy artifacts therefore fail closed with the table/site/column and
  expected length rather than continuing into identity assignment. No Arrow
  runtime dependency was added and the existing stable first-source identity
  deduplication contract is unchanged.
- Regression coverage now includes typed optional NAs, Date/factor preservation,
  legitimate zero-row metadata, dependency-free RDS round-trip, and the exact
  corrupt shape from this run: a nonempty frame with a zero-length
  `individualID`. `Rscript --vanilla scripts/test_bundle_identity.R` passes all
  10 fixtures. `scripts/test_helpers.R` passes all 11 fixtures using a temporary
  local library; every R source parses, all five one-payload handler and cover
  checks pass, all three workflow YAML files and the embedded publisher Bash
  parse, and `git diff --check` passes.
- Exact-artifact local proof used R 4.5.3 on macOS arm64, temporary Arrow 25.0.0
  only to decode and normalize the producer bytes, then an explicitly Arrow-free
  library to read and validate all 46 normalized RDS files with zero warnings.
  The sorted aggregate normalized-raw SHA-256 is
  `0aa0d4f44d527b6ea2a996a160814b5ca00f7cb0402fff4d3408cbfab461ab92`.
  A full isolated build from those bytes succeeded for all 46 sites: 5,735,598
  bundled observations, 9,537 retained individuals, 723 national onsets, 723
  search taxa, 46 search sites, demo site HARV, and KONA `trend = NULL`.
  Two index rebuilds had identical MD5 values (`3850299bdc76e069b7d839e4ae87be74`
  national, `7cc7a5503f26bcc2d1ecc2acac6c797c` search,
  `d8ef3c8dfcb9fde1496e52fe5c350be8` site), and two trend normalizations were
  idempotent across 47 files.
- Diagnostic attempts that did not pass were resolved rather than counted as
  evidence: the first full-build assertion expected 244 ABBY identities before
  accounting for the existing observation semi-join (the correct final count is
  240); helper tests initially lacked temporary `tidyr` and `RColorBrewer`;
  local Ruby 2.6 rejected the newer `aliases:` keyword and an initial workflow
  list named nonexistent `pages.yml`; and an early error-substring assertion was
  too order-specific. The first aggregate R-parse wrapper also misescaped its
  filename regex. An exact Arrow-free validator assertion initially surfaced a
  corrupt auxiliary categorical-code table before the required identity table;
  validation now deliberately checks the two required build tables first.
  Corrected assertions and environment-independent parsers pass. Temporary
  evidence/libraries remain only under explicit `/private/tmp` paths and are not
  repository or release artifacts.
- No estimator, threshold, grouping, label, generated RDS, demo, index,
  `manifest.json`, workflow authority, token, publisher, Connect, Pages, or Driver
  byte changed. Scientific disposition remains `HOLD / NO DRIVER BYTE CHANGE`.
  Residual gates after local review and commit: run exact-head CI on pinned R
  4.5.2 / Ubuntu 22.04 / Haswell / one thread, merge only a green head, then
  dispatch a complete `skip_download=false` refresh and promote only its fully
  validated candidate through the review-branch publisher. The macOS proof is
  strong diagnostic evidence but is not a release or publication receipt.

## 2026-08-03 scheduled-refresh native-crash repair candidate

- Audit time: `2026-08-03 08:40:38 EDT (-0400)`. Work began from exact
  `origin/master` `50106f205a38ab5abf1e807f1c54e44a9b5d8885` in isolated
  worktree `/private/tmp/neon-phenology-refresh-fix.duRTRe`, branch
  `codex/phenology-refresh-native-crash`. At audit time no repair candidate had
  been committed, pushed, merged, dispatched, or deployed; the publication
  receipt below remains required before any production claim.
- Scheduled run `30736823432` did not update production. `fetch_raw` job
  `91467014297` succeeded for all 46 expected sites. Its immutable raw artifact
  was ID `8830739400`, 224,849,352 bytes, SHA-256
  `5bc89c0b7c919a115735f6b2e8100ab23f2869e364f1eef74a1845b5a1092856`;
  the former one-day retention expired it before this repair pass. ABBY, the
  first alphabetic bundle, contained 136,563 status rows and 244 individual rows.
- `build_candidate` job `91473889852` used pinned R 4.5.2 with dplyr 1.2.1,
  vctrs 0.7.3, and tibble 3.3.1, then received SIGSEGV / null address at
  `scripts/bundle_phe_data.R:36`. The trace entered
  `vctrs::vec_unique_loc(cols)` through
  `dplyr::distinct(individualID, .keep_all = TRUE)`. ABBY being first does not
  establish malformed ABBY data, and the expired raw artifact prevents a
  lower-level reproduction from those exact bytes. Publisher job `91475415648`
  was skipped, so there was no validated candidate artifact, review-branch
  update, PR update, merge, Pages update, or Connect update.
- Repair scope is build/release hardening only. New pure-base helper
  `scripts/bundle_identity.R` requires the eight identity fields, materializes
  `individualID` as UTF-8, fails closed on absent fields or NA/blank keys, and
  keeps the complete first source row with stable `!duplicated()` selection.
  `scripts/bundle_phe_data.R` applies that boundary before tibble conversion and
  no longer routes the raw identity key through vctrs hashing. Dependency-free
  adversarial fixtures cover unsorted and non-ASCII keys, conflicting duplicate
  metadata, exact output schema, absent fields, NA keys, and whitespace-only keys.
- Raw-evidence retention is now seven days. The publisher now follows the
  Breeding Birds exact-head contract: exact `master` base, direct-child promotion
  commit, scoped staged-byte comparison, force-with-lease, remote-head receipt,
  one unambiguous `master <- automation/plant-phenology-data-refresh` PR, and
  verification that an existing PR's `headRefOid` equals the pushed commit. It
  never calls `gh pr create`; when no PR exists it emits the reviewer-authenticated
  exact-head PR notice, and when one exists it emits the workflow-approval notice.
- Local PASS on R 4.5.3: `Rscript --vanilla scripts/test_bundle_identity.R`
  (all six fixtures); parse of `scripts/bundle_identity.R`,
  `scripts/bundle_phe_data.R`, `scripts/test_bundle_identity.R`, and
  `scripts/test_helpers.R`; Ruby YAML parse plus `bash -n` of the embedded
  publisher; `node scripts/check_custom_message_handlers.mjs` (five exact
  one-payload handlers); workflow static assertions; and `git diff --check`.
  `Rscript --vanilla scripts/test_helpers.R` is locally BLOCKED before fixture
  execution because this worktree runtime lacks `dplyr` and `tibble`; those are
  installed by the pinned workflow, and no substitute result is claimed.
- No generated bundle, index, demo, or `manifest.json` byte was touched. Scientific
  disposition remains `HOLD / NO DRIVER BYTE CHANGE`; no estimator, threshold,
  grouping, label, or app runtime contract changed.
- Residual gate and next action: review and publish this source-only candidate,
  require green exact-head CI, merge it, then manually run the complete refresh
  with `skip_download=false`. The old failed run cannot validate the repair because
  it remains attached to the old source SHA and its raw artifact expired; the
  `skip_download=true` path only rebuilds committed indexes and does not execute
  the repaired bundler. Review and merge only the new workflow's fully validated
  generated candidate, then verify the exact production merge.

## 2026-07-22 Suite Living Poster V1 source candidate

- Working branch: `agent/phenology-living-poster-v1`; production remains the
  verified release recorded later in this ledger until the pinned validator,
  review, merge, and Connect/Pages promotion path completes.
- Pages and the in-app first-run surface now share the approved poster contract:
  **“Read the seasons.”** / **“Follow tagged plants through the turning year.”** /
  **“Pick a place.”** The face has one Driver route, one contextual CTA, dominant
  responsive editorial art, an explicit illustration/data boundary, and compact
  source and claim-boundary notes. The prior fact band, method cards, release
  receipt, and full suite directory were removed from the companion face.
- The documented seasonal desktop/mobile art was reused without a new generative
  operation and mirrored byte-for-byte into `www/assets/`. The 1200×630 social
  card was recomposed from its checked-in HTML/SVG sources around the same hook
  and promise; `docs/IMAGE-PROVENANCE.md` carries the new exact hashes.
- Local source verification passed `node --check scripts/check_cover.mjs`,
  `node scripts/check_cover.mjs`, `git diff --check`, a clean 1280×720 browser
  render with one H1/Driver route and no root overflow, and an exact 1200×630
  social-card inspection. This shell has no R runtime, so the R parse, manifest,
  deterministic artifact, 390/320 browser, Connect, and Pages gates remain for
  the pinned validator. No scientific estimator, bundle, or Driver vote changed.

## Product and release identity

- Repository: `tgilbert14/NEON-Plant-Phenology-Explorer`
- Watched branch: `master`
- Data product: NEON Plant Phenology Observations `DP1.10055.001`
- Expected site roster: 46 terrestrial sites from `R/site_metadata.R`
- Baseline source: `master` commit
  `1917f760bddd1781388462bcfebedff322edc6af`
- Pages: <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/>
- Connect: <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>
- Connect content ID: `019ee118-bf17-1622-bd5d-e59cab3b36a7`

## Current release state

`P0 OUTAGE / RELEASE UNSAFE` as of the baseline below. The public Connect URL
renders Posit's `Startup Error` page. The signed-in record reports its last deploy
as 2026-07-08 from source `1917f76`; available logs show Shiny starting, listening,
connecting to a worker, and then stopping without the underlying R error being
visible in the inspected excerpt. Do not report recovery until a content-aware
public check finds this app's semantic-ready marker.

The tracked `manifest.json` claims R 4.5.2, 92 packages, and 60 files, but its
checksums disagree with eight tracked runtime files: `global.R`, `R/codebook.R`,
`R/phe_helpers.R`, `R/site_metadata.R`, `server.R`, `ui.R`, `www/phe.css`, and
`www/styles.css`. Its ordinary repository is a moving `jammy/latest` snapshot and
some installed-package metadata originated on Windows. The manifest is not a
publishable source of truth.

The only workflow, `.github/workflows/refresh-data.yml`, currently uses moving
action/runner references, combines build and write authority, and pushes generated
data directly to `master`. `scripts/fetch_all_phe.R` requests only through
`2024-12`. These are release blockers, not maintenance conveniences.

## Scientific contract and known issue

The observational unit is a status record for a tagged plant and phenophase. The
Phenology Clock response opportunity is one
`individualID x phenophaseName x year x week` cell after excluding uncertain
status. Multiple visits within a cell collapse with `yes` winning; different years
remain separate plant-year opportunities. Pooling those opportunities produces a
descriptive typical-year curve.

Baseline `weekly_yesrate()` incorrectly omits `year` from its first grouping. It
therefore turns one plant's `yes` in a calendar week in any year into `yes` for that
plant-week across all years and can report an ever-yes construct rather than
plant-year prevalence. Correct the estimand, labels, codebook, exports, and
adversarial fixtures together.

Existing source already contains several important protections that must remain:
interval-censored onset, explicit left censoring, plant-year de-pseudoreplication
for onset trends, leaf-active duration, green-up coverage, desert-aware metric
selection, cadence guards, and within-species slope framing. They are source
findings only until the pinned build and deployed semantic receipt pass.

## Required release gates

1. Static R parse, JavaScript syntax, workflow syntax, and cover/accessibility
   contracts.
2. Assertion-based scientific fixtures for plant-year clock opportunity, repeated
   visits, uncertain status, support suppression, onset censoring, trend
   de-pseudoreplication, leaf-active duration, and green-up coverage.
3. All 46 committed site bundles load and satisfy required schemas; site, national,
   search, and demo indexes load and agree with the site roster.
4. Pinned R 4.5.2 / Ubuntu 22.04 / Haswell / one-thread build with exact geospatial
   source closure and a dated package snapshot.
5. Manifest generated in that environment, exact file/checksum equality, required
   runtime packages present, build-only packages absent, and trusted provenance.
6. Bundle-only offline boot; all custom-message handlers accept one payload.
7. Green exact PR head and green merge; Connect explicitly deploys the merge commit.
8. Public semantic-ready marker and representative interaction with no unexpected
   first-party console/server failure.
9. Pages cover at desktop and 390 px: stable geometry, no persistent horizontal
   overflow, canonical/social metadata and natural image dimensions, keyboard
   access, and every public/suite link healthy.
10. Final knowledge package, Driver disposition, suite register, and Driver backlog
    updated before beginning the next app.

## Baseline entry

### 2026-07-18 16:54 MST - pass 2 baseline / Codex

- Started on clean local branch `agent/phenology-pass1` at immutable source
  `1917f760bddd1781388462bcfebedff322edc6af`; `origin/master` matched.
- Expected public result: a functioning bundle-backed Plant Phenology Explorer.
  Actual: the share URL displayed `Startup Error`. The signed-in Connect record
  identified commit `1917f76`, last deployed 2026-07-08 21:19; the inspected log
  excerpt started/listened/connected and then stopped without a visible R exception.
- Audited the tracked manifest and found the eight runtime checksum mismatches and
  moving/provenance risks summarized above. Manifest SHA-256 at baseline:
  `e96b7e43511e602fa96bd32bc4e8751c8fa4e710bc3b9ab56b9a207bd859cceb`.
- Audited the refresh path and found direct write-to-`master`, combined authority,
  moving workflow inputs, fixed `enddate = "2024-12"`, and print-only helper
  diagnostics rather than assertions.
- Audited the Clock and found the missing-`year` plant-week grouping bug. The
  intended replacement estimand is one scored plant-year-week opportunity; repeat
  visits collapse within year, years remain independent opportunities, and weeks
  with fewer than five opportunities remain suppressed.
- Local environment has no `Rscript`; R execution, manifest generation, bundle
  validation, and boot tests must therefore run in pinned GitHub Actions. This is a
  baseline constraint, not evidence that any R gate passed.
- Changed only the app-local governance/handoff/knowledge-package scaffold in this
  baseline step. No runtime, generated data, manifest, deployment, or Driver
  artifact byte was changed. Release evidence remains invalidated by the outage and
  manifest drift.
- Next concrete action: implement the plant-year estimand and adversarial fixtures,
  repair custom-message contracts, then install the pinned read-only validator and
  restricted refresh-candidate pipeline before visual/product changes.

### 2026-07-18 17:33 MST - release candidate assembled / Codex

- Corrected `weekly_yesrate()` to one scored opportunity per
  `individualID x phenophaseName x year x week`, aligned every Clock label/export
  description, and replaced print diagnostics with fail-closed fixtures covering
  repeat visits, independent years, uncertain status, n suppression, onset
  censoring, trend de-pseudoreplication, multi-flush leaf-active duration,
  green-up coverage, and within-species gradient support.
- Installed a pinned R 4.5.2 validator, exact geospatial source closure (including
  the full `https://cran.r-project.org/.../wk_0.9.5.tar.gz` archive reference),
  deterministic two-build index gate, full bundle/index/schema verifier, exact
  manifest artifact, bundle-only source test, and custom-message signature check.
  The isolated R 4.1.1 fetch lane now uses a dated 2024-12-31 package snapshot; the
  validator/publisher remain read-only/review-branch separated.
- Removed the search index's `Sys.Date()` build input. Its compatibility field
  `built` is now the maximum committed observation date, so identical input does
  not manufacture a refresh. Added key/schema/cross-index checks for individual
  summaries, trends, search taxa, and search sites.
- Removed all font, toast, and DOM-to-image CDNs from app startup. Card export now
  uses a local SVG-foreignObject renderer and local status toast. All five Shiny
  custom-message handlers accept one payload argument.
- Rebuilt the Pages cover with local responsive seasonal imagery, explicit CAN / 
  CANNOT / suite-role boundaries, all ten suite destinations, canonical/social
  metadata, a new exact 1200 x 630 social card, and no opaque app prewarm. Image
  prompts, source assets, alt text, dimensions, and SHA-256 receipts are in
  `docs/IMAGE-PROVENANCE.md`.
- Local checks passed: Ruby parsed all three workflow YAML files; Node parsed the
  cover/checkers/app/pin-card JavaScript; exactly five message handlers passed;
  Bash parsed the semantic smoke; `git diff --check` passed; and the cover/image
  contract passed. No local `Rscript` is installed, so these are not substitutes
  for the pending pinned R gates.
- Local browser receipt: desktop rendered at 1280 x 720 with a 1180 px hero and no
  content wider than the viewport; 390 x 844 selected the 864 x 1821 portrait
  asset, kept both launch controls at least 51 px tall, and reported
  `scrollWidth = innerWidth = 390`. Semantic landmark inspection found one h1,
  one main, labeled navigation, the complete can/cannot boundary, and all suite
  links.
- Independent subagent audit identified and drove the deterministic search receipt,
  pinned fetch lane, stronger derived schemas, corrected 2016-2024 cover vintage,
  and explicit distinction between an HTTP identity smoke and a real Shiny-session
  receipt. Those rules were also fed back into the app-local NEONize playbook.
- Generated/derived release bytes (`manifest.json` and derived RDS indexes) are
  intentionally not hand-edited. Next concrete action: commit and push this review
  head, promote only the exact green validator artifact when CI exposes the
  expected generated-byte diff, then merge, republish the exact merge on Connect,
  and run public app/Pages browser verification.

### 2026-07-18 18:20 MST - first pinned validator finding and repair / Codex

- Published candidate `8b443c4adf2d0687cf9f02ac8474b3965cd05477` to draft PR #3.
  Pinned run `29667231377`, job `88139693110`, compiled the full R 4.5.2 source
  closure in 22m00s, then passed the loaded Haswell/one-thread runtime, static
  contracts, all original scientific fixtures, deterministic index rebuild, and
  manifest generation.
- The run failed closed at bundle verification with one exact finding:
  `data/sites/KONA.rds trend must be NULL or a non-empty data frame`. Offline boot,
  validated artifact upload, and committed-byte equality were correctly withheld.
  The uploaded manifest was explicitly diagnostic/unvalidated.
- Root cause: `onset_trend()` returned `NULL` when no onset observations existed,
  but returned a typed zero-row data frame when observations existed and every
  species-year was removed by the `n >= 3` support gate. KONA preserved that
  semantically unavailable container. The verifier's rule is correct and was not
  weakened.
- Repair: `onset_trend()` now normalizes an all-suppressed result to `NULL`, with a
  new two-individual adversarial fixture. A focused bundle normalizer changes only
  historical zero-row `trend` fields to `NULL`, fetches no data, fails on malformed
  containers, and is executed twice under the pinned runtime with exact all-bundle
  hashes to prove idempotence.
- Artifact boundary: the validator now includes exact `data/sites/KONA.rds` bytes
  alongside the three rebuilt indexes and generated manifest in the immutable
  release candidate. The expected next run may fail only at committed-byte equality
  after every semantic, bundle, manifest, and offline-boot gate passes; only that
  validated artifact is eligible for promotion.
- Local static gates (PASS): Ruby parsed all three workflows; Node parsed the two
  runtime scripts and passed the five-handler and cover contracts; Bash parsed the
  semantic smoke; `git diff --check` passed. Local R remains unavailable, so the new
  R fixture, normalizer, bundle verifier, and artifact bytes require the pinned
  GitHub run.
- Artifacts/non-impact: no RDS or manifest byte was hand-edited, no Connect publish
  occurred, and no Driver artifact changed. The public app remains a P0 Startup
  Error until a green promoted release is merged and explicitly deployed.
- Next action: commit and push the focused repair to PR #3, inspect the exact failing
  or passing gate, download and promote only a fully validated release-candidate
  artifact, then require a clean exact-head rerun.

### 2026-07-18 18:40 MST - migration idempotence finding / Codex

- Run `29668461839`, job `88143068558`, on repair head `fbf854b` passed the full
  dependency install, loaded Haswell/one-thread check, static contracts, and the
  expanded scientific helper suite. The new all-suppressed-trend fixture therefore
  passed in pinned R 4.5.2.
- The first normalizer pass found and changed exactly one file,
  `data/sites/KONA.rds`. Its second/idempotence pass failed because R list assignment
  with `bundle$trend <- NULL` deletes the named field. The strict bundle-container
  check then correctly reported that KONA no longer had a `trend` field. All later
  build, manifest, bundle, boot, and artifact steps were withheld.
- Repair: use `bundle["trend"] <- list(NULL)` so the required name is retained with
  an unavailable `NULL` value. This is an R container-semantics correction; no
  scientific threshold, verifier, bundle schema, or artifact rule changed.
- Next action: push the one-line structure-preserving correction, rerun the pinned
  validator from its now-populated dependency cache, and require the normalizer's
  second pass to reproduce exact all-bundle hashes before any artifact promotion.

### 2026-07-18 19:05 MST - validated release-byte promotion / Codex

- Run `29668976235`, job `88144464344`, on source head `72c6271` and PR merge
  revision `a87e44bb1edf91366fdd32f43c34e69b185c59cb` completed the full R 4.5.2
  dependency closure and passed the loaded Haswell/one-thread runtime, static
  contracts, expanded scientific helpers, two-pass trend normalization with exact
  all-bundle hashes, two-build deterministic indexes, pinned manifest generation,
  bundle/index/manifest verification, and complete offline app sourcing.
- The run failed only at the intended final committed-byte equality guard. Both
  validated artifact uploads had already completed; no semantic or runtime gate
  failed. Exact release candidate:
  `plant-phenology-release-candidate-a87e44bb1edf91366fdd32f43c34e69b185c59cb`.
- Promoted all five files directly from that artifact, without rebuilding or hand
  editing: `data/sites/KONA.rds`, `data/site_index.rds`,
  `data/national_onsets.rds`, `data/search_index.rds`, and `manifest.json`.
  SHA-256 receipts, in that order: `9b294811f7e880a29f05d3c11d0305d9034367b3822a529338e5b79c358b6f9e`,
  `c2686b9e744384bbec16acaf43ff4da125f12f50bd9db19987bdb8d293516a63`,
  `c0935aacbfeb319146eadef29f720d748f39fd03cebcef3cd10444f1767e5446`,
  `0e3c1e3790c1a108fb991699442d5721e4b54018e7725d8609ceb0bacff899bc`,
  and `cc5e2a464b2c96772c6e2b441b55a4eabb603f36311c08d4342e4ed0f59a5325`.
- A fresh browser release pass at 390 and 320 CSS pixels found a page-level
  horizontal overflow in the mobile suite carousel: `100vw` included the reserved
  scrollbar. The carousel now extends from its shell with `calc(100% + 15px)`, and
  the body's minimum width allows the 305-pixel usable content area on a 320-pixel
  test viewport. Final 390 result: client/scroll `375/375`; final 320 result:
  `305/305`. The carousel itself remains independently scrollable, both launch
  controls remain visible, and the responsive portrait artwork is selected.
- Next action: commit the exact promoted bytes and responsive correction, push the
  PR head, and require the complete exact-head validator to finish green before
  merge or Connect publication.

### 2026-07-18 19:32 MST - publication closeout / Codex

- Exact PR head `cc0151dae58d4128e831e74cc44f2f7c01ec3ac6` passed the complete
  release validator in run `29669603912`, job `88146136480` (21m08s). The final
  committed-byte equality guard was clean after every scientific, deterministic,
  manifest, bundle, and offline-source gate.
- PR #3 merged as `29c0ed119fe7a4183d77b9fae475a8d6ddff9154`. GitHub Pages
  published that exact merge in run `29670192167`. Connect was explicitly
  republished from watched branch `master`; Content Info reports Last deployed
  `29c0ed1` at 2026-07-18 19:26 MST.
- Production semantic run `29670192516` passed the app-specific marker and host
  error rejection. An independent one-attempt smoke also returned HTTP 200 plus
  semantic body checks for both Connect and Pages.
- Fresh unauthenticated browser session: selected HARV, loaded 211 tagged plants,
  20 species, two plots, median green-up day 116, and analysis-bundle/report-card
  download routes. Overview, Phenology Clock, Onset Lab, and Across Sites rendered;
  the Clock exposed its scored plant-year opportunity, no-shift CI, and roster
  caveat, while Across Sites led with a 10-site within-species Acer rubrum view,
  cadence support, interval censoring, and explicit observational/non-causal limits.
- Public app at 390 x 844 reported root client/scroll `375/375`, retained semantic
  marker `plant-phenology-v1`, loaded HARV, and showed KPI values 211/20/2/116.
  Public Pages passed desktop `1425/1425`, 390 `375/375`, and 320 `305/305` root
  geometry; selected the 1666 x 944 desktop and 864 x 1821 mobile assets; retained
  57/52-pixel launch controls at 390 and 77/52-pixel controls at 320; and exposed
  the canonical URL, exact `og-image-v2.jpg`, all ten suite links, and one current
  app marker.
- Driver disposition is `HOLD / NO DRIVER BYTE CHANGE`. The corrected app-local
  onset/leaf-active/coverage signals are trusted; adoption still requires the exact
  eligible site-year join, support/censoring gates, and a registered analysis.
- Master validator run `29670192503`, job `88147654406`, passed the same complete
  contract on merge `29c0ed1` in 20m26s, including exact committed data/manifest
  equality and offline source. No release gate remains.
- Central Driver PR #25 merged the reusable R-list, idempotent migration,
  documentary/stylized cover, and 320-pixel overflow lessons as Driver master
  `9c70951`; its post-merge rebuild `29670522783` and Pages run `29670522519`
  passed with no Driver artifact change. Final action: merge this documentation-only
  app receipt and advance the suite to Plant Diversity.
