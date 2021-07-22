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
from numpy import genfromtxt
import os, sys, getopt, glob
import scipy
import dipy
import dipy.stats.analysis as dsa
import dipy.data as dpd
import pkgutil
import matplotlib
matplotlib.use('Qt5Agg')
import csv
import string
import statsmodels.stats.api as sms
import matplotlib.pyplot as plt
from nilearn import plotting
from dipy.tracking import utils
from dipy.io.image import load_nifti, load_nifti_data
from dipy.io.stateful_tractogram import Space, StatefulTractogram
from dipy.io.streamline import load_tractogram, save_tractogram
from dipy.segment.clustering import QuickBundles
from dipy.segment.metric import AveragePointwiseEuclideanMetric, ResampleFeature

# inputfile = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_TCKs_output/CST_RT_output/QQ/CST_RT_fin_WB_iFOD2_inMNI_rTCK.tck'
# mdir = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_prep'
# metcsv = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_TCKs_output/CST_RT_output/QQ/CST_RT_fin_WB_iFOD2_FA_MNI.csv'

def main(argv):
    inputfile = ''
    mdir = ''
    metcsv = ''
    try:
        opts, args = getopt.getopt(argv,"hi:m:c:",["ifile=","mdir=","metcsv="])
    except getopt.GetoptError:
        print ('KUL_FWT_QQ_TCKs.py -i <inputfile> -c <metcsv>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('KUL_FWT_QQ_TCKs.py -i <inputfile> -c <metcsv>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
        elif opt in ("-m", "--mdir"):
            mdir = arg
        elif opt in ("-c", "--csv"):
            metcsv = arg
    print ('Input TCK file is ', inputfile)
    print ('Metrics folder is "', mdir)
    print ('Metrics csv is ', metcsv)

    # sanity checks
    if os.path.isfile(inputfile):
        if os.path.isdir(mdir):
            if os.path.isfile(metcsv):

            # define paths and names
            in_path, in_nam = os.path.split(inputfile)
            in_name = os.path.splitext(in_nam)[0]
            _, met_nam = os.path.split(metcsv)
            met_nam1 = os.path.splitext(met_nam)[0].split('_')[-2]
            met_name = (met_nam1.upper())

            # # open the metrics.csv file, transpose it and save as numpy array
            # with open(metcsv, newline='') as f:
            #     csv_l1 = list(csv.reader(f, delimiter=' '))
            #     csv_l2 = np.asarray(csv_l1[1:], dtype=np.float).T

            # read in your csv using genfromtxt to nympy array directly
            csv_l1 = genfromtxt(metcsv, delimiter = ' ')
            csv_l2 = np.asarray(csv_l1, dtype=np.float).T

            # declare arrays for storing mean values per segment and 95% conf intervals
            co, _ = csv_l2.shape

            print(co)

            # create arrays to hold means and conf_ints
            means = np.zeros([co,1])
            conf_ints = np.zeros([co,2])

            # calculate mean and conf ints per column (segment)
            # https://stackoverflow.com/questions/15033511/compute-a-confidence-interval-from-sample-data
            for i in range(co):
                means[i] = np.asarray(np.mean(csv_l2[:,i])) 
                conf_ints[i] = np.asarray(sms.DescrStatsW(csv_l2[:,i]).tconfint_mean())

            # get your gun 
            prof_fig1 = os.path.join(in_path, in_name + '_' + met_name + '_scalar_profiles.pdf')
            fig, (ax1) = plt.subplots(1,1)
            ax1.plot(csv_l2)
            # ax1.fill_between(range(co), csv_l2[:,0], csv_l2[:,-1], color='b', alpha=.1)
            ax1.set_ylabel(met_name)
            ax1.set_xlabel('Bundle segment no.')
            ax1.ticklabel_format(axis="y", style="sci", scilimits=(0,0))
            plt.title(in_name)
            plt.tight_layout()
            fig.savefig(prof_fig1, bbox_inches='')
            plt.close()

            # save the means and confidence intervals to a .csv file
            stats_out = os.path.join(in_path, in_name + '_' + met_name + '_mean_95ci.csv')
            bbb = np.concatenate((means, conf_ints),axis=1)
            np.savetxt(stats_out, bbb, delimiter=',', header='Mean,Lower_95CI,Upper_95CI', comments='')

            # read your map
            # use scale1 MSBP uint8
            brain_m1 = os.path.join(mdir, '*_LC+spine_inMNI.nii.gz')
            brain_m2 = glob.glob(brain_m1)
            brain_map = load_nifti_data(brain_m2[0])
            _, bm_affine = load_nifti(brain_m2[0])

            # make name for output pdf
            conn_fp = os.path.join(in_path, in_name + '_conn_fingerprint.pdf')
            connfp_csv = os.path.join(in_path, in_name + '_conn_grouping.csv')

            # make the conn_fp figure if not yet made
            if not os.path.exists(conn_fp):
                # read your tck
                refff = nib.load(brain_m2[0])
                tck_in = load_tractogram(inputfile, refff).streamlines

                ## we set the first row and column to zero before viewing
                M, _ = utils.connectivity_matrix(tck_in, bm_affine, brain_map.astype(np.uint8), return_mapping=True, mapping_as_streamlines=True)
                M[:1, :] = 0
                M[:, :1] = 0
                conn_FP = plt.imshow(np.log1p(M), interpolation='nearest')
                conn_FP.figure.savefig(conn_fp, dpi = 300)
                plt.close()
                np.savetxt(connfp_csv, M, delimiter=',')

if __name__ == "__main__":
   main(sys.argv[1:])