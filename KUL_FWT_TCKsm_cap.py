#!/usr/bin/env python3

import nibabel as nib
import numpy as np
import os, sys, getopt, glob
# import matplotlib
# import matplotlib.pyplot as plt
import dipy.tracking.streamline as dts
from nilearn import plotting
from dipy.viz import actor, window, colormap as cmap

# inputfile = '/media/rad/Data/DF_final/sub-S5_KUL_WBTCK_Seg_output/sub-S5_TCKs_output/CST_LT_output/QQ/CST_LT_fin_WB_iFOD2_rs50_segments_MNI.nii.gz'

# inputfile = '/media/rad/Data/DF_final/trial_warp_segment.nii.gz'

def main(argv):
    inputfile = ''
    try:
        opts, args = getopt.getopt(argv,"hi:",["ifile="])
    except getopt.GetoptError:
        print ('KUL_FWT_TCKsm_cap.py -i <inputfile>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('KUL_FWT_TCKsm_cap.py -i <inputfile>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
    print ('Input TCK segmentation file is "', inputfile)

    # insert if loop looking for inputfile here
    # tck_seg_map to be saved as a fig as well
    if os.path.isfile(inputfile):

        # get paths and names
        in_path, in_nam = os.path.split(inputfile)
        in_name = os.path.splitext(os.path.splitext(in_nam)[0])[0]

        # load the segmentation map
        tckm_im = nib.load(inputfile)

        # screenshot name
        scnsht_map = os.path.join(in_path, in_name + '_segments_map.pdf')

        maps_glass = plotting.plot_glass_brain(tckm_im, title= in_name, display_mode='lyrz', cmap= 'hsv', plot_abs=True, threshold=0.05, vmin=0.05, vmax=50, colorbar=True)

        maps_glass.savefig(scnsht_map, dpi = 300)

if __name__ == "__main__":
   main(sys.argv[1:])