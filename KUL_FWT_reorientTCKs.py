#!/usr/bin/env python3

# A small python script to reorient a TCK bundle and its centroid based on VOIs
# AR @ ahmed.radwan@kuleuven.be, radwanphd@gmail.com

import nibabel as nib
import numpy as np
import os, sys, getopt, glob
import scipy
import dipy
import dipy.stats.analysis as dsa
import dipy.tracking.streamline as dts
from dipy.tracking import utils
from dipy.io.image import load_nifti, load_nifti_data, save_nifti
from dipy.io.stateful_tractogram import Space, StatefulTractogram
from dipy.io.streamline import load_tractogram, save_tractogram
import dipy.data as dpd
import pkgutil
from dipy.io.utils import create_nifti_header, get_reference_info

# import matplotlib
# import csv
# matplotlib.use('Qt5Agg')
# import matplotlib.pyplot as plt
# from nilearn import plotting
# from dipy.viz import actor, window, colormap as cmap
# from dipy.segment.clustering import QuickBundles
# from dipy.segment.metric import AveragePointwiseEuclideanMetric, ResampleFeature


# inf1 = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_TCKs_output/CST_LT_output/QQ/tmp/CST_LT_fin_WB_iFOD2_rs1c_inMNI.tck'
# inf2 = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_TCKs_output/CST_LT_output/QQ/tmp/CST_LT_fin_WB_iFOD2_inMNI_centroid1.tck'
# voi1 = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_VOIs/CST_LT_VOIs_inMNI/CST_LT_incs1_map_inMNI.nii.gz'
# voi2 = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_VOIs/CST_LT_VOIs_inMNI/CST_LT_incs2_map_inMNI.nii.gz'
# mdir = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_prep'

def main(argv):
    inf1 = ''
    inf2 = ''
    mdir = ''
    voi1 = ''
    voi2 = ''
    try:
        opts, args = getopt.getopt(argv,"hi:c:m:s:e:",["inf1=","inf2=","mdir=","voi1=","voi2="])
    except getopt.GetoptError:
        print ('KUL_FWT_reorientTCKs.py -i <ifile> -c <cfile> -m <mdir> -s <voi1> -e <voi2>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('KUL_FWT_reorientTCKs.py -i <ifile> -c <cfile> -m <mdir> -s <voi1> -e <voi2>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inf1 = arg
        elif opt in ("-c", "--cfile"):
            inf2 = arg
        elif opt in ("-m", "--mdir"):
            mdir = arg
        elif opt in ("-s", "--voi1"):
            voi1 = arg
        elif opt in ("-e", "--voi2"):
            voi2 = arg
    print ('Input bundle TCK file is "', inf1)
    print ('Input centroid TCK file is "', inf2)
    print ('Start VOI file is  "', voi1)
    print ('End VOI file is  "', voi2)
    print ('Metrics folder is "', mdir)

    # sanity checks
    if os.path.isfile(inf1):
        if os.path.isfile(inf2):
            if os.path.isfile(voi1):
                if os.path.isfile(voi2):
                    if os.path.isdir(mdir):
                        # define metric images
                        refff = glob.glob(os.path.join(mdir, 'FS_2_UKBB_*_Warped.nii.gz'))[0]

                        # for refff we should load FS warped to MNI from prep dir
                        reff = nib.load(refff)
                        tckv1 = nib.load(voi1)
                        tckv2 = nib.load(voi2)

                        # binarize on the fly
                        tckv1.get_fdata()[tckv1.get_fdata()>1] = 1
                        tckv2.get_fdata()[tckv2.get_fdata()>1] = 1

                        # get name of input ??
                        # get paths and names
                        in_path, _ = os.path.split(inf1)
                        in_nr = str.rsplit((str.split(inf1, '/')[-1]), '_',2)
                        # _, c_nam = os.path.split(inf2)

                        # get your gun
                        o_dir, _ = os.path.split(in_path)
                        # we are already in QQ right?
                        outf1 = os.path.join(o_dir, (in_nr[0]) + '_inMNI_rTCK.tck')
                        outf2 = os.path.join(o_dir, (in_nr[0]) + '_inMNI_centroid_rTCK.tck')

                        # load the input tractogram centroid
                        tck_in = load_tractogram(inf1, reff, bbox_valid_check=False).streamlines
                        tck_cent = load_tractogram(inf2, reff, bbox_valid_check=False).streamlines

                        reor_tck = dts.orient_by_rois(tck_in, (reff.affine), (tckv1.get_fdata()), (tckv2.get_fdata()), in_place=False, as_generator=False)
                        reor_c = dts.orient_by_rois(tck_cent, (reff.affine), (tckv1.get_fdata()), (tckv2.get_fdata()), in_place=False, as_generator=False)

                        reor_c_out = StatefulTractogram(reor_c, reff, Space.RASMM)
                        reor_TCK_out = StatefulTractogram(reor_tck, reff, Space.RASMM)
                        save_tractogram(reor_TCK_out, outf1, bbox_valid_check=False)
                        save_tractogram(reor_c_out, outf2, bbox_valid_check=False)

                        # reor_tck = dts.orient_by_streamline(tck_in, reor_tckc, n_points=100, in_place=False, as_generator=False)

                        # QB stuff
                        # feature = ResampleFeature(nb_points=51)
                        # metric = AveragePointwiseEuclideanMetric(feature)
                        # qb = QuickBundles(np.inf, metric=metric)
                        # #find your center ;)
                        # clust_tck = qb.cluster(tck_r)
                        # tck_center = clust_tck.centroids[0]

                        # rs_tckc = dsa.set_number_of_points(tck_r, 100)

                        # get your weights
                        # w_tcks = dsa.gaussian_weights(reor_tck)
                        # reor_tck = dts.orient_by_streamline(tck_in,rs_tckc)
                        # reor_cent = dts.orient_by_streamline(tck_cent,rs_tckc)

                        # reor_cent_out = StatefulTractogram(reor_tckc, reff, Space.RASMM)
                        # save_tractogram(reor_tck_out, outf1, bbox_valid_check=False)


if __name__ == "__main__":
   main(sys.argv[1:])