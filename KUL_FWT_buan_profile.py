#!/usr/bin/env python3

import argparse
import csv
import nibabel as nib
from dipy.io.streamline import load_tractogram
from dipy.stats.analysis import afq_profile


def profile_bundle(bundle_tck, reference_nii, scalar_nii, metric_name, output_txt,
                    n_points, orient_by_tck=None, plot_pdf=None, plot_title=None):
    ref_img = nib.load(reference_nii)
    streamlines = load_tractogram(bundle_tck, ref_img, bbox_valid_check=False).streamlines

    orient_by = None
    if orient_by_tck:
        centroid = load_tractogram(orient_by_tck, ref_img, bbox_valid_check=False).streamlines
        orient_by = centroid[0]

    scalar_img = nib.load(scalar_nii)
    scalar_data = scalar_img.get_fdata()

    profile = afq_profile(scalar_data, streamlines, scalar_img.affine,
                           n_points=n_points, orient_by=orient_by)

    with open(output_txt, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Segments", f"Mean_{metric_name}"])
        for i, val in enumerate(profile, start=1):
            writer.writerow([i, val])

    if plot_pdf:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        segments = list(range(1, len(profile) + 1))
        fig, ax = plt.subplots(figsize=(6, 4))
        ax.plot(segments, profile, marker="o", markersize=3, linewidth=1)
        ax.set_xlabel("Segment (along-tract, node 1 = orient_by start)")
        ax.set_ylabel(f"Mean {metric_name}")
        ax.set_title(plot_title or metric_name)
        fig.tight_layout()
        fig.savefig(plot_pdf)
        plt.close(fig)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="BUAN-style (dipy.stats.analysis.afq_profile) along-tract scalar "
                     "profile for one bundle/metric — the canonical KUL_FWT tractometry "
                     "method (see KUL_FWT_tractometry_functions.sh)."
    )
    parser.add_argument("bundle_tck", type=str, help="Resampled bundle .tck file (native space).")
    parser.add_argument("reference_nii", type=str,
                         help=".nii.gz reference for the .tck (e.g. subj_FA); provides the affine.")
    parser.add_argument("scalar_nii", type=str, help=".nii.gz scalar volume to sample along the bundle.")
    parser.add_argument("metric_name", type=str,
                         help="Metric name for the output header (e.g. FA, ADC, TDI).")
    parser.add_argument("output_txt", type=str,
                         help="Output .txt path (Segments, Mean_<metric> columns).")
    parser.add_argument("--n-points", type=int, default=50,
                         help="Number of along-tract segments (default: 50, matches the "
                              "convention previously set by scil_bundle_label_map).")
    parser.add_argument("--orient-by-tck", type=str, default=None,
                         help="Single-streamline .tck (e.g. the bundle centroid from "
                              "scil_bundle_compute_centroid) used to consistently orient "
                              "every streamline before per-node averaging. Without this, "
                              "streamlines with inconsistent start/end order would average "
                              "together points from different anatomical locations.")
    parser.add_argument("--plot-pdf", type=str, default=None,
                         help="Optional output .pdf: a simple along-tract line plot of the "
                              "profile, self-contained (no external label-map/background "
                              "image needed).")
    parser.add_argument("--plot-title", type=str, default=None,
                         help="Optional plot title (default: metric_name).")
    args = parser.parse_args()

    profile_bundle(args.bundle_tck, args.reference_nii, args.scalar_nii, args.metric_name,
                    args.output_txt, args.n_points, args.orient_by_tck,
                    args.plot_pdf, args.plot_title)
