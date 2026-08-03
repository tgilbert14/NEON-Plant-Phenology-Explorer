# Plant Phenology Explorer build/test handoff

This is the durable cross-session record for the application, its scientific
contract, generated data, release state, and publication evidence. Read it before
work and re-read the latest entry immediately before appending or revising it.

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
