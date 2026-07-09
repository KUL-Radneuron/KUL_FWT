# Changelog

## Unreleased (working tree, 2026-07-09, batch 2 — wishlist item 2, BUAN)

New `KUL_FWT_buan_profile.py`: a small standalone script wrapping
`dipy.stats.analysis.afq_profile` (the primitive underneath DIPY's BUAN
along-tract profiling) to sample one scalar volume along one bundle at
n-points (default 50), oriented via a reference streamline (the bundle
centroid) so per-node averaging doesn't mix up anatomically different
points from inconsistently-oriented streamlines — verified this matters
with a synthetic test (unoriented: profile flattens to a meaningless
constant; oriented: correctly recovers the underlying spatial gradient).

**Additive, not a replacement**: `KUL_FWT_make_TCKs.sh` and
`KUL_FWT_make_TCKs_4Temp.sh` both now call this alongside (not instead of)
the existing MRtrix fixel-based per-segment sampling, writing to separate
`*_buan_scores_*.txt` files so old and new can be compared before the old
path is ever removed. Only covers the plain scalar/shape metrics — FA,
ADC, AD, RD, TDI, Length, Curve in `make_TCKs.sh` (no per-subject DTI
scalars in `_4Temp.sh`'s template-space context, so TDI/Length/Curve
only there). The fixel-only metrics (FD, Disp, Peaks, FC, logFC, FDC) have
no BUAN/DIPY equivalent (fixel data isn't a per-point scalar volume) and
stay MRtrix-fixel-based only, untouched.

Uses whichever conda env is already active for the rest of the FWT run
(the `-f <scilpy_env>` passed to `KUL_clinical_fmridti.sh`/activated by
its caller) — no separate env-switching needed, since that env must
already have scilpy (and therefore dipy) for the existing
`scil_bundle_compute_centroid`/`scil_bundle_label_map` calls to work.

## Unreleased (working tree, 2026-07-09, batch 2 — wishlist item 5)

- `KUL_FWT_make_TCKs.sh`: added an experimental, **opt-in only** `-U` flag.
  When given, and if `KUL_dwiprep.sh` has produced
  `response/lore_sd/rfa_modulated_fod_reg2T1w.mif` (odf .* rfa contrast,
  see `KUL_NIS` changelog), that FOD is preferred over the plain lore_sd
  ODF for tractography (same `-cutoff 0.05` as plain lore_sd). Without
  `-U`, behavior is byte-for-byte unchanged — plain lore_sd ODF is still
  auto-preferred over dhollander CSD FOD exactly as before.
- `KUL_FWT_make_TCKs_4Temp.sh` was **not** touched for this — it has no
  lore_sd awareness at all (only plain dhollander/template FOD), so adding
  the rfa-modulated preference there would mean building lore_sd support
  from scratch, which is out of scope for this item.

## Unreleased (working tree, 2026-07-09)

- `KUL_FWT_make_TCKs.sh` / `KUL_FWT_make_TCKs_4Temp.sh`: `tckgen` maximum
  turning angle bumped from 45 to 60 degrees, applied consistently across
  every `-angle` occurrence in both files (live bundle-tracking commands,
  the whole-brain tractogram commands, and the commented-out variants).
  No other logic changed.
