# Plant Phenology Explorer build/test handoff

This is the durable cross-session record for the application, its scientific
contract, generated data, release state, and publication evidence. Read it before
work and re-read the latest entry immediately before appending or revising it.

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
