# Plant Phenology Explorer -> Driver knowledge package

## Decision state

`HOLD - PASS IN PROGRESS`. This package is a scaffold, not an adoption receipt.
No Driver artifact byte is authorized from the current source or public deployment.

## Product identity

- Repository: `tgilbert14/NEON-Plant-Phenology-Explorer`
- Product: NEON Plant Phenology Observations `DP1.10055.001`
- Baseline source: `1917f760bddd1781388462bcfebedff322edc6af`
- Bundle/schema version: not yet formalized; 46 committed per-site RDS bundles plus
  site, national-onset, search, and demo indexes require pinned validation.

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

These remain candidates until raw-oracle, fixture, bundle, manifest, and public
release receipts pass.

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

Learning classes: `suite-platform`, `scientific-contract`, `cover-system`, and potentially
`Driver-impacting`. Final classification and exact Driver disposition are pending.

## Driver decision and next dependency

Current decision: `HOLD`. The first dependency that can change it is a verified
release containing the corrected plant-year estimand and adversarial tests, followed
by an exact eligible site-year join and registered temperature/onset analysis. If
that analysis does not support an inferential vote, preserve green-up/leaf-active as
`CONTEXT` rather than forcing adoption.
