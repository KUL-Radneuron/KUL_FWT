#!/usr/bin/env python3

# A small python script to run FBC filtering
# 3 inputs arguments are expected, 1 - input tck, 2 - reference anatomy image, and 3 - output tck.
# AR @ ahmed.radwan@kuleuven.be, radwanphd@gmail.com

import nibabel as nib
import os, sys, getopt
import scipy
import dipy
from dipy.io.stateful_tractogram import Space, StatefulTractogram
from dipy.io.streamline import load_tractogram, save_tractogram
from dipy.io.utils import create_nifti_header, get_reference_info
from dipy.denoise.enhancement_kernel import EnhancementKernel
from dipy.tracking.fbcmeasures import FBCMeasures

# print 'Number of arguments:', len(sys.argv), 'arguments.'
# print 'Argument List:', str(sys.argv)

# inputfile = '/media/rad/Data/TCKedit_exp/data_4_trying/PT079/sub-PT079_KUL_WBTCK_Seg_output/sub-PT079_TCKs_output/CST_LT_output/CST_LT_initial.tck'
# reffile = '/media/rad/Data/TCKedit_exp/data_4_trying/PT079/dwiprep/sub-PT079/sub-PT079/qa/fa_reg2T1w.nii.gz'
# outputfile = '/media/rad/Data/TCKedit_exp/data_4_trying/PT079/trial_FBC.tck'

def main(argv):
    inputfile = ''
    reffile = ''
    outputfile = ''
    try:
        opts, args = getopt.getopt(argv,"hi:r:o:",["ifile=","rfile=","ofile="])
    except getopt.GetoptError:
        print ('KUL_FWT_FBC_4TCKs.py -i <inputfile> -r <reffile> -o <outputfile>')
        sys.exit(2)
    for opt, arg in opts:
        if opt == '-h':
            print ('KUL_FWT_FBC_4TCKs.py -i <inputfile> -r <reffile> -o <outputfile>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
        elif opt in ("-r", "--rfile"):
            reffile = arg
        elif opt in ("-o", "--ofile"):
            outputfile = arg
    print ('Input file is "', inputfile)
    print ('Reference anatomy file is "', reffile)
    print ('Output file is "', outputfile)
    # load the reference anatomy
    print ( reffile )
    img = nib.load(reffile)

    # qform = img.header.get_qfrom()
    # img.header.set_sform(qform,1)
    # img.to_filename(${prep_d}/sub-${subj}${ses_str}_T1brain_inFA_sform_fixed.nii.gz)
    # nib.load('${prep_d}/sub-${subj}${ses_str}_T1brain_inFA_sform_fixed.nii.gz')

    # FBC relevant values
    D33 = 1.0
    D44 = 0.02
    t = 1
    k = EnhancementKernel(D33, D44, t)

    # load the reference tractogram
    tck_in = load_tractogram(inputfile, img)

    # apply FBV to input TCK
    rfbc = FBCMeasures(tck_in.streamlines, k)

    # rFBC threshold is empirically defined
    # sliding down from 0.2
    rfbc_thr = 0.02

    # apply threshold to streamlines
    rfbc_sl, rfbc_rgb, rfbc_rfbc = rfbc.get_points_rfbc_thresholded(rfbc_thr, emphasis=0.01)

    # filter the streamlines
    rfbc_thr_TCK = StatefulTractogram(rfbc_sl, img, Space.RASMM)

    # save them
    save_tractogram(rfbc_thr_TCK, outputfile, bbox_valid_check=False)

if __name__ == "__main__":
   main(sys.argv[1:])