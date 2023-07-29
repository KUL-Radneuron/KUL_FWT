#!/usr/bin/env python3

import nibabel as nib
import matplotlib.pyplot as plt
import argparse
import os
from dipy.io.streamline import load_tractogram
from dipy.tracking import utils
import numpy as np

def plot_connectivity_fp(input_tck, input_labels, output_path):

    refff = nib.load(input_labels)
    ref_aff = refff.affine
    ref_data = refff.get_fdata()
    tck_in = load_tractogram(input_tck, refff).streamlines
    M, _ = utils.connectivity_matrix(tck_in, ref_aff, np.uint8(ref_data), return_mapping=True, mapping_as_streamlines=True)
    M[:1, :] = 0
    M[:, :1] = 0

    # still need to get path from output_file
    # and output the .csv map and the .pdf/.png plot

    base_name = os.path.basename(input_tck)
    bundle = base_name.split('fin_')[0]
    connfp_csv = os.path.join(output_path, (bundle + "_connectivity_matrix.csv"))
    connfp_plot = os.path.join(output_path, (bundle + "_connectivity_plot.png"))
    conn_FP = plt.imshow(np.log1p(M), interpolation='nearest')
    conn_FP.figure.savefig(connfp_plot, dpi = 300)
    plt.close()
    np.savetxt(connfp_csv, M, delimiter=',')

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Calculate and plot connectivity matrix from tractograms .tck file and parcellation .nii.gz file .')
    parser.add_argument('Bundle_tck', type=str, help='.tck file for tractogram.')
    parser.add_argument('Parc_map', type=str, help='.nii.gz file for parcellation map.')
    parser.add_argument('Output_path', type=str, help='Output path.')
    args = parser.parse_args()

    plot_connectivity_fp(args.Bundle_tck, args.Parc_map, args.Output_path)