# KUL_FWT — recipe audit, filtering audit, and roadmap

Date: 2026-08-08
Branch: `KUL_FWT_v2.0`
Commits: `5f9c406` (parser + symmetry), plus the ThR/SAF intent fixes below.

---

## 0. How a recipe actually resolves

Three facts drive nearly everything in this document. They are worth stating up
front because most of the bugs found are consequences of them.

1. **The label selects voxels.** `make_VOIs` does `<source_map> <label> -eq`.
2. **The name selects the atlas**, by substring match against an ordered
   `if/elif` chain in `KUL_FWT_make_VOIs.sh`:
   `MSBP → FS → 2009 → Fx → lobe → aseg → SUIT → CIT → DISTAL_STN → TMP_BStem
   → MAN → UKBB → JHU → custom`.
   Within the `FS` branch, the name must contain a literal `_WM_` to reach
   `wmparc` rather than `aparc`.
3. **For `_custom` VOIs the name *is* the filename**
   (`custom_VOIs/<name>.nii.gz`) and **the label is ignored entirely**.

So `LT`/`RT` in a name is cosmetic for atlas-derived VOIs but load-bearing for
custom ones; `FS` anywhere in a name beats `lobe` and `2009`; and nothing in the
pipeline ever cross-checked name against label.

---

## 1. The DRTT cortical seed/include

The cortical inclusion was restored to `track_recipes/DRT_{LT,RT}.txt` in
`2560c48`, but **it was inert**. The recipe parser hardcoded
`incs1|incs2|incs3|excs` case arms, so the `incs4` line matched no arm and was
dropped at read time. The VOI directory was never created, and the `incs*` glob
in `make_TCKs.sh` therefore found nothing to add.

Fixed by discovering inclusion segments from the recipe file itself:

```
DRT_LT segments: incs1 incs2 incs3 incs4
    incs1 : Dent_RT_SUIT      | 30
    incs2 : PD25_RN_LT_custom | 1
    incs3 : PD25_VL_LT_custom | 1
    incs4 : M1_GM_FS_LT       | 1024
```

Verified identical to the pre-`c4accb8` hardcoded definitions
(`M1_GM_FS_LT 1024` / `M1_GM_FS_RT 2024`).

**Carry-over caveat.** `seeds_str` is built from *every* inclusion VOI, so M1 is
now a seed as well as a waypoint. That matches pre-01/07 behaviour, but it does
change DRT seeding density — the DRT model bundles should be regenerated.

**Unresolved.** Restoring the VOI does not by itself guarantee a
dentato-rubro-thalamo-*cortical* tract, because the filtering step applies every
inclusion as `any include` (see §4.1). A streamline that merely grazes M1 still
satisfies it.

---

## 2. LT/RT symmetry

A mirror comparator was built using per-atlas laterality rules:

| Atlas | Rule |
|---|---|
| FS aparc / wmparc / lobes | `1xxx ↔ 2xxx`, `3xxx ↔ 4xxx`, `5001 ↔ 5002` |
| FS aseg | explicit pair table (`3↔42`, `11↔50`, `12↔51`, `17↔53`, …) |
| Destrieux a2009s | `±1000` (`11xxx ↔ 12xxx`) |
| MSBP sc3 | `±124`; **249–251 are midline** (midbrain/pons/medulla), unpaired |
| SUIT | lobular pair table (`1↔2`, `23↔25`, `29↔30`, `31↔32`, `33↔34`, …) |
| UKBB brainstem | `1↔3`, `2↔4` |
| DISTAL STN | `1↔2` |
| `_custom` | label ignored; mirror the name only |

Known deliberate contralateral VOIs are treated as intended: `BStemr_exc_*`,
`hypothal_vDC_*_excr`, `Bs_Pons_*` (CPCT/MCP crossing), `cerebellum_*_X`,
`Fx_*` insula, and DRT's decussating `Dent_*_SUIT` / `cIX_*_SUIT`.

**Result: 40/40 pairs mirror exactly. Every label validates against its atlas
range. No name/label side disagreements remain.**

### 2.1 Wrong-side labels — silent no-ops

All of these sat behind the automatic hemispheric exclude (`auto_X`), so the
intended structure was **never excluded at all**.

| Recipe | Was | Should be | Effect |
|---|---|---|---|
| `PyT_SMA_LT` | M1/S1 GM+WM = `2024/4024/2022/4022` | `1024/3024/1022/3022` | **left PyT_SMA never separated from M1/S1 — reconstructed with CST fibres in it** |
| `PyT_SMA_LT` | `Cing_lobeWM_LT 2003` | `3003` | left cingulate WM never excluded |
| `PyT_PMC_LT` | `M1_WM_LT_FS 2024`, `Cing_lobeWM_LT 2003` | `3024`, `3003` | same class |
| `ThR_Sup_RT` | `Putamen 12`, `Caudate 11` | `51`, `50` | excluded the *left* basal ganglia |
| `PyT_SMA_RT` | `Putamen_RT_FS 12` | `51` | excluded the *left* putamen |
| `IPLFus_LT`, `SRF_LT`, `VOFc_LT` | `STG 2030/4030` | `1030/3030` | excluded the *right* STG |
| `Fx_RT` | `SegWM_LT_ALIC_custom` | `SegWM_RT_ALIC_custom` | custom VOI — wrong file entirely |
| `OR_RT`, `OR_occlobe_RT` | `PD25_VA_VL_LT_custom` | `..._RT_custom` | excluded the *left* VA/VL |

`PyT_SMA_LT` is the most consequential: every left PyT_SMA produced to date is
contaminated with corticospinal fibres.

### 2.2 Wrong atlas

`ILF_LT` used `Front_lobeGM_FS` / `Pari_lobeGM_FS` / `..._WM_FS`. Because `FS`
is tested **before** `lobe`, these resolved to `aparc`, not the lobes map:

- `Front_lobeGM_FS 1001` → `ctx-lh-bankssts` instead of the whole frontal lobe
- `Front_lobeWM_FS 3001` → name lacks a literal `_WM_`, so routed to `aparc`,
  where no `3xxx` label exists → **empty VOI**

`ILF_RT` was correct throughout. Renamed to `*_lobeGM_LT` / `*_lobeWM_LT`.

### 2.3 Wrong label outright

| Recipe | Was | Should be |
|---|---|---|
| `OR_LT`, `OR_occlobe_LT` | `Front_lobeGM_LT 1006` (parietal label), `Pari_lobeGM_LT 1` (not a lobe) | `1001`, `1006` |
| `ILF`, `MdLF` (both sides) | `G_OSup..._2009 1116/2116` — **a2005s** numbering against an **a2009s+aseg** map | `11120` / `12120` |
| `SRF_RT` | `Fusi2 86`, `Fusi3 87` | `85`, `86` |
| `IFOF_LT` | `rMFG5 141`, `rMFG6 142` | `142`, `143` |

The `G_OSup` case produced an **empty VOI on both sides** — an exclude in `ILF`
and an `incs1` seed/waypoint in `MdLF`.

The MSBP off-by-ones were resolved against the consensus of every other recipe
using those parcels (`Fusi1=84 … Fusi4=87`; `rMFG1=14` ⇒ `rMFG5=18, rMFG6=19`,
`+124` for left). Not verified against a subject's own MSBP LUT.

### 2.4 Duplicate names within one segment

`make_VOIs` writes each non-first VOI to `${tmpo_d}/<name>_tmp.nii.gz`. Two
entries with the same name in the same segment collide on that path — the second
overwrites the first, and both `Vs_other_str` entries then point at the same
file.

- `CC_Sensory_Comm` — two `Occ_lobeGM_LT` (`1004`, `2004`): the **left**
  occipital exclude was overwritten by the right.
- `SLF_I_RT` — two `cMFG_GM_RT_FS` (`2003`, `2027`): **caudal** MFG overwritten
  by rostral. Renamed to `rMFG_GM_RT_FS`, matching `SLF_I_LT`.
- `VOFc_{LT,RT}` — two `LOcc5_MSBP_*`. Position 0 has no temp file, so this one
  did not actually collide, but it would after any reorder. Renamed to
  `LOcc4` (labels are `203/204` and `79/80`, consistently `+124`).

### 2.5 Fall-through names

Nine names matched **no** atlas pattern. Since the `if/elif` chain has no `else`
and `source_map` was only cleared at function entry, they silently inherited
whatever atlas the *previous* entry resolved to — correctness depended on line
order. All happened to work; none was guaranteed to.

- `UF_{LT,RT}`: `Unseg_WM_*` → now `Unseg_WM_FS_*`; `IFG_POp_{GM,WM}_*` → now
  `IFG_POp_{GM,WM}_*_FS`. (`UF_LT` also had `IFG_POp_WM_RT` carrying the *left*
  label `3018`.)
- `ThR_{Par,S1,Sup}_{LT,RT}`: `vDC_*` → now `vDC_*_aseg`.
- `CPCT_{LT,RT}`: `cerebellum_{RT,LT}_X` still matches nothing, which is
  **correct** — it falls to the custom path and those files exist. Now
  position-independent.

`source_map` is cleared at the top of each loop iteration, so an unmatched name
now falls to the custom path and fails loudly on a missing file rather than
reading the wrong atlas.

### 2.6 Missing mirror

`SLF_IId_LT` and `SLF_IIv_LT` lacked the three IFG pars excludes
(`IFGpTr 1020`, `IFGpOp 1018`, `IFGpOr 1019`) that both RT counterparts carried.
Added.

### 2.7 Naming normalisation

`Putamen_RT_FS` → `Putamen_GM_RT_FS` in `CST_RT`, `M1_CST_RT`, `PyT_all_RT`;
`Putamen_LT_FS` → `Putamen_GM_LT_FS` in `PyT_SMA_LT`.

---

## 3. Recipe intent fixes (applied 2026-08-08, second pass)

Two symmetric-but-mislabelled entries where the name and the label disagreed on
*which structure was meant*. Both sides agreed, so they were not symmetry bugs;
resolving them changes results, so they were deferred to an explicit decision.

**Resolved: follow the name.**

| Recipe | Was | Now |
|---|---|---|
| `ThR_Ant_{LT,RT}` | `Temp_lobeGM 1003/2003` (= cingulate) | `1005/2005` (temporal) |
| `ThR_OCD_DBS_{LT,RT}` | `Temp_lobeGM 1003/2003` (= cingulate) | `1005/2005` (temporal) |
| `SAF_{LT,RT}` | `Cing_lobeGM/WM 1005/3005, 2005/4005` (= temporal) | `1003/3003, 2003/4003` (cingulate) |

These look like a single swapped copy-paste pair (lobes index 3 = cingulate,
5 = temporal).

Note `ThR_Ant` was excluding the cingulate **twice** — line 17 (`Temp_lobeGM`,
label `1003`) and line 34 (`Cing_lobeGM`, label `1003`) — while never touching
the temporal lobe. After the fix it excludes temporal *and* cingulate.
`ThR_OCD_DBS` has no separate cingulate exclude, so it now excludes temporal
instead of cingulate.

Symmetry and side-consistency re-verified after these edits: **0 asymmetric
segments, 0 side mismatches.**

---

## 4. Filtering audit

Chain: `tckgen`/`tckedit` → `tckresample -num_points 101` →
`scil_tractogram_filter_by_roi` → `detect_loops` → `reject_outliers` →
`smooth --gaussian 5` → optional RecoBundles.

### 4.1 Everything is `any include`; nothing is `either_end`

`KUL_FWT_make_TCKs.sh:1119-1165`. Only the `_Comm` branch uses `either_end`.
For every lateral bundle the first, middle *and* terminal inclusion VOIs are all
`any include`, so there is **no endpoint constraint at all**.

This is the single highest-value change available. It is also what stops the
restored DRT M1 inclusion from doing what it is meant to do.

Minor: the `OR_LT`/`OR_RT` test at `:1136-1147` has identical `then` and `else`
bodies — dead code.

### 4.2 Resampling to 101 points *before* filtering

`tck_init` → `tck_init_rs` resamples every streamline to 101 points regardless
of length, and all downstream filtering inherits it. Step size becomes
length-dependent:

- a 250 mm bundle gets ~2.5 mm spacing → **thin excludes can be stepped over**
  (`filter_by_roi` tests vertices, not segments). Risk for `SegWM_*`,
  `LT_ML_X_custom`.
- a 90 mm bundle (UF) gets ~0.9 mm spacing → **excludes bite harder**.

So the resample simultaneously makes excludes leaky for long bundles and harsh
for short ones. Filter at native step size; resample only immediately before
`reject_outliers` and centroid computation, which are the steps that genuinely
require equal point counts.

### 4.3 Curvature QC is computed on the smoothed bundle

`:1662` computes the curvature and length maps from `tck_filt5`, i.e. after
`scil_tractogram_smooth --gaussian 5`. The reported curvature is therefore
partly a property of the smoothing kernel, and gaussian 5 measurably flattens
sharp turns (AF arc, UF hook, Fx). Compute QQ maps from `filt3`; keep smoothing
for visualisation and centroids only.

### 4.4 No per-stage attrition logging

Only the initial count and the post-`filt1` count are recorded. A per-stage
count table is cheap and would have made every no-op exclude in §2.1 visible
immediately.

### 4.5 No minimum-count floor before outlier rejection

There is a `count2 -gt 10` gate before `filt1`, but nothing before `filt3`. At
`alpha 0.40` a marginal bundle can be gutted.

### 4.6 RecoBundles fallback is silent in provenance

If RecoBundles returns too few streamlines the code falls back to `filt4`, which
is correct, but nothing downstream records which path produced `_fin`. That
materially changes what the bundle *is*. Write a per-bundle provenance stamp.

### 4.7 `-minlength 10` on the `tckedit` paths

Very permissive for bundle segmentation. Per-bundle minimum lengths would be
better — a DRT fragment under ~70 mm is not a DRT.

---

## 5. The UF over-exclusion problem

**Symptom:** UF frequently loses its main trunk through the temporal stem at the
`filter_by_roi` step.

### 5.1 Is there a "forgiving" option in `filter_by_roi`? No.

Verified against the installed scilpy (`/opt/kul_software/src/scilpy`,
`b2bf4ac9`, 2026-06-04). The signature is:

```
--drawn_roi ROI MODE CRITERIA [DISTANCE]
  MODE     ∈ {any, all, either_end, both_ends}
  CRITERIA ∈ {include, exclude}
  DISTANCE   int, in voxels, optional
```

In `scilpy/segment/streamlines.py::filter_grid_roi`:

```python
if filter_distance != 0:
    bin_struct = generate_binary_structure(3, 2)
    mask = binary_dilation(mask, bin_struct, iterations=filter_distance)
```

`DISTANCE` **only ever dilates**, for `include` and `exclude` alike. There is no
erosion path and no tolerance parameter. Adding a distance to an exclude makes
it *stricter*. So there is no knob to soften an exclude.

**The real lever is MODE**, which is currently hardcoded to `any` for every
exclude (`drawn_excs_str` at `:1167`):

| Mode + `exclude` | Rejects a streamline when |
|---|---|
| `any` | any vertex is inside — **current behaviour, harshest** |
| `either_end` | an *endpoint* is inside — lets the trunk pass through |
| `both_ends` | both endpoints inside |
| `all` | the entire streamline is inside — nearly never |

For any structure a bundle legitimately **traverses**, `either_end exclude` is
the correct semantics: reject streamlines that *terminate* there, permit those
that *pass through*.

### 5.2 The specific culprit: `Unseg_WM_FS_*` is all of the deep WM

`UF_{LT,RT}` exclude `Unseg_WM_FS_{LT,RT}` (`5001`/`5002`). In `wmparc` these
are Left/Right-UnsegmentedWhiteMatter — WM beyond ~5 mm of cortex.

The pipeline's own code proves the scope. `KUL_FWT_make_VOIs.sh:1584-1605`
takes `5001 ∪ 5002` and propagates JHU labels *through* it to carve out ALIC,
PLIC, and the frontal/mid/parietal periventricular regions:

```
LT PLIC is 20, LT ALIC is 18 ... frontal PV LT is 24 ... pari PV LT is 28
```

So `5001` spans the internal and external capsule territory — which necessarily
includes **the temporal stem the UF must traverse**. With `any exclude`, any
streamline whose trunk enters deep WM is discarded.

This also explains the *intermittency*: the wmparc 5001 boundary shifts with
atrophy and ventricle size, so in some subjects the trunk clears it and in
others it does not.

Second cut point: `UF_Ins_exc_*_custom` is built from the insular segmentation
plus `Ins_wm_subseg == 1` (`:1820-1825`), which sits at the limen insulae —
again directly on the UF trunk — and `Ins1/Ins2/Ins3_MSBP` compound it. The
0.9 mm effective step spacing from §4.2 makes all of these bite harder on a
bundle of UF's length.

Also affected: `CCing_{LT,RT}` and `TCing_{LT,RT}` carry the same
`Unseg_WM_FS_*` exclude and should be re-examined on the same grounds.

### 5.3 Recommended fix, cheapest first

1. **Drop `Unseg_WM_FS_*` from `UF_{LT,RT}`.** — **APPLIED, `17c64d8`.** It is a
   deep-WM catch-all, not an anatomical constraint. If specific deep-WM
   territory genuinely needs excluding, use the sub-VOIs the pipeline **already
   derives** from it (`SegWM_*_ALIC`, `SegWM_*_PLIC`, `SegWM_*_{M,L,P}PV`)
   rather than the union.

   The remaining excludes still close every escape route it was covering:
   Pari/Occ lobes (GM+WM) posteriorly, M1 GM+WM superiorly, rACC and MedOF
   medially, `CC_allr` across the midline, `BStem` and `Thal` inferiorly. An
   IFOF- or ILF-like streamline leaving the temporal stem is caught by the
   occipital exclude. `CCing`/`TCing` still carry the same exclude — open.
2. **Diagnose before tuning.** `filter_by_roi` supports `--save_rejected` and
   `--display_counts`, neither of which the pipeline uses. Running UF once with
   `--save_rejected` isolates exactly which exclude removes the trunk instead of
   inferring it.
3. **Switch traversed excludes to `either_end`.** Requires the mode column
   below; the insular and deep-WM excludes are the obvious candidates.

### 5.4 The deeper refactor

The root cause is that the recipe format cannot express *endpoint semantics*, so
`make_TCKs.sh` hardcodes `any` for everything and each bundle then compensates
by hand-tuning its exclude list. That is also what produced the SLF_IId/IIv
drift in §2.6.

Proposed: a fourth, optional column, defaulting to today's behaviour so all 90
recipes stay valid unchanged.

```
# type  name                 label   mode
incs1   Dent_RT_SUIT         30      any
incs4   M1_GM_FS_LT          1024    either_end
excs    Unseg_WM_FS_LT       5001    either_end
excs    Occ_lobeGM_LT        1004    any
```

This single change delivers §4.1 (endpoint constraints, fixing DRT properly),
§5.1 (forgiving excludes for traversed structures), and removes the need for
most hand-tuned compensating excludes.

Worth pairing with a `seed` row type — currently *every* inclusion VOI is also a
seed, which is fine for DRT's dentate but wasteful when a terminal VOI is a whole
lobe.

---

## 6. Roadmap: connectome-based bundle assembly

The infrastructure is largely present. `T_app` 2/3 already tracks 10 M
whole-brain streamlines and runs `tcksift2`, then discards that structure per
bundle via `tckedit`. Replacing that last step is the whole change.

### 6.1 Mechanics

`tck2connectome ... -out_assignments A.txt` writes, per streamline, the node
pair its endpoints were assigned to. `connectome2tck` then extracts arbitrary
edges from that file. The assignment is computed **once per atlas** over the
whole tractogram; extraction afterwards is essentially free.

This inverts the cost model: today cost scales with the number of bundles;
there it scales with the number of *atlases*, and bundles become nearly free.

### 6.2 Translating the recipe grammar

| Recipe element | Connectome equivalent |
|---|---|
| `incs1` + terminal `incsN` | the two node sets of an edge — **endpoint-based by construction** |
| middle `incs` (RN, VL, pons, ALIC) | no equivalent; remain waypoint filters on the extracted bundle |
| `excs` | remain, applied post-extraction |

The first row is the deep argument for the approach: it makes "where the bundle
*goes*" structural rather than a filter option, which is exactly the DRT problem
in §1/§4.1 — solved for free.

### 6.3 Multi-atlas edges

Mixed provenance is currently hidden inside VOI names (DRT draws on
SUIT + PD25 + FS; IFOF on MSBP + FS + custom). In a connectome framing it
becomes explicit: build one assignment file per atlas over the *same*
tractogram, then define a bundle as a boolean expression over edges from
different atlases —

```
(SUIT dentate ↔ PD25 VL)  ∧  (FS: reaches M1)
```

Streamline indices are shared across all assignment files, so intersection is
set algebra on indices. Cheap, and it makes cross-atlas definitions auditable
in a way the current name-encoded scheme is not.

### 6.4 Honest caveats

- Endpoint assignment is brittle exactly where it matters most.
  `-assignment_radial_search` fails for deep grey targets (dentate, RN, VIM)
  that are not cortical-surface-adjacent; DRT's dentate seed needs
  `-assignment_all_voxels` or a hybrid.
- SIFT2 weights must be carried through (`-tck_weights_in`) or edges are
  misweighted.
- A 10 M whole-brain tractogram will not have the local density that targeted
  seeding gives a thin bundle like the DRTT. Expect to top up with seeded
  tracking for the DBS bundles.

Treat this as **complementary** to targeted tracking for surgical targets, not a
replacement.

---

## 7. Roadmap: hierarchical whole-brain segmentation

MSBP is *already* a hierarchy — scales 1→5 are nested, and the pipeline uses
sc3. That affords a coarse-to-fine cascade over a single tractogram:

| Level | Basis | Purpose |
|---|---|---|
| 0 | hemisphere / brainstem crossings | commissural vs projection vs association vs cerebellar; prunes the search space |
| 1 | MSBP sc1, or the existing `lobes` map | lobar edges (frontal↔parietal, thalamus↔occipital) |
| 2 | MSBP sc3 | the current recipes' resolution |
| 3 | MSBP sc5 | the fine splits now hand-built (SLF I/IId/IIv/III, SFG1–8, STG1–5) |

Because the levels are nested, a streamline's level-3 assignment *implies* its
level-1 assignment. Streamlines whose fine assignment contradicts their coarse
one can be flagged — a genuinely new QC signal.

It also reframes the output as a **labelled partition of the whole tractogram**
rather than 90 independently extracted sets that may overlap or leave gaps,
which is what finally makes "what fraction of the tractogram is unaccounted
for?" an answerable question.

### Sequencing

1. Validate on bundles with unambiguous cortical endpoints (CST, AF, IFOF, ILF),
   where edge extraction should closely reproduce the current recipes.
2. Keep DRT / ML / CPCT on targeted tracking with waypoint filters until deep
   grey assignment is solved.
3. Acceptance criterion: Dice against the current `_fin` bundles.

**Baseline warning.** Fixing `PyT_SMA_LT` and the other no-op excludes changes
those bundles. Any comparison baseline must be regenerated from `5f9c406` or
later, not from existing outputs.

---

## 8. Suggested next actions

| Priority | Action | Ref |
|---|---|---|
| High | Regenerate DRT and PyT_SMA model bundles — both materially changed | §1, §2.1 |
| High | ~~Drop `Unseg_WM_FS_*` from `UF`~~ — done, `17c64d8`. `CCing`/`TCing` still open | §5.2, §5.3 |
| High | **Clear `<bundle>_VOIs.done` markers + VOI dirs for already-processed subjects** — every recipe fix in this document is inert until then | §9 |
| High | Add the `mode` column; set terminal cortical VOIs to `either_end` | §5.4, §4.1 |
| Medium | Move resampling to after ROI filtering | §4.2 |
| Medium | Per-stage streamline count logging | §4.4 |
| Medium | Compute QQ curvature/length on `filt3`, not `filt5` | §4.3 |
| Medium | Run the recipe linter in CI (side, atlas, label range, duplicate names) | §2 |
| Low | Recipe inheritance to stop family drift (CST/PyT, SLF) | §2.6 |
| Low | RecoBundles provenance stamp | §4.6 |

---

## 9. Operational caveat: recipe edits are inert for processed subjects

`KUL_FWT_make_VOIs.sh` gates VOI creation on a per-bundle marker:

```bash
dotdones[$q]="${ROIs_d}/${tck_list[$q]}_VOIs.done"
srch_dotdones[$q]=$(find ${ROIs_d} ... | grep "${tck_list[$q]}_VOIs.done")

if [[ -z ${srch_dotdones[$q]} ]]; then
    ...parse recipe, build VOIs...
else
    echo "${tck_list[$q]}_VOIs already generated, skip"
fi
```

The recipe is only read when the marker is **absent**. For any subject already
processed, **every fix in this document — the DRT `incs4`, all of §2, §3, and
the UF change — has no effect until the marker and the VOI directory are
cleared**:

```bash
rm -rf  <ROIs_d>/<bundle>_VOIs  <ROIs_d>/<bundle>_VOIs_inMNI
rm -f   <ROIs_d>/<bundle>_VOIs.done
```

`make_TCKs.sh` caches independently on the presence of the output `.tck` files,
so those need clearing too for the bundle to be re-tracked.

Bundles affected by this session's changes, and therefore needing a rebuild:

- **§1** `DRT_LT`, `DRT_RT`
- **§2.1** `PyT_SMA_LT/RT`, `PyT_PMC_LT`, `ThR_Sup_RT`, `IPLFus_LT`, `SRF_LT`,
  `VOFc_LT`, `Fx_RT`, `OR_RT`, `OR_occlobe_RT`
- **§2.2–2.4** `ILF_LT/RT`, `MdLF_LT/RT`, `OR_LT`, `OR_occlobe_LT`, `SRF_RT`,
  `IFOF_LT`, `CC_Sensory_Comm`, `SLF_I_RT`, `VOFc_LT/RT`
- **§2.5** `UF_LT/RT`, `ThR_Par_LT/RT`, `ThR_S1_LT/RT`, `ThR_Sup_LT/RT`
- **§2.6** `SLF_IId_LT`, `SLF_IIv_LT`
- **§3** `ThR_Ant_LT/RT`, `ThR_OCD_DBS_LT/RT`, `SAF_LT/RT`
- **§5.3** `UF_LT/RT`

A `--force-voi-rebuild` flag, or hashing the recipe file into the `.done`
marker so it self-invalidates when the recipe changes, would remove this
footgun permanently. Recommended.
