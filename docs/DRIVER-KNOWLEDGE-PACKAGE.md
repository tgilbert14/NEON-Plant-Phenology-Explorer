# Plant Phenology Explorer -> Driver knowledge package

## Decision state

`HOLD - PASS 2 COMPLETE / NO DRIVER BYTE CHANGE`. The app release is verified;
the candidate phenology signals are not an adoption receipt. No Driver artifact
byte is authorized from this pass.

## Product identity

- Repository: `tgilbert14/NEON-Plant-Phenology-Explorer`
- Product: NEON Plant Phenology Observations `DP1.10055.001`
- Baseline source: `1917f760bddd1781388462bcfebedff322edc6af`
- Verified release source/deployment: `29c0ed119fe7a4183d77b9fae475a8d6ddff9154`
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

1. Plant-year green-up onset, summarized only after plant-year collapse and support
   gates. Unit: day of year. Earlier values mean earlier observed onset, subject to
   interval/left censoring.
2. Leaf-active duration, estimated as distinct weeks with `Leaves = yes` times
   seven. Unit: approximate active-leaf days; preferred where green-up phenophases
   are sparsely recorded.
3. Green-up coverage, the share of monitored tagged plants with a finite green-up
   onset. This is a support/interpretability signal, not phenological timing.

These are trusted app-local signals after the fixture, bundle, deterministic-index,
manifest, offline-source, and public release receipts passed. They remain Driver
candidates until the exact eligible site-year join and registered analysis pass.

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

- Driver temperature -> green-up voting role until the corrected opportunity
  contract, exact site-year join, support/missingness gates, registered model, and
  release evidence are complete.
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

- Green PR head: `cc0151dae58d4128e831e74cc44f2f7c01ec3ac6`, run
  `29669603912`, job `88146136480`.
- Merge, Pages, and Connect Last deployed:
  `29c0ed119fe7a4183d77b9fae475a8d6ddff9154`; Pages run `29670192167`.
- Master validator `29670192503`, job `88147654406`, reproduced the complete
  release on merge in 20m26s.
- Production semantic run `29670192516` passed. A fresh public HARV session loaded
  211 tagged plants, 20 species, two plots, and median green-up day 116, then
  rendered Overview, Phenology Clock, Onset Lab, and Across Sites. The 390-pixel
  app and the 390/320-pixel Pages cover had no page-level horizontal overflow.

## Driver decision and next dependency

Current decision: `HOLD / NO DRIVER BYTE CHANGE`. The corrected plant-year estimand,
adversarial tests, and verified release are complete. The first dependency that can
change the decision is an exact eligible site-year join with support/censoring gates
and a registered temperature/onset analysis. If that analysis does not support an
inferential vote, preserve green-up/leaf-active as `CONTEXT` rather than forcing
adoption.
