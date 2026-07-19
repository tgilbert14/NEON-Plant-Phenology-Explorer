# Deploy and hosting runbook

Plant Phenology has two public surfaces and both are release-critical:

- GitHub Pages cover: <https://tgilbert14.github.io/NEON-Plant-Phenology-Explorer/>
- Posit Connect Cloud app:
  <https://019ee118-bf17-1622-bd5d-e59cab3b36a7.share.connect.posit.cloud/>

The app is git-backed from `master`, but a merge is not proof that the public
worker changed. A release is complete only when the Connect record identifies the
exact merge commit and a real browser session initializes and completes a
representative interaction.

## Release contract

1. Open a review branch from current `master` and preserve the baseline commit.
2. Let `.github/workflows/ci.yml` run in pinned R 4.5.2 / Ubuntu 22.04 / dated
   RSPM / Haswell / one-thread mode.
3. If generated release bytes differ, download the workflow's validated
   `plant-phenology-release-candidate-<sha>` artifact. Promote those exact files;
   never hand-edit `manifest.json` or an RDS index.
4. Require the exact PR head to pass: source/static contracts, adversarial
   scientific fixtures, two identical derived-index builds, 46-bundle/schema
   verification, exact manifest provenance, cover/image contracts, and offline
   app sourcing.
5. Merge only that green head, then require the merge commit's CI and Pages build
   to pass.
6. In Connect Cloud, republish/sync the `master` source if it has not already
   selected the merge. Record the deployed full commit, not just a seven-character
   display prefix.
7. Verify the public app is not a host error page, contains
   `ddl-app-ready=plant-phenology-v1`, establishes a Shiny session, loads a
   representative bundled site, changes one analysis control, and produces no
   unexpected first-party console error.
8. Verify the Pages cover at desktop and 390 px: no persistent horizontal
   overflow; correct responsive image; canonical and 1200 × 630 social metadata;
   keyboard-reachable launch, methods, suite, source, data-product, and license
   links.
9. Write exact run IDs, commit identities, manifest/image hashes, and residual
   risks into `docs/BUILD-TEST-HANDOFF.md` before declaring recovery.

`.github/workflows/post-deploy.yml` adds a cold-start-aware first line of defense:
it rejects common Posit host error pages and requires the app-specific static
identity marker. That HTTP check cannot prove a WebSocket-backed Shiny session;
step 7 remains mandatory.

## Manifest and runtime

The deployed app starts entirely from committed bundles. `neonUtilities` and
`arrow` are refresh/build inputs only and must not enter the runtime manifest.

`scripts/write_manifest.R` is the sole manifest generator. It:

- scans the exact runtime file set;
- prunes build-only packages;
- canonicalizes ordinary packages to the dated RSPM snapshot;
- pins the source-built geospatial closure, including the complete `https://`
  archive URL for `wk 0.9.5`; and
- fails on an untrusted package identity or provenance field.

Run the generator only inside the pinned validator. The committed manifest must
be byte-equivalent in meaning and checksum to the validated artifact before
release. The current Connect dependency incident was caused by treating a stale,
moving manifest as trustworthy; this contract prevents that class of failure.

## Cover and social assets

The Pages source is `docs/index.html`. It launches the fixed Connect URL directly;
there is no opaque no-CORS “prewarm” and no claim that the app is ready before a
semantic check.

Published cover assets are local:

- `docs/assets/phenology-seasonal-hero-v1.jpg`
- `docs/assets/phenology-seasonal-mobile-v1.jpg`
- `docs/og-image-v2.jpg` (exactly 1200 × 630)

Generation prompts, source PNGs, editable social layouts, dimensions, hashes, alt
text, and the non-data interpretation boundary are recorded in
`docs/IMAGE-PROVENANCE.md`. `node scripts/check_cover.mjs` is the fail-closed
verification command. To intentionally replace an asset, regenerate its web
derivative, update the provenance register and checker hash together, render the
cover at desktop and 390 px, and review the change through CI.

## Data refresh

`.github/workflows/refresh-data.yml` is a candidate pipeline, not a production
writer:

1. An isolated R 4.1.1 fetch lane uses a dated package snapshot to download
   `DP1.10055.001` into an empty raw staging directory.
2. The pinned R 4.5.2 validator builds all 46 bundles and indexes, rebuilds the
   derived indexes twice to require identical bytes, runs every release gate, and
   uploads one immutable candidate.
3. A separate write-enabled job checks that `master` has not moved and opens or
   updates `automation/plant-phenology-data-refresh` for human review. It never
   pushes refreshed bytes directly to `master`.

The workflow needs the `NEON_TOKEN` repository secret. `PHE_ENDDATE` defaults to
the current year-month and can be overridden explicitly. `PHE_RAW_OUT_DIR` and
`PHE_RAW_DIR` keep raw staging outside committed data. The deterministic
`search_index$built` receipt is the maximum observation date in the candidate,
not the day the workflow happened to run.

## Rollback

Do not delete the last known-good bundles or rewrite history. Revert the release
commit through a new review PR, let the same gates pass, merge, republish that
merge in Connect, and repeat the semantic/browser receipt. If only Connect is
stale, republish the already-green merge without changing source.
