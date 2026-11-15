#!/usr/bin/env python3

# Outlier rejection for a single bundle (KUL_FWT filt3 / -R rord_outlier step).
#
# Drop-in replacement for scilpy's scil_bundle_reject_outliers, which we used
# until it was found to delete the anatomically complete part of fanning
# bundles -- most visibly the whole frontal limb of the UF.
#
# Both tools score streamlines identically, with scilpy's own library function
# (outliers_removal_using_hierarchical_quickbundles): recursive QuickBundles
# clustering over a ladder of shrinking thresholds, scoring each streamline by
# how deep into the hierarchy it survived, normalised by the deepest streamline
# in the bundle. What differs is how that score is turned into a keep/drop
# decision.
#
# scil_bundle_reject_outliers cuts at an absolute --alpha. That is unsafe here
# for three compounding reasons:
#
#   1. The score is relative to the bundle's own densest core, not to any
#      absolute notion of "outlier". A bundle with a narrow bottleneck feeding
#      a wide cortical fan (UF, CCing, ILF, TCing) grades its fan against its
#      bottleneck and loses the fan.
#   2. Clusters stop being subdivided at <=10 members, so the score is partly a
#      density measure. A small but real sub-fascicle scores like an outlier no
#      matter how anatomically correct it is.
#   3. The score's scale is bundle- and subject-specific -- it depends on the
#      bundle's bounding box, which sets the clustering ladder's depth. Across
#      one cohort's uncinate bundles the median score ranged 0.55-0.78, so a
#      fixed alpha=0.58 sat on the steep part of the distribution and swung
#      retention between 40% and 92% for anatomically comparable bundles.
#
# So an absolute alpha alone cannot be tuned to be simultaneously safe on a
# compact bundle and on a fanning one. Instead we bound the cut from both
# sides, with the score computed once and thresholded as many times as needed
# (the clustering is the expensive part, ~10s/bundle; re-thresholding is free):
#
#   --alpha             nothing scoring above this is ever dropped, however
#                       many low scorers there are (protects clean bundles from
#                       a fixed tithe)
#   --drop_percentile   at most this share of the bundle is ever dropped,
#                       however low the scores run (protects fanning bundles
#                       from the relative-scale problem)
#   --min_retention     hard floor on what survives; if the cut above still
#                       goes below it, the cut is relaxed to exactly this and
#                       the event is logged loudly
#
# With both given the effective threshold is min(alpha, Pth percentile): a
# pristine bundle whose scores all sit above alpha loses nothing, and a bundle
# whose score distribution has collapsed loses the agreed share and no more.
#
# AR @ ahmed.radwan@kuleuven.be, radwanphd@gmail.com

import argparse
import json
import logging
import os
import sys

import numpy as np
from dipy.io.streamline import load_tractogram, save_tractogram

from scilpy.tractanalysis.bundle_operations import \
    outliers_removal_using_hierarchical_quickbundles

# Below this many streamlines the hierarchical QuickBundles score is not a
# meaningful population statistic -- the <=10-members-stop-subdividing rule
# means most of the bundle drops out of the hierarchy immediately and scores
# like an outlier. Pass such bundles through untouched rather than gutting them.
#
# Note this is the one respect in which -f 3 does NOT reproduce the old
# scil_bundle_reject_outliers behaviour: that tool would happily filter a
# 12-streamline bundle. For anything at or above this count -f 3 is bit-exact
# against it (verified streamline-for-streamline on a real filt2 bundle).
MIN_STREAMLINES = 20

# Scoring parameters. Kept identical to scil_bundle_reject_outliers' defaults so
# that -f 3 reproduces pre-existing runs exactly.
NB_POINTS = 12
NB_SAMPLINGS = 30


def _build_arg_parser():
    p = argparse.ArgumentParser(
        description='Reject outlier streamlines from a bundle, bounding the '
                    'cut both by an absolute score floor (--alpha) and by a '
                    'share of the bundle (--drop_percentile). See the comments '
                    'at the top of this file for why both bounds are needed.',
        formatter_class=argparse.RawTextHelpFormatter)

    p.add_argument('in_bundle', help='Fiber bundle to remove outliers from.')
    p.add_argument('out_bundle', help='Fiber bundle without outliers.')

    p.add_argument('--reference', required=True,
                   help='Reference anatomy (.nii/.nii.gz), required for .tck.')

    p.add_argument('--alpha', type=float, default=None,
                   help='Absolute score floor: streamlines scoring at or above '
                        'this are never dropped. ]0, 1].')
    p.add_argument('--drop_percentile', type=float, default=None,
                   help='Upper bound on damage: never drop more than this '
                        'percent of the bundle, lowest-scoring first. [0, 100[.')
    p.add_argument('--min_retention', type=float, default=0.65,
                   help='Hard floor on the surviving fraction. If the cut would '
                        'go below it, the cut is relaxed to exactly this and a '
                        'warning is logged. [%(default)s]')

    p.add_argument('--remaining_bundle',
                   help='Write the rejected streamlines here (QC).')
    p.add_argument('--json_out',
                   help='Write a JSON record of what was decided here (QC).')
    p.add_argument('--min_streamlines', type=int, default=MIN_STREAMLINES,
                   help='Pass the bundle through untouched below this count. '
                        '[%(default)s]')

    p.add_argument('-f', '--force', action='store_true',
                   help='Overwrite existing output.')
    p.add_argument('-v', '--verbose', default='INFO',
                   choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
                   help='Logging level. [%(default)s]')

    return p


def _passthrough(sft, args, reason, record):
    """Write the input unchanged as the output, and say why."""
    logging.warning('%s -- passing the bundle through unfiltered.', reason)
    record.update(mode='passthrough', reason=reason,
                  streamline_count_after=len(sft.streamlines),
                  threshold=None)
    save_tractogram(sft, args.out_bundle, bbox_valid_check=False)
    if args.remaining_bundle:
        save_tractogram(sft[[]], args.remaining_bundle, bbox_valid_check=False)
    return record


def main():
    parser = _build_arg_parser()
    args = parser.parse_args()
    logging.basicConfig(level=getattr(logging, args.verbose),
                        format='%(levelname)s: %(message)s')

    if args.alpha is None and args.drop_percentile is None:
        parser.error('at least one of --alpha / --drop_percentile is required')
    if args.alpha is not None and not 0 < args.alpha <= 1:
        parser.error('--alpha should be ]0, 1]')
    if args.drop_percentile is not None and not 0 <= args.drop_percentile < 100:
        parser.error('--drop_percentile should be [0, 100[')
    if not 0 < args.min_retention <= 1:
        parser.error('--min_retention should be ]0, 1]')

    for f in (args.in_bundle, args.reference):
        if not os.path.isfile(f):
            parser.error('missing input: {}'.format(f))
    if os.path.isfile(args.out_bundle) and not args.force:
        parser.error('{} exists, use -f to overwrite'.format(args.out_bundle))

    sft = load_tractogram(args.in_bundle, args.reference,
                          bbox_valid_check=False)
    n_before = len(sft.streamlines)

    record = {'in_bundle': args.in_bundle,
              'out_bundle': args.out_bundle,
              'streamline_count_before': int(n_before),
              'alpha': args.alpha,
              'drop_percentile': args.drop_percentile,
              'min_retention': args.min_retention,
              'retention_floor_applied': False}

    # Degenerate inputs: hand the bundle on rather than leaving the output
    # missing. task_exec in KUL_FWT_make_TCKs.sh aborts the whole bundle on a
    # nonzero exit, and a missing filt3 breaks the smoothing step after it, so
    # every recoverable case here has to exit 0 with a usable output file.
    if n_before == 0:
        record = _passthrough(sft, args, 'input bundle is empty', record)
    elif n_before < args.min_streamlines:
        record = _passthrough(
            sft, args,
            'only {} streamlines (< --min_streamlines {}), too few for a '
            'population statistic'.format(n_before, args.min_streamlines),
            record)
    else:
        sft.to_rasmm()
        score = outliers_removal_using_hierarchical_quickbundles(
            sft.streamlines, nb_points=NB_POINTS, nb_samplings_max=NB_SAMPLINGS)
        score = np.asarray(score, dtype=float)

        if not np.all(np.isfinite(score)):
            record = _passthrough(
                sft, args, 'scoring returned non-finite values', record)
        else:
            record['score_quantiles'] = {
                str(q): float(np.percentile(score, q))
                for q in (1, 5, 10, 25, 50, 75, 95)}

            # Effective threshold. With both bounds given the lower one wins:
            # alpha stops us cutting into streamlines that score well even when
            # the percentile would reach them, and the percentile stops us
            # cutting deep into a bundle whose scores have collapsed wholesale.
            candidates = []
            if args.alpha is not None:
                candidates.append(float(args.alpha))
            if args.drop_percentile is not None:
                candidates.append(
                    float(np.percentile(score, args.drop_percentile)))
            threshold = min(candidates)

            keep = score >= threshold

            # Retention floor. Inert whenever --drop_percentile already bounds
            # the damage above it; this is the backstop for a bare --alpha and
            # a last line of defence against any future scoring change.
            if keep.sum() < args.min_retention * n_before:
                relaxed = float(np.percentile(
                    score, (1.0 - args.min_retention) * 100.0))
                logging.warning(
                    'outlier rejection would have kept %d/%d (%.1f%%), below '
                    'the --min_retention floor of %.0f%% -- relaxing the cut '
                    'from %.4f to %.4f. This bundle is worth looking at.',
                    int(keep.sum()), n_before, keep.mean() * 100,
                    args.min_retention * 100, threshold, relaxed)
                threshold = relaxed
                keep = score >= threshold
                record['retention_floor_applied'] = True

            inliers = np.flatnonzero(keep)
            outliers = np.flatnonzero(~keep)

            record.update(mode='score', threshold=float(threshold),
                          streamline_count_after=int(inliers.size))

            logging.info('kept %d/%d streamlines (%.1f%%) at score >= %.4f',
                         inliers.size, n_before,
                         inliers.size / n_before * 100, threshold)

            save_tractogram(sft[inliers], args.out_bundle,
                            bbox_valid_check=False)
            if args.remaining_bundle:
                save_tractogram(sft[outliers], args.remaining_bundle,
                                bbox_valid_check=False)

    if args.json_out:
        with open(args.json_out, 'w') as fh:
            json.dump(record, fh, indent=2)

    return 0


if __name__ == '__main__':
    sys.exit(main())
