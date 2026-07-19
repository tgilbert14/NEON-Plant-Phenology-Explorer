# Repository operating instructions

These instructions apply to the entire repository. User and platform instructions
take precedence.

## Mandatory entry point

Before inspecting, changing, testing, rebuilding, publishing, or reporting on this
repository, read `docs/BUILD-TEST-HANDOFF.md` and
`docs/DRIVER-KNOWLEDGE-PACKAGE.md` completely. For suite work, also read the Driver
repository's complete `docs/NEON-SUITE-LEARNING-LOOP.md`,
`docs/NEON-SUITE-REVAMP-PLAN.md`, and `docs/neonize-playbook.md`.

Start and end every session with `git status --short --branch` and preserve changes
you did not create. Record the source branch, source commit, watched deployment
branch, public Pages URL, Connect URL, and exact test state before changing release
bytes.

## Scientific contract

- The product is NEON Plant Phenology Observations `DP1.10055.001`. It describes
  recorded phenophase timing for tagged plants; it does not estimate plant
  abundance, productivity, demographic performance, or causal climate effects.
- The Phenology Clock estimand is one scored opportunity per
  `individualID x phenophaseName x year x week`. Repeated visits within that cell
  collapse to one opportunity; years do not collapse. Pooling creates a descriptive
  typical-year profile of plant-year opportunities, not a population trend.
- Onset is interval-censored between the last preceding `no` and first `yes`;
  left-censored onsets must remain explicit. Trend summaries first collapse to one
  plant-year value so repeated plants or phenophases are not pseudoreplicated.
- Green-up coverage is a separate support diagnostic. Warm-desert sites may require
  leaf-active duration instead of a sparsely scored green-up phenophase.
- Sampling cadence, structural missingness, and support thresholds are scientific
  gates. Within-species gradients lead; cross-species relationships are contextual.
- Maintain explicit `CAN`, `CANNOT`, and `HELD` claims. Prefer a visible unavailable
  state to an unsupported estimate.

## Build, release, and data rules

1. Runtime must boot entirely from committed bundles. Do not add a startup network
   dependency or use an opaque HTTP response as an app-health claim.
2. Never edit `manifest.json` by hand. Generate it in the pinned validator,
   validate every tracked file/checksum and dependency-provenance rule, and promote
   only the exact validator artifact.
3. A data refresh must stage a complete candidate, verify all 46 expected sites and
   every derived index, and publish through a review branch. Never push refreshed
   artifacts directly to `master`; never delete a valid committed bundle before a
   replacement candidate passes.
4. Pin the R version, runner image, package snapshot/source closure, BLAS core and
   thread count, workflow actions, and release identities. Do not weaken a gate to
   make an environment pass.
5. Every Shiny custom-message handler must accept exactly one payload argument,
   including handlers that ignore it.
6. A release requires green tests on the exact PR head, green tests on the merge,
   exact manifest equality, a matching Connect-deployed commit, an app-specific
   semantic-ready marker, and desktop/mobile Pages verification. HTTP 200 alone is
   not health.
7. Cover/social imagery must be locally served, responsive, accessible, documented
   in `docs/IMAGE-PROVENANCE.md`, and verified at desktop and 390 px. The cover must
   distinguish what the app can and cannot answer and place it accurately in the
   suite.

## Durable closeout

Immediately before editing either durable record, re-read its latest entry. Update
`docs/BUILD-TEST-HANDOFF.md` with timestamp/time zone, scope, exact commands and
environment, expected/actual outcomes, hashes and release identities, failed
attempts/cleanup, residual risks, and the next concrete action. Update
`docs/DRIVER-KNOWLEDGE-PACKAGE.md` with the scientific support, opportunity,
eligible joins, engineering learning, and an explicit `ADOPT`, `HOLD`, `CONTEXT`,
`COMPLEMENT`, `REJECT`, or `NONE` decision.

A companion pass is not closed until its verified knowledge package is recorded in
the Driver repository's suite register and implication backlog. Do not modify Driver
artifact bytes until that decision and its evidence are complete.
