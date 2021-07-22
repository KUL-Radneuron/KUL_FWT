#!/usr/bin/env python3

# A small python script to run AFQ on filtered bundles
# 2 inputs arguments are expected, 1 - input tck, 2 - mdir.
# AR @ ahmed.radwan@kuleuven.be, radwanphd@gmail.com

# following this example -> https://dipy.org/documentation/1.3.0./_downloads/e344c36d129dda8d2f2bcac50ee292fd/afq_tract_profiles.py/


import nibabel as nib
import numpy as np
import os, sys, getopt, glob, re
import scipy
import dipy
import dipy.stats.analysis as dsa
import dipy.data as dpd
import pkgutil
import matplotlib
import csv
matplotlib.use('Qt5Agg')
import matplotlib.pyplot as plt
import dipy.tracking.streamline as dts
from nilearn import plotting
from dipy.tracking import utils
from dipy.viz import actor, window, colormap as cmap
from dipy.io.image import load_nifti, load_nifti_data, save_nifti
from dipy.io.stateful_tractogram import Space, StatefulTractogram
from dipy.io.streamline import load_tractogram, save_tractogram
from dipy.io.utils import create_nifti_header, get_reference_info
from dipy.segment.clustering import QuickBundles
from dipy.segment.metric import AveragePointwiseEuclideanMetric, ResampleFeature

# inputfile = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_TCKs_output/CST_LT_output/QQ/tmp/CST_LT_fin_WB_iFOD2_inMNI_rTCK.tck'
# mdir = '/media/rad/Data/DF_final/sub-DF_KUL_WBTCK_Seg_output/sub-DF_prep'

def main(argv):
    inputfile = ''
    mdir = ''
    try:
        opts, args = getopt.getopt(argv,"hi:c:v:m:",["ifile=","mdir=","scalars="])
    except getopt.GetoptError:
        print ('KUL_FWT_TCKsQQ.py -i <inputfile> -m <mdir>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('KUL_FWT_TCKsQQ.py -i <inputfile> -m <mdir>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
        elif opt in ("-m", "--mdir"):
            mdir = arg
    print ('Input TCK file is "', inputfile)
    print ('Metrics folder is "', mdir)

    # sanity checks
    if os.path.isfile(inputfile):
        if os.path.isdir(mdir):

            # first we find our input dir
            in_path, _ = os.path.split(inputfile)
            in_nr = str.rsplit((str.split(inputfile, '/')[-1]), '_',2)

            # second what kind of tractogram is it?
            in_na = str.rsplit((str.split(in_nr[0], '/')[-1]), '_',2)[-1]

            # third define metrics common to both approaches
            # FA, ADC, AD, RD, Curvature
            fa_im = os.path.join(mdir, 'FA_MNI.nii.gz')
            refff = nib.load(fa_im)
            fa, _ = load_nifti(fa_im)

            # load the input tractogram
            # and find the centroid to load it as well
            tck_in = load_tractogram(inputfile, refff).streamlines

            # find your weights
            w_tcks = dsa.gaussian_weights(tck_in)

            # more metrics
            # metrics1 = ['FA', 'ADC', 'AD', 'RD', 'Curv']
            names1 = ('Fractional Anisotropy', 'Apparent Diffusion Coefficient', 'Axial Diffusivitiy', 'Radial Diffusivity')
            metrics1 = ('FA', 'ADC', 'AD', 'RD')

            if re.match('iFOD2', in_na) or re.match('iFOD1', in_na) or re.match('iFOD2', in_na):
                names1 += ('Apparent Fiber Density', 'Fiber Dispersion', 'FOD Peaks')
                metrics1 += ('fd', 'disp', 'peaks')

            for m in range(len(metrics1)):
                im = os.path.join(mdir, str(metrics1[m]) + '_MNI.nii.gz')
                im_l, _ = load_nifti(im)
                prof_fig = os.path.join(in_path, in_nr[0] + '_' + in_nr[1] + '_' + str(metrics1[m]) + '_scalar_profile.pdf')
                prof_tck = dsa.afq_profile(im_l, tck_in, refff.affine, weights=w_tcks)
                prof_out = os.path.join(in_path, in_nr[0] + '_' + in_nr[1] + '_' + str(metrics1[m]) + '_scalar_profile.csv')
                np.savetxt(prof_out, prof_tck, delimiter=',')
                fig, (ax1) = plt.subplots(1,1)
                ax1.plot(prof_tck)
                ax1.set_ylabel(names1[m])
                ax1.set_xlabel('Node along bundle')
                ax1.ticklabel_format(axis="y", style="sci", scilimits=(0,0))
                plt.title(in_nr[0])
                plt.tight_layout()
                fig.savefig(prof_fig, bbox_inches='')
                plt.close()
                del fig


            # deal with tract specific maps
            names2 = ('Streamlines TDI', 'Streamlines Lengths', 'Streamlines Curvature')
            metrics2 = ('tdi', 'length', 'curve')

            for n in range(len(metrics2)):
                im2 = os.path.join(in_path, in_nr[0] + '_' + str(metrics2[n]) + '_inMNI.nii.gz')
                im_l2, _ = load_nifti(im2)
                prof_fig2 = os.path.join(in_path, in_nr[0] + '_' + in_nr[1] + '_' + str(metrics2[n]) + '_scalar_profile.pdf')
                prof_tck2 = dsa.afq_profile(im_l2, tck_in, refff.affine, weights=w_tcks)
                prof_out2 = os.path.join(in_path, in_nr[0] + '_' + in_nr[1] + '_' + str(metrics2[n]) + '_scalar_profile.csv')
                np.savetxt(prof_out2, prof_tck2, delimiter=',')
                fig2, (ax2) = plt.subplots(1,1)
                ax2.plot(prof_tck2)
                ax2.set_ylabel(names2[n])
                ax2.set_xlabel('Node along bundle')
                ax2.ticklabel_format(axis="y", style="sci", scilimits=(0,0))
                plt.title(in_nr[0])
                plt.tight_layout()
                fig2.savefig(prof_fig2, bbox_inches='')
                plt.close()
                del fig2

            # read your map
            # use scale1 MSBP uint8
            brain_m1 = os.path.join(mdir, '*_LC+spine_inMNI.nii.gz')
            brain_m2 = glob.glob(brain_m1)
            brain_map = load_nifti_data(brain_m2[0])
            _, bm_affine = load_nifti(brain_m2[0])

            # make name for output pdf
            conn_fp = os.path.join(in_path, in_nr[0] + '_' + in_nr[1] + '_conn_fingerprint.pdf')
            connfp_csv = os.path.join(in_path, in_nr[0] + '_' + in_nr[1] + '_conn_grouping.csv')

            # make the conn_fp figure if not yet made
            if not os.path.exists(conn_fp):
                # read your tck
                refff = nib.load(brain_m2[0])
                # tck_in = load_tractogram(inputfile, refff).streamlines

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