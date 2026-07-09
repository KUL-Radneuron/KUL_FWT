# Changelog

## Unreleased (working tree, 2026-07-09, batch 2 — QQ tractometry unification)

**Supersedes the "additive, not a replacement" entry below** — the two-track
design (MRtrix fixel-based 50-segment sampler + a separate additive BUAN pass)
has been unified into one profiling path for all 13 metrics. The
`*_buan_scores_*.txt` naming from the previous entry no longer exists; output
is back to the original `sub-X_<metric>_scores_<bundle>.txt` naming, now
produced by the unified method.

- **Removed entirely**: `scil_bundle_label_map`/`Bundle_segs_dir` (the
  50-segment voxel label map), the MNI-warp of that label map,
  `KUL_FWT_TCKsm_cap.py`, the per-bundle `fixel_segment_1..50.mif` split, the
  `mrstats -mask fixel_segment_N.mif` sampling loop, `KUL_FWT_plot_fixel_bundle_metrics.py`
  (for this workflow — the script itself still exists, just unused here), and
  `fixelconnectivity`/`fixelfilter smooth`. That last one's removal is a real
  methods decision, not just cleanup: `fixelconnectivity`/`fixelfilter`
  borrow "fixel-based analysis"'s name, but their actual statistical
  justification comes from connectivity-based enhancement across subjects
  (`fixelcfestats`), which doesn't apply when run within one subject's own
  bundle-restricted connectivity matrix. `afq_profile`'s own cross-streamline
  averaging at each node is the noise reduction now, for every metric alike.
- **New**: the 6 fixel-only metrics (FD, Disp, Peaks, FC, logFC, FDC) are no
  longer a dead end for BUAN-style profiling — MRtrix's `fixel2voxel ... mean`
  collapses this bundle's own already-isolated fixel data (via `tck2fixel`,
  restricted to this tract, so most voxels have exactly one relevant fixel)
  into a plain per-voxel scalar volume, which then goes through the exact
  same `KUL_FWT_buan_profile.py` call as every other metric. All 13 metrics
  now share one profiling path instead of two.
- **New**: the whole-bundle mask needed for the fixel-only metrics is now
  derived directly from the TDI map's nonzero footprint
  (`mrcalc <tdi.nii.gz> 0 -gt -nan`) instead of thresholding
  `scil_bundle_label_map`'s output — removes that dependency cleanly.
- **New** `KUL_FWT_tractometry_functions.sh`: a shared, *sourced* (not
  executed) function file (`KUL_FWT_run_tractometry`), called once per bundle
  from both `KUL_FWT_make_TCKs.sh` and `KUL_FWT_make_TCKs_4Temp.sh`, replacing
  ~250 lines of near-duplicated QQ logic in each with one shared
  implementation. Net effect across both scripts: 360 lines removed, 25
  added — real simplification, not just addition.
- `KUL_FWT_buan_profile.py`: added `--plot-pdf`/`--plot-title` — a
  self-contained along-tract line plot (segment vs. mean value), replacing
  the removed `KUL_FWT_plot_fixel_bundle_metrics.py` + segment-map-PDF
  background for this workflow. No external label-map/background image
  needed anymore.
- Left alone as harmless leftovers (not worth the risk of touching): the
  `Bundle_segs_dir`/`tck_rs1_inT` variable *declarations* still exist in both
  scripts but are no longer referenced/consumed by anything.
- Not run against real tractography data in this environment — verified via
  `bash -n`/`py_compile` and a synthetic-data smoke test
  (fake nifti + fake .tck) through the full profile-and-plot path only.

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
