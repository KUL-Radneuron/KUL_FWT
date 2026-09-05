#!/usr/bin/env python3
#
# KUL_FWT_bundle_spider_plot.py
#
# Assembles every bundle's per-metric along-tract score files (written by
# KUL_FWT_buan_profile.py, one row per segment) into one bundle x metric summary,
# then plots one radar/spider chart per bundle: each spoke is a metric, the thick
# opaque polygon is that bundle's along-tract mean, and the 20 (or however many
# --n-points the run used) thin, near-transparent polygons behind it are the raw
# per-segment values -- so the mean shape and the along-tract spread are both
# visible without needing 20 axes. Every axis is scaled 0-1 using that metric's
# own min/max across every bundle processed for this subject, since a single
# clinical subject has no population reference to normalize against -- so a
# bundle's spoke reads as "high/low relative to this subject's own other
# bundles", not against any clinical norm.
#
# Run once per subject, after every bundle's QQ step (KUL_FWT_run_tractometry)
# has finished -- it needs every bundle's scores in hand before it can normalize.

import argparse
import csv
import glob
import json
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nibabel as nib
import numpy as np

# Canonical axis order -- keeps spokes in the same relative position across
# every bundle's chart, so shapes are comparable at a glance. A bundle missing
# a metric (e.g. no fixel_metrics, no LoRE-SD) just skips that spoke.
METRIC_ORDER = [
    "FA", "ADC", "AD", "RD", "TDI", "Length", "Curve",
    "FD", "Disp", "Peaks", "PeakCount",
    "LoRE_RFA", "LoRE_IntraAx", "LoRE_ExtraAx", "LoRE_FreeWater",
]

# scilpy/dataviz reference palette, categorical slot 1 (blue) -- single-series
# chart, so no legend is needed; the title names the bundle.
SERIES_COLOR = "#2a78d6"
INK_PRIMARY = "#0b0b0b"
INK_SECONDARY = "#52514e"
INK_MUTED = "#898781"
GRIDLINE = "#e1e0d9"
BASELINE = "#c3c2b7"
SURFACE = "#fcfcfb"

# Dark palette for the interactive spider3d.html page only (NOT the static
# matplotlib PDF/PNG above, which keeps the light palette) -- the bundle
# geometry panel's whole point is bright per-point tract colour (directional
# or viridis-by-segment), which reads as washed out against a light page the
# same way it would in any renderer; a dark surface is what makes it pop,
# matching the black background the scil_viz_bundle_screenshot_mni renders
# already use.
HTML_SERIES_COLOR = "#5b9bf0"
HTML_INK_PRIMARY = "#f0efec"
HTML_INK_SECONDARY = "#c7c5bf"
HTML_INK_MUTED = "#918f89"
HTML_GRIDLINE = "#3a3c41"
HTML_BASELINE = "#4c4e54"
HTML_SURFACE = "#25272b"


# How many endpoint pairs the connectivity table lists. The matrix is ~89x89 but
# a single bundle only ever touches a handful of parcels, so this is generous.
N_CONNECTIVITY_ROWS = 15


def load_parcel_labels():
    """Return {label index: parcel name} for the connectivity matrix's rows/cols.

    The matrix is built (KUL_FWT_plot_bundle_connectivity.py) on
    sub-*_LC+spine_inFA.nii.gz, which KUL_FWT_make_VOIs.sh produces by running
    `labelconvert` into the MRtrix fs_default ordering (1-84) and then appending
    the UKBB brainstem parcels at 84+. So fs_default.txt -- which ships next to
    this script -- is the lookup for 1-84, and anything above that is brainstem.
    """
    lut = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fs_default.txt")
    labels = {}
    try:
        with open(lut) as fh:
            for line in fh:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                fields = line.split()
                if len(fields) >= 3 and fields[0].isdigit():
                    labels[int(fields[0])] = fields[2]
    except OSError:
        # no LUT reachable -- the table still renders, just with bare indices
        return {}
    return labels


def load_connectivity(qq_dir, labels):
    """Rank the bundle's endpoint parcel pairs by streamline count.

    Replaces what the QQ connectivity PNG showed: that was an unlabelled 89x89
    imshow of a matrix that is ~99.9% zeros, so the handful of pairs that
    actually carry the bundle were a few unreadable pixels. Same data, read as
    "which parcels does this bundle connect, and how strongly".
    """
    hits = sorted(glob.glob(os.path.join(qq_dir, "*_connectivity_matrix.csv")))
    if not hits:
        return None
    try:
        matrix = np.loadtxt(hits[0], delimiter=",", usecols=None, ndmin=2)
    except (OSError, ValueError):
        return None
    if matrix.size == 0:
        return None

    # dipy's connectivity_matrix fills both triangles; fold them together so a
    # pair is counted once, and drop label 0 (background / unparcellated).
    folded = np.triu(matrix) + np.tril(matrix, -1).T
    folded[0, :] = 0
    folded[:, 0] = 0
    total = folded.sum()
    if total <= 0:
        return None

    def name_for(idx):
        if idx in labels:
            return labels[idx]
        # 85+ are the appended UKBB brainstem parcels, which fs_default.txt
        # does not cover -- name them honestly rather than inventing a label
        return f"brainstem ({idx})" if idx > 84 else f"label {idx}"

    pairs = []
    for i, j in zip(*np.nonzero(folded)):
        pairs.append({
            "a": name_for(int(i)),
            "b": name_for(int(j)),
            "count": int(folded[i, j]),
            "pct": round(100.0 * folded[i, j] / total, 1),
        })
    pairs.sort(key=lambda p: -p["count"])

    # Companion heatmap: the same data as a matrix, but restricted to the parcels
    # this bundle actually touches. The QQ PNG plotted all 89x89 -- ~99.9% zeros,
    # so the signal was a few unlabelled pixels. Ordering parcels by total
    # involvement puts the bundle's main endpoints in the top-left.
    involved = sorted(
        {int(i) for i, _ in zip(*np.nonzero(folded))}
        | {int(j) for _, j in zip(*np.nonzero(folded))},
        key=lambda k: -(folded[k, :].sum() + folded[:, k].sum()),
    )
    cells = []
    for r, i in enumerate(involved):
        for c, j in enumerate(involved):
            v = folded[i, j] + folded[j, i] if i != j else folded[i, j]
            if v > 0:
                cells.append([r, c, int(v)])

    return {
        "pairs": pairs[:N_CONNECTIVITY_ROWS],
        "n_pairs": len(pairs),
        "total": int(total),
        "matrix": {
            "labels": [name_for(i) for i in involved],
            "cells": cells,
            "max": int(folded.max()),
        },
    }


def find_score_files(tcks_output_dir, subj, ses_str):
    """Return {bundle: {metric: [per-segment values]}} across every bundle dir."""
    data = {}
    prefix = f"sub-{subj}{ses_str}_"
    for qq_dir in sorted(glob.glob(os.path.join(tcks_output_dir, "*_output", "QQ"))):
        bundle = os.path.basename(os.path.dirname(qq_dir))[: -len("_output")]
        suffix = f"_scores_{bundle}.txt"
        for score_file in sorted(glob.glob(os.path.join(qq_dir, f"{prefix}*{suffix}"))):
            fname = os.path.basename(score_file)
            if not (fname.startswith(prefix) and fname.endswith(suffix)):
                continue
            metric = fname[len(prefix): -len(suffix)]
            values = []
            with open(score_file, newline="") as f:
                reader = csv.reader(f)
                next(reader, None)  # header: Segments,Mean_<metric>
                for row in reader:
                    if len(row) >= 2:
                        values.append(float(row[1]))
            if values:
                data.setdefault(bundle, {})[metric] = values
    return data


def compute_global_ranges(data):
    """Per-metric (min, max) across every raw segment value, every bundle.

    afq_profile can return nan at individual segments (e.g. an endpoint node
    with ~0 streamline weight, or a fixel-derived volume with masked/nan
    background voxels there) -- those segments are skipped via nanmin/nanmax
    rather than poisoning the whole metric's range.
    """
    ranges = {}
    for bundle_metrics in data.values():
        for metric, values in bundle_metrics.items():
            if all(np.isnan(v) for v in values):
                continue
            lo, hi = np.nanmin(values), np.nanmax(values)
            if metric in ranges:
                prev_lo, prev_hi = ranges[metric]
                ranges[metric] = (min(prev_lo, lo), max(prev_hi, hi))
            else:
                ranges[metric] = (lo, hi)
    return ranges


def normalize(value, lo, hi):
    # cast to a native float: values here feed both matplotlib (which doesn't
    # care) and json.dumps for the 3D HTML viewer (which chokes on numpy
    # float64 without a custom encoder)
    if hi == lo:
        return 0.5
    return float((value - lo) / (hi - lo))


def format_value(metric, value):
    if metric in ("FA", "Curve"):
        return f"{value:.2f}"
    if metric in ("ADC", "AD", "RD"):
        return f"{value:.2e}"
    if metric in ("TDI",):
        return f"{value:.0f}"
    if metric in ("Length",):
        return f"{value:.0f}mm"
    if metric in ("PeakCount",):
        # an along-tract *average* fixel count, via afq_profile's weighted,
        # interpolated sampling of a per-voxel integer map -- genuinely
        # fractional here, not rounded to a fake integer
        return f"{value:.2f}"
    return f"{value:.3g}"


def find_bundle_tck(tcks_output_dir, bundle):
    """The per-bundle resampled native-space tck already produced for
    tractometry (tck_rs1_innat in KUL_FWT_make_TCKs.sh) -- reused here instead
    of re-deriving bundle geometry, so this needs no new pipeline output.
    """
    matches = glob.glob(os.path.join(
        tcks_output_dir, f"{bundle}_output", "QQ", "tmp", f"{bundle}_fin_*_rs1c.tck"))
    return matches[0] if matches else None


def find_bundle_centroid_tck(tcks_output_dir, bundle):
    """The same orientation-corrected centroid KUL_FWT_make_TCKs.sh builds for
    afq_profile's own orient_by-based per-streamline flipping (model-anchored,
    or incs1-VOI-anchored fallback -- see that script's centroid block). Reused
    here to flip each raw streamline the same way: afq_profile's flip only
    happens in memory for its own weighted average, it's never written back to
    the tck file on disk, so without redoing it here, individual streamlines
    keep tckgen's arbitrary seed-dependent point order and segment-color
    inconsistently from one to the next.
    """
    matches = glob.glob(os.path.join(
        tcks_output_dir, f"{bundle}_output", "QQ", "tmp",
        f"{bundle}_fin_*_inMNI_centroid1_uniform.tck"))
    return matches[0] if matches else None


def _resample_points(points, n_points):
    if len(points) == n_points:
        return points
    idx = np.linspace(0, len(points) - 1, n_points).astype(int)
    return points[idx]


def load_bundle_geometry(tck_path, n_segments, centroid_path=None, max_streamlines=250):
    """Downsampled streamline geometry for the rotatable bundle panel: real
    bundles run to thousands of streamlines x 101 points, far more SVG path
    data than a drag-to-rotate redraw loop can carry smoothly, so this keeps a
    representative, evenly-strided subsample instead of every point of every
    streamline. Centered on its own centroid and scaled to roughly fill the
    same -1..1 footprint the tower uses, so both panels share one projection
    scale/center in the viewer despite being unrelated coordinate systems
    (metric-radar-space vs. real anatomical mm).

    Downsamples each streamline to exactly n_segments points -- the same
    along-tract node count the tower/afq_profile uses on this same oriented,
    resampled tck -- so a point's index here corresponds to the same segment
    number as the tower, letting the two panels share one color scale --
    *if* centroid_path is given: each streamline is compared forward vs.
    reversed against that reference centroid (same distance-based flip
    scilpy's uniformize_bundle_sft uses) and flipped if reversed is closer,
    since raw streamlines in the tck have no consistent orientation otherwise.
    """
    streamlines = nib.streamlines.load(tck_path).streamlines
    if len(streamlines) > max_streamlines:
        stride = len(streamlines) // max_streamlines
        streamlines = streamlines[::stride]

    all_points = np.concatenate(list(streamlines))
    center = all_points.mean(axis=0)
    # ONE shared scalar across all three axes, not per-axis: this is real
    # anatomical geometry (unlike the tower panel's metric-radar space), so
    # x/y/z must scale together or the rendered shape is warped relative to
    # the bundle's true proportions -- e.g. a bundle naturally longer A-P than
    # S-I would render artificially cube-shaped under independent per-axis
    # scaling, which reads as a distorted bundle next to the (isotropic)
    # scilpy screenshot renderings of the same geometry. A bundle short along
    # one axis simply doesn't fill -1..1 there, same as in the screenshots.
    extent_scalar = float(np.abs(all_points - center).max())
    if extent_scalar == 0:
        extent_scalar = 1.0
    extent = np.array([extent_scalar, extent_scalar, extent_scalar])

    ref_centroid = None
    if centroid_path and os.path.isfile(centroid_path):
        centroid_sl = nib.streamlines.load(centroid_path).streamlines[0]
        ref_centroid = _resample_points(centroid_sl, n_segments)

    lines = []
    for sl in streamlines:
        sl = _resample_points(sl, n_segments) if len(sl) > n_segments else sl
        if ref_centroid is not None and len(sl) == len(ref_centroid):
            dist_fwd = np.linalg.norm(sl - ref_centroid, axis=1).sum()
            dist_rev = np.linalg.norm(sl[::-1] - ref_centroid, axis=1).sum()
            if dist_rev < dist_fwd:
                sl = sl[::-1]

        # Directional (DEC-style) per-point colour, same recipe as the fixed
        # scil_viz_bundle_screenshot_mni --local_coloring: local tangent via
        # np.gradient, abs (direction, not sign, is what's colour-coded), then
        # each point normalised by its OWN max component so every point hits
        # full saturation on its dominant axis. Computed from sl's raw mm
        # coordinates -- BEFORE the per-axis /extent normalisation below --
        # since that normalisation independently rescales x/y/z for display
        # and would otherwise distort the true anatomical tangent direction.
        grad = np.abs(np.gradient(sl, axis=0))
        grad_max = grad.max(axis=1, keepdims=True)
        grad_max[grad_max == 0] = 1.0
        dec = np.clip(grad / grad_max, 0.0, 1.0)
        colors = [
            "#{:02x}{:02x}{:02x}".format(*(dec[i] * 255).astype(int))
            for i in range(len(sl))
        ]

        lines.append([
            {"x": float((p[0] - center[0]) / extent[0]),
            "y": float((p[1] - center[1]) / extent[1]),
            "z": float((p[2] - center[2]) / extent[2]),
            "seg": i + 1,
            "color": colors[i]}
            for i, p in enumerate(sl)
        ])
    return lines


def plot_bundle_spider(bundle, bundle_metrics, global_ranges, out_pdf, subj, ses_str):
    # A metric that's nan at every segment for this bundle (e.g. FD sitting
    # entirely outside a masked fixel volume) has no data here -- treat it the
    # same as a metric that was never computed at all: drop the spoke.
    metrics = [
        m for m in METRIC_ORDER
        if m in bundle_metrics and not all(np.isnan(v) for v in bundle_metrics[m])
    ]
    if len(metrics) < 3:
        return  # a radar needs at least 3 spokes to mean anything

    n = len(metrics)
    angles = np.linspace(0, 2 * np.pi, n, endpoint=False).tolist()
    angles_closed = angles + angles[:1]

    fig, ax = plt.subplots(figsize=(6.5, 6.5), subplot_kw=dict(polar=True))
    fig.patch.set_facecolor(SURFACE)
    ax.set_facecolor(SURFACE)

    n_segments = len(bundle_metrics[metrics[0]])
    for seg_i in range(n_segments):
        seg_raw = [bundle_metrics[m][seg_i] for m in metrics]
        if any(np.isnan(v) for v in seg_raw):
            # afq_profile occasionally returns nan at a single segment (e.g. a
            # sparse endpoint node) -- skip that segment's polygon rather than
            # draw a shape with an undefined vertex.
            continue
        seg_vals = [normalize(v, *global_ranges[m]) for m, v in zip(metrics, seg_raw)]
        seg_vals_closed = seg_vals + seg_vals[:1]
        ax.plot(angles_closed, seg_vals_closed, color=SERIES_COLOR,
                linewidth=0.6, alpha=0.18, zorder=1)

    mean_vals = [float(np.nanmean(bundle_metrics[m])) for m in metrics]
    mean_norm = [normalize(v, *global_ranges[m]) for m, v in zip(metrics, mean_vals)]
    mean_norm_closed = mean_norm + mean_norm[:1]
    ax.plot(angles_closed, mean_norm_closed, color=SERIES_COLOR, linewidth=2,
            zorder=3)
    ax.fill(angles_closed, mean_norm_closed, color=SERIES_COLOR, alpha=0.12,
            zorder=2)
    ax.scatter(angles, mean_norm, color=SERIES_COLOR, s=36, zorder=4,
               edgecolors=SURFACE, linewidths=1)

    for angle, r, metric, val in zip(angles, mean_norm, metrics, mean_vals):
        ax.annotate(format_value(metric, val), xy=(angle, r),
                    xytext=(angle, min(r + 0.14, 1.18)),
                    ha="center", va="center", fontsize=8, color=INK_SECONDARY,
                    zorder=5)

    ax.set_xticks(angles)
    ax.set_xticklabels(metrics, fontsize=10, color=INK_MUTED)
    ax.set_ylim(0, 1.25)
    ax.set_yticks([0.25, 0.5, 0.75, 1.0])
    ax.set_yticklabels([])
    ax.spines["polar"].set_color(BASELINE)
    ax.grid(color=GRIDLINE, linewidth=0.8)
    ax.tick_params(axis="x", pad=12)

    ax.set_title(f"sub-{subj}{ses_str} — {bundle}", fontsize=13,
                 color=INK_PRIMARY, pad=24)
    fig.text(0.5, 0.035,
             f"thick line = along-tract mean • faint lines = individual "
             f"segments (n={n_segments})",
             ha="center", fontsize=8, color=INK_MUTED)
    fig.text(0.5, 0.012,
             "each axis scaled 0–1 across this subject's own bundles",
             ha="center", fontsize=8, color=INK_MUTED)

    fig.tight_layout(rect=(0, 0.07, 1, 1))
    fig.savefig(out_pdf, facecolor=SURFACE)
    # Also a PNG next to the PDF -- KUL_FWT_bundle_report.py embeds this as a
    # thumbnail in the subject-level contact sheet, where a PDF can't be inlined.
    fig.savefig(os.path.splitext(out_pdf)[0] + ".png", facecolor=SURFACE, dpi=150)
    plt.close(fig)


SPIDER_3D_TEMPLATE = """<!doctype html>
<html><head><meta charset="utf-8"><title>{title}</title>
<style>
  body {{ margin: 0; font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
        background: {surface}; color: {ink_primary}; }}
  h1 {{ font-size: 15px; font-weight: 600; text-align: center; margin: 16px 0 2px; }}
  #caption {{ text-align: center; font-size: 11px; color: {ink_muted}; margin-bottom: 4px; }}
  #hint {{ text-align: center; font-size: 10px; color: {ink_muted}; margin-bottom: 8px; }}
  #panels {{ display: flex; justify-content: center; gap: 12px; flex-wrap: wrap; }}
  .panel {{ text-align: center; }}
  .panel h2 {{ font-size: 12px; font-weight: 500; color: {ink_muted}; margin: 4px 0; }}
  #color-toggle {{ font: inherit; font-size: 10px; color: {ink_muted};
                  background: none; border: 1px solid {gridline};
                  border-radius: 10px; padding: 1px 8px; margin-left: 6px;
                  cursor: pointer; vertical-align: middle; }}
  #color-toggle:hover {{ color: {ink_primary}; border-color: {ink_muted}; }}
  #bundle-legend {{ text-align: center; font-size: 10px; color: {ink_muted};
                   margin-top: 6px; min-height: 30px; }}
  .legend-title {{ margin-bottom: 3px; }}
  .legend-bar {{ width: 220px; height: 8px; margin: 0 auto; border-radius: 2px; }}
  .legend-ticks {{ width: 220px; margin: 2px auto 0; display: flex;
                  justify-content: space-between; font-variant-numeric: tabular-nums; }}
  .legend-rgb {{ display: flex; justify-content: center; gap: 14px; flex-wrap: wrap; }}
  .legend-swatch {{ display: inline-block; width: 9px; height: 9px; border-radius: 2px;
                   margin-right: 4px; vertical-align: middle; }}
  #tower, #bundle {{ display: block; cursor: grab; touch-action: none; }}
  #tower.dragging, #bundle.dragging {{ cursor: grabbing; }}
  .tower-label {{ font-size: 13px; fill: {ink_muted}; text-anchor: middle;
                dominant-baseline: middle; pointer-events: none; user-select: none; }}
  .scale-label {{ font-size: 10px; fill: {ink_muted}; text-anchor: start;
                dominant-baseline: middle; pointer-events: none; user-select: none; }}
  .empty-note {{ font-size: 11px; color: {ink_muted}; padding-top: 220px; }}
  #profiles-title {{ text-align: center; font-size: 13px; font-weight: 600;
                    color: {ink_primary}; margin: 28px 0 4px; }}
  #profiles {{ display: grid; grid-template-columns: repeat(auto-fill, 220px);
             justify-content: center; gap: 14px; max-width: 1100px;
             margin: 0 auto 20px; }}
  .profile-card {{ text-align: center; }}
  .profile-card h3 {{ font-size: 11px; font-weight: 500; color: {ink_muted};
                     margin: 0 0 2px; }}
  .profile-axis-label {{ font-size: 9px; fill: {ink_muted}; }}
  #stats-title {{ text-align: center; font-size: 13px; font-weight: 600;
                 color: {ink_primary}; margin: 28px 0 4px; }}
  #stats {{ border-collapse: collapse; margin: 0 auto 20px; font-size: 11px;
           max-width: 620px; width: 92%; }}
  #stats th, #stats td {{ padding: 4px 12px; text-align: right;
                         border-bottom: 1px solid {gridline}; }}
  #stats th:first-child, #stats td:first-child {{ text-align: left; }}
  #stats th {{ font-weight: 500; color: {ink_muted}; }}
  #stats td {{ color: {ink_secondary}; font-variant-numeric: tabular-nums; }}
  #conn-title {{ text-align: center; font-size: 13px; font-weight: 600;
                color: {ink_primary}; margin: 28px 0 4px; }}
  #conn-note {{ text-align: center; font-size: 10px; color: {ink_muted};
               margin-bottom: 8px; }}
  #conn-heat {{ display: flex; justify-content: center; margin-bottom: 14px;
               overflow-x: auto; }}
  .heat-label {{ font-size: 9px; fill: {ink_secondary}; }}
  .heat-cell {{ stroke: {surface}; stroke-width: 1; }}
  #conn {{ border-collapse: collapse; margin: 0 auto 32px; font-size: 11px;
          max-width: 620px; width: 92%; }}
  #conn th {{ font-weight: 500; color: {ink_muted}; text-align: left;
             border-bottom: 1px solid {baseline}; padding: 4px 8px; }}
  #conn td {{ padding: 3px 8px; border-bottom: 1px solid {gridline};
             color: {ink_secondary}; }}
  #conn td.num {{ text-align: right; font-variant-numeric: tabular-nums;
                 white-space: nowrap; }}
  #conn td.pair {{ color: {ink_primary}; }}
  .bar {{ display: inline-block; height: 7px; background: {series_color};
         border-radius: 1px; vertical-align: middle; }}
</style></head>
<body>
<h1>{title}</h1>
<div id="caption">{caption}</div>
<div id="hint">drag a panel to rotate it independently</div>
<div id="panels">
  <div class="panel"><h2>metric profile</h2>
    <svg id="tower" width="480" height="480" viewBox="0 0 480 480"></svg>
  </div>
  <div class="panel"><h2>bundle geometry
    <button id="color-toggle" title="switch between direction and along-tract segment coloring">color: direction</button>
  </h2>
    <svg id="bundle" width="480" height="480" viewBox="0 0 480 480">
      {bundle_empty_note}
    </svg>
    <div id="bundle-legend"></div>
  </div>
</div>
<div id="profiles-title">along-tract profiles</div>
<div id="profiles"></div>
<div id="stats-title">summary statistics</div>
<table id="stats"></table>
<div id="conn-title">endpoint connectivity</div>
<div id="conn-note"></div>
<div id="conn-heat"></div>
<table id="conn"></table>
<script>
const CONNECTIVITY = {connectivity_json};
const DATA = {payload_json};
const BUNDLE_LINES = {bundle_json};
const BUNDLE_AXES = {bundle_axes_json};
const PROFILES = {profiles_json};
const STATS = {stats_json};
const COLOR_SERIES = "{series_color}";
const COLOR_GUIDE = "{gridline}";
const INK_MUTED = "{ink_muted}";
const NS = "http://www.w3.org/2000/svg";
const towerSvg = document.getElementById("tower");
const bundleSvg = document.getElementById("bundle");
const SCALE = 170, CENTER_X = 240, CENTER_Y = 280;
let bundleColorMode = "direction"; // "direction" or "segment", toggled by #color-toggle

// each panel gets its own independent view -- dragging one never moves the other.
// bundle's default azimuth is mirrored for _RT bundles: LT/RT are real mirror-image
// anatomy (negative vs positive x), so the same starting angle applied to both makes
// them *look* like they run in opposite directions even when the underlying
// segment-to-anatomy mapping is identical (verified directly, not assumed) --
// negating azimuth for one side cancels that mirroring in the two default views.
const views = {{
  tower: {{ azimuth: 0.7, elevation: 0.55, dragging: false, lastX: 0, lastY: 0, dirty: true }},
  bundle: {{ azimuth: {bundle_azimuth}, elevation: 0.55, dragging: false, lastX: 0, lastY: 0, dirty: true }},
}};

function rotateY(p, theta) {{
  const c = Math.cos(theta), s = Math.sin(theta);
  return {{ x: p.x * c + p.z * s, y: p.y, z: -p.x * s + p.z * c }};
}}
function rotateX(p, phi) {{
  const c = Math.cos(phi), s = Math.sin(phi);
  return {{ x: p.x, y: p.y * c - p.z * s, z: p.y * s + p.z * c }};
}}
// world axes: point.x/point.y = the flat radar-plane position (or, for the
// bundle panel, its own centered/scaled anatomical x/y), point.z = height
function project(pt, view) {{
  let p = {{ x: pt.x, y: pt.z, z: pt.y }};
  p = rotateY(p, view.azimuth);
  p = rotateX(p, view.elevation);
  return {{ sx: p.x * SCALE + CENTER_X, sy: -p.y * SCALE + CENTER_Y, depth: p.z }};
}}
function ringPath(points, view) {{
  const proj = points.map(pt => project(pt, view));
  const d = proj.map((p, i) => (i === 0 ? "M" : "L") + p.sx.toFixed(1) + "," + p.sy.toFixed(1)).join(" ");
  const depth = proj.reduce((a, p) => a + p.depth, 0) / proj.length;
  return {{ d, depth, proj }};
}}

function renderTower() {{
  const view = views.tower;
  while (towerSvg.firstChild) towerSvg.removeChild(towerSvg.firstChild);
  const elements = [];

  DATA.guides.forEach(pts => {{
    const r = ringPath(pts, view);
    elements.push({{ depth: r.depth, kind: "guide", d: r.d }});
  }});
  DATA.segment_rings.forEach(pts => {{
    const r = ringPath(pts, view);
    elements.push({{ depth: r.depth, kind: "segment", d: r.d }});
  }});
  {{
    const r = ringPath(DATA.mean_ring, view);
    elements.push({{ depth: r.depth, kind: "mean", d: r.d, proj: r.proj, pts: DATA.mean_ring }});
  }}
  {{
    const p1 = project(DATA.scale_line[0], view), p2 = project(DATA.scale_line[1], view);
    const d = "M" + p1.sx.toFixed(1) + "," + p1.sy.toFixed(1) + " L" + p2.sx.toFixed(1) + "," + p2.sy.toFixed(1);
    elements.push({{ depth: (p1.depth + p2.depth) / 2, kind: "scaleline", d }});
  }}

  // painter's algorithm: draw farthest first so nearer strokes land on top
  elements.sort((a, b) => b.depth - a.depth);

  for (const el of elements) {{
    const path = document.createElementNS(NS, "path");
    path.setAttribute("d", el.d);
    path.setAttribute("fill", "none");
    if (el.kind === "guide") {{
      path.setAttribute("stroke", COLOR_GUIDE);
      path.setAttribute("stroke-width", "1.5");
    }} else if (el.kind === "segment") {{
      path.setAttribute("stroke", COLOR_SERIES);
      path.setAttribute("stroke-width", "1.2");
      path.setAttribute("opacity", "0.38");
    }} else if (el.kind === "scaleline") {{
      path.setAttribute("stroke", INK_MUTED);
      path.setAttribute("stroke-width", "1");
      path.setAttribute("stroke-dasharray", "3,3");
    }} else {{
      path.setAttribute("stroke", COLOR_SERIES);
      path.setAttribute("stroke-width", "3");
    }}
    towerSvg.appendChild(path);
    if (el.kind === "mean") {{
      el.proj.slice(0, -1).forEach((p, i) => {{
        const c = document.createElementNS(NS, "circle");
        c.setAttribute("cx", p.sx); c.setAttribute("cy", p.sy); c.setAttribute("r", "4");
        c.setAttribute("fill", COLOR_SERIES);
        const title = document.createElementNS(NS, "title");
        title.textContent = el.pts[i].label;
        c.appendChild(title);
        towerSvg.appendChild(c);
      }});
    }}
  }}

  DATA.labels.forEach(l => {{
    const p = project(l, view);
    const t = document.createElementNS(NS, "text");
    t.setAttribute("x", p.sx); t.setAttribute("y", p.sy);
    t.setAttribute("class", "tower-label");
    t.textContent = l.text;
    towerSvg.appendChild(t);
  }});

  DATA.scale_ticks.forEach(tick => {{
    const p = project(tick, view);
    const dot = document.createElementNS(NS, "circle");
    dot.setAttribute("cx", p.sx); dot.setAttribute("cy", p.sy); dot.setAttribute("r", "2.5");
    dot.setAttribute("fill", INK_MUTED);
    towerSvg.appendChild(dot);
    const t = document.createElementNS(NS, "text");
    t.setAttribute("x", p.sx + 10); t.setAttribute("y", p.sy);
    t.setAttribute("class", "scale-label");
    t.textContent = "seg " + tick.text;
    towerSvg.appendChild(t);
  }});
}}

// Was viridis, but viridis's dark end (near-black purple) loses almost all
// contrast against this page's dark surface -- every stop here instead keeps
// meaningfully higher lightness than the background, so the ramp reads
// clearly on dark rather than fading into it, while still spanning enough of
// the color space for ~20 distinct segment steps to stay discriminable and
// ordering monotonically (unlike jet/rainbow).
const SEQ_RAMP = ["#22d3ee", "#3b82f6", "#a855f7", "#ec4899", "#f97316", "#facc15"];
function hexToRgb(hex) {{
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}}
const SEQ_RGB = SEQ_RAMP.map(hexToRgb);
function segColor(frac) {{
  const n = SEQ_RGB.length - 1;
  const pos = Math.max(0, Math.min(1, frac)) * n;
  const i = Math.min(Math.floor(pos), n - 1);
  const t = pos - i;
  const a = SEQ_RGB[i], b = SEQ_RGB[i + 1];
  const rgb = a.map((v, k) => Math.round(v + (b[k] - v) * t));
  return "rgb(" + rgb.join(",") + ")";
}}

function renderBundle() {{
  if (!BUNDLE_LINES.length) return;
  const view = views.bundle;
  while (bundleSvg.firstChild) bundleSvg.removeChild(bundleSvg.firstChild);
  const maxSeg = BUNDLE_LINES[0].length;
  const elements = [];
  BUNDLE_LINES.forEach(pts => {{
    const proj = pts.map(pt => project(pt, view));
    for (let i = 0; i < proj.length - 1; i++) {{
      const p1 = proj[i], p2 = proj[i + 1];
      const d = "M" + p1.sx.toFixed(1) + "," + p1.sy.toFixed(1) +
               " L" + p2.sx.toFixed(1) + "," + p2.sy.toFixed(1);
      const segColorHere = segColor((pts[i].seg - 1) / (maxSeg - 1));
      elements.push({{
        depth: (p1.depth + p2.depth) / 2, d,
        color: bundleColorMode === "segment" ? segColorHere : (pts[i].color || segColorHere),
      }});
    }}
  }});
  elements.sort((a, b) => b.depth - a.depth);
  for (const el of elements) {{
    const path = document.createElementNS(NS, "path");
    path.setAttribute("d", el.d);
    path.setAttribute("fill", "none");
    path.setAttribute("stroke", el.color);
    path.setAttribute("stroke-width", "1.3");
    path.setAttribute("opacity", "0.55");
    bundleSvg.appendChild(path);
  }}

  // radiology orientation labels (L/R, A/P, H/F) -- also on top, also rotate
  // with the bundle since they're projected through the same view
  BUNDLE_AXES.forEach(ax => {{
    const p = project(ax, view);
    const t = document.createElementNS(NS, "text");
    t.setAttribute("x", p.sx); t.setAttribute("y", p.sy);
    t.setAttribute("class", "tower-label");
    t.textContent = ax.text;
    bundleSvg.appendChild(t);
  }});
}}

function renderBundleLegend() {{
  const el = document.getElementById("bundle-legend");
  if (!el || !BUNDLE_LINES.length) {{ if (el) el.innerHTML = ""; return; }}
  const maxSeg = BUNDLE_LINES[0].length;
  if (bundleColorMode === "segment") {{
    const gradient = "linear-gradient(to right, " + SEQ_RAMP.join(", ") + ")";
    el.innerHTML =
      '<div class="legend-title">segment</div>' +
      '<div class="legend-bar" style="background:' + gradient + '"></div>' +
      '<div class="legend-ticks"><span>1</span><span>' + maxSeg + '</span></div>';
  }} else {{
    el.innerHTML =
      '<div class="legend-rgb">' +
      '<span><span class="legend-swatch" style="background:#ff3b3b"></span>R = left–right</span>' +
      '<span><span class="legend-swatch" style="background:#3bff3b"></span>G = anterior–posterior</span>' +
      '<span><span class="legend-swatch" style="background:#3b6bff"></span>B = superior–inferior</span>' +
      '</div>';
  }}
}}

function tick() {{
  if (views.tower.dirty) {{ renderTower(); views.tower.dirty = false; }}
  if (views.bundle.dirty) {{ renderBundle(); views.bundle.dirty = false; }}
  requestAnimationFrame(tick);
}}

function pointerDown(view, svgEl, x, y) {{
  view.dragging = true; view.lastX = x; view.lastY = y;
  svgEl.classList.add("dragging");
}}
function pointerMove(view, x, y) {{
  if (!view.dragging) return;
  view.azimuth += (x - view.lastX) * 0.01;
  view.elevation = Math.max(-1.4, Math.min(1.4, view.elevation - (y - view.lastY) * 0.01));
  view.lastX = x; view.lastY = y;
  view.dirty = true;
}}
function pointerUp(view, svgEl) {{
  view.dragging = false;
  svgEl.classList.remove("dragging");
}}

for (const [key, svgEl] of [["tower", towerSvg], ["bundle", bundleSvg]]) {{
  const view = views[key];
  svgEl.addEventListener("mousedown", e => pointerDown(view, svgEl, e.clientX, e.clientY));
  window.addEventListener("mousemove", e => pointerMove(view, e.clientX, e.clientY));
  window.addEventListener("mouseup", () => pointerUp(view, svgEl));
  svgEl.addEventListener("touchstart", e => {{ const t = e.touches[0]; pointerDown(view, svgEl, t.clientX, t.clientY); }}, {{passive: true}});
  svgEl.addEventListener("touchmove", e => {{ const t = e.touches[0]; pointerMove(view, t.clientX, t.clientY); }}, {{passive: true}});
  svgEl.addEventListener("touchend", () => pointerUp(view, svgEl));
}}

const colorToggleBtn = document.getElementById("color-toggle");
if (colorToggleBtn) {{
  colorToggleBtn.addEventListener("click", () => {{
    bundleColorMode = bundleColorMode === "direction" ? "segment" : "direction";
    colorToggleBtn.textContent = "color: " + bundleColorMode;
    views.bundle.dirty = true;
    renderBundleLegend();
  }});
}}
renderBundleLegend();

// small-multiple along-tract line charts, one per metric this bundle has --
// plain 2D, not part of the rotation system above -- built from the same
// score data as the tower/PDF rather than embedding the matplotlib PDFs
// directly, so it reads as one consistent page instead of a mismatched image
function renderProfiles() {{
  const container = document.getElementById("profiles");
  // padL needs headroom for a full 7-char scientific-notation label
  // (e.g. "5.89e+0") right-anchored against it -- 34 clipped some of them
  // past the SVG's left edge depending on exact character widths
  const W = 220, H = 130, padL = 44, padR = 10, padT = 10, padB = 20;
  const plotW = W - padL - padR, plotH = H - padT - padB;

  PROFILES.forEach(prof => {{
    const card = document.createElement("div");
    card.className = "profile-card";
    const h3 = document.createElement("h3");
    h3.textContent = prof.name + " (mean " + prof.mean_label + ")";
    card.appendChild(h3);

    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("width", W); svg.setAttribute("height", H);
    svg.setAttribute("viewBox", "0 0 " + W + " " + H);

    const known = prof.values.filter(v => v !== null);
    const lo = Math.min(...known), hi = Math.max(...known);
    const n = prof.values.length;
    const xAt = i => padL + (n > 1 ? (i / (n - 1)) * plotW : plotW / 2);
    const yAt = v => hi === lo ? padT + plotH / 2
                               : padT + plotH - ((v - lo) / (hi - lo)) * plotH;

    const baseline = document.createElementNS(NS, "line");
    baseline.setAttribute("x1", padL); baseline.setAttribute("x2", W - padR);
    baseline.setAttribute("y1", H - padB); baseline.setAttribute("y2", H - padB);
    baseline.setAttribute("stroke", COLOR_GUIDE);
    svg.appendChild(baseline);

    let d = "", started = false;
    prof.values.forEach((v, i) => {{
      if (v === null) {{ started = false; return; }}
      d += (started ? "L" : "M") + xAt(i).toFixed(1) + "," + yAt(v).toFixed(1) + " ";
      started = true;
    }});
    const path = document.createElementNS(NS, "path");
    path.setAttribute("d", d.trim());
    path.setAttribute("fill", "none");
    path.setAttribute("stroke", COLOR_SERIES);
    path.setAttribute("stroke-width", "2");
    svg.appendChild(path);

    prof.values.forEach((v, i) => {{
      if (v === null) return;
      const hit = document.createElementNS(NS, "circle");
      hit.setAttribute("cx", xAt(i)); hit.setAttribute("cy", yAt(v)); hit.setAttribute("r", "6");
      hit.setAttribute("fill", "transparent");
      const title = document.createElementNS(NS, "title");
      title.textContent = "segment " + (i + 1) + ": " + v;
      hit.appendChild(title);
      svg.appendChild(hit);
      const dot = document.createElementNS(NS, "circle");
      dot.setAttribute("cx", xAt(i)); dot.setAttribute("cy", yAt(v)); dot.setAttribute("r", "1.6");
      dot.setAttribute("fill", COLOR_SERIES);
      dot.setAttribute("pointer-events", "none");
      svg.appendChild(dot);
    }});

    [hi, lo].forEach((val, i) => {{
      const t = document.createElementNS(NS, "text");
      t.setAttribute("x", padL - 4); t.setAttribute("y", (i === 0 ? padT : H - padB) + 3);
      t.setAttribute("text-anchor", "end");
      t.setAttribute("class", "profile-axis-label");
      // scientific notation, fixed width regardless of magnitude -- a plain
      // decimal (e.g. ADC ~0.000731) ran long enough to spill into the next
      // card's column at this card width
      t.textContent = val.toExponential(2);
      svg.appendChild(t);
    }});
    const xlab = document.createElementNS(NS, "text");
    xlab.setAttribute("x", W / 2); xlab.setAttribute("y", H - 4);
    xlab.setAttribute("text-anchor", "middle");
    xlab.setAttribute("class", "profile-axis-label");
    xlab.textContent = "segment 1 → " + n;
    svg.appendChild(xlab);

    card.appendChild(svg);
    container.appendChild(card);
  }});
}}
renderProfiles();

function renderStats() {{
  const table = document.getElementById("stats");
  const thead = document.createElement("thead");
  thead.innerHTML = "<tr><th>metric</th><th>min</th><th>max</th><th>mean</th>"
    + "<th>median</th><th>IQR</th><th title='Shapiro-Wilk normality test'>normality (p)</th></tr>";
  table.appendChild(thead);
  const tbody = document.createElement("tbody");
  STATS.forEach(s => {{
    const tr = document.createElement("tr");
    // same scientific-notation convention as the profile axis labels above --
    // fixed width regardless of a metric's own magnitude (FA ~0.3, ADC ~0.0007)
    const fmt = v => v.toExponential(2);
    const normp = (s.shapiro_p === null || s.shapiro_p === undefined) ? "n/a" : fmt(s.shapiro_p);
    tr.innerHTML = "<td>" + s.name + "</td><td>" + fmt(s.min) + "</td><td>"
      + fmt(s.max) + "</td><td>" + fmt(s.mean) + "</td><td>" + fmt(s.median)
      + "</td><td>" + fmt(s.iqr) + "</td><td>" + normp + "</td>";
    tbody.appendChild(tr);
  }});
  table.appendChild(tbody);
}}
renderStats();

// Same matrix the table lists, restricted to the parcels this bundle touches.
// Single-hue ramp from the surface colour to the series blue: these are counts
// with a true zero and no meaningful midpoint, so a sequential scale is right
// and a diverging one would invent a centre. sqrt on the ramp keeps the many
// small incidental pairs visible next to one dominant connection.
function renderConnHeat() {{
  const m = CONNECTIVITY && CONNECTIVITY.matrix;
  if (!m || !m.labels.length) return;
  const n = m.labels.length;
  const cell = n > 16 ? 14 : 20, padL = 128, padT = 128;
  const W = padL + n * cell + 12, H = padT + n * cell + 12;

  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("width", W); svg.setAttribute("height", H);
  svg.setAttribute("viewBox", "0 0 " + W + " " + H);

  m.cells.forEach(([r, c, v]) => {{
    const rect = document.createElementNS(NS, "rect");
    rect.setAttribute("class", "heat-cell");
    rect.setAttribute("x", padL + c * cell);
    rect.setAttribute("y", padT + r * cell);
    rect.setAttribute("width", cell); rect.setAttribute("height", cell);
    rect.setAttribute("fill", COLOR_SERIES);
    rect.setAttribute("fill-opacity", (0.12 + 0.88 * Math.sqrt(v / m.max)).toFixed(3));
    const title = document.createElementNS(NS, "title");
    title.textContent = m.labels[r] + " \\u2194 " + m.labels[c] + ": " + v;
    rect.appendChild(title);
    svg.appendChild(rect);
  }});

  m.labels.forEach((lab, i) => {{
    const y = document.createElementNS(NS, "text");
    y.setAttribute("class", "heat-label");
    y.setAttribute("x", padL - 6);
    y.setAttribute("y", padT + i * cell + cell / 2);
    y.setAttribute("text-anchor", "end");
    y.setAttribute("dominant-baseline", "middle");
    y.textContent = lab;
    svg.appendChild(y);

    const x = document.createElementNS(NS, "text");
    x.setAttribute("class", "heat-label");
    x.setAttribute("x", padL + i * cell + cell / 2);
    x.setAttribute("y", padT - 6);
    x.setAttribute("text-anchor", "start");
    x.setAttribute("dominant-baseline", "middle");
    // rotated so long parcel names do not overlap at any realistic n
    x.setAttribute("transform", "rotate(-90 " + (padL + i * cell + cell / 2)
                   + " " + (padT - 6) + ")");
    x.textContent = lab;
    svg.appendChild(x);
  }});

  document.getElementById("conn-heat").appendChild(svg);
}}

function renderConnectivity() {{
  const note = document.getElementById("conn-note");
  const table = document.getElementById("conn");
  if (!CONNECTIVITY || !CONNECTIVITY.pairs.length) {{
    note.textContent = "no connectivity matrix found for this bundle";
    return;
  }}
  const shown = CONNECTIVITY.pairs.length;
  note.textContent = "parcel pairs joined by this bundle, by streamline count"
    + " \\u2022 " + CONNECTIVITY.total + " streamline endpoints across "
    + CONNECTIVITY.n_pairs + " pair" + (CONNECTIVITY.n_pairs === 1 ? "" : "s")
    + (shown < CONNECTIVITY.n_pairs ? " \\u2022 showing the top " + shown : "");

  renderConnHeat();

  const head = document.createElement("tr");
  ["parcel pair", "streamlines", "% of bundle", ""].forEach(h => {{
    const th = document.createElement("th");
    th.textContent = h;
    head.appendChild(th);
  }});
  table.appendChild(head);

  // bars are scaled against the strongest pair, so the dominant connection
  // reads as full-width and the incidental ones as slivers
  const top = CONNECTIVITY.pairs[0].count;
  CONNECTIVITY.pairs.forEach(p => {{
    const tr = document.createElement("tr");
    const pair = document.createElement("td");
    pair.className = "pair";
    pair.textContent = p.a + " \\u2194 " + p.b;
    const count = document.createElement("td");
    count.className = "num";
    count.textContent = p.count;
    const pct = document.createElement("td");
    pct.className = "num";
    pct.textContent = p.pct.toFixed(1) + "%";
    const barCell = document.createElement("td");
    const bar = document.createElement("span");
    bar.className = "bar";
    bar.style.width = Math.max(1, Math.round(90 * p.count / top)) + "px";
    barCell.appendChild(bar);
    [pair, count, pct, barCell].forEach(td => tr.appendChild(td));
    table.appendChild(tr);
  }});
}}
renderConnectivity();

requestAnimationFrame(tick);
</script>
</body></html>
"""


def plot_bundle_spider_3d(bundle, bundle_metrics, global_ranges, out_html, subj,
                          ses_str, bundle_geometry=None, connectivity=None):
    """Interactive companion to plot_bundle_spider: the same mean-vs-segments
    idea, but as a drag-to-rotate 3D tower instead of flat alpha-blended
    overlays -- each along-tract segment gets its own ring stacked in order,
    the thick mean ring sits at the vertical center of that stack (the middle
    of the cloud, not a floor beneath it), and a muted vertical guide line per
    metric axis connects the segment stack so the eye can track one axis up
    the tower. A second panel (bundle_geometry, from load_bundle_geometry)
    shows the actual downsampled streamlines, with its own independent
    rotation state -- letting the metric fingerprint and the real anatomy be
    compared side by side without dragging one forcing the other's view.

    Hand-rolled SVG + vanilla JS (manual 3D rotation matrices, orthographic
    projection, painter's-algorithm depth sorting for occlusion) rather than
    Plotly's go.Scatter3d: that trace type requires a WebGL canvas, which
    isn't available in every viewing context (confirmed empty in this
    session's sandboxed preview). SVG has no such dependency -- it renders
    anywhere a browser does, including headless/remote/VDI clinical
    workstations without GPU passthrough. Kept as a complementary output to
    the static PDF above, not a replacement, since the PDF still prints.
    """
    metrics = [
        m for m in METRIC_ORDER
        if m in bundle_metrics and not all(np.isnan(v) for v in bundle_metrics[m])
    ]
    if len(metrics) < 3:
        return

    n = len(metrics)
    angles = np.linspace(0, 2 * np.pi, n, endpoint=False)

    mean_vals = [float(np.nanmean(bundle_metrics[m])) for m in metrics]
    mean_norm = [normalize(v, *global_ranges[m]) for m, v in zip(metrics, mean_vals)]

    n_segments = len(bundle_metrics[metrics[0]])
    seg_rings = []  # (segment index, normalized values, raw values)
    for seg_i in range(n_segments):
        seg_raw = [bundle_metrics[m][seg_i] for m in metrics]
        if any(np.isnan(v) for v in seg_raw):
            continue
        seg_norm = [normalize(v, *global_ranges[m]) for m, v in zip(metrics, seg_raw)]
        seg_rings.append((seg_i, seg_norm, seg_raw))

    if not seg_rings:
        return

    # a compact stack, not an elongated spike: total height ~ half the footprint radius
    z_scale = 1.0 / len(seg_rings)
    # the mean sits at the vertical center of the segment stack, not the base,
    # so it reads as "the middle of the cloud" rather than a floor beneath it
    mean_z = z_scale * (len(seg_rings) + 1) / 2

    # json.dumps chokes on numpy float64 without a custom encoder -- cast every
    # coordinate to a native float at the point it's built
    def ring_points(norm_vals, z, raw_vals, is_mean):
        pts = []
        for m, v, angle, raw in zip(metrics, norm_vals, angles, raw_vals):
            label = f"{m}: {format_value(m, raw)}" + (" (mean)" if is_mean else "")
            pts.append({"x": float(v * np.cos(angle)), "y": float(v * np.sin(angle)),
                       "z": float(z), "label": label})
        pts.append(pts[0])
        return pts

    mean_ring = ring_points(mean_norm, mean_z, mean_vals, True)
    segment_rings = [
        ring_points(seg_norm, (i + 1) * z_scale, seg_raw, False)
        for i, (seg_i, seg_norm, seg_raw) in enumerate(seg_rings)
    ]
    # guide cage connects the segment stack itself (bottom to top); the mean
    # ring is drawn separately, layered in the middle of that cage
    guides = []
    for ax_i, angle in enumerate(angles):
        line = []
        for i, (seg_i, seg_norm, _) in enumerate(seg_rings):
            line.append({"x": float(seg_norm[ax_i] * np.cos(angle)),
                        "y": float(seg_norm[ax_i] * np.sin(angle)),
                        "z": float((i + 1) * z_scale)})
        guides.append(line)
    labels = [{"x": float(1.15 * np.cos(a)), "y": float(1.15 * np.sin(a)),
              "z": 0.0, "text": m}
             for a, m in zip(angles, metrics)]

    # vertical segment-number scale: a dashed reference line just outside the
    # ring, with a tick + "seg N" label at readable intervals, so a ring's
    # along-tract position can actually be read off, not just inferred
    n_seg = len(seg_rings)
    scale_angle = -np.pi / 2
    scale_r = 1.35
    scale_x = float(scale_r * np.cos(scale_angle))
    scale_y = float(scale_r * np.sin(scale_angle))
    scale_line = [
        {"x": scale_x, "y": scale_y, "z": float(z_scale)},
        {"x": scale_x, "y": scale_y, "z": float(n_seg * z_scale)},
    ]
    tick_step = 1 if n_seg <= 10 else (5 if n_seg <= 25 else 10)
    tick_nums = list(range(tick_step, n_seg + 1, tick_step))
    if 1 not in tick_nums:
        tick_nums.insert(0, 1)
    if n_seg not in tick_nums:
        tick_nums.append(n_seg)
    scale_ticks = [{"x": scale_x, "y": scale_y, "z": float(seg_num * z_scale),
                    "text": str(seg_num)} for seg_num in tick_nums]

    payload = {
        "mean_ring": mean_ring,
        "segment_rings": segment_rings,
        "guides": guides,
        "labels": labels,
        "scale_line": scale_line,
        "scale_ticks": scale_ticks,
    }

    bundle_empty_note = (
        "" if bundle_geometry
        else '<text x="240" y="240" text-anchor="middle" class="empty-note">'
             'bundle geometry not found</text>'
    )

    # standard radiology orientation labels (L/R, A/P, H/F), placed along the
    # real x/y/z axes at a fixed radius just outside the bundle's own extent.
    # Valid because load_bundle_geometry only centers/scales the raw tck
    # coordinates -- it never reorients them -- so x/y/z here are still real
    # RAS+ world axes (+x right, +y anterior, +z superior), the same
    # convention already confirmed by LT/RT sitting at negative/positive x.
    # Rotates with the bundle (same views.bundle state), same as the scale.
    bundle_axes = []
    if bundle_geometry:
        r = 1.3
        bundle_axes = [
            {"x": r, "y": 0.0, "z": 0.0, "text": "R"},
            {"x": -r, "y": 0.0, "z": 0.0, "text": "L"},
            {"x": 0.0, "y": r, "z": 0.0, "text": "A"},
            {"x": 0.0, "y": -r, "z": 0.0, "text": "P"},
            {"x": 0.0, "y": 0.0, "z": r, "text": "H"},
            {"x": 0.0, "y": 0.0, "z": -r, "text": "F"},
        ]

    # one along-tract line-chart per metric, built from the same score data as
    # the tower/PDF -- nan segments become null so the JS line breaks there
    # instead of drawing a false straight line through them
    profiles = [
        {
            "name": m,
            "mean_label": format_value(m, mv),
            "values": [None if np.isnan(v) else float(v) for v in bundle_metrics[m]],
        }
        for m, mv in zip(metrics, mean_vals)
    ]

    # summary statistics per metric, across this bundle's own along-tract segments
    from scipy import stats as spstats
    stats = []
    for m in metrics:
        vals = np.asarray(bundle_metrics[m], dtype=float)
        vals = vals[~np.isnan(vals)]
        if vals.size == 0:
            continue
        q1, q3 = np.percentile(vals, [25, 75])
        shapiro_p = None
        if vals.size >= 3 and np.ptp(vals) > 0:
            try:
                shapiro_p = float(spstats.shapiro(vals).pvalue)
            except ValueError:
                shapiro_p = None
        stats.append({
            "name": m,
            "min": float(np.min(vals)), "max": float(np.max(vals)),
            "mean": float(np.mean(vals)), "median": float(np.median(vals)),
            "iqr": float(q3 - q1), "shapiro_p": shapiro_p,
        })

    # LT/RT are real mirror-image anatomy -- negate the bundle panel's default
    # azimuth for _RT so the two sides' default views appear consistently
    # oriented instead of mirrored (see the views.bundle comment in the template)
    bundle_azimuth = -0.7 if bundle.endswith("_RT") else 0.7

    html = SPIDER_3D_TEMPLATE.format(
        title=f"sub-{subj}{ses_str} — {bundle}",
        caption=f"thick ring = along-tract mean &bull; faint rings = individual "
               f"segments (n={len(seg_rings)}) &bull; each axis scaled 0-1 "
               f"across this subject's own bundles",
        payload_json=json.dumps(payload),
        bundle_json=json.dumps(bundle_geometry or []),
        bundle_axes_json=json.dumps(bundle_axes),
        profiles_json=json.dumps(profiles),
        stats_json=json.dumps(stats),
        connectivity_json=json.dumps(connectivity),
        bundle_empty_note=bundle_empty_note,
        bundle_azimuth=bundle_azimuth,
        series_color=HTML_SERIES_COLOR, gridline=HTML_GRIDLINE, baseline=HTML_BASELINE,
        surface=HTML_SURFACE, ink_primary=HTML_INK_PRIMARY, ink_muted=HTML_INK_MUTED,
        ink_secondary=HTML_INK_SECONDARY,
    )
    with open(out_html, "w") as f:
        f.write(html)


def write_summary_csv(data, out_csv):
    metrics_present = [m for m in METRIC_ORDER
                       if any(m in bm for bm in data.values())]
    with open(out_csv, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Bundle"] + metrics_present)
        for bundle in sorted(data):
            row = [bundle]
            for m in metrics_present:
                values = data[bundle].get(m)
                if not values or all(np.isnan(v) for v in values):
                    row.append("")
                else:
                    row.append(f"{np.nanmean(values):.6g}")
            writer.writerow(row)


def main():
    parser = argparse.ArgumentParser(
        description="Assemble every bundle's QQ scores into one bundle x metric "
                    "summary (CSV) and one spider/radar plot per bundle."
    )
    parser.add_argument("tcks_output_dir", type=str,
                       help="sub-<subj><ses_str>_TCKs_output directory.")
    parser.add_argument("subj", type=str)
    parser.add_argument("ses_str", type=str, nargs="?", default="")
    args = parser.parse_args()

    data = find_score_files(args.tcks_output_dir, args.subj, args.ses_str)
    if not data:
        return

    global_ranges = compute_global_ranges(data)
    parcel_labels = load_parcel_labels()

    write_summary_csv(
        data,
        os.path.join(args.tcks_output_dir,
                     f"sub-{args.subj}{args.ses_str}_bundle_metric_means.csv"),
    )

    for bundle, bundle_metrics in data.items():
        qq_dir = os.path.join(args.tcks_output_dir, f"{bundle}_output", "QQ")
        out_pdf = os.path.join(
            qq_dir, f"sub-{args.subj}{args.ses_str}_spider_{bundle}.pdf")
        out_html = os.path.join(
            qq_dir, f"sub-{args.subj}{args.ses_str}_spider3d_{bundle}.html")

        bundle_geometry = None
        tck_path = find_bundle_tck(args.tcks_output_dir, bundle)
        if tck_path:
            n_segments = len(next(iter(bundle_metrics.values())))
            centroid_path = find_bundle_centroid_tck(args.tcks_output_dir, bundle)
            bundle_geometry = load_bundle_geometry(
                tck_path, n_segments, centroid_path=centroid_path)

        plot_bundle_spider(bundle, bundle_metrics, global_ranges, out_pdf,
                          args.subj, args.ses_str)
        plot_bundle_spider_3d(bundle, bundle_metrics, global_ranges, out_html,
                             args.subj, args.ses_str, bundle_geometry,
                             connectivity=load_connectivity(qq_dir, parcel_labels))


if __name__ == "__main__":
    main()
