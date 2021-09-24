#!/usr/bin/env python3

# A small python script to run AFQ on filtered bundles
# 3 inputs arguments are expected, 1 - input tck, 2 - reference anatomy image, and 3 - output tck.
# AR @ ahmed.radwan@kuleuven.be, radwanphd@gmail.com

# following this example -> https://dipy.org/documentation/1.3.0./_downloads/e344c36d129dda8d2f2bcac50ee292fd/afq_tract_profiles.py/

# managed to generate tract profile for CST_LT
# will need load_nifti from dipy
# No need to reorient fibers if deriving centroid from the same bundle
# No need to include any warps or transforms as we stick to subject space
# still need a script for generating screenshots

import nibabel as nib
import numpy as np
import os, sys, getopt, glob
import scipy
import dipy
import dipy.stats.analysis as dsa
import dipy.data as dpd
import pkgutil
import matplotlib
matplotlib.use('Qt5Agg')
import matplotlib.pyplot as plt
import dipy.tracking.streamline as dts
from nilearn import plotting


# inputfile = '/media/rad/Data/DF_final/sub-S5_KUL_WBTCK_Seg_output/sub-S5_TCKs_output/CST_LT_output/CST_LT_fin_WB_iFOD2_inMNI.tck'
# mdir = '/media/rad/Data/DF_final/sub-S5_KUL_WBTCK_Seg_output/sub-S5_prep'
# vdir = '/media/rad/Data/DF_final/sub-S5_KUL_WBTCK_Seg_output/sub-S5_VOIs/CST_LT_VOIs_inMNI'

def main(argv):
    inputfile = ''
    vdir = ''
    mdir = ''
    try:
        opts, args = getopt.getopt(argv,"hi:v:m:",["ifile=","vdir=","mdir="])
    except getopt.GetoptError:
        print ('KUL_FWT_SCs_TCKs.py -i <inputfile> -v <vdir> -m <mdir>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('KUL_FWT_SCs_TCKs.py -i <inputfile> -v <vdir> -m <mdir>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
        elif opt in ("-v", "--vdir"):
            vdir = arg
        elif opt in ("-m", "--mdir"):
            mdir = arg
    print ('Input TCK file is "', inputfile)
    print ('VOIs dir is "', vdir)
    print ('Metrics folder is "', mdir)

    # sanity checks
    if os.path.isfile(inputfile):
      if os.path.isdir(vdir):
        if os.path.isdir(mdir):

            # define metric images
            # refff_p = os.path.join(mdir, 'UKBB_2_FA_*_InverseWarped.nii.gz')
            # # adc_im = os.path.join(mdir, 'adc.nii.gz')
            # refff = nib.load(refff_p)

            # get paths and names
            in_path, in_nam = os.path.split(inputfile)
            in_name = str(os.path.splitext(in_nam)[0])

            # get your gun
            new_dir = os.path.join(in_path, 'Screenshots')

            if not os.path.exists(new_dir): 
                os.makedirs(new_dir)

            # make glass brain rendering with nilearn
            # use tck tdi map
            # find the map
            str1 = "_WB_"
            str2 = "_BT_"
            if str1 in in_name:
                tckmeth = "WB"
            elif str2 in in_name:
                tckmeth = "BT"

            print(tckmeth)

            tck_map_src = os.path.join(in_path, '*_fin_map_' + tckmeth + '_*_inMNI.nii.gz')
            tck_map = glob.glob(tck_map_src)
            tckm_im = nib.load(tck_map[0])
            scrn_shot2 = os.path.join(new_dir, in_name + '_screenshot1_niGB.pdf')
            gbd = plotting.plot_glass_brain(tckm_im, title= in_name, display_mode='lyrz', cmap= 'cool')
            gbd.savefig(scrn_shot2, dpi = 300)



            # need to find my VOIs
            incs_lst = os.path.join(vdir, '*incs*_map_inMNI.nii.gz')
            incs = glob.glob(incs_lst)
            # excs_lst = os.path.join(vdir, '*excs*_bin_inMNI.nii.gz')
            # excs = glob.glob(excs_lst)

            # start with the bundle
            vois_glasses = plotting.plot_glass_brain(tckm_im, title= in_name, display_mode='lyrz', cmap= 'cool')

            # loop over incs

            voi_ims = nib.load(incs[0])
            vois_glasses.add_contours(voi_ims, colors='gold', linewidths= 0.75 )

            # # handle the vois ims
            for el in incs[1:]:
                voi_ims = nib.load(el)
                vois_glasses.add_contours(voi_ims, colors='gold', linewidths= 0.75 )
                # vois_glasses.add_contours(voi_ims, colors='gold', threshold=0.01)

            scrn_shot3 = os.path.join(new_dir, in_name + '_screenshot2_niGB.pdf')
            vois_glasses.savefig(scrn_shot3, dpi = 300)

if __name__ == "__main__":
   main(sys.argv[1:])