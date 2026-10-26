# Plant Phenology Explorer -> Driver knowledge package

## Decision axes

- **Application contract trust: `VERIFIED`.** The corrected opportunity,
  censoring, support, deterministic-build, manifest, offline-source, Pages, and
  production-health contracts all passed for the current promoted release.
- **Ecological Driver disposition: `HOLD / NO DRIVER BYTE CHANGE`.** App contract
  trust is not an ecological adoption receipt. Neither the current onset family
  nor the existing temperature -> green-up vote is authorized to change or vote in
  Driver from this package.

## 2026-10-26 bracketed estimand (hk follow-ups and audit items)

- Decision: `HOLD / NO DRIVER BYTE CHANGE` (`scientific-contract`,
  `Driver-impacting`). The app estimand is refined; no Driver artifact, adapter,
  model or vote changed, and none is authorized from this package. The
  application contract stays `PENDING` until PR #14's head, its merge, the Connect
  deploy and the post-merge raw refresh pass.
- Scientific support. The green-up summary now brackets the median onset by the
  visit gap and censoring: `greenup_lo` is the two-stage median of each
  plant-year's last 'no', `greenup_hi` the median of the first 'yes', and the
  value stays the midpoint median (point when the bracket is under 14 days, else
  range; an upper bound reads the first-'yes' median). Leaf-active is the
  interval-censored span with a 31-day year-boundary bridge; where unbridged edges
  could add 14 days or more, the value is a lower bound ("at least N days", 27 of
  the 42 sites with a leaf value). A trend direction needs 6 solid years and must
  agree with and without the censoring-heavy points. An independent oracle,
  written from the signed rule sheet `scripts/headline_rules.md`, reproduces every
  headline exactly at site, site-year, plant-year and species level.
- Opportunity and support: unchanged from the 2026-10-21 entry (plant-year
  opportunities; the site-year support gate; 369 watched site-years). Exact
  duplicate obs rows (30,332, 0.53%) are removed, so obs row counts fall while every
  onset and span is unchanged; uncertain records are disclosed where they reach 10%
  (NIWO 25%, RMNP 14%).
- Eligible joins. Trend keys and onsets are unchanged (the Atlas Gate-0 audit sees
  the same rows; `trend` gains only `lc_share`). Driver-calendar compatibility for
  the corrected family remains `UNMEASURED`. NEON's issue log (2026-01-28) limits
  phenology to core sites from 2026, and DELA observations ended on 2025-12-31, so
  any future join adds years only at core sites; the release watch in
  `refresh-data.yml` warns on both entries.
- Atlas implication. The Atlas computes its own weeks x 7 leaf-active, which has the
  same edge problem the app now labels; iris's recommendation to HOLD the
  leaf-active feed unless the adapter adopts the interval-censored span and the
  edge rule stands. The Atlas bundle validator passes all 46 rebuilt bundles; the
  obs byte change reaches the Atlas refresh without a PR gate.
- CANNOT (new): read a green-up range as a confidence interval (it bounds visit
  spacing and censoring, not sampling error); read "at least N days" as the full
  leaf period; give a trend direction that flips depending on how censoring-heavy
  points are treated; fit a leaf slope through lower-bound sites.
- Engineering learning: write the oracle from a signed rule sheet and compare
  exactly at every level, reimplementing the support gate (medians hid a
  carry-over bug); canonical row order plus content-keyed writes give
  byte-identical rebuilds; cap within-year spans at the year, not +Inf; gate a
  device-feedback call (vibrate) on user activation once deep links can load a view
  without a tap.

## 2026-10-21 estimand correction (audit 2026-10-18 item 12)

- Decision: `HOLD / NO DRIVER BYTE CHANGE` (`scientific-contract`,
  `Driver-impacting`). The app-local green-up and leaf-active estimands changed;
  no Driver artifact, adapter, model, or vote changed, and none is authorized
  from this package. The application contract returns to `PENDING` until the PR
  head, merge, Connect deploy, and the post-merge raw refresh pass.
- Scientific support. Green-up per plant-year is the earliest bud-break onset,
  with the first new Young leaves as a per-plant-year fallback for Drought
  deciduous broadleaf only (NEON never scores bud-break for that form). Evergreen
  shrubs without leaf buds (Larrea), cacti, leafless evergreens, and forms that
  sprout with autumn rain (SJER and SOAP forbs and graminoids) have no
  calendar-year green-up, and neither do forms that are green across the new year
  in most years (LAJA grasses and semi-evergreen broadleaf). A January 'yes' that
  was also 'yes' at the plant's last visit within 31 days is carried-over leaves,
  not an onset. Site and species
  green-up are two-stage medians over supported years with a censoring lower bound;
  the published value is withheld (upper bound) where most plants were already
  greening at the first visit. Leaf-active is the interval-censored span of each
  run of Leaves = yes visits; the earlier weeks x 7 tracked visit effort (median
  within-site correlation 0.73 with visited weeks) and is kept only as `leaf_weeks`.
- Opportunity and support. A site-year enters a metric's medians and trends only
  when the site has >= 3 watched seasons, was visited on its usual schedule that
  year (median visit-weeks >= 0.75 of its typical), and was not truncated by a
  late start for that metric (green-up: >= half of the year's onsets censored or
  coverage < half the site's typical; leaf: >= half of the plant-years already in
  leaf at the first visit). Result: of 369 watched site-years, 276 supported for
  green-up (76 low effort, 36 of them in 2020; 11 late start; 6 short record) and
  273 for the leaf metrics. Sites: 33 point, 4 range, 5 upper-bound (BARR, NIWO,
  ONAQ, WOOD, YELL), 4 short-record (DCFS, KONA, STEI, STER).
- Eligible joins. App-supported finite-green-up site-years fall from 346 across 45
  sites (39 with >= 6) to 272 across 42 sites (33 with >= 6). Driver-calendar and
  eligible adapter rows for the corrected family are `UNMEASURED`; the 346/346
  calendar match belongs to the prior release only.
- Atlas implication. The Atlas v2 adapter reads these bundles and computes its own
  green-up (bud-break phases only, no carry-over, no Young-leaves fallback) and its
  own weeks x 7 leaf-active, so the corrected definitions do not reach the Atlas
  until cass adopts them; its bundle validator passes all 46 rebuilt bundles. The
  existing HOLD stays.
- CANNOT (new): a calendar-year green-up for evergreens, cacti or autumn-sprouting
  annuals; a Young-leaves green-up treated as the same day-for-day event as
  bud-break; a green-up range read as a confidence interval (it bounds censoring,
  not sampling error); a green-up where most plants were already greening at the
  first visit, or from fewer than three seasons.
- Engineering learning: count summary columns before reassigning their source in
  one `summarise()`; re-derive stored summaries from `obs` in the index rebuild and
  gate that they reproduce; locale-independent (`method = "radix"`) ordering for
  any character key that reaches committed bytes.

## 2026-08-05 cover-label refinement

- Decision: `NONE / NO DRIVER BYTE CHANGE` (`cover-system`, `suite-platform`).
- The Pages and in-app poster omit the visible illustration badge while retaining
  a meaningful text alternative and the durable source, prompt, dimensions, and
  hashes in `docs/IMAGE-PROVENANCE.md`. Executable absence checks prevent the
  visible label or caption from returning.
- The fixed tagged-plant scope and abundance, productivity, and causal-claim limits
  remain on both first impressions. No opportunity, estimator, support, join,
  ecological disposition, data/runtime authority, or Driver artifact changed.

## Product identity

- Repository: `tgilbert14/NEON-Plant-Phenology-Explorer`
- Product: NEON Plant Phenology Observations `DP1.10055.001`
- Baseline source: `1917f760bddd1781388462bcfebedff322edc6af`
- Promoted data candidate: `3089dc8e527340245735efbc62c95aa2faee5b25`
- Current verified release/deployment: `7d0f29f7886cfae1c760a9ffc9e056184ec6fc68`
- Release family: 46 committed per-site RDS bundles plus site, national-onset,
  search, and demo indexes; pinned R 4.5.2 / Haswell / one-thread validation.

## Unit and support

- Entity: a fixed, tagged plant individual.
- Record: an observer-scored phenophase status at a visit.
- Spatial support: a terrestrial NEON site and monitored plant/transect roster;
  current candidate Driver join is by exact NEON terrestrial site and year.
- Temporal support: repeated visits during monitored seasons and repeated years.
- Clock opportunity: one scored
  `individualID x phenophaseName x year x week`; repeated visits within that cell
  collapse, while years remain separate opportunities.
- Onset support: last preceding `no` to first `yes` interval, with an explicit
  left-censored case when no preceding `no` exists.
- Missingness: unscored phenophases are not zero. Warm-desert green-up support can
  be structurally thin and requires an explicit coverage diagnostic or an
  alternative leaf-active metric.

## Candidate trusted signals

1. Plant-year green-up onset (bud-break, or first new Young leaves for drought-
   deciduous shrubs, with the 31-day carry-over rule), summarized only after
   plant-year collapse, the site-year support gate, and the censoring bounds.
   Unit: day of year, published as a point, a range, or withheld as an upper
   bound. Earlier values mean earlier observed onset.
2. Leaf-active duration, the interval-censored span of each run of `Leaves = yes`
   visits summed per plant-year, over supported site-years only. Unit: days. The
   earlier weeks x 7 estimate is retained only as the `leaf_weeks` QC column.
3. Green-up coverage, the share of monitored tagged plants with a green-up onset
   in a supported year. This is a support/interpretability signal, not
   phenological timing.

These are trusted app-local signals after the fixture, bundle, deterministic-index,
manifest, offline-source, and public release receipts passed. They remain Driver
candidates until the exact eligible site-year join and registered analysis pass.

## Measured Driver compatibility

The 2026-08-04 immutable-object audit found 346 distinct app-supported finite-onset
site-year keys across 45 sites. All 346/346 match the current Driver calendar keys,
and 39 sites have at least six supported years. This closes only the calendar-key
question for the app-supported result. It does **not** prove that the app's support
row is the registered Driver response, that censoring and species selection are
preserved by an independent adapter, or that the existing Driver green-up family
has old/new parity. The current Driver pin also differs from this promoted release.

Therefore:

- app contract trust is `VERIFIED`;
- calendar compatibility is measured rather than assumed;
- Driver estimator eligibility remains `UNMEASURED` until the adapter/model gate;
  and
- vote eligibility remains `HOLD`.

## Claims

### CAN

- Describe when recorded phenophases were active among scored plant-year-week
  opportunities.
- Summarize interval-censored onset and plant-year timing when support gates pass.
- Expose cadence, coverage, censoring, and exact contributing rows for inspection.

### CANNOT

- Infer plant abundance, productivity, survival, demographic performance, or
  unobserved phenophases.
- Treat unscored phenophases as absence, or treat repeated visits/plants as
  independent biological replicates.
- Claim a causal climate response from a descriptive site/year relationship.

### HELD

- Driver temperature -> green-up voting role until a current-source independent
  adapter preserves support/censoring, a registered model defines species/season/
  lag and eligibility before results are inspected, and old/new parity is reviewed.
  The 346/346 calendar match does not clear these gates.
- Cross-species gradients as mechanisms; within-species estimates must lead and
  pooled taxonomic patterns remain contextual.

## Reusable engineering learning

- App-specific semantic health must reject host `Startup Error` pages; HTTP 200 and
  opaque cover prewarm responses are not evidence.
- A companion manifest is a generated release artifact. Exact tracked checksum and
  dependency provenance must be validated on a pinned platform before promotion.
- Every Shiny custom-message handler needs exactly one payload parameter under the
  current Shiny client contract.
- Refreshes stage and validate a full 46-site candidate before opening a review
  branch; they never publish directly from a write-enabled producer.
- A staged RDS is an interface between producer and consumer environments, not an
  in-process cache. Materialize package-backed ALTREP columns into ordinary base
  vectors before serialization, then fail closed on non-rectangular tables at the
  consumer boundary. Optional unknowns are full-length typed `NA` values; a
  zero-length column in a nonempty frame is portability corruption, not optional
  data. Do not solve that corruption by silently adding the producer's storage
  backend to the application runtime. Raw-boundary validators must also be neutral
  to valid producer container subclasses: inspect named columns through `[[`.
  Base-style `x[character_names]` is column selection for a data frame but invokes
  join semantics for a live `data.table`; require an executable fixture using the
  producer's actual container class before publishing the boundary.
- Derived artifacts must not embed wall-clock build dates. Derive freshness from
  immutable inputs (here the maximum observation date) and require two rebuilds to
  produce identical hashes before publication.
- A static app-identity marker plus host-error rejection is an HTTP smoke, not a
  session receipt. A Driver-eligible companion release still requires a browser to
  establish the Shiny session and complete a representative data interaction.
- Cover imagery can be expressive without becoming evidence: retain source and web
  derivatives, prompts, dimensions, hashes, alt text, and an explicit non-data
  interpretation boundary; keep app startup independent of third-party CDNs.
- A filtered derived result with no supported rows is an unavailable value, not a
  valid empty estimate. Normalize typed zero-row trend frames to `NULL`; when a
  named R-list field must remain in the schema, use `bundle["trend"] <- list(NULL)`
  because `$trend <- NULL` deletes the field. Run migrations twice and require exact
  all-bundle hashes on the second pass.
- A 320-pixel browser can reserve 15 pixels for its vertical scrollbar. Avoid
  `100vw` inside shell-relative mobile carousels, allow the body below 320 pixels,
  and require root `clientWidth == scrollWidth` at both 390 and 320 widths while
  allowing the carousel itself to scroll.
- A product cover should lead with a memorable app-native promise and honest task
  routes. This pass used an explicitly stylized seasonal cut-paper scene; suite
  cohesion comes from shared navigation, claim boundaries, and receipts rather
  than forcing every app into the same hero or repetitive relationship prose.

Learning classes: `suite-platform`, `scientific-contract`, `cover-system`, and
`Driver-impacting` (held; no byte change).

## Publication receipt

- Validated refresh candidate: `3089dc8e527340245735efbc62c95aa2faee5b25`.
- PR #9 exact-head check: `30841258764`.
- Current promoted merge: `7d0f29f7886cfae1c760a9ffc9e056184ec6fc68`.
- Merged validation: `30842200764`; Pages: `30842196863`; exact production
  health: `30842199076`.
- Current manifest SHA-256:
  `512737700fdad555264737303439a1816eb189f5ec456e7420aa40dc9165d29b`.
- The approved Suite Living Poster remains part of the verified current release;
  the data promotion did not replace its cover contract.

## Driver decision and next dependency

Current decision: `HOLD / NO DRIVER BYTE CHANGE`. The application contract and
current promoted release are trusted, and the calendar join is measured at 346/346
app-supported site-years. The first dependency that can change the ecological
decision is a separately registered current-source Driver adapter and
temperature/onset analysis that preserve support and censoring and pass old/new
parity. If that gate does not support an inferential vote, keep green-up and
leaf-active timing as `CONTEXT` rather than forcing adoption.
