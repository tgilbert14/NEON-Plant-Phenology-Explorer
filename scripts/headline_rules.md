# Plant Phenology headline estimand: the written rules (signed off by iris, 2026-10-21)

This is the plain-language contract for the two headline site metrics, median green-up and
median leaf-active days, plus their bounds. It is the single source for both the app helpers
(R/phe_helpers.R) and the independent oracle (scripts/headline_oracle.R), which was written from
this sheet alone. scripts/verify_bundle.R requires the two to agree exactly at four levels
(site, site-year, plant-year, species x site). A disagreement is settled by correcting this
sheet with the estimand owner's sign-off, never by bending the oracle to match the helpers.

Days are day-of-year (Jan 1 = 1). R's round() is used everywhere a value is rounded (IEC 60559,
half to even: round(196.5) = 196, round(103.5) = 104). "Median" is R's stats::median (the mean of
the two middle values for an even count).

## 0. Observations

- Input: a site bundle's `obs` table. Columns used: individualID, year, date, dayOfYear,
  phenophaseName, status, growthForm (factor columns compare by their character values).
- If dayOfYear is NA but date is valid, dayOfYear = the date's day-of-year.
- Only status 'yes' and 'no' are scored; 'uncertain' never counts as either.
- If date is missing or invalid, the row's date is January 1 of its year plus
  (dayOfYear - 1) days.
- One status per plant x phenophase x visit date, formed from that date's 'yes' and 'no' rows
  only: 'yes' if any of them is 'yes', else 'no'. A date with no 'yes' or 'no' row is not a
  visit. The visit's day d is the smallest dayOfYear among those rows. Section 7 groups
  Leaves rows by plant x day number instead.
- Dates and day numbers. NEON's recorded dayOfYear disagrees with the date on one or two
  visit dates at six sites: ABBY -8, DSNY -1, GRSM -4, LAJA +14 (part of one date's rows),
  ONAQ -3, and SRER -7 and -1 days. Keep the recorded value. Green-up (section 2) uses dates
  only to group rows into visits, to pick the year's first and last visit, to measure the
  31-day gap across the new year, and to place the previous year's last visit on this year's
  day scale (p in the bridged case). Every other comparison, and all onset arithmetic, uses
  the visits' day numbers d. Sections 5 and 7 never read the date column: section 5 works on
  rows, and section 7 groups Leaves rows by plant x day number, orders visits by day number
  and measures its 31-day bridge in day numbers. This keeps lo <= hi even where date and day
  number disagree.
- A plant's growth form is the growthForm on its obs rows (constant per plant).

## 1. Green-up phases

- Bud-break phases: "Breaking leaf buds", "Initial growth", "Emerging needles",
  "Breaking needle buds".
- Fallback phase: "Young leaves", only for plants whose growth form is
  "Drought deciduous broadleaf".

## 2. Onset of one phase in one calendar year (per plant)

Take the plant's scored visits for the phase in that year. Let Y be the day numbers d of the
'yes' visits and N those of the 'no' visits. If Y is empty there is no onset. Let f = min(Y).
- Standard case. If some n in N has n < f: lo = the largest such n, onset = (lo + f) / 2,
  hi = f, left_censored = FALSE. Otherwise onset = f, lo = NA, hi = f,
  left_censored = TRUE. Call this onset s (the standard onset).
- Year-boundary check, applied only when the year's first visit BY DATE is 'yes'. Take the
  plant's last visit BY DATE for the same phase in the previous calendar year. If it exists
  and its date is at most 31 days before the date of this year's first visit:
  - previous visit 'yes' (carried over): let d1 = the day number of this year's first visit
    (by date). Let N1 = the n in N with n > d1; if N1 is empty there is no onset. Let y2 =
    the smallest y in Y with y > min(N1); if none, no onset. Else lo = the largest n in N with
    n < y2, onset = (lo + y2) / 2, hi = y2, left_censored = FALSE. The plant-year is flagged
    carryover = TRUE whether or not a later transition exists.
  - previous visit 'no' (bridged): let p = the previous visit's date expressed as a day of
    this year (Dec 31 of last year = 0, Dec 30 = -1, ...). onset = max(1, (p + s) / 2),
    lo = max(1, p) (always 1), hi = f, left_censored = FALSE.
  - Otherwise (no previous visit within 31 days) the standard case stands.

## 3. Green-up per plant-year

Among the bud-break phases with an onset that year, take the one with the smallest onset
(greenup = its onset; lo, hi, left_censored and carryover come from that same phase);
source "bud-break". If there is none and the plant is "Drought deciduous broadleaf", use the
"Young leaves" onset under the same rules; source "young-leaves". (On the committed data no
plant-year has two bud-break phases.)

## 4. Growth forms with no calendar-year green-up (per site, all years)

- Autumn forms: over the plant-years kept in step 3, per growth form, with n plant-years and
  s = share with greenup >= 274: if n >= 10 and s >= 0.35 the form is dropped.
- Carry-over forms: over every plant-year that has at least one scored relevant phase (a
  bud-break phase, or Young leaves for Drought deciduous broadleaf), whether or not it has an
  onset, per growth form: carried = the plant-year has carryover = TRUE on any relevant
  phase. If n >= 10 plant-years and the carried share >= 0.35 (and the form is not already an
  autumn form), the form is dropped.
- Plants of dropped forms have no green-up at that site.

## 5. Site-year support

Use every obs row with a finite dayOfYear (all phenophases and all statuses, including
'uncertain'). Visit week = (dayOfYear - 1) %/% 7 + 1.
- Per plant-year: weeks = number of distinct visit weeks. Per year: med_weeks = median of
  weeks over the plants with any row that year; n_plants = that number of plants;
  first_doy = the smallest dayOfYear that year.
- typical_weeks = median of med_weeks over the site's years; typical_first = median of
  first_doy over the years. low_effort = NOT (med_weeks / typical_weeks >= 0.75).
  late_date = first_doy - typical_first > 30. short = fewer than 3 years at the site.
- Green-up truncation: from the plant-years of step 4 with a green-up, per year:
  lc = share left-censored, cov = (distinct plants with a green-up) / n_plants (0 when none).
  typical_cov = median of cov over the years; cov_ratio = cov / typical_cov (NA when
  typical_cov is not > 0). The year is late for green-up when late_date AND (lc is NA OR
  lc >= 0.5 OR cov_ratio < 0.5 with cov_ratio finite).
- Leaf truncation: per plant-year with scored "Leaves" visits, first_in_leaf = whether the
  plant-year's earliest Leaves visit day has a 'yes'. Per year, lf = mean of first_in_leaf.
  The year is late for leaf when late_date AND (lf is NA OR lf >= 0.5).
- Reason per year and metric: "supported"; else "late_start" when late for that metric;
  "low_effort" overrides late_start; "short_record" overrides everything when short.
  greenup_supported and leaf_supported mean reason == "supported".

## 6. Site green-up summary (two-stage bounds)

Rows: plant-years with greenup_supported and a green-up, for every plant in obs (listed in
inds or not).
- Per plant: mid = round(median(greenup)); lo = median(lo, with left-censored plant-years
  set to -Inf), rounded when finite; hi = round(median(hi)).
- Site: value = round(median of the plants' mid); hi = round(median of the plants' hi);
  lo = median of the plants' lo, rounded when finite.
- Status: "short_record" when every year is short_record (this overrides "none");
  otherwise "none" when there are no rows; otherwise "upper_bound" when lo is -Inf,
  "point" when hi - lo < 14, else "range".
- Published: median_greenup = value for point and range, NA otherwise; greenup_lo = lo
  when finite, else NA; greenup_hi = hi (also published for upper_bound; NA for none and
  short_record).
- Labels: point "day {value}"; range "day {lo} to {hi}"; upper_bound "day {hi} or earlier".

## 7. Leaf span per plant-year

Use "Leaves" visits with status 'yes' or 'no' and a finite dayOfYear; one status per plant x
day ('yes' wins). Within the calendar year, order by day.
- Each run of consecutive 'yes' visits counts from a = the midpoint between the previous
  'no' and the run's first 'yes' (or the first 'yes' itself if the run starts at the year's
  first visit) to b = the midpoint between the run's last 'yes' and the next 'no' (or the
  last 'yes' itself if the run ends at the year's last visit). leaf_active = sum of (b - a).
  Plant-years with no 'yes' have no leaf row (but their visits still count for bridging).
- Year-boundary bridge. ylen = 366 in a leap year, else 365. If the year's first Leaves
  visit is 'yes': take the plant's last Leaves visit in the previous calendar year, at day p
  of that year, and let p_rel = p - ylen(previous year) (a day <= 0 in this year's terms).
  If it exists and first_day - p_rel <= 31: a 'yes' there moves the run's start to day 1; a
  'no' there moves it to max(1, (p_rel + first_day) / 2). Then leaf_edge_start = FALSE.
  Otherwise leaf_edge_start = TRUE and the start stays at the first visit.
  If the year's last Leaves visit is 'yes': take the plant's first Leaves visit in the next
  calendar year, at day q, and let q_rel = q + ylen(this year). If it exists and
  q_rel - last_day <= 31: a 'yes' there moves the run's end to ylen + 1; a 'no' there moves
  it to min(ylen + 1, (last_day + q_rel) / 2). Then leaf_edge_end = FALSE. Otherwise
  leaf_edge_end = TRUE. A visit in any adjacent year counts, supported or not. A plant in
  leaf all year with bridges on both sides gets exactly ylen days.
- leaf_active_hi = leaf_active + (first_day - 1) * leaf_edge_start
  + (ylen + 1 - last_day) * leaf_edge_end, where first_day and last_day are the year's first
  and last Leaves visit days. It is the longest span the visits allow within the year.

## 8. Site leaf-active summary (two-stage)

Rows: plant-years with leaf_supported and a leaf row, for plants listed in the bundle's
inds table only. (PR #14 takes the site value from the per-plant summary, which is built on
inds. DSNY has one obs plant, NEON.PLA.D03.DSNY.00653, that is missing from inds.)
- Per plant: n = round(median(leaf_active)); m = round(median(leaf_active_hi)).
- Site: value = round(median of the plants' n); hi = round(median of the plants' m).
- Status: "short_record" when every year is short_record (value and hi NA; this overrides
  "none"); otherwise "none" with no rows; otherwise "lower_bound" when hi - value >= 14
  (label "at least {value} days"), else "point" (label "{value} days").
- leaf_edge_share = share of the rows with leaf_edge_start or leaf_edge_end, rounded to 3
  decimals; NA when there are no rows.

## 8b. Site counts (site_index)

n_years_watched = number of years at the site (section 5); n_supported_years = years with
greenup_supported; n_leaf_supported_years = years with leaf_supported.

## 10. Species x site summary (national_onsets)

- Plants: from the bundle's `inds` table, keep plants with is_species TRUE and a
  scientificName; their scientificName and growthForm come from `inds`.
- Rows: those plants' plant-years with greenup_supported and a green-up (section 3/4).
  Group by scientificName x growthForm. A group needs at least 3 distinct plants (n_ind).
- greenup, greenup_lo, greenup_hi, greenup_status: section 6 applied to the group's rows
  (two-stage over its plants; status point / range / upper_bound / none).
- lc_share = share of the group's rows left-censored, rounded to 3 decimals.
- Leaf: for each plant of the group (the plants present in its rows), la = median of its
  leaf_active over its leaf-supported years with a leaf row, NOT rounded; la_hi likewise for
  leaf_active_hi. leaf_active = round(median of the group's finite la), NA when none;
  leaf_active_hi = round(median of the group's finite la_hi); leaf_active_lower_bound =
  leaf_active_hi - leaf_active >= 14 (NA when leaf_active is NA).
- leaf_edge_share = share of edge-flagged leaf rows (leaf_edge_start or leaf_edge_end) over
  the group's plants' leaf-supported plant-years with a leaf row, 3 decimals, NA when none.
- n_years = number of distinct years among the group's rows (supported green-up years);
  leaf_n_years = number of distinct leaf-supported years in which at least one of the
  group's plants has a leaf row.

## 9. Trend points (per species-year; not part of the oracle)

- Green-up trend: per species x supported year with >= 3 plants, onset = round(median of
  the plant-years' greenup), bud-break source only; lc_share = share of those plant-years
  left-censored, rounded to 3 decimals. The point is hollow when lc_share >= 0.5 (with k of
  n censored, 2k >= n: the median has no lower bound).
- Leaf trend: per species x leaf-supported year with >= 3 plants, onset = round(median
  leaf_active), onset_hi = round(median leaf_active_hi); hollow when onset_hi - onset >= 14.
  Spans come from all years (the bridge), then supported years are kept.
- Verdict: fit A = lm(year median ~ year) over the solid points only (the year median is
  the median of that year's solid species points); fit B = the same over all points as
  recorded. Fewer than 6 years with a solid point -> "too short". A's 95% CI spans zero ->
  no detectable shift. A excludes zero and B excludes zero on the same side -> a direction,
  reported from A with "N of M points left out". A excludes zero but B does not (or B points
  the other way) -> "the direction depends on the left-out points".
