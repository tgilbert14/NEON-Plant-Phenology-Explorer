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
