# Changelog

## Unreleased (committed locally, 2026-08-08 — optic-radiation _fin_map_inMNI)

In the `${TCK_2_make} == "O"*` branch of `make_bundle` — the FBC-filtering path
used for the optic radiations — `${TCK_2_make}_fin_map_${T}_${algo_f}_inMNI.nii.gz`
was written from `tck_filt1_inT`, i.e. from `tck_filt1`, the tractogram *before*
`scil_tractogram_smooth`. A second block ~15 lines later writes the same filename
from `tck_filt5_inT`, the smoothed `_fin_` streamlines the name refers to.

Both are guarded by `if [[ ! -f <that same file> ]]`, so the first always won and
the second always skipped. The MNI-space map for OR bundles was the unsmoothed
filt1 geometry under a "fin" name. Streamline counts are identical either way —
smoothing moves points, it does not drop streamlines — so this is invisible in
`tckstats` and shows up only in the map.

Confirmed on an existing dataset (sub-VanRooyRosalia, `OR_occlobe_LT`) by
rebuilding the map from each candidate and differencing against the shipped file:

| rebuilt from | max abs diff | nonzero voxels |
|---|---|---|
| `filt1_inMNI` | 9.2e-05 (float rounding) | 24411 (= shipped) |
| `fin_inMNI` | 125.9 | 23247 |

The tell-tale `OR_occlobe_LT_filt1_BT_iFOD2_inMNI.tck`, which only the removed
block produces, is present for the OR bundles and absent for all others.

**Scope:** only bundles matching `"O"*` take this branch. Everything else reaches
the correct block directly — verified on `CST_LT` from the same subject, whose map
matches its `fin` tract to float precision. The subject-space `_fin_map` is
correct for all bundles.

Removed the earlier block so the correct one runs.

## Unreleased (working tree, 2026-07-12 — fix middle-inclusion-VOI array indexing bug)

Spotted live during a real test run: `KUL_FWT_make_TCKs.sh: line 1044: <path>.nii.gz:
syntax error: operand expected` for `ML_LT`/`ML_RT` (non-fatal -- printed to stderr,
script continued). Both TCKs scripts, in the multi-VOI drawn-ROI-string construction
(`vsz -gt 2` branch, any bundle with more than 2 inclusion VOIs):
```bash
for vi in ${TCK_I_b[@]:1:$((vsz-2))}; do
    drawn_incs_str+=$(printf ... "${TCK_I_b[$vi]}")   # bug
done
```
`${TCK_I_b[@]:offset:len}` yields the array's *values* (VOI paths), not indices --
`vi` already holds the path itself. Re-indexing with `${TCK_I_b[$vi]}` tried to
arithmetically evaluate a filesystem path as an array subscript, which bash rejects
with exactly the observed "syntax error: operand expected," and the expansion then
evaluates to empty -- silently dropping every middle inclusion VOI from
`drawn_incs_str` for the duration of that loop iteration. Verified the real impact
with a synthetic 4-element array: the old code kept only the final VOI (the two
middle ones silently vanished, only their syntax errors printed); the fix keeps all
of them. For any bundle with 3+ inclusion VOIs (confirmed hit: `ML_LT`/`ML_RT`), this
meant `scil_tractogram_filter_by_roi` was applying a less restrictive "start + end
only" filter than intended -- the middle-waypoint constraints were never actually
enforced, degrading tract specificity (not a crash, so this had been running silently
wrong, not obviously broken). Fixed in both `KUL_FWT_make_TCKs.sh` and `_4Temp.sh` by
using `${vi}` directly instead of re-indexing.

## Unreleased (working tree, 2026-07-11 — fix the actual crash a -Q-less run hits, plus RecoBundles)

Root-caused via a real failed test run (`sub-11072026trial`, no `-Q` passed): the run
died in a one-time whole-brain prep step before any bundle-specific work even started.
Also cross-referenced an older run (`sub-09072026trial`, before this session's
`task_exec` fix) where the same crash was silently swallowed and the pipeline
continued into per-bundle RecoBundles calls, which then failed too — giving visibility
into both bugs in one investigation.

- **`warp2metric -fc` was running unconditionally regardless of `-Q`.** Traced every
  consumer of `fod2fixel`'s and `warp2metric`'s outputs (the 6 "fixel-only" metrics:
  FD/Disp/Peaks/FC/logFC/FDC) — the only place any of them are read is
  `KUL_FWT_tractometry_functions.sh`'s per-bundle profiling, which only runs when
  `Q_flag==1`. So on a `-Q`-less run this entire block (including the crashing
  `warp2metric -fc` call computing whole-brain fiber cross-section) was pure wasted
  work that also happened to be exactly what crashed. Gated the whole block
  (`fod2fixel`/`warp2metric`/`mrcalc`/`fixel2voxel`) behind `Q_flag==1` in both
  `KUL_FWT_make_TCKs.sh` and `_4Temp.sh` — a `-Q`-less run now skips it entirely,
  which would have avoided this crash outright. The underlying `warp2metric -fc`
  SIGSEGV itself is not fixed by this (still occurs when `-Q` *is* used) — see
  `../TODO.md`.
- **Fixed inverted status-message logic**: `if [[ "${Q_flag}" -eq 0 ]]; then echo
  "...switched on"` printed "switched on" precisely when the flag was off (same bug
  for `S_flag`/Screenshots), in both TCKs scripts — this is why a `-Q`-less run's log
  claimed "Quantitative and qualitative analysis switched on." Flipped both to `-eq 1`.
- **RecoBundles fixes, both TCKs scripts** (`scil_tractogram_segment_with_recobundles`,
  the per-bundle final-filtering step, independent of `-T`/tracking approach):
  - `--tractogram_clustering_thr` was never passed. scilpy's own default-filling logic
    for this flag (`scilpy/src/scilpy/cli/scil_tractogram_segment_with_recobundles.py`,
    commit `f950a6fa`) is inverted — `elif args.tractogram_clustering_thr is not None:
    args.tractogram_clustering_thr = 8.0` only fills in the default when the value is
    *already* not `None`, so an unset flag stays `None` and crashes
    `RecoBundles.__init__`'s `clust_thr` formatting downstream
    (`TypeError: unsupported format string passed to NoneType.__format__`, confirmed
    from a real traceback affecting 17-18 bundle-segmentation attempts). This is a
    genuine scilpy regression (their own fix commit for a different bug introduced this
    one), not something wrong on our end — but since passing *any* value for
    `--tractogram_clustering_thr` flips it from `None` to scilpy's hardcoded `8.0`
    regardless of what's passed, adding `--tractogram_clustering_thr 8` sidesteps the
    crash entirely without needing to patch the local scilpy checkout.
  - Added `--inverse`. The docstring for this scilpy script says the ANTs transform
    should be computed `-m MODEL_REF -f SUBJ_REF` (moving=model, fixed=subject) and
    used with `--inverse`; `MNI_2_MNI_..._0GenericAffine.mat`
    (`KUL_FWT_make_VOIs.sh`/`_4Temp.sh`, `antsRegistrationSyN.sh -f ${UKBB_temp} -m
    <subject-in-template>`) is computed in the opposite orientation
    (fixed=template/moving=subject) without `--inverse` being passed at the recobundles
    call site. A real run's log showed exactly the symptom the script's docstring says
    this causes: pre/post-registration barycenter distance got *worse*, not better
    (0.0 → 0.817), rather than a warning-free identity-close transform.
  - Not verified against real data — no test dataset available in this environment.
    The `--tractogram_clustering_thr 8` fix is a direct, mechanical read of scilpy's
    own crashing code path and should be reliable. The `--inverse` fix is a
    well-supported diagnosis (matches the script's own documented warning condition
    exactly) but unverified — the next real run with actual bundle segmentation
    results is what will confirm whether the resulting alignment is actually correct.

## Unreleased (working tree, 2026-07-10 — logging/status-reporting correctness pass)

Prompted by real test runs where a `warp2metric` SIGSEGV still logged "exit status 0" and
where empty/misleading logs made debugging hard. Root cause across all four `task_exec`
copies (`KUL_FWT_make_TCKs.sh`, `_4Temp.sh`, `KUL_FWT_make_VOIs.sh`, `_4Temp.sh`): the real
success/fail branch was commented out, and `eval ${task_in} | tee -a ${prep_log2} &`
backgrounded the whole pipeline, so `wait`/`$?` reflected `tee`'s exit status, not the actual
command's.

- **`task_exec` fixed in all four scripts**: switched from a literal pipe-to-`tee` to process
  substitution (`eval ${task_in} > >(tee -a "${prep_log2}") 2>&1 &`), so the PID captured by
  `$!` and the exit status captured by `wait "$pid"` belong to the real command. Restored the
  real `Success`/`Fail` branch (previously commented out) with `exit 1` on failure. Verified in
  an isolated bash harness: a clean success continues, a failing command (`false`) reports
  `Fail` and aborts, and a real SIGSEGV (exit 139) is now correctly caught instead of silently
  reported as `exit status 0`. For a bundle running in its own backgrounded subshell
  (`make_bundle &`), `exit 1` only aborts that one bundle's remaining steps — it does not
  affect concurrently-running bundles or the parent script.
- **`KUL_FWT_make_VOIs.sh`/`_4Temp.sh` use `task_exec &`** (backgrounding the whole function,
  54 call sites) rather than calling it bare, so the restored `exit 1` only kills that one
  background job, not the caller — multiple `task_exec &` calls in a loop were not being
  waited on before their `.done` marker was touched. Added a new helper,
  `KUL_wait_all_bg_and_check` (waits on every currently-outstanding background job via
  `jobs -p`, returns nonzero if any failed), and wrapped the 4 `.done`-marker sites in both
  scripts (`priors_warped.done`, `Part1.done`, `Part2.done`, per-bundle `_VOIs.done`) so the
  marker is only written if every backgrounded job actually succeeded.
- **`KUL_FWT_tractometry_functions.sh`**: `KUL_FWT_run_tractometry`'s final per-metric
  profiling loop backgrounds up to 13 `task_exec &` calls (one per along-tract metric) with no
  `wait` before returning — the exact same class of bug just fixed in the VOIs scripts, just
  discovered here on a final sweep. Added a wait+check loop at the end of the function; it now
  returns nonzero (and logs an `ERROR` line) if any profiling job failed, instead of silently
  returning success while jobs were still running or had crashed.
- **`QQ_done.done`/`Sc_done.done` gating**, both `KUL_FWT_make_TCKs.sh` and `_4Temp.sh`:
  `KUL_FWT_run_tractometry`'s return value is now checked before touching `QQ_done.done`
  (`if KUL_FWT_run_tractometry; then touch ...; else echo ERROR ...; fi`) instead of touching
  it unconditionally right after the call. Separately, the Screenshots `Sc_done.done` touch sat
  *outside* the `if [[ -f ...inMNI.tck ]] && [[ ! -f ...Sc_done.done ]]` guard in both scripts —
  meaning it was touched even when the source `.tck` didn't exist and no screenshot work ran at
  all. Moved the touch inside the guarded block so it only fires after the screenshot commands
  actually ran (and, via `task_exec`'s restored `exit 1`, only if they succeeded).
- **Fixed a vacuous dead-code bug**, both TCKs scripts (~line 1712/1475 region): the VOIs-ready
  guard tested `[[ -z "${ROIs_d}/Part1.done" ]]`/`[[ ! -z ... ]]` — a literal path *string*,
  which is never empty, so the "VOIs not generated" branch could never fire and the "already
  generated" branch always did, regardless of whether the files existed. Changed to
  `[[ ! -f ... ]]`/`[[ -f ... ]]`, testing the actual file.
- **Main-log pointer**: since `prep_log2` is reassigned per-bundle (from the earlier
  parallelization work), the shared main log now gets one line
  (`Bundle ${TCK_to_make}: see ${output_d}/...`) right before each per-bundle log is created, so
  it stays a useful index into the per-bundle logs instead of looking like it stopped after the
  run header.
- Not run against real tractography data in this environment — same standing caveat as the
  rest of this session's work; the next real test run is what will confirm no regressions.

## Unreleased (working tree, 2026-07-10 — parallelize tractography over and within bundles)

Real test run took 4+ hours in `KUL_FWT_make_TCKs.sh` for one participant: bundles were
processed strictly sequentially (`make_bundle` called plain, no `&`, at both call sites in
both `KUL_FWT_make_TCKs.sh` and `KUL_FWT_make_TCKs_4Temp.sh`), ~51 bundle/hemisphere
combinations one at a time.

- **New auto-scheduling**, computed once from the existing `-n` (ncpu) flag right after
  `tck_list` is populated, in both scripts:
  ```
  bundles_simultaneous = min(n_bundles_total, ncpu)   # capped at ncpu concurrent bundles
  ncpu_per_bundle       = max(1, ncpu / bundles_simultaneous)
  ```
  Same core-packing philosophy as `KUL_fmriproc_spm_new.sh`'s `-c` auto mode: many bundles
  -> more concurrency, few bundles -> more threads each.
- **`KUL_throttle`** (job-pool limiter) ported from `KUL_fmriproc_spm_new.sh` as a local
  function in both scripts — blocks until fewer than `$bundles_simultaneous` bundles are
  running.
- Both per-bundle loops (whole-brain-tractogram-segmentation and individual-bundle
  tractography, in both scripts) now do `KUL_throttle "$bundles_simultaneous"; make_bundle &`
  instead of a plain blocking call, with a `wait` barrier after each loop. Safe because
  backgrounding a function call forks a subshell with its own copy-on-write snapshot of
  every variable at fork time — nothing inside `make_bundle` needed to change for
  correctness (same reasoning already validated for `KUL_run_fmriprep &`/`KUL_run_dwiprep &`
  running in parallel).
- Every `-nthreads`/`--slr_threads ${ncpu}` *inside* `make_bundle` (37 occurrences in
  `KUL_FWT_make_TCKs.sh`, 29 in `_4Temp.sh`) now uses `${ncpu_per_bundle}` instead, so
  concurrent bundles don't oversubscribe cores. Usages *outside* `make_bundle` (one-time
  VOI-prep/whole-brain steps, not run concurrently with anything) were left at the full
  `$ncpu` budget.
- `prep_log2` is now set per-bundle (was one shared file for the entire run — unreadable
  once ~10+ bundles write to it concurrently via `task_exec`'s `tee -a`).
- Not touched: `task_exec`'s pre-existing `wait ${pid}` quirk (an unset variable, so it
  degenerates to bare `wait`) — confirmed harmless here, since each bundle's own subshell
  has an independent job table, so it behaves the same per-bundle as it already does
  per-sequential-run today.
- Out of scope for this pass: manual `-j`/`-J`/`-T`-style override flags on top of the auto
  default (mirroring the fmriproc convention) — auto-only for now, since that's what was
  asked for.
- Not run against real tractography data in this environment — same standing caveat as
  everything else this session. The next real test run is what will actually validate the
  wall-clock improvement and confirm no oversubscription/log-interleaving problems remain.

## Unreleased (working tree, 2026-07-10 — first real-data test, bugfix)

Found via a real test run (`KUL_LOG_test_10072026`): the whole-bundle mask step
in `KUL_FWT_tractometry_functions.sh` used `mrcalc <tdi> 0 -gt -nan <out> -force`
— but `mrcalc` has no `-nan` option (only `mrthreshold` does; that's what the
pre-existing labels_map-based mask used, before this session's unification).
This broke immediately with `mrcalc: [ERROR] unknown option "-nan"`, cascading
through every downstream step for the 6 fixel-only metrics per bundle
(`voxel2fixel` → `fixel2voxel` → `KUL_FWT_buan_profile.py`, each failing on a
file that was never created because the one before it failed). Fixed by
switching back to `mrthreshold ... -abs 0.0 -comparison gt -nan ...`, the same
tool/flag the original code used, just pointed at the TDI map instead of the
removed label map.

Also found in the same test run, **not from this session's changes** —
flagging for separate investigation:
- `warp2metric` segfaults (SIGSEGV) computing subject-level fiber
  cross-section, but the wrapping `task_exec` still reports `exit status 0` —
  it doesn't actually check subprocess exit codes, so a crash silently lets
  the pipeline continue with missing/corrupt output.
- `scil_tractogram_segment_with_recobundles` → `dipy.segment.bundles.RecoBundles`
  crashes with `TypeError: unsupported format string passed to NoneType.__format__`
  (`clust_thr` ends up `None` despite `--model_clustering_thr 4` being passed)
  — hit 17 of 51 bundle-segmentation attempts in this run (AF_all_RT, CCing_LT/RT,
  CST_LT/RT, FAT_RT, IFOF_LT/RT, ILF_LT/RT, MdLF_LT/RT, ML_LT, TCing_LT/RT,
  UF_LT/RT), preventing those tracts from being generated at all. Looks like a
  scilpy/dipy version-mismatch bug in how the CLI wrapper passes
  `--model_clustering_thr` through to `RecoBundles`.

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
