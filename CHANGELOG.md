# Changelog

## Unreleased (2026-09-05 — subcortical VOIs stop being treated as cortex; the QQ report gets real colour)

### `-T 4`/`-T 5` were GMWMI-narrowing subcortical VOIs

DRT's `incs3` — the VL thalamus — was coming back masked by the GMWMI, which is
not a cortical VOI by any reading. The cause was the survival rule: both
approaches computed the GMWMI intersection unconditionally and only fell back to
the original VOI when the result dropped below a 250-voxel floor. That floor is
not a test of whether a VOI is cortical. VL-thalamus has 0 % overlap with
`ctx_mask_inFA` yet still produced 283 GMWMI voxels — just over the floor — so it
was silently narrowed as if it were cortex. Any deep-GM VOI large enough to clear
250 voxels of incidental interface overlap had the same problem.

- Both `-T 4` and `-T 5` now **gate on corticality before narrowing at all**,
  using the same test `-K` already used: voxel overlap with `ctx_mask_inFA`,
  cortical at ≥ 50 %. Applied in all four blocks (DTI and non-DTI branches of
  each approach).
- Non-cortical VOIs are passed through **unchanged** — for `-T 5`, both the seed
  and the include side. An interim version gave them a "WM outline" (dilate 1
  pass ∩ `WM_mask_inFA`) instead; that was dropped deliberately. GMWMI/WM
  narrowing is a cortical construct and subcortical VOIs should simply be left
  alone.
- `ctx_mask_inFA` is now built for `T_app` 4 and 5 as well (previously only `-K`,
  `-T 2`), since the gate needs it.

### `incs_map_agg` could be stale while the VOIs it describes were fresh

The QQ overlay map is built from `TCK_I_b`, but was guarded by
`if [ ! -f <..._incs_map_agg_inMNI.nii.gz> ]`. `TCK_I_b`'s own per-VOI outputs
have separate `-f` guards, and `tckgen` is skipped independently when `tck_init`
already has enough streamlines — so a rerun could legitimately recompute
`TCK_I_b`'s content while this step, seeing its old output present, served a map
baked from whatever `TCK_I_b` pointed at on some earlier run. Observed directly:
only 204 of 949 voxels of the current VOI appeared in the map on disk.

- The guard is removed in both `KUL_FWT_make_TCKs.sh` and `_4Temp.sh`. The step
  is a few `mrcalc` calls plus one `antsApplyTransforms` — cheap next to `tckgen`
  — so it always rebuilds from whatever `TCK_I_b` currently is.

### tckgen thread oversubscription

`ncpu_per_bundle` was derived so that the sum of live `-nthreads` never exceeded
physical cores. `tckgen`'s threads are not fully CPU-bound (mutex contention on
the shared streamline-output queue), so a modest oversubscription fills those
gaps rather than genuinely demanding more cores.

- New `oversubscribe_pct` (default 25) inflates the budget used for the
  per-dispatch thread split only. `bundles_simultaneous` stays anchored to real
  `ncpu`, so the number of concurrent `tckgen` processes is unchanged and only
  each one's thread count rises.

### The QQ report: directional colour, true proportions, dark surface

- **Bundle geometry is coloured by direction (DEC).** Per-point tangent via
  `np.gradient`, `abs`, normalised per point by its own max component — the same
  recipe `scil_viz_bundle_screenshot_mni --local_coloring` uses. Computed from
  raw mm coordinates *before* display normalisation, so the colours reflect true
  anatomical direction. A toggle switches back to the previous
  along-tract-segment colouring.
- **The rotatable panel is no longer warped.** `load_bundle_geometry` scaled
  x/y/z independently, each stretched to fill its own -1..1, so a bundle longer
  A-P than S-I rendered artificially cube-shaped next to the (isotropic) scilpy
  screenshots of the same geometry. It now uses one shared scale factor.
- **A legend** that follows the colour mode: R/G/B → left-right /
  anterior-posterior / superior-inferior for direction, or a fixed-width ramp
  labelled 1..N for segments.
- The segment ramp moved off viridis, whose dark end vanished against the page,
  and the page itself moved to a dark surface so the tract colours read the way
  they do in the screenshots. The static matplotlib PDF/PNG keeps the light
  palette.
- The per-bundle in-panel dotted "seg N" scale line was removed; the legend now
  carries that information.
- **Summary statistics per metric** (min/max/mean/median/IQR plus a Shapiro-Wilk
  normality p-value) in the standalone page. The combined report shows only the
  iframe's copy — it no longer renders a second table of the same numbers below
  it.

## Unreleased (accumulated — `-T 5`, five experimental flags, recipe v2/Lausanne2018, filtering-chain rewrites)

Work that had built up uncommitted alongside the entries below, written up here
before committing.

### New tracking approach `-T 5` (`BT_WMR`)

`-T 4` reassigns one mask, which fixes *seeding* but leaves `-include` as wide as
the raw VOI — so `-stop` only fires once a streamline has already tunnelled deep
into a gyrus. `-T 5` splits the two roles. From one shared GMWMI interface patch
and a 1-pass shell it builds:

- `TCK_I_seed_b` — shell ∩ WM, minus the interface: pure WM one voxel past the
  ribbon, so no streamline is born in GM.
- `TCK_I_b` (reassigned) — interface ∪ (shell ∩ (WM ∪ raw VOI)): the WM ring, the
  interface, and a ~1-voxel cortical rim, so `-stop` fires at the ribbon.

Each stage falls back under the same 250-voxel floor.

### Five experimental opt-in flags (all default-off, all parse-validated)

- **`-K`** — dilates cortical inclusion VOIs one pass *inward* into WM
  (dilate ∩ `WM_mask_inFA`), absorbing T1→FA registration slop at the GM/CSF
  boundary without jumping a sulcus. Corticality is detected by ≥50 % overlap
  with `ctx_mask_inFA` rather than by filename, since one `incsN` slot can merge
  several recipe entries. Reassigns `TCK_I_b` so tckgen and the downstream scilpy
  `--drawn_roi` filter stay consistent; excludes are deliberately untouched.
- **`-O`** — `-include_ordered` instead of `-include`. tckgen refuses ordered
  includes without `-seed_unidirectional`, so `-O` also narrows seeding to the
  chain's *first* VOI; otherwise a mid-chain seed captures only half the pathway.
- **`-Z <mm>`** — explicit `tckgen -step` override, to bound per-step curvature
  through sharp turns (Meyer's loop, the DRT's dentate/red-nucleus segment).
- **`-Y`** — `-seed_random_per_voxel`, with per-VOI *n* inversely weighted by
  voxel count to target ~50 000 attempts per seed VOI. Note the budget is fixed,
  so a bundle can come back under `-select`.
- **`-M <N>`** — rind-excluded tracking mask for `-T 1/4/5`. Erodes the
  CSF-stripped brain mask N passes (eroding cortex directly was tried first and
  eats the whole ribbon), then adds back brainstem, corpus callosum, fornix
  (label 250 specifically — matching any-nonzero pulled in 635 k voxels and undid
  the erosion) and ventricles dilated by N.

### Changed tracking defaults

- **`-stop` on every bundle-specific `tckgen`** (`-T 1/4/5`), and
  `-include ctx_mask_inFA -stop` on `-T 2`'s whole-brain run: streamlines now
  terminate at first cortex contact.
- **`-seeds` capped at `10000 × -select`**, replacing unlimited (`0`). Unlimited
  can genuinely run away under `-M`/`-T 5`'s tighter masks; 10 000× keeps ten
  times MRtrix's own headroom while guaranteeing termination.
- `KUL_FWT_tracks_list.txt`: CST target **10 000 → 8 000**; `VOF_*` → `VOFc_*`
  (the list named a recipe that did not exist).

### `filt1` endpoint filtering rewritten

`either_end` had been dead code for the pipeline's entire history. Simply
enabling it for both VOIs of a two-VOI bundle cost AF_all/CST/OR 50-75 % of
`filt1` and collapsed IFOF. It is now applied — with a new 2-voxel tolerance
(`either_end include 2`) — to only the *smaller, more precise* VOI, leaving the
broad cortical one at `any`. CST/PyT/ML_ get `either_end` unconditionally on
their cortical terminus.

### Optic radiation chain rebuilt

OR previously ran FBC alone, then smoothing. FBC verifies neither where a
streamline terminates nor its shape, so thalamic overextension and ILF/temporal-
stem strays survived. It now mirrors the standard chain's bookends: ROI filter →
FBC → smooth → RecoBundles. Also fixes the model path, which used
`${tck_list[$q]}` instead of `${TCK_2_make}`.

### `-R`: augmented filtering chain

Anatomy-endpoint filter (`scil_tractogram_filter_by_anatomy --dilate_ctx 2`) →
loop detection → outlier rejection → smoothing → a **3-run bootstrap RecoBundles
ensemble** over 70 % subsamples, combined by `scil_bundle_filter_by_occurrence`
at ratio `1.0`. Unanimity rather than 2-of-3: majority behaved as an OR-ish
criterion *looser* than a single run. 70 % (down from 80 %) makes the runs less
redundant, at the stated cost that a sparse real sub-branch may be dropped.
Requires a one-time `int32` recast of `subj_aparc_inFA` — ANTs multilabel writes
float and scilpy refuses it.

### Atlas dispatcher rewritten; MSBP replaced by Lausanne2018

`make_VOIs*.sh` used a name-substring `if/elif` chain with **no `else`**, so a
name matching nothing silently inherited the *previous* entry's atlas — the
`Front_lobeWM_FS` bug. Replaced with a `case` on an explicit **`atlas` column**
in the recipes, `MSBP` → `Lausanne3`. The `*)` branch is a generic escape hatch
that finds and warps `<token>.mgz` on demand. Ten optional warped atlases added
(Lausanne scales 1/2/4/5, HCP-MMP1, ThalamicNuclei, hippoAmygLabels, BrainstemSs,
hypothalamic subunits).

### `track_recipes_v2/` (92 recipes)

3-column → 4-column format carrying the `atlas` token, plus a `_ctx` infix on
cortical GM VOI names (consumed by `-K`, `-T 4`, `-T 5`). **No new bundles** —
content is byte-identical after normalising those two markers, with one
exception: the OR family, whose seed/target are swapped (calcarine is now
`incs1`, LGN/pulvinar `incs2`) and whose `Ins_infL_wm` exclude is dropped for
sitting in the Meyer's-loop corridor.

### Bugfixes

- **Retry-path staleness**: the `count ≤ 10` retry regenerated `tck_init` but
  left `tck_init_rs`/`_inT` stale, so everything downstream — count, filtering,
  QQ — read the old near-empty file. Both are now re-resampled and re-transformed.
- **`.trk` conversion moved before Screenshots**: a fury `--local_coloring` crash
  aborts the bundle subshell, so CST's `.trk` was consistently missing despite a
  valid `fin.tck`.
- **Screenshots take the native-space bundle and `sub_T1inFA`** with
  `--target_template MNI152_T1_1mm_brain`, not the nonlinearly-warped `_inMNI`
  inputs. The "warped" renderings were real geometric deformation from the ANTs
  warp, not a rendering defect; `--target_template` restores correct framing via
  affine-only registration.
- **`voxel2fixel` grid mismatch**: the TDI-derived bundle mask is now regridded
  onto `subj_fod`'s grid (`mrgrid -interp nearest`). Fixels are addressed by voxel
  index, so this hard-failed before.
- **CSF mask eroded one pass** before subtraction in `make_VOIs.sh` (not yet
  ported to `_4Temp.sh`).
- **PD25 red nucleus**: `mrfilter smooth` dropped — at dMRI resolution the RN is a
  few voxels and smoothing in a uint16 stream rounded it away entirely.
- **`make_VOIs_4Temp.sh`** discovers `incsN` from the recipe instead of hardcoding
  `incs1..3`, which silently dropped the DRT's `incs4` M1 endpoint.
- **`-f` input normalised** via `$((filt_fl2))`, so `-f 01` / `-f +1` still work
  after the switch from `-eq` to `case`.

### Reporting

- The spider plot and bundle report now regenerate **incrementally** after each
  bundle's QQ/screenshots (flock-serialised, non-fatal) rather than once at end
  of run, so a partial run still has a usable report.
- `bundle_report.py`: new **"Qualitative and Quantitative" tab** embedding the
  spider page via lazy iframe; **spider link path fixed** (`basename` →
  `relpath`) — the `metrics →` links were 404ing.
- `spider_plot.py`: PNG sibling written at dpi 150 for the contact sheet.

## Unreleased (2026-09-03 — outlier rejection stops eating fanning bundles; the two make_TCKs scripts converge)

### `filt3` was deleting the anatomically complete part of fanning bundles

The uncinate came back missing its whole frontal limb on some subjects and not
others. Traced to `filt3`, the outlier-rejection step, which called scilpy's
`scil_bundle_reject_outliers --alpha`. That tool scores each streamline by how
deep it survives a hierarchical QuickBundles clustering, normalised by the
deepest streamline in the *same bundle*, then cuts below an absolute `alpha`.
Three compounding problems:

- The score is relative to the bundle's own densest core, so a bundle with a
  narrow bottleneck feeding a wide cortical fan (UF, CCing, ILF, TCing) grades
  its fan against its bottleneck and loses the fan.
- Clusters stop subdividing at ≤10 members, making the score partly a *density*
  measure — a small but real sub-fascicle scores like an outlier however
  anatomically correct it is.
- The score's scale is bundle- and subject-specific (it depends on the bundle's
  bounding box, which sets the clustering ladder's depth). Across one cohort's
  uncinate bundles the median score ran 0.55–0.78, so a fixed `alpha=0.58` sat
  on the steep part of the distribution and swung retention between 40 % and
  92 % on anatomically comparable bundles.

Measured on 38 real bundles: at `alpha=0.58` the correlation between a
streamline's score and its length was negative in 18 of 19 uncinate bundles
(median ≈ −0.60), and on the worst subject `filt3` discarded 49 % of the
streamlines whose two endpoints landed in the recipe's own terminal VOIs, while
keeping 58 % of those terminating in neither.

- **New `KUL_FWT_reject_outliers.py`** replaces `scil_bundle_reject_outliers` at
  every call site in both `KUL_FWT_make_TCKs.sh` and `_4Temp.sh`. Same scoring —
  it calls scilpy's own `outliers_removal_using_hierarchical_quickbundles`, so
  no fork of scilpy and nothing for the pinned checkout to clobber — but the cut
  is bounded from both sides: `--alpha` (nothing scoring above it is ever
  dropped, so a clean bundle pays no fixed tithe) and `--drop_percentile` (never
  drop more than this share, however low the scores run). Effective threshold is
  `min(alpha, Pth percentile)`. A `--min_retention` floor (0.65) relaxes the cut
  and logs loudly if it would still go below it.
- It never exits nonzero on a degenerate input — empty bundle, or fewer than 20
  streamlines where the score is not a meaningful population statistic — since
  `task_exec` aborts the whole bundle on any nonzero status and a missing
  `filt3` breaks the smoothing step after it.
- **`-f` levels redefined**: `1` = standard (floor 0.40, ≤10 % dropped), `2` =
  lenient (0.30, ≤5 %), `3` = legacy strict (0.58, no ceiling). Level `1`
  previously meant what `3` means now, and was the shipped default in
  `KUL_NIS/study_config/_base/run_fwt.txt`, so every clinical run took the
  harshest branch while the log said "conservative". Level `3` is bit-exact
  against the old tool — verified streamline-for-streamline on a real `filt2`
  bundle — for reproducing prior runs.
- Every bundle now writes `*_filt3_rejected_*.tck` and a
  `*_outlier_rejection.json` (threshold, counts, score quantiles, whether the
  floor fired). This step is the largest streamline loss in the chain and was
  previously invisible.
- Cohort result (38 bundles): mean retention 74.0 % → 97.0 %, worst case 28.2 %
  → 90.0 %. Rerun on one subject's UF with tracking reused (no `tckgen`):
  `-T 4` UF_LT `fin` went 2282 → 3749 streamlines, and the bundle's anterior
  extent (max-y p95) from 65.0 mm to 90.6 mm.

### `KUL_FWT_make_TCKs_4Temp.sh` brought to flow parity

The template variant had drifted well behind its subject-space counterpart.
Back-ported: `-R`, `-O`, `-Z`, `-Y`, `-M`, `-T 5`, the `KUL_FWT_bundle_report.py`
call under `-S`, and the 25 % thread oversubscription in
`KUL_dispatch_bundles` (which the 2026-09-02 entry above notes as
`KUL_FWT_make_TCKs.sh` only — no longer true). Four further drift items found
during that port and fixed: the tracking-mask default (CSF-stripped is now the
default for every bundle, not only `OR_`/`AF_`/`CP_`/`DRT_` and `-T 4`), `-T 4`'s
cortical-overlap gate, `-T 2`'s `-include ctx_mask -stop`, and `-angle 60` on
whole-brain `-seed_dynamic`.

What still legitimately differs: the subject-dMRI input overrides
(`-W`/`-G`/`-B`/`-L`/`-C`/`-U`), `_inFA` vs `_inFOD` naming, `_GT_log_` log
filenames, and `-f 3`'s alpha (0.48 here, 0.58 there — each restores its own
former default).

### tckgen cutoff is now explicit, and reconstruction-aware

- **`-power 2.0` removed** from `_4Temp.sh`'s tckgen. iFOD2's default power is
  `1/nsamples` (0.25 with the default `-samples 4`), so 2.0 was an 8× exponent,
  and `-power` sharpens the sampled direction distribution: a candidate arc at
  half the local-maximum amplitude goes from 84 % relative acceptance at the
  default to 25 % at 2.0. That suppresses exactly the sub-maximal directions a
  cortical fan is made of — the same failure mode as the `filt3` bug, one stage
  earlier and unrecoverable downstream.
- **New `-X <value>`** in both scripts: explicit tckgen `-cutoff`, applied to
  every tckgen in the run, validated as numeric at parse time, and honoured
  whatever the algorithm (with a warning if the scale looks wrong for it).
  Exposed as `fwt_cutoff` in `KUL_NIS/study_config/_base/run_fwt.txt`.
- **Default cutoff is now reconstruction-dependent again**: MRtrix's own default
  for an ordinary CSD FOD, `0.05` for a LoRE-SD one. This reverses an earlier
  change that applied 0.05 to everything on the grounds that a
  reconstruction-dependent threshold was a confound. That had the premise
  backwards — 0.05 was derived from LoRE-SD's amplitude scale, so applying it to
  CSD was using a threshold on a reconstruction it was never tuned for. A fixed
  cutoff across reconstructions is still a legitimate thing to want when
  comparing methods; that is what `-X` is for.
- Three dead `algo_f` FACT/Tensor branches removed from `KUL_FWT_make_TCKs.sh`'s
  bundle `cmd_str` (`-T 1/4/5`). Once `fod_cutoff_opt` is emptied for those
  algorithms, both arms of each branch expand to an identical command; the `-T 1`
  pair was already byte-identical. Verified by expanding `cmd_str` for all 5
  tracking approaches × 6 algorithms before and after: identical in all 30.

Not yet run end to end against template data — `_4Temp.sh` was verified by
syntax checks, flag-parsing unit tests and command-string assembly only.

## Unreleased (2026-09-02 — bundle scheduling: 2 fat tckgen jobs, not N thin ones)

Total wall-clock in `KUL_FWT_make_TCKs.sh` is set by the *slowest single bundle*,
not by aggregate throughput, so the previous scheduler optimised the wrong thing.
It derived concurrency from a fixed 8-thread floor (`bundles_simultaneous =
ncpu / 8`), which on a 32-core box meant 4 bundles at 8 threads each — and a
bundle asking for 10k streamlines sat on those 8 threads for the length of the run
while the other three slots churned through trivial ones.

- **Cap first, split second**, in both `KUL_FWT_make_TCKs.sh` and `_4Temp.sh`:
  ```
  max_parallel_bundles   = 2                                  # hard cap
  bundles_simultaneous   = min(max_parallel_bundles, ncpu)
  min_threads_per_bundle = max(1, ncpu / bundles_simultaneous) # even split, also the floor
  ```
  On 32 cores that is 2 bundles × 16 threads instead of 4 × 8. The
  smallest-workload-first dispatch order and the per-dispatch `running_threads`
  ledger are unchanged — a bundle whose partner has finished still grows past the
  even split when the ledger says the cores are free.
- **New per-bundle ceiling at `$ncpu`** in `KUL_dispatch_bundles`. With only two
  slots, the 25 % oversubscription budget (`KUL_FWT_make_TCKs.sh` only) would
  otherwise hand a lone bundle `ncpu * 1.25` threads; oversubscription is meant to
  fill scheduling gaps *across* concurrent jobs, not to inflate one process past
  the hardware.
- Dispatch math dry-run in an isolated harness (no tractography): `ncpu=32`, 5
  bundles → 20, 16, 16, 16, then 24 threads for the last one running alone (the
  first job takes the oversubscription headroom while nothing else is live).
  `ncpu=6` → 3, 3, 4. `ncpu=1` → cap collapses to 1 bundle × 1 thread, no
  divide-by-zero.
- Tune with `max_parallel_bundles` at the top of the scheduler block; set
  `oversubscribe_pct=0` for an exact `ncpu/2` split with no headroom.
- Not yet run against real tractography data — the next real run is what confirms
  the wall-clock win.

## Unreleased (2026-08-11 — .trk for freeview; the QQ report becomes self-sufficient)

### `.trk` alongside every `.tck`

freeview reads TrackVis `.trk` but not MRtrix `.tck`, so the final bundles could
only be viewed in mrview. `KUL_FWT_make_TCKs.sh` now writes a `.trk` next to each
final `.tck` (`scil_tractogram_convert`; skipped with a warning if scilpy is not
on `PATH`, like the other add-on outputs here).

The reference is `subj_FA`, **not** the `-F` parcellation, and that distinction
is not cosmetic. `KUL_FWT_make_VOIs.sh` registers FreeSurfer to FA itself
(`antsIntermodalityIntrasubject.sh`) and warps every label *into FA space*, so
tracking — and therefore these streamlines — happen in FA space. FS space
coincides with it only when dwiprep's `_reg2T1w` step already made that
registration near identity. Hand KUL_FWT a dMRI series that was never aligned to
the T1w (a separate session, say) and the two frames genuinely differ, at which
point an FS-space reference writes a `.trk` that renders offset. `.tck` carries
no reference at all, which is why this only bites here.

Verified on a clinical subject: streamline count preserved, coordinates equal to
float32 precision, no bounding-box violations.

### Endpoint connectivity in the per-bundle report

The QQ connectivity output was an unlabelled 89×89 `imshow` that is ~99.9 %
zeros, so the handful of parcel pairs actually carrying the bundle were a few
unreadable pixels. `KUL_FWT_bundle_spider_plot.py` now renders the same matrix as
a ranked parcel-pair table plus a labelled heatmap restricted to the parcels the
bundle touches, ordered by involvement so the dominant endpoints sit top-left.

Labels come from the `fs_default` LUT shipped beside the script — which is what
`labelconvert` builds `LC+spine_inFA` from — and indices above 84 are the
appended UKBB brainstem parcels, named as such rather than invented.

Sanity-checked against known anatomy:

| bundle | strongest pair | share |
|---|---|---|
| CST_LT | precentral ↔ brainstem | 74 % |
| FAT_LT | parsopercularis ↔ superiorfrontal | 97 % |
| MdLF_LT | superiorparietal ↔ superiortemporal | 68 % |
| IFOF_LT | parstriangularis ↔ superiorparietal | 35 % (pars triangularis anchors every top pair) |

With this the `.html` carries everything its sibling QQ files did — the
along-tract profiles the `*_scores_*_plot.pdf` show, the spider PDF's content as
the interactive tower, and now the connectivity matrix — so it is a single
self-contained artifact rather than one file among a dozen.

### `KUL_FWT_bundle_report.py` (new)

One self-contained HTML contact sheet per subject: every bundle's screenshots,
three orientations, all four renderings switchable at once, a bundle filter, each
bundle's strongest endpoint pair in its caption, and a link to its detail page.
Reviewing a run is one file instead of 22 directories. Runs under `-S`, once, at
the end of `KUL_FWT_make_TCKs.sh`.

Images are re-encoded rather than embedded as-is: the source PNGs are 1920×1080
RGBA totalling ~32 MB per subject, which base64s into a page no browser opens
happily. Autocropped, downscaled to 800 px and JPEG'd at q82 they come to ~14 MB,
and at contact-sheet size the difference is not visible. The page needs no
sibling files or network access, but the `metrics →` links are bare filenames, so
the per-bundle pages must travel with it.

**Note:** this needs Pillow, which the `scilpy` env currently provides only
transitively (via matplotlib/fury/scikit-image) rather than as an explicit
dependency.

## Unreleased (2026-08-09 — ICP/MCP/DRT never tracked; ThR_Inf never filtered)

Nine of 46 bundles failed on a clinical run. Two distinct causes, both silent.

### `MSBP_CSF_mask` has no producer (ICP, MCP, DRT — 6 bundles, empty)

`KUL_FWT_make_TCKs.sh` excluded
`${prep_d}/sub-X_MSBP_CSF_mask.nii.gz` for every `*CP_*` and `*DRT_*` bundle.
Nothing anywhere writes that file: MSBP was replaced by the Lausanne
parcellation plus FreeSurfer subfields, and this one reference was never
re-pointed. A missing `-exclude` is fatal rather than degrading — `tckgen`
cannot parse the path as an image or a sphere and aborts the bundle — so
`ICP_LT/RT`, `MCP_LT/RT` and `DRT_LT/RT` produced **no output at all**, with the
reason only in a per-bundle log.

Now uses `FS_csf_mask` (`sub-X_FS_CSF_mask.nii.gz`), which
`KUL_FWT_make_VOIs.sh` already builds from the FreeSurfer aseg — labels
4/43/14/15/24/31/63 intersected with the brain mask. Verified on a subject:
65976 CSF voxels, and CSF + brain-minus-CSF sums exactly to the brain mask, so
it is a complete partition. Guarded, so a missing file now warns and tracks
without the CSF exclude instead of losing the bundle.

Note the substitute must be a **CSF** mask (positive inside fluid), not
`T1_BM_inFA_minCSF` (brain *minus* CSF) — passing the latter to `-exclude` would
exclude the whole brain and yield an empty bundle, i.e. the same symptom from the
opposite cause. Stated in the code so it is not "fixed" that way later.

### A 4D VOI (ThR_Inf — 2 bundles, stopped after `initial`)

`ThR_Inf_*_incs1_bin.nii.gz` came out `173×173×114×1`, and
`scil_tractogram_filter_by_roi` → dipy raises
`ValueError: Buffer has wrong number of dimensions (expected 3, got 4)`.

Cause: the per-volume cut from the 4D Juelich atlas used
`mrconvert -coord 3 ${gn}`, which keeps the singleton 4th axis. Added
`-axes 0,1,2` in `KUL_FWT_make_VOIs.sh` and `_4Temp.sh`. Verified: `ndim 4 → 3`,
712 voxels preserved.

A scan of every VOI found four 4D images — the two `ThR_Inf_*_incs1` and both
`OR_occlobe_*_incs2`, i.e. exactly the recipes containing a `JuHA_*` entry.
**`OR_occlobe` survived only by luck**: its filtering runs through `tckedit`,
which tolerates the singleton, while `ThR_Inf` goes through scilpy. It was
carrying the same defect.

### Not fixed

`Ant_Comm` completes but yields ~10 streamlines. Measured, and it is **not** a
VOI or exclude problem: `incs1` overlaps the excludes by 1 voxel of 185, the AC
centroid is properly midline (x = 1.1 mm), and only 10% of a 3-voxel dilation is
excluded. It is a hard target — mean FA 0.36 in the AC against 0.53 in CC motor —
compounded by seeding from every inclusion group, so ~⅔ of seeds start in
~36,800-voxel cortical parcels rather than the 185-voxel commissure. Changing
that would make Ant_Comm the only bundle seeding from one VOI; left as a recipe
decision.

### Naming note added

`KUL_FWT_make_VOIs.sh` gains a header block recording that `MS`/`MSBP` in
filenames is historical — `T1brain_MSinFA_Warped` is FreeSurfer `brain.mgz`,
`T1bm_MSinFA_Warped` is `brainmask.mgz`, `MSBP_scale3_inFA` is
`lausanne2018_scale3` with FS brainstem and hypothalamic subfields patched in.
The transform is named honestly (`fa_2_UKBB_vFS_*`), which is the tell. Renaming
the files would invalidate every subject's cached prep, so the names stay and the
provenance is documented instead — inferring provenance from an `MS` prefix is
what cost six bundles above.

## Unreleased (committed locally, 2026-08-08 — restore DRT's cortical inclusion)

**Regression, introduced 2026-07-01 in c4accb8** ("KUL_FWT v2.0: externalise
bundle recipes"). The hardcoded definitions had four inclusion VOIs for DRT:

```
DRT_LT_incs4_Ls=("M1_GM_FS_LT");  DRT_LT_incs4_Is=("1024")
DRT_RT_incs4_Ls=("M1_GM_FS_RT");  DRT_RT_incs4_Is=("2024")
```

`incs4` was dropped when the recipes moved to `track_recipes/`, leaving DRT with
only dentate, red nucleus and VL — no cortical endpoint. Every DRT reconstructed
since then terminates at the thalamus rather than in M1, and, because nothing
constrained the cortical end, streamlines were free to end anywhere after VL and
still satisfy all inclusions. For an ET DBS target that is the difference between
a dentato-rubro-thalamic and a dentato-rubro-thalamo-*cortical* tract.

Restored verbatim. Also note `incs4` becomes a seed as well as a waypoint, since
`seeds_str` in KUL_FWT_make_TCKs.sh is built from every inclusion VOI — which is
how it behaved before c4accb8 too.

Every bundle was re-checked against the pre-externalisation definitions
programmatically: DRT_LT/RT were the **only** ones that lost a VOI. The two
`ThR_OCD_DBS` bundles differ deliberately (STN added to `incs1`, frontal-lobe GM
refined into specific SFG/OFC/FrP/cACC parcels); all other 80+ bundles transcribe
exactly.

## Unreleased (committed locally, 2026-08-08 — build the PD25 VIM composite)

`PD25_labels_LT/RT` has always listed `PD25_VIM_LT/RT`, but `PD25_lab_gen` never
built a composite for it — the arrays that get assembled are VA, VL, VPL, VPM,
PUL, VC and Pulvi_exc. So no VIM VOI has ever existed on disk, which is why the
DRT recipes use `PD25_VL_{LT,RT}_custom` as `incs3`: VL is what actually exists,
and it spans all 14 VLa+VLp labels rather than the VIM target.

Now built, from `PD25-histo-labels.csv`:

| label | Schaltenbrand-Wahren | Hirai & Jones | 1 mm atlas vol (RT) |
|---|---|---|---|
| 91 | Ventro-intermedius internus (V.im.i) | VLp | 157 mm³ |
| 94 | Ventro-intermedius externus (V.im.e) | VLp | 248 mm³ |
| 104 | Ventro-intermedius internus (V.im.i) | VLp | 3 mm³ |

91 and 94 carry essentially all of it; 104 is a sliver that vanishes once warped
to dMRI resolution and is kept only for completeness. Label 122 (also
*Ventro-intermedius externus*, 6 mm³) is deliberately excluded: it duplicates
94's name but is mapped to VLa rather than VLp and is already excluded from the
VL composite. Whether it belongs is an anatomical judgement, flagged in a comment
rather than decided silently.

Same construction as the other composites — union, threshold, smooth, largest
connected component, masked by the FreeSurfer thalamus.

### How it compares to the FreeSurfer thalamic segmentation

Built both on a real subject (sub-VanRooyRosalia) and compared in the subject's
FA space:

| | PD25 VIM | FS VLp | Dice | PD25 VIM inside FS VLp |
|---|---|---|---|---|
| right | 222 mm³ | 751 mm³ | 0.23 | 51.5 % |
| left | 279 mm³ | 824 mm³ | 0.28 | 55.1 % |

Controls, to separate registration error from atlas-convention differences:

| comparison | Dice | centroid offset |
|---|---|---|
| PD25 nuclei-union vs FS whole thalamus | 0.73–0.74 | 2.7 mm (100 % contained) |
| PD25_VL vs FS VLp | 0.47–0.48 | 1.4–2.0 mm |
| PD25 VIM vs FS VLp | 0.23–0.28 | 4.5–4.8 mm |

Registration is not grossly wrong — the PD25 nuclei land fully inside the FS
thalamus with Dice 0.73. But the two "VIM" definitions genuinely disagree: only
about half of the PD25 VIM falls inside FS VLp, even though the CSV crosswalk
maps V.im to VLp, i.e. containment should be near-total if the atlases agreed.
Part of the low Dice is simply that VIM is a small subregion of a much larger
VLp; the containment figure is the meaningful one.

Practical consequence: intersecting a DRT with FS VLp would intersect it with a
structure the tract was never constrained by — only ~42–46 % of PD25_VL (the
tract's actual `incs3`) falls inside FS VLp. Intersecting with PD25_VIM is
coherent, since VIM is a subset of the VL the tract already passes through.

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
