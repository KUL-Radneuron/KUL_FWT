#!/bin/bash

# set -x

# the point of this one is to make my life easier!
# version = v2.0_01072026
# when it comes to VOI gen

cwd="$(pwd)"

# function Usage
function Usage {

cat <<USAGE

    `basename $0` part of the KUL_FWT package of fully automated workflows for fiber tracking

    Usage:

    `basename $0` -p pat001 -s 01  -F /path_to/FS_dir/aparc+aseg.mgz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output

    Examples:

    `basename $0` -p pat001 -s 01 -F /path_to/FS_dir/aparc+aseg.mgz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output -n 6

    Purpose:

    This workflow generates the VOIs needed for fiber tracking by KUL_FWT_make_TCKs.sh from FreeSurfer output (including KUL_multiparc lausanne2018 parcellations) for all bundles specified in the input config file for group-averaged template data

    Required arguments:

    -p:  BIDS participant name (anonymised name of the subject without the "sub-" prefix)
    -s:  BIDS participant session (session no. without the "ses-" prefix)
    -F:  full path and file name of aparc+aseg.mgz from FreeSurfer (lausanne2018.scale3+aseg.mgz must be in the same mri/ directory)
    -c:  path to config file with list of tracks to segment from the whole brain tractogram
    -d:  path to directory with diffusion data (specific to subject and run)
    -o:  full path to output dir (if not set reverts to default output ./sub-*_ses-*_KUL_FWT_output)

    Optional arguments:

    -n:  number of cpu for parallelisation (default is 6)
    -h:  prints help menu

USAGE

    exit 1
}

# add this later
#    -b:  if using BIDS and all data is in BIDS/derivatives


# CHECK COMMAND LINE OPTIONS -------------
# 
# Set defaults

# Set required options
p_flag=0
s_flag=0
F_flag=0
c_flag=0
d_flag=0
o_flag=0
# b_flag=0

if [ "$#" -lt 1 ]; then
    Usage >&2
    exit 1

else

    while getopts "p:s:t:M:F:c:d:o:n:h" OPT; do

        case $OPT in
        p) #participant
            p_flag=1
            subj=$OPTARG
        ;;
        s) #session
            s_flag=1
            ses=$OPTARG
        ;;
        F) #FS aparc+aseg.mgz
            F_flag=1
            FS_apas_in=$OPTARG
        ;;
        c) #config file
            c_flag=1
            conf_f=$OPTARG
        ;;
        d) #diffusion dir
            d_flag=1
            d_dir=$OPTARG	
        ;;
        o) #output
            o_flag=1
            out_dir=$OPTARG
        ;;
        n) #parallel
            n_flag=1
            ncpu=$OPTARG
        ;;
        h) #help
            Usage >&2
            exit 0
        ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            echo
            Usage >&2
            exit 1
        ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            echo
            Usage >&2
            exit 1
        ;;
        esac

    done

fi

# deal with ncpu and itk ncpu

# MRTRIX verbose or not?
# if [ $silent -eq 1 ] ; then 

#     export MRTRIX_QUIET=1

# fi

# REST OF SETTINGS ---

# timestamp
start=$(date +%s)
d=$(date "+%Y-%m-%d_%H-%M-%S")

# check for required inputs

# config file
srch_conf_str=($(basename ${conf_f})) ; conf_dir=($(dirname ${conf_f}))
srch_conf_c=($(find ${conf_dir} -type f | grep  ${srch_conf_str}))

# diffusion data dir
srch_ddir_str=($(basename ${d_dir})) ; diff_dir=($(dirname ${d_dir}))
srch_ddir_c=($(find ${diff_dir} -type d | grep  ${srch_ddir_str}))

# FS dirs
srch_FS_str=($(basename ${FS_apas_in})) ; FS_dir=($(dirname ${FS_apas_in}))
srch_FS_c=($(find ${FS_dir} -type f | grep  ${srch_FS_str}))

# MSBP dirs
if [[ ${p_flag} -eq 0 ]] || [[ ${F_flag} -eq 0 ]] || [[ ${c_flag} -eq 0 ]] || [[ ${d_flag} -eq 0 ]]; then
	
    echo
    echo "Inputs to -s -f -d and -c must be set." >&2
    echo
    exit 2
	
else

    if [[ -z "${srch_FS_c}" ]]; then
    
        echo
        echo " Incorrect path to the FS aparc+aseg, please check the path and name "
        echo
        exit 2

    fi

    if [[ -z "${srch_ddir_c}" ]]; then

        echo
        echo " Incorrect path to the diffusion data dir, please check the dir path and name "
        echo
        exit 2

    fi

    if [[ -z "${srch_conf_c}" ]]; then

        echo
        echo " Incorrect config file, please check the path and name "
        echo
        exit 2

    fi

    if [[ ! ${d_dir} == *"${subj}"* ]] || [[ ! ${FS_dir} == *"${subj}"* ]]; then

        echo
        echo " Subject string does not match input files, please double check your inputs "
        echo
        exit 2

    else

        if [[ ! -z ${ses} ]]; then

            if [[ ! ${d_dir} == *"ses-${ses}"* ]] || [[ ! ${FS_dir} == *"ses-${ses}"* ]]; then

                echo
                echo " Session string does not match input files, please double check your inputs "
                echo
                exit 2

            fi

        fi

    fi

    echo "Inputs are -p  ${subj} -s ${ses} -c  ${conf_f} -d ${d_dir}  -F ${FS_dir} "

fi

# set this manually for debugging
# this is now searching for the genVOIs script
function_path=($(which KUL_FWT_make_VOIs.sh | rev | cut -d"/" -f2- | rev))
mrtrix_path=($(which mrmath | rev | cut -d"/" -f3- | rev))

if [[  -z  ${function_path}  ]]; then

    echo "update function path to reflect function name line 215"
    # exit 2

else

    echo " KUL_FWT lives in ${function_path} "

fi

# deal with scan sessions

if [[ -z ${s_flag} ]]; then

    # no session flag defined
    ses_str="";
    ses_str_dir="";

elif [[ ${s_flag} -eq 1 ]]; then

    # this is fine
    ses_str="_ses-${ses}";
    ses_str_dir="/ses-${ses}/";

fi

# REST OF SETTINGS ---

# Some parallelisation

if [[ "$n_flag" -eq 0 ]]; then

	ncpu=6

	echo " -n flag not set, using default 6 threads. "

else

	echo " -n flag set, using " ${ncpu} " threads."

fi

FSLPARALLEL=$ncpu; export FSLPARALLEL
OMP_NUM_THREADS=$ncpu; export OMP_NUM_THREADS

# Priors dir and check
## change the temps dir name later
pr_d="${function_path}/KUL_FWT_templates"

if [[ ! -d ${pr_d} ]]; then

    echo "KUL_FWT priors directory not found where expected, exiting"
    exit 2

fi

# handle the dirs

cd ${cwd}

# handle output and processing dirs

if [[ "$o_flag" -eq 1 ]]; then

    output_d="${out_dir}"

else

    output_d="${cwd}/sub-${subj}${ses_str}_KUL_FWT_output"

fi

# output sub-dirs

ROIs_d="${output_d}/sub-${subj}${ses_str}_VOIs"

prep_d="${output_d}/sub-${subj}${ses_str}_prep"

# make your dirs

mkdir -p ${output_d} >/dev/null 2>&1

mkdir -p ${prep_d} >/dev/null 2>&1

mkdir -p ${ROIs_d} >/dev/null 2>&1

mkdir -p "${ROIs_d}/custom_VOIs" >/dev/null 2>&1

# make your log file

prep_log2="${output_d}/KUL_FWT_VOIs_GT_log_${subj}_${d}.txt";


if [[ ! -f ${prep_log2} ]] ; then

    touch ${prep_log2}

else

    echo "${prep_log2} already created"

fi

# set mrtrix tmp dir to prep_d

rm -rf ${prep_d}/tmp_ims_*

tmpo_d=($(find ${prep_d} -type d -name *"tmp_ims_"*))

if [[ -z ${tmpo_d} ]]; then

    tmpo_d="${prep_d}/tmp_ims_${d}"

fi

mkdir -p "${tmpo_d}" >/dev/null 2>&1

export MRTRIX_TMPFILE_DIR="${tmpo_d}"

# report pid

processId=$(ps -ef | grep 'ABCD' | grep -v 'grep' | awk '{ printf $2 }')
echo $processId

echo "KUL_FWT_make_VOIs_4Temp.sh @ ${d} with parent pid $$ and process pid $BASHPID " | tee -a ${prep_log2}
echo "Inputs are -p  sub-${subj} -s ses-${ses} -c  ${conf_f} -d ${d_dir}  -F ${FS_dir} " | tee -a ${prep_log2}

# read the config file
# if a hash is found this cell is populated with ##

declare -a tck_lst1

declare -a tck_list

declare -a nosts_list

# tck_lst1=($(cat  ${conf_f}))

IFS=$'\n' read -d '' -r -a tck_lst1 < ${conf_f}

for i in ${!tck_lst1[@]}; do

    if [[ ${tck_lst1[$i]} == *"#"* ]]; then

        tck_list[$i]="none"

    else

        # tck_list[$i]=${tck_lst1[$i]}
        tck_list[$i]=$(echo ${tck_lst1[$i]} | cut -d ',' -f1)
        # test to make sure tck_list[$i] contains a string
        if [[ ${tck_list[$i]} =~ ^[+-]?[0-9]+$ ]]; then 
            echo " there is a problem with config file, first column does not contain a string" 
            exit 2
        fi

        nosts_list[$i]=$(echo ${tck_lst1[$i]} | cut -d ',' -f2)
        # test to make sure nosts_list[$i] contains a number
        if [[ ! ${nosts_list[$i]} =~ ^[+-]?[0-9]+$ ]]; then 
            echo " there is a problem with config file, second column does not contain numbers" 
            exit 2
        fi

    fi

done

# unset tcks_lst1

# now echo this

echo "You have asked to segment the following bundles from whole brain TCK ${tck_list[@]}" | tee -a ${prep_log2}

# Exec_all function
# need to recreate this function to include proc. control

function task_exec {

    echo "-------------------------------------------------------------" | tee -a ${prep_log2}

    echo ${task_in} | tee -a ${prep_log2}

    echo " Started @ $(date "+%Y-%m-%d_%H-%M-%S")" | tee -a ${prep_log2}

    # Run via process substitution (not a literal pipe to tee) so the PID/exit status we
    # capture below belong to the actual command, not to tee — a literal `cmd | tee &`
    # backgrounds the whole pipeline and `wait`/$? end up reflecting tee, not cmd.
    eval ${task_in} > >(tee -a "${prep_log2}") 2>&1 &

    pid=$!

    echo " pid = $pid " | tee -a ${prep_log2}

    wait "$pid"

    result=$?

    sleep 5

    echo "exit status $result" | tee -a ${prep_log2}

    if [ "$result" -eq 0 ]; then
        echo Success | tee -a ${prep_log2}
    else
        echo Fail | tee -a ${prep_log2}
    fi

    echo " Finished @ $(date "+%Y-%m-%d_%H-%M-%S")" | tee -a ${prep_log2}

    echo "-------------------------------------------------------------" | tee -a ${prep_log2}

    echo "" | tee -a ${prep_log2}

    unset task_in

    if [ "$result" -ne 0 ]; then
        exit 1
    fi

}

function KUL_wait_all_bg_and_check {
    # Wait for every currently-outstanding background job (e.g. several `task_exec &`
    # calls launched without an individual wait) and report failure if any of them failed.
    # Used right before writing a .done marker, so a job that failed "silently" from the
    # caller's perspective (task_exec's own `exit 1` only kills its own subshell) doesn't
    # let the marker get written anyway.
    local _fail=0
    local _j
    for _j in $(jobs -p); do
        wait "$_j" || _fail=1
    done
    return $_fail
}

# script start here
# part 1 of this workflow is general purpose and should be run for all bundles
# use processing control

# find your priors
# all priors are in MNI space

UKBB_temp=($(find ${pr_d} -type f -name "T1_preunbiased.nii.gz"))

UKBB_temp_mask=($(find ${pr_d} -type f -name "T1_UKBB_brain_mask.nii.gz"))

UKBB_labels="${pr_d}/UKBB_BStem_VOIs_comb.nii.gz" # done
# these would benefit from a propagate labels step probably

JHU_labels="${pr_d}/JHU_WM_labels.nii.gz" # done

JuHA_labels="${pr_d}/Juelich_GNs_inMNI.nii.gz" # done

Man_VOIs="${pr_d}/Manual_VOIs.nii.gz" # done

PD25="${pr_d}/PD25_hist_1mm_RLinMNI.nii.gz" # done

SUIT="${pr_d}/SUIT_atlas_inMNI.nii.gz" # done

CIT="${pr_d}/CIT168toMNI152_prob_atlas_bilat_1mm_STN.nii.gz" # done

DISTAL_STN="${pr_d}/DISTAL_STN_motor_bilateral_in_FSL_6thgen_symm.nii.gz" # done

TMP_BStem="${pr_d}/Temp_BStem_labels.nii.gz" # done

RL_VOIs="${pr_d}/RL_hemi_masks.nii.gz" # done

####

# these we create
# will probably need some for the tckseg script

# fix the name of this file to be FOD2T1
sub_FOD_in_T1="${prep_d}/sub-${subj}${ses_str}_FA2T1brainMS_Warped.nii.gz"

sub_T1inFOD="${prep_d}/sub-${subj}${ses_str}_T1brain_MSinFOD_Warped.nii.gz"

T1_brain_mask_in_FOD="${prep_d}/sub-${subj}${ses_str}_T1bm_MSinFOD_Warped.nii.gz"

FS_csf_mask="${prep_d}/sub-${subj}${ses_str}_FS_CSF_mask.nii.gz"

FS_csf_mask_binv="${ROIs_d}/custom_VOIs/sub-${subj}${ses_str}_FS_CSF_mask_binv.nii.gz"

T1_BM_in_FOD_minCSF="${prep_d}/sub-${subj}${ses_str}_T1bm_MSinFOD_minCSF.nii.gz"

RL_in_FOD="${prep_d}/sub-${subj}${ses_str}_RL_masks_inFOD.nii.gz"

PD25_in_FOD="${prep_d}/sub-${subj}${ses_str}_PD25_histological_inFOD.nii.gz"

SUIT_in_FOD="${prep_d}/sub-${subj}${ses_str}_SUIT_cerebellar_atlas_inFOD.nii.gz"

CIT_in_FOD="${prep_d}/sub-${subj}${ses_str}_CIT_inFOD.nii.gz"

DISTAL_STN_in_FOD="${prep_d}/sub-${subj}${ses_str}_DISTAL_STN_inFOD.nii.gz"

TMP_BStem_in_FOD="${prep_d}/Temp_BStem_labels_in_FOD.nii.gz" # done

UKBB_in_FOD="${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFOD.nii.gz"

JuHA_in_FOD="${prep_d}/sub-${subj}${ses_str}_Juelich_VOIs_inFOD.nii.gz"

JHU_in_FOD="${prep_d}/sub-${subj}${ses_str}_JHU_VOIs_inFOD.nii.gz"

Man_VOIs_in_FOD="${prep_d}/sub-${subj}${ses_str}_Manual_VOIs_inFOD.nii.gz"

subj_aparc_in_FOD="${prep_d}/sub-${subj}${ses_str}_aparc_inFOD.nii.gz"

subj_aseg_in_FOD="${prep_d}/sub-${subj}${ses_str}_aseg_inFOD.nii.gz"

subj_FS_WMaparc_in_FOD="${prep_d}/sub-${subj}${ses_str}_WMaparc_inFOD.nii.gz"

subj_MSsc3_in_FOD="${prep_d}/sub-${subj}${ses_str}_MSBP_scale3_inFOD.nii.gz"

CFP_aparc_in_FOD="${prep_d}/sub-${subj}${ses_str}_LC+spine_inFOD.nii.gz"

# subj_MSsc1_in_FOD_uint8="${prep_d}/sub-${subj}${ses_str}_MSBP_scale1_in_FOD_uint8.nii.gz"

subj_FS_lobes_in_FOD="${prep_d}/sub-${subj}${ses_str}_FS_lobes_inFOD.nii.gz"

subj_FS_2009_in_FOD="${prep_d}/sub-${subj}${ses_str}_FS_2009_inFOD.nii.gz"

subj_FS_Fx_in_FOD="${prep_d}/sub-${subj}${ses_str}_FS_fornix_inFOD.nii.gz"

##

# parallel breaks
qo=4;

function PD25_lab_gen {

    PD25_labels_LT=("PD25_DM_LT" "PD25_DL_LT" "PD25_VA_LT" "PD25_VL_LT" "PD25_VPL_LT" "PD25_VPM_LT" "PD25_Pulvi_LT" \
    "PD25_MG_LT" "PD25_RN_LT");

    PD25_labels_RT=("PD25_DM_RT" "PD25_DL_RT" "PD25_VA_RT" "PD25_VL_RT" "PD25_VPL_RT" "PD25_VPM_RT" "PD25_Pulvi_RT" \
    "PD25_MG_RT" "PD25_RN_RT");

    PD25_vals_RT=("37" "40" "53" "26" "28" "36" "89" \
    "86" "87" "88" "90" "91" "92" "93" "94" "104" \
    "111" "112" "114" "120" "123" "96" "97" "98" \
    "115" "117" "118" "95" "113" \
    "102" "103" "105" "106" "107" "116" "119" "68" "48");

    PD25_vals_LT=("3700" "4000" "5300" "2600" "2800" "3600" "8900" \
    "8600" "8700" "8800" "9000" "9100" "9200" "9300" "9400" "10400" \
    "11100" "11200" "11400" "12000" "12300" "9600" "9700" "9800" \
    "11500" "11700" "11800" "9500" "11300" \
    "10200" "10300" "10500" "10600" "10700" "11600" "11900" "6800" "4800");

    # this should be 36 entries per side + RNs
    # vals outnumber labels, as each nucleus (label) constitutes
    # multiple ROIs from the atlas

    srch_PD25Ls=($(find ${ROIs_d}/custom_VOIs -type f | grep "PD25_VPALPLPM_RT_custom.nii.gz"))

    if [[ ! ${srch_PD25Ls} ]]; then

        qs=0;

        for hl in ${!PD25_vals_LT[@]}; do

            ((qs++))
            ((qs=${qs}%${qo}))

            echo " separating PD25_LT ROIs" >> ${prep_log2}

            # isolate rois

            task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${PD25_in_FOD} ${FS_csf_mask_binv} -mult ${PD25_vals_LT[$hl]} \
            -eq ${tmpo_d}/PD25_ROI_${PD25_vals_LT[$hl]}_LT_custom.nii.gz" 
            
            task_exec &

            if [[ ${qs} == 0 ]]; then

                wait

            fi

        done

        # sleep 200

        wait

        # unset hl

        qs=0;

        for hr in ${!PD25_vals_RT[@]}; do

            ((qs++))
            ((qs=${qs}%${qo}))

            echo " separating PD25_RT ROIs" >> ${prep_log2}

            # isolate rois

            task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${PD25_in_FOD} ${FS_csf_mask_binv} -mult ${PD25_vals_RT[$hr]} \
            -eq ${tmpo_d}/PD25_ROI_${PD25_vals_RT[$hr]}_RT_custom.nii.gz" 
            
            task_exec &

            if [[ ${qs} == 0 ]]; then

                wait
                
            fi

        done

        wait

        sleep 50

        # unset hr

        # make nuclei

        echo " Creating PD25 derived thalamic VOIs " >> ${prep_log2}

        ##################

        VA_rois_RT=("26" "28" "36" "89");
        VA_rois_LT=("2600" "2800" "3600" "8900");
        VL_rois_RT=("86" "87" "88" "90" "91" "92" "93" "94" "104" \
        "111" "112" "114" "120" "123");
        VL_rois_LT=("8600" "8700" "8800" "9000" "9100" "9200" "9300" "9400" "10400" \
        "11100" "11200" "11400" "12000" "12300");
        VPL_rois_RT=("96" "97" "98" "115" "117" "118");
        VPL_rois_LT=("9600" "9700" "9800" "11500" "11700" "11800");
        VPM_rois_RT=("95" "113");
        VPM_rois_LT=("9500" "11300");
        PUL_rois_RT=("102" "103" "105" "106" "107" "116" "119");
        PUL_rois_LT=("10200" "10300" "10500" "10600" "10700" "11600" "11900");

        # Isolate the thalamus from the aparc
        # We use this to refine PD25 thalamic VOIs
        task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 10 -eq 0 -gt ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 49 -eq 0 -gt ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz"

        task_exec

        # DM
        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_37_RT_custom.nii.gz ${tmpo_d}/PD25_ROI_40_RT_custom.nii.gz \
        -add 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_DM_RT_custom.nii.gz -force"
        task_exec &

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_3700_LT_custom.nii.gz ${tmpo_d}/PD25_ROI_4000_LT_custom.nii.gz \
        -add 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_DM_LT_custom.nii.gz -force"
        task_exec &

        #################################

        # DL
        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_53_RT_custom.nii.gz 0.5 -gt  - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - \
        0.5 -gt ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_DL_RT_custom.nii.gz"
        task_exec &

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_5300_LT_custom.nii.gz 0.5 -gt  - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - \
        0.5 -gt ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_DL_LT_custom.nii.gz"
        task_exec &

        #################################

        # VA
        VA_adds_RT=$(printf " ${tmpo_d}/PD25_ROI_%s_RT_custom.nii.gz -add"  "${VA_rois_RT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_26_RT_custom.nii.gz ${tmpo_d}/PD25_ROI_28_RT_custom.nii.gz -add \
        ${VA_adds_RT} 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VA_RT_custom.nii.gz -force"
        task_exec

        VA_adds_LT=$(printf " ${tmpo_d}/PD25_ROI_%s_LT_custom.nii.gz -add"  "${VA_rois_LT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_2600_LT_custom.nii.gz ${tmpo_d}/PD25_ROI_2800_LT_custom.nii.gz -add \
        ${VA_adds_LT} 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VA_LT_custom.nii.gz -force"
        task_exec

        #################################

        # VL
        VL_adds_RT=$(printf " ${tmpo_d}/PD25_ROI_%s_RT_custom.nii.gz -add"  "${VL_rois_RT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_86_RT_custom.nii.gz ${tmpo_d}/PD25_ROI_87_RT_custom.nii.gz -add \
        ${VL_adds_RT} 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VL_RT_custom.nii.gz -force"
        task_exec &

        VL_adds_LT=$(printf " ${tmpo_d}/PD25_ROI_%s_LT_custom.nii.gz -add"  "${VL_rois_LT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_8600_LT_custom.nii.gz ${tmpo_d}/PD25_ROI_8700_LT_custom.nii.gz -add \
        ${VL_adds_LT} 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VL_LT_custom.nii.gz -force"
        task_exec &

        #################################

        # VPL
        VPL_adds_RT=$(printf " ${tmpo_d}/PD25_ROI_%s_RT_custom.nii.gz -add"  "${VPL_rois_RT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_96_RT_custom.nii.gz ${tmpo_d}/PD25_ROI_97_RT_custom.nii.gz -add \
        ${VPL_adds_RT} 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VPL_RT_custom.nii.gz -force"
        task_exec &

        VPL_adds_LT=$(printf " ${tmpo_d}/PD25_ROI_%s_LT_custom.nii.gz -add"  "${VPL_rois_LT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_9600_LT_custom.nii.gz ${tmpo_d}/PD25_ROI_9700_LT_custom.nii.gz -add \
        ${VPL_adds_LT} 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VPL_LT_custom.nii.gz -force"
        task_exec &

        #################################

        # VPM
        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_95_RT_custom.nii.gz ${tmpo_d}/PD25_ROI_113_RT_custom.nii.gz -add \
        0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VPM_RT_custom.nii.gz -force"
        task_exec

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_9500_LT_custom.nii.gz ${tmpo_d}/PD25_ROI_11300_LT_custom.nii.gz -add \
        0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_VPM_LT_custom.nii.gz -force"
        task_exec

        #################################

        # Pulvi
        # switched to -npass 2 dilation with maskfilter from mrfilter only for the pulvies
        PUL_adds_RT=$(printf " ${tmpo_d}/PD25_ROI_%s_RT_custom.nii.gz -add"  "${PUL_rois_RT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_102_RT_custom.nii.gz ${tmpo_d}/PD25_ROI_103_RT_custom.nii.gz -add \
        ${PUL_adds_RT} 0.5 -gt - | maskfilter - dilate -npass 1 - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_Pulvi_RT_custom.nii.gz -force"
        task_exec &

        PUL_adds_LT=$(printf " ${tmpo_d}/PD25_ROI_%s_LT_custom.nii.gz -add"  "${PUL_rois_LT[@]:2}")

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_10200_LT_custom.nii.gz ${tmpo_d}/PD25_ROI_10300_LT_custom.nii.gz -add \
        ${PUL_adds_LT} 0.5 -gt - | maskfilter - dilate -npass 1 - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_Pulvi_LT_custom.nii.gz -force"
        task_exec &

        #################################

        # # MG
        # task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_68_RT_custom.nii.gz 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        # ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_MG_RT_custom.nii.gz -force"
        # task_exec &

        # task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_6800_LT_custom.nii.gz 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        # ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz -mult ${ROIs_d}/custom_VOIs/PD25_MG_LT_custom.nii.gz -force"
        # task_exec &

        #################################

        # Red Nucleus
        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_48_RT_custom.nii.gz 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/PD25_RN_RT_custom.nii.gz -force"
        task_exec

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${tmpo_d}/PD25_ROI_4800_LT_custom.nii.gz 0.5 -gt - | mrfilter - smooth - | maskfilter - connect -largest -connectivity - | mrcalc -force -datatype uint16 - 0.5 -gt \
        ${ROIs_d}/custom_VOIs/PD25_RN_LT_custom.nii.gz -force"
        task_exec

        ###

        # this will be used for the ORs, ML and the thalamic radiations

        task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${ROIs_d}/custom_VOIs/PD25_VA_LT_custom.nii.gz ${ROIs_d}/custom_VOIs/PD25_VL_LT_custom.nii.gz -add 0.5 -gt ${ROIs_d}/custom_VOIs/PD25_VA_VL_LT_custom.nii.gz && \
        mrcalc -force -datatype uint16 -force -nthreads 1 ${ROIs_d}/custom_VOIs/PD25_VPL_LT_custom.nii.gz ${ROIs_d}/custom_VOIs/PD25_VPM_LT_custom.nii.gz -add 0.5 -gt ${ROIs_d}/custom_VOIs/PD25_VPL_VPM_LT_custom.nii.gz && \
        mrcalc -force -datatype uint16 -force -nthreads 1 ${ROIs_d}/custom_VOIs/PD25_VA_VL_LT_custom.nii.gz ${ROIs_d}/custom_VOIs/PD25_VPL_VPM_LT_custom.nii.gz -add 0.5 -gt ${ROIs_d}/custom_VOIs/PD25_VPALPLPM_LT_custom.nii.gz \
        && mrcalc -force -datatype uint16 -force -nthreads 1 ${ROIs_d}/custom_VOIs/PD25_VA_RT_custom.nii.gz ${ROIs_d}/custom_VOIs/PD25_VL_RT_custom.nii.gz -add 0.5 -gt ${ROIs_d}/custom_VOIs/PD25_VA_VL_RT_custom.nii.gz && \
        mrcalc -force -datatype uint16 -force -nthreads 1 ${ROIs_d}/custom_VOIs/PD25_VPL_RT_custom.nii.gz ${ROIs_d}/custom_VOIs/PD25_VPM_RT_custom.nii.gz -add 0.5 -gt ${ROIs_d}/custom_VOIs/PD25_VPL_VPM_RT_custom.nii.gz && \
        mrcalc -force -datatype uint16 -force -nthreads 1 ${ROIs_d}/custom_VOIs/PD25_VA_VL_RT_custom.nii.gz ${ROIs_d}/custom_VOIs/PD25_VPL_VPM_RT_custom.nii.gz -add 0.5 -gt ${ROIs_d}/custom_VOIs/PD25_VPALPLPM_RT_custom.nii.gz"

        task_exec


    else

        echo "PD25 labels already warped to subject space, skipping " >> ${prep_log2}

    fi

}

# initial vars

subj_fod=($(find ${d_dir} -type f -name "fod_template.mif"))

temp_fod1=($(find ${d_dir} -type f -name "fod_template_firstvol.nii.gz"))

subj_dwi_bm=($(find ${d_dir} -type f -name "fod_temp_mask.nii.gz"))

# find label images 

subj_aparc_mgz=($(find ${FS_dir} -type f -name "aparc+aseg.mgz"))

subj_aseg_mgz=($(find ${FS_dir} -type f -name "aseg.mgz"))

subj_aparc_nii="${prep_d}/sub-${subj}${ses_str}_aparc+aseg.nii.gz"

subj_aseg_nii="${prep_d}/sub-${subj}${ses_str}_aseg.nii.gz"

subj_LS3_mgz="${FS_dir}/mri/lausanne2018.scale3+aseg.mgz"
subj_LS3_nii="${prep_d}/sub-${subj}${ses_str}_lausanne2018_scale3.nii.gz"
subj_bss_mgz="${FS_dir}/mri/brainstemSsLabels.mgz"
subj_bss_nii="${prep_d}/sub-${subj}${ses_str}_brainstemSs.nii.gz"
subj_hypo_mgz="${FS_dir}/mri/hypothalamic_subunits_seg.v1.mgz"
subj_hypo_nii="${prep_d}/sub-${subj}${ses_str}_hypothalamic_subunits.nii.gz"

subj_FS_lobes=($(find ${FS_dir} -type f -name "sub-${subj}${ses}_lobes.mgz"))

subj_FS_2009=($(find ${FS_dir} -type f -name "aparc.a2009s+aseg.mgz"))

subj_FS_Fx=($(find ${FS_dir} -type f -name "sub-${subj}${ses_str}_Fx_aseg.mgz"))

subj_FS_WMaparc=($(find ${FS_dir} -type f -name "wmparc.mgz"))

subj_FS_brain=($(find ${FS_dir} -type f -name "brain.nii.gz"))

subj_FS_bm=($(find ${FS_dir} -type f -name "brainmask.nii.gz"))

##

temp2subj_str="FS_2_UKBB_${subj}${ses_str}"

temp2subj="${prep_d}/${temp2subj_str}"

FOD2FS_str="${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}"

# split the JuHA labels apart already
GNs=("LGN_RT" "LGN_LT" "MGN_RT" "MGN_LT");

# find your dwis
# needs to be made to fit only the FOD_template

# find FODs

if [[ -z ${subj_fod} ]]; then

    subj_fod=($(find ${d_dir} -type f -name "*fod_template.mif"))

    if [[ -z ${subj_fod} ]]; then

        echo "no FODs found, quitting" | tee -a ${prep_log2}
        exit 2

    fi

fi

# find diff brain mask

if [[ ! -f ${subj_dwi_bm} ]]; then

    subj_dwi_bm=($(find ${d_dir} -type f -name "*fod_temp_mask.nii.gz"))

    if [[ ! -f ${subj_dwi_bm} ]]; then

        echo "no dwi brain mask found, quitting" | tee -a ${prep_log2}
        exit 2

    fi

fi

pt1_done="${ROIs_d}/Part1.done"

srch_pt1_done=($(find ${ROIs_d} -not -path '*/\.*' -type f | grep "Part1.done"))

if [[ -z ${srch_pt1_done} ]]; then

    echo " general purpose steps "

    # subject dwi inputs
    # find dwis, fods, and make dt, and derivatives if not found
    # these strings are currently hardcoded to work with KUL_NITs output
    # and the HCP data we've preproced
    # right now the FA being used is not the right one
    # must handle multiple instances, in case KUL_dwiprep_2_MNI has been applied - on it
    # we assume the T1s and dMRIs are already registered right?

    if [[ ! -f ${subj_aparc_mgz} ]] || [[ ! -f ${subj_LS3_mgz} ]]; then

        echo " aparc+aseg.mgz or lausanne2018.scale3+aseg.mgz not found in FS directory, quitting "
        exit 2

    fi

    if [[ ! -f ${subj_bss_mgz} ]]; then

        echo " brainstemSsLabels.mgz not found in FS directory, quitting "
        exit 2

    fi

    if [[ ! -f ${subj_hypo_mgz} ]]; then

        echo " hypothalamic_subunits_seg.v1.mgz not found in FS directory, quitting "
        exit 2

    fi

    # look for the FS lobes segmentation
    # avoid WarpImageMultiTransform use antsApplyTransforms instead

    if [[ ! -f ${subj_FS_lobes} ]]; then

        echo " Making FS lobes segmentation image in .mgz"  | tee -a ${prep_log2}

        subj_FS_lobes="${FS_dir}/sub-${subj}${ses}_lobes.mgz"

        task_in="mri_annotation2label --subject sub-${subj}${ses_str} --sd ${FS_dir}/../.. --hemi lh --lobesStrict lobes \
        && mri_annotation2label --subject sub-${subj}${ses_str} --sd ${FS_dir}/../.. --hemi rh --lobesStrict lobes"

        task_exec

        task_in="mri_aparc2aseg --s sub-${subj}${ses_str} --sd ${FS_dir}/../..  --rip-unknown  --volmask --o ${subj_FS_lobes}  --annot lobes --labelwm  --hypo-as-wm"

        task_exec

    else

        echo " FS Lobes map already generated, skipping"  | tee -a ${prep_log2}

    fi

    # fornix time

    srch_Fx_aseg=($(find ${FS_dir} -type f -name "sub-${subj}${ses_str}_Fx_aseg.mgz"))

    if [[ -z ${srch_Fx_aseg}  ]]; then

        # this generates a new CC and Fornix segmentation using the aseg.auto.noCCseg.mgz label file

        echo " FS fornix seg not found, generating" | tee -a ${prep_log2}

        subj_FS_Fx="${FS_dir}/sub-${subj}${ses_str}_Fx_aseg.mgz"

        task_in="mri_cc -aseg aseg.auto_noCCseg.mgz -o sub-${subj}${ses_str}_Fx_aseg.mgz -sdir ${FS_dir}/../.. -f -force sub-${subj}${ses_str}"

        task_exec

    else

        echo "FS fornix parcellation already done, skipping " | tee -a ${prep_log2}

    fi

    # if there is a lesion mask?
    # or do we always use the VBG filled brain in MSBP anyway?
    # the simpler antsRegSyN works better than giving also masks and using float precision

    temp2subj_str="FS_2_UKBB_${subj}${ses_str}"

    temp2subj="${prep_d}/${temp2subj_str}"

    if [[ ! -f "${temp2subj}_Warped.nii.gz" ]]; then

        echo "UKBB 2 Subj reg starting now" | tee -a ${prep_log2}

        task_in="antsRegistrationSyN.sh -d 3 -f ${UKBB_temp} -m ${subj_FS_brain} -x ${UKBB_temp_mask},${subj_FS_bm} -o ${temp2subj}_ -t s -n ${ncpu}"

        task_exec

    else 

        echo "Template warp to subject already done, skipping" | tee -a ${prep_log2}

    fi

    # Warp from FS brain to FOD template space
    # srch_FS2FA=($(find ${prep_d} -type f -name "sub-${subj}${ses_str}_FA2T1brainFS_Warped.nii.gz"))

    if [[ ! -f ${subj_FS_WMaparc_in_FOD}  ]]; then

        # this generates a new CC and Fornix segmentation using the aseg.auto.noCCseg.mgz label file

        echo " FS to FA warp not found, generating" | tee -a ${prep_log2}

        FOD2FS_str="${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}"

        if [[ ! -f "${FOD2FS_str}_template.nii.gz" ]]; then

            task_in="antsIntermodalityIntrasubject.sh -d 3 -i ${temp_fod1} -r ${subj_FS_brain} -x ${subj_FS_bm} -t 3 -w ${prep_d}/FS_2_UKBB_${subj}${ses_str}_ -T ${UKBB_temp} -o ${FOD2FS_str}_"

            task_exec

        fi

        # now all these become nonlinear
        task_in="antsApplyTransforms -d 3 -i ${subj_FS_lobes} -o ${subj_FS_lobes_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_2009} -o ${subj_FS_2009_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_Fx} -o ${subj_FS_Fx_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_WMaparc} -o ${subj_FS_WMaparc_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

    else

        echo "FS T1, lobes, and Fx warped to FA, skipping " | tee -a ${prep_log2}

    fi

    # Warp FS brain, brain mask, aparc+aseg, aseg, and lausanne scale3 to FOD template space

    if [[ ! -f ${T1_BM_in_FOD_minCSF} ]]; then

        echo "Warping FS volumes to FOD template space" | tee -a ${prep_log2}

        # convert FS label volumes to NIfTI for ANTs
        task_in="mri_convert ${subj_aparc_mgz} ${subj_aparc_nii} && mri_convert ${subj_aseg_mgz} ${subj_aseg_nii} && mri_convert ${subj_LS3_mgz} ${subj_LS3_nii} && mri_convert ${subj_bss_mgz} ${subj_bss_nii} && mri_convert ${subj_hypo_mgz} ${subj_hypo_nii}"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_brain} -o ${sub_T1inFOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_bm} -o ${T1_brain_mask_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_LS3_nii} -o ${subj_MSsc3_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        # Patch FS brainstem subfields into subj_MSsc3_in_FOD: remap 173(mid)→249, 174(pons)→250, 175(medulla)→251
        # Two-step replace: build patch image, then overwrite (not add) lausanne labels at those voxels.
        # Additive approach was wrong when lausanne scale3+aseg carries label 16 at brainstem voxels.
        task_in="antsApplyTransforms -d 3 -i ${subj_bss_nii} -o ${tmpo_d}/bss_in_FOD.nii.gz -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n NearestNeighbor \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
        ${tmpo_d}/bss_in_FOD.nii.gz 173 -eq 249 -mult \
        ${tmpo_d}/bss_in_FOD.nii.gz 174 -eq 250 -mult -add \
        ${tmpo_d}/bss_in_FOD.nii.gz 175 -eq 251 -mult -add \
        ${tmpo_d}/bss_patch_in_FOD.nii.gz \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
        ${subj_MSsc3_in_FOD} \
        ${tmpo_d}/bss_patch_in_FOD.nii.gz 0 -gt -not -mult \
        ${tmpo_d}/bss_patch_in_FOD.nii.gz -add \
        ${subj_MSsc3_in_FOD}"

        task_exec

        # Patch FS hypothalamic subunits into subj_MSsc3_in_FOD: remap L(801-805)→248, R(806-810)→124
        # Pre-clear step: lausanne label 248 incorrectly falls on 4th ventricle (CSF) and label 124
        # is absent. Zero both slots first so only FS-derived hypothalamus occupies them.
        task_in="antsApplyTransforms -d 3 -i ${subj_hypo_nii} -o ${tmpo_d}/hypo_in_FOD.nii.gz -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n NearestNeighbor \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
        ${subj_MSsc3_in_FOD} 248 -eq -not \
        ${subj_MSsc3_in_FOD} 124 -eq -not \
        -mult \
        ${subj_MSsc3_in_FOD} -mult \
        ${tmpo_d}/MSsc3_hypo_cleared_in_FOD.nii.gz \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
        ${tmpo_d}/hypo_in_FOD.nii.gz 801 -eq \
        ${tmpo_d}/hypo_in_FOD.nii.gz 802 -eq -add \
        ${tmpo_d}/hypo_in_FOD.nii.gz 803 -eq -add \
        ${tmpo_d}/hypo_in_FOD.nii.gz 804 -eq -add \
        ${tmpo_d}/hypo_in_FOD.nii.gz 805 -eq -add \
        248 -mult \
        ${tmpo_d}/hypo_in_FOD.nii.gz 806 -eq \
        ${tmpo_d}/hypo_in_FOD.nii.gz 807 -eq -add \
        ${tmpo_d}/hypo_in_FOD.nii.gz 808 -eq -add \
        ${tmpo_d}/hypo_in_FOD.nii.gz 809 -eq -add \
        ${tmpo_d}/hypo_in_FOD.nii.gz 810 -eq -add \
        124 -mult -add \
        ${tmpo_d}/hypo_patch_in_FOD.nii.gz \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
        ${tmpo_d}/MSsc3_hypo_cleared_in_FOD.nii.gz \
        ${tmpo_d}/hypo_patch_in_FOD.nii.gz 0 -gt -not -mult \
        ${tmpo_d}/hypo_patch_in_FOD.nii.gz -add \
        ${subj_MSsc3_in_FOD}"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_aparc_nii} -o ${subj_aparc_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_aseg_nii} -o ${subj_aseg_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        # Make the CSF inverse mask for downstream atlas masking
        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} -force -quiet ${subj_aseg_in_FOD} 4 0 -replace - | mrcalc -force -datatype uint16 - 43 0 -replace - | mrcalc -force -datatype uint16 - 24 0 \
        -replace - | mrcalc -force -datatype uint16 - 14 0 -replace - | mrcalc -force -datatype uint16 - 31 0 -replace - | mrcalc -force -datatype uint16 - 63 0 -replace - | mrcalc -force -datatype uint16 - 15 0 -replace 0 -gt \
        ${T1_brain_mask_in_FOD} -sub -1 -eq 0.9 -ge ${FS_csf_mask} -force && fslmaths ${FS_csf_mask} -binv ${FS_csf_mask_binv} \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} ${T1_brain_mask_in_FOD} ${FS_csf_mask_binv} -mult ${T1_BM_in_FOD_minCSF}"

        task_exec

    else

        echo "FS brain mask, aparc+aseg, aseg, and lausanne scale3 already warped to FOD template space, skipping" | tee -a ${prep_log2}

    fi

    # split the JuHA labels apart already
    GNs=("LGN_RT" "LGN_LT" "MGN_RT" "MGN_LT");

    if [[ ! -f ${ROIs_d}/priors_warped.done ]]; then

        ## UKBB VOIs

        # Limiting UKBB VOIs to Pons and providing eroded versions to use as excludes
        task_in="mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 16 -eq 0 -gt 1 -mult ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz \
        && mrcalc -force -datatype uint16 -force -quiet ${subj_MSsc3_in_FOD} 250 -eq 0 -gt ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz \
        && antsApplyTransforms -d 3 -i ${UKBB_labels} -o ${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFOD.nii.gz \
        -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFOD.nii.gz \
        ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz -mult ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz \
        && ImageMath 3 ${UKBB_in_FOD} PropagateLabelsThroughMask ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz 2 \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz 1 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/LT_CST_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/LT_CST_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/LT_CST_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu} \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz 3 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/RT_CST_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/RT_CST_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/RT_CST_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu} \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz 2 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/LT_ML_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/LT_ML_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/LT_ML_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu} \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz 4 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/RT_ML_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/RT_ML_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/RT_ML_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu}"

        task_exec &

        ## R/L labels also
        # right is 2 and left is 1
        task_in="antsApplyTransforms -d 3 -i ${RL_VOIs} -o ${RL_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel \
        && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${RL_in_FOD} 1 -eq ${ROIs_d}/custom_VOIs/Left_hemir_custom.nii.gz \
        && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${RL_in_FOD} 2 -eq ${ROIs_d}/custom_VOIs/Right_hemir_custom.nii.gz"
        task_exec &

        ## PD25
        task_in="antsApplyTransforms -d 3 -i ${PD25} -o ${PD25_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ##  SUIT
        task_in="antsApplyTransforms -d 3 -i ${SUIT} -o ${SUIT_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ##  CIT
        task_in="antsApplyTransforms -d 3 -i ${CIT} -o ${CIT_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ##  DISTAL_STN
        task_in="antsApplyTransforms -d 3 -i ${DISTAL_STN} -o ${DISTAL_STN_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n NearesNeighbor"
        task_exec &

        ##  TMP_Bstem
        task_in="antsApplyTransforms -d 3 -i ${TMP_BStem} -o ${TMP_BStem_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ## Manual VOIs
        task_in="antsApplyTransforms -d 3 -i ${Man_VOIs} -o ${Man_VOIs_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ## JHU VOIs
        task_in="antsApplyTransforms -d 3 -i ${JHU_labels} -o ${JHU_in_FOD} -r ${temp_fod1} -t [${FOD2FS_str}_0GenericAffine.mat,1] -t ${FOD2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ## Juelich Histological Atlas
        # using WarpTimeSeriesImage for this one
        task_in="WarpTimeSeriesImageMultiTransform 4 ${JuHA_labels} ${JuHA_in_FOD} -R ${temp_fod1} -i ${FOD2FS_str}_0GenericAffine.mat ${FOD2FS_str}_1InverseWarp.nii.gz -i ${temp2subj}_0GenericAffine.mat ${temp2subj}_1InverseWarp.nii.gz"
        task_exec

        # this one is made for the connectivity finger printing
        task_in="labelconvert -force ${subj_aparc_in_FOD} ${function_path}/FreeSurferColorLUT.txt \
        ${mrtrix_path}/share/mrtrix3/labelconvert/fs_default.txt - | mrcalc - 0 \
        `mrcalc -force ${ROIs_d}/custom_VOIs/UKBB_in_FOD_BStem_masked.nii.gz 84 -add 84 0 -replace - ` -replace -datatype uint8 -force ${CFP_aparc_in_FOD}"

        task_exec

        # use ncpu/4 to avoid flooding the CPU ;)
        for gn in {0..3}; do 

            task_in="mrcalc -force -datatype uint16 -force -nthreads $((ncpu/4)) `mrconvert -force -coord 3 ${gn} ${JuHA_in_FOD} - ` 25 -gt \
            - | maskfilter - connect ${ROIs_d}/custom_VOIs/JuHA_${GNs[$gn]}_custom.nii.gz -largest -force"
            task_exec &

        done

        # use the PD25 labels function
        PD25_lab_gen

        if KUL_wait_all_bg_and_check; then
            touch ${ROIs_d}/priors_warped.done && echo "Priors warping done" >> ${ROIs_d}/priors_warped.done
        else
            echo "ERROR: one or more background steps failed before priors_warped.done — not marking done" | tee -a ${prep_log2}
            exit 1
        fi

    else

        echo "Applying warps to template label maps already done, skipping " | tee -a ${prep_log2}

    fi

    if KUL_wait_all_bg_and_check; then
        touch ${pt1_done} && echo "Part 1 done" >> ${pt1_done}
    else
        echo "ERROR: one or more background steps failed before Part1.done — not marking done" | tee -a ${prep_log2}
        exit 1
    fi

else

    echo " Part 1 already done, skipping" | tee -a ${prep_log2}

fi

# this is for scil_reco_bundles
if [[ ! -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_Warped.nii.gz" ]]; then

    task_in="antsRegistrationSyN.sh -d 3 -f ${UKBB_temp} -m ${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_template.nii.gz -t a -n ${ncpu} -o ${prep_d}/MNI_2_MNI_${subj}${ses_str}_"

    task_exec

fi

# using last generated file
srch_tck_warp=($(find ${prep_d} -type f -name FS_2_UKBB_${subj}_inv_4TCKs.mif));
srch_tck_warp2=($(find ${prep_d} -type f -name FS_2_UKBB_${subj}_forward_4TCKs.mif));

if [[ -z ${srch_tck_warp} ]]; then

    # from https://community.mrtrix.org/t/registration-using-transformations-generated-from-other-packages/2259
    # we use this to transform TCKs to MNI
    # antsApplyTransforms needs to be applied in the opposite direction
    task_in="warpinit ${UKBB_temp} ${tmpo_d}/TCKs_iw_[].nii.gz -f"

    task_exec

    for wi in {0..2}; do 

        task_in="antsApplyTransforms -d 3 -i ${tmpo_d}/TCKs_iw_${wi}.nii.gz \
        -o ${tmpo_d}/TCKs_iw_w_${wi}.nii.gz -r ${temp_fod1} \
        -t [${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,1] \
        -t ${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_1InverseWarp.nii.gz \
        -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,1] \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1InverseWarp.nii.gz
        --default-value 2147483647"

        task_exec

    done

    task_in="warpcorrect ${tmpo_d}/TCKs_iw_w_[].nii.gz ${prep_d}/FS_2_UKBB_${subj}_inv_4TCKs.mif -force -marker 2147483647"

    task_exec

else

    echo "Generating backward warps already done, skipping " | tee -a ${prep_log2}

fi

if [[ -z ${srch_tck_warp2} ]]; then

    # from https://community.mrtrix.org/t/registration-using-transformations-generated-from-other-packages/2259
    # we use this to transform TCKs from MNI to native
    # antsApplyTransforms needs to be applied in the opposite direction
    task_in="warpinit ${temp_fod1} ${tmpo_d}/TCKs_w_[].nii.gz -f"

    task_exec

    for wi in {0..2}; do 

        task_in="antsApplyTransforms -d 3 -i ${tmpo_d}/TCKs_w_${wi}.nii.gz \
        -o ${tmpo_d}/TCKs_w_w_${wi}.nii.gz -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz \
        -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz \
        -t [${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        --default-value 2147483647"

        task_exec

    done

    task_in="warpcorrect ${tmpo_d}/TCKs_w_w_[].nii.gz ${prep_d}/FS_2_UKBB_${subj}_forward_4TCKs.mif -force -marker 2147483647"

    task_exec

else

    echo "Generating forward warps already done, skipping " | tee -a ${prep_log2}

fi

pt2_done="${ROIs_d}/Part2.done"

srch_pt2_done=($(find ${ROIs_d} -not -path '*/\.*' -type f | grep "Part2.done"))

if [[ -z ${srch_pt2_done} ]]; then

    ## Unseg_WM/JHU work-around starts here

    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 5001 -eq 0 -gt \
    `mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 5002 -eq 0 -gt - ` -add 0 -gt ${ROIs_d}/custom_VOIs/Unseg_WM_bil_FS_custom.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/Seg_unseg_WM_bil_FS.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/Unseg_WM_bil_FS_custom.nii.gz ${JHU_in_FOD}"

    task_exec

    # need to split them up again
    # LT PLIC is 20, LT ALIC is 18
    # RT PLIC is 19, RT ALIC is 17
    # frontal PV LT is 24, frontal PV RT is 23.
    # mid PV LT is 26, mid PV RT is 25.
    # pari PV LT is 28, pari PV RT is 27.
    # LFP PV LT is 42, LFP PV RT is 41.
    # M_periAt LT is 48, M_periAt RT is 47.

    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 5001 -eq 0 -gt ${ROIs_d}/custom_VOIs/Seg_unseg_WM_bil_FS.nii.gz -mult ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 5002 -eq 0 -gt ${ROIs_d}/custom_VOIs/Seg_unseg_WM_bil_FS.nii.gz -mult ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 18 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_ALIC_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 20 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_PLIC_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 22 -eq 0 -gt ${tmpo_d}/SegWM_LT_TOV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 24 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_FPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 26 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_MPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 28 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_PPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 30 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_TOpV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 40 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_PHi_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 42 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_LPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 44 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_mIPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz 48 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_LT_mTPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 17 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_ALIC_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 19 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_PLIC_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 21 -eq 0 -gt ${tmpo_d}/SegWM_RT_TOV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 23 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_FPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 25 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_MPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 27 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_PPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 29 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_TOpV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 39 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_PHi_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 41 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_LPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 43 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_mIPV_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz 47 -eq 0 -gt ${ROIs_d}/custom_VOIs/SegWM_RT_mTPV_custom.nii.gz"

    task_exec &

    # exit 2

    ## subdividing the STG WM

    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 224 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG1_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 225 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG2_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 226 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG3_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 227 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG4_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 228 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG5_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 3030 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG_LT_WM_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 100 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG1_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 101 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG2_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 102 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG3_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 103 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG4_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 104 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG5_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 4030 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG_RT_WM_FS.nii.gz"

    task_exec

    # found and fixed small bug here
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/STG1_LT_MSBP.nii.gz 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG2_LT_MSBP.nii.gz 2 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG3_LT_MSBP.nii.gz 3 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG4_LT_MSBP.nii.gz 4 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG5_LT_MSBP.nii.gz 5 -mult -` -replace ${ROIs_d}/custom_VOIs/STG5ps_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/STG1_RT_MSBP.nii.gz 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG2_RT_MSBP.nii.gz 2 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG3_RT_MSBP.nii.gz 3 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG4_RT_MSBP.nii.gz 4 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/STG5_RT_MSBP.nii.gz 5 -mult -` -replace ${ROIs_d}/custom_VOIs/STG5ps_RT_MSBP.nii.gz"

    task_exec

    # exit 2

    # switched to only STG5GMWM
    task_in="ImageMath 3 ${ROIs_d}/custom_VOIs/STG5ps_WM_LT_MSBP.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/STG_LT_WM_FS.nii.gz ${ROIs_d}/custom_VOIs/STG5ps_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/STG5ps_WM_LT_MSBP.nii.gz 5 -ge \
    `mrcalc -force -datatype uint16 -quiet -force ${ROIs_d}/custom_VOIs/STG5ps_LT_MSBP.nii.gz 5 -ge - ` -add 0 -gt \
    ${ROIs_d}/custom_VOIs/STG5_GMWM_LT_custom.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/STG5ps_WM_RT_MSBP.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/STG_RT_WM_FS.nii.gz ${ROIs_d}/custom_VOIs/STG5ps_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/STG5ps_WM_RT_MSBP.nii.gz 5 -ge \
    `mrcalc -force -datatype uint16 -quiet -force ${ROIs_d}/custom_VOIs/STG5ps_RT_MSBP.nii.gz 5 -ge - ` -add 0 -gt \
    ${ROIs_d}/custom_VOIs/STG5_GMWM_RT_custom.nii.gz"

    task_exec &

    # adding subsegmentation of the Fusiform WM
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 208 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi1_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 209 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi2_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 210 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi3_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 211 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi4_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 3007 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi_LT_WM_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 84 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi1_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 85 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi2_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 86 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi3_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 87 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi4_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 4007 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi_RT_WM_FS.nii.gz"

    task_exec

    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Fusi1_LT_MSBP.nii.gz 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Fusi2_LT_MSBP.nii.gz 2 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Fusi3_LT_MSBP.nii.gz 3 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Fusi4_LT_MSBP.nii.gz 4 -mult -` -replace \
    ${ROIs_d}/custom_VOIs/Fusi4ps_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Fusi1_RT_MSBP.nii.gz 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Fusi2_RT_MSBP.nii.gz 2 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Fusi3_RT_MSBP.nii.gz 3 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Fusi4_RT_MSBP.nii.gz 4 -mult -` -replace \
    ${ROIs_d}/custom_VOIs/Fusi4ps_RT_MSBP.nii.gz"

    task_exec

    task_in="ImageMath 3 ${ROIs_d}/custom_VOIs/Fusi4ps_WM_LT_MSBP.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/Fusi_LT_WM_FS.nii.gz ${ROIs_d}/custom_VOIs/Fusi4ps_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Fusi4ps_WM_LT_MSBP.nii.gz 4 -ge \
    `mrcalc -force -datatype uint16 -quiet -force ${ROIs_d}/custom_VOIs/Fusi4ps_LT_MSBP.nii.gz 4 -ge - ` -add 0 -gt \
    ${ROIs_d}/custom_VOIs/Fusi4_GMWM_LT_custom.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/Fusi4ps_WM_RT_MSBP.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/Fusi_RT_WM_FS.nii.gz ${ROIs_d}/custom_VOIs/Fusi4ps_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Fusi4ps_WM_RT_MSBP.nii.gz 4 -ge \
    `mrcalc -force -datatype uint16 -quiet -force ${ROIs_d}/custom_VOIs/Fusi4ps_RT_MSBP.nii.gz 4 -ge - ` -add 0 -gt \
    ${ROIs_d}/custom_VOIs/Fusi4_GMWM_RT_custom.nii.gz"

    task_exec & 

    ## Insular WM work-around
    # isolate the VOIs needed
    # switching to JHU labels for Insula subsegmentation as well

    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 3035 -eq  0 -gt ${ROIs_d}/custom_VOIs/Insula_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 4035 -eq 0 -gt ${ROIs_d}/custom_VOIs/Insula_WM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 1014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_GM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 3014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 2014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_GM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 4014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_WM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 1012 -eq 0 -gt ${ROIs_d}/custom_VOIs/LatOF_GM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_in_FOD} 3012 -eq 0 -gt ${ROIs_d}/custom_VOIs/LatOF_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 1035 -eq 0 -gt ${ROIs_d}/custom_VOIs/Insula_GM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 2035 -eq 0 -gt ${ROIs_d}/custom_VOIs/Insula_GM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 230 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins1_LT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 231 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins2_LT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 232 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins3_LT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 106 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins1_RT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 107 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins2_RT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_in_FOD} 108 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins3_RT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 18 -eq 0 -gt ${ROIs_d}/custom_VOIs/Amyg_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 54 -eq 0 -gt ${ROIs_d}/custom_VOIs/Amyg_RT_FS.nii.gz"

    task_exec

    # propagate the VOIs into Insular WM (level 1)
    # ${JHU_in_FOD} 2
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Insula_WM_LT_FS.nii.gz ${ROIs_d}/custom_VOIs/Insula_WM_RT_FS.nii.gz -add 0 -gt \
    ${ROIs_d}/custom_VOIs/Insula_WM_Bil_FS.nii.gz && ImageMath 3 ${ROIs_d}/custom_VOIs/Ins_seg_z_Bil_custom.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/Insula_WM_Bil_FS.nii.gz ${JHU_in_FOD}"

    task_exec

    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_Bil_custom.nii.gz ${ROIs_d}/custom_VOIs/Insula_WM_LT_FS.nii.gz -mult \
    ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_Bil_custom.nii.gz \
    ${ROIs_d}/custom_VOIs/Insula_WM_RT_FS.nii.gz -mult ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz"

    task_exec

    # break apart the labelled Insular WM
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 34 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_center_wm_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 33 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_center_wm_RT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 42 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_supL_wm_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 46 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_infL_wm_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 41 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_supL_wm_RT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 45 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_infL_wm_RT_custom.nii.gz \
    && maskfilter -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_center_wm_RT_custom.nii.gz dilate ${ROIs_d}/custom_VOIs/Ins_center_wm_RT_custom_dil1.nii.gz \
    && maskfilter -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_center_wm_LT_custom.nii.gz dilate ${ROIs_d}/custom_VOIs/Ins_center_wm_LT_custom_dil1.nii.gz"

    task_exec

    # more insular VOIs
    task_in="mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 18 -eq 0 -gt 0 \
    `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 24 -eq 0 -gt - ` -replace 0 \
    `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 26 -eq 0 -gt - ` -replace 0 \
    `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 28 -eq 0 -gt - ` -replace \
    ${ROIs_d}/custom_VOIs/Ins_IFOF_exc_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 19 -eq 0 -gt 0 \
    `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 23 -eq 0 -gt - ` -replace 0 \
    `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 25 -eq 0 -gt - ` -replace 0 \
    `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 27 -eq 0 -gt - ` -replace \
    ${ROIs_d}/custom_VOIs/Ins_IFOF_exc_RT_custom.nii.gz"
    # to be less strict we removed these 
    # `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 20 -eq 0 -gt - ` -replace 0 \
    # `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 21 -eq 0 -gt - ` -replace 0 \

    task_exec

    # propagate VOIs into the inf. subdivision of Insular WM
    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins1_LT_MS.nii.gz 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Ins2_LT_MS.nii.gz 2 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Ins3_LT_MS.nii.gz 3 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/MedOF_GM_LT_FS.nii.gz ${ROIs_d}/custom_VOIs/MedOF_GM_RT_FS.nii.gz -add 0 -gt 4 -mult -` \
    -replace 0 `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Amyg_LT_FS.nii.gz 5 -mult -` -replace ${ROIs_d}/custom_VOIs/Ins_dv2_VOIs_LT_custom.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz PropagateLabelsThroughMask ${ROIs_d}/custom_VOIs/Ins_center_wm_LT_custom_dil1.nii.gz \
    ${ROIs_d}/custom_VOIs/Ins_dv2_VOIs_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins1_RT_MS.nii.gz 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Ins2_RT_MS.nii.gz 2 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Ins3_RT_MS.nii.gz 3 -mult -` -replace 0 \
    `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/MedOF_GM_RT_FS.nii.gz ${ROIs_d}/custom_VOIs/MedOF_GM_RT_FS.nii.gz -add 0 -gt 4 -mult -` \
    -replace 0 `mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/Amyg_RT_FS.nii.gz 5 -mult -` -replace ${ROIs_d}/custom_VOIs/Ins_dv2_VOIs_RT_custom.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz PropagateLabelsThroughMask ${ROIs_d}/custom_VOIs/Ins_center_wm_RT_custom_dil1.nii.gz \
    ${ROIs_d}/custom_VOIs/Ins_dv2_VOIs_RT_custom.nii.gz"

    task_exec

    # break them apart again
    # this gives 3 subdivisions
    task_in="mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz 1 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg1_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz 2 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg2_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz 3 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg3_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz 4 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg4_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz 5 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg5_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz 1 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg1_RT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz 2 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg2_RT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz 3 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg3_RT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz 4 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg4_RT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -quiet -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz 5 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins_subseg5_RT_custom.nii.gz"

    task_exec

    # make custom UF exclude VOI
    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_LT_custom.nii.gz 32 0 -replace 46 0 -replace 34 0 -replace \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_LT_custom.nii.gz 1 -eq - ` -add 0 -gt \
    ${ROIs_d}/custom_VOIs/UF_Ins_exc_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_seg_z_RT_custom.nii.gz 31 0 -replace 45 0 -replace 33 0 -replace \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Ins_wm_subseg_RT_custom.nii.gz 1 -eq - ` -add 0 -gt \
    ${ROIs_d}/custom_VOIs/UF_Ins_exc_RT_custom.nii.gz"

    task_exec &

    ## Cerebellum from aparc+aseg LT GM - WM - RT GM - WM : "7"  "46"  "8"  "47"
    # FIX THIS! you're doing the BStem and Cerebellar exclude work twice!
    # simplify and unify while dilating the braistem+UKBB labels to be as permissive as possible for ML fibers
    # do not erode the cerebellar wm, rather dilate the bstem.
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${subj_aparc_in_FOD} 7 -eq 0 -gt 1 -mult 0 \
    `mrcalc -force -datatype uint16 -quiet ${subj_aparc_in_FOD} 8 -eq 0 -gt 1 -mult - ` -replace ${tmpo_d}/LT_cerebellum_GMWM.nii.gz
    && mrcalc -force -datatype uint16 -quiet ${subj_aparc_in_FOD} 46 -eq 0 -gt 1 -mult 0 \
    `mrcalc -force -datatype uint16 -quiet ${subj_aparc_in_FOD} 47 -eq 0 -gt 1 -mult - ` -replace ${tmpo_d}/RT_cerebellum_GMWM.nii.gz"
    task_exec

    task_in="maskfilter -force -nthreads ${ncpu} -npass 2 ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz dilate - | mrcalc - -neg 0 -ge ${tmpo_d}/BStemr_dilx2inv.nii.gz -force -nthreads ${ncpu} -datatype uint16 && mrcalc -datatype uint16 -force -quiet ${tmpo_d}/LT_cerebellum_GMWM.nii.gz ${tmpo_d}/BStemr_dilx2inv.nii.gz -mult 0 -gt ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz \
    && mrcalc -datatype uint16 -force -quiet ${tmpo_d}/RT_cerebellum_GMWM.nii.gz ${tmpo_d}/BStemr_dilx2inv.nii.gz -mult 0 -gt ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz && mrcalc -quiet -force -nthreads ${ncpu} -datatype uint16 ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz \
    ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz -add 0 -gt ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz"
    task_exec &

    # Hypothalamus LT (248 from FS hypothalamic subunits)
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} \
    `mrcalc -datatype uint16 -force -quiet ${subj_MSsc3_in_FOD} 248 -eq - ` 0.5 -gt \
    - | maskfilter - connect - -largest -connectivity -nthreads ${ncpu} | maskfilter - \
    dilate  ${ROIs_d}/custom_VOIs/hypothal_LT_excr_custom.nii.gz -force -nthreads ${ncpu}"
    task_exec &

    # Hypothalamus RT (124 from FS hypothalamic subunits)
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -quiet ${subj_MSsc3_in_FOD} 124 -eq - ` 0.5 -gt \
    - | maskfilter - connect - -largest -connectivity -nthreads ${ncpu} | maskfilter - \
    dilate  ${ROIs_d}/custom_VOIs/hypothal_RT_excr_custom.nii.gz -force -nthreads ${ncpu}"
    task_exec &

    # Hypothalamus + VentralDC LT (248+247) — contralateral exclusion for RT projection fibers
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -quiet ${subj_MSsc3_in_FOD} 248 -eq - | \
    mrcalc -force -datatype uint16 -quiet - ${subj_MSsc3_in_FOD} 247 -eq -add - ` 0.5 -gt \
    - | maskfilter - connect - -largest -connectivity -nthreads ${ncpu} | maskfilter - \
    dilate  ${ROIs_d}/custom_VOIs/hypothal_vDC_LT_excr_custom.nii.gz -force -nthreads ${ncpu}"
    task_exec &

    # Hypothalamus + VentralDC RT (124+123) — contralateral exclusion for LT projection fibers
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -quiet ${subj_MSsc3_in_FOD} 124 -eq - | \
    mrcalc -force -datatype uint16 -quiet - ${subj_MSsc3_in_FOD} 123 -eq -add - ` 0.5 -gt \
    - | maskfilter - connect - -largest -connectivity -nthreads ${ncpu} | maskfilter - \
    dilate  ${ROIs_d}/custom_VOIs/hypothal_vDC_RT_excr_custom.nii.gz -force -nthreads ${ncpu}"
    task_exec &

    # Make R and L Pontine excludes
    # pons mask already created
    task_in="maskfilter -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz dilate \
    - | mrcalc -force -datatype uint16 - ${ROIs_d}/custom_VOIs/Left_hemir_custom.nii.gz -subtract 0.5 -gt ${ROIs_d}/custom_VOIs/Bs_Pons_RT_custom.nii.gz \
    -force -nthreads ${ncpu} && maskfilter -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz \
    dilate - | mrcalc -force -datatype uint16 - ${ROIs_d}/custom_VOIs/Right_hemir_custom.nii.gz -subtract 0.5 -gt \
    ${ROIs_d}/custom_VOIs/Bs_Pons_LT_custom.nii.gz -force -nthreads ${ncpu}"
    task_exec

    # Split BStem into R/L
    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz \
    `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 247 -eq 0 -gt - ` -add ${ROIs_d}/custom_VOIs/Left_hemir_custom.nii.gz \
    -mult 0.5 -gt ${ROIs_d}/custom_VOIs/BStemr_exc_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz \
    `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 123 -eq 0 -gt - ` -add ${ROIs_d}/custom_VOIs/Right_hemir_custom.nii.gz \
    -mult 0.5 -gt ${ROIs_d}/custom_VOIs/BStemr_exc_RT_custom.nii.gz"
    task_exec &

    # make an exclude for SCPs
    task_in="maskfilter -force -quiet -npass 4 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Bs_Pons_LT_custom.nii.gz erode ${ROIs_d}/custom_VOIs/e4BsPons_LT_custom.nii.gz && maskfilter -force -quiet -npass 4 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Bs_Pons_RT_custom.nii.gz erode ${ROIs_d}/custom_VOIs/e4BsPons_RT_custom.nii.gz"
    task_exec &

    # CC all
    # fslmaths is simpler here
    task_in="fslmaths ${subj_aparc_in_FOD} -thr 250 -uthr 255 ${ROIs_d}/custom_VOIs/CC_allr_custom.nii.gz"
    task_exec &

    # Thalami eroded
    # values for basal ganglia + thalami from FS aparc+aseg
    # "Amyg_LT"  "Amyg_RT"  "Put_LT"  "Put_RT"  "Pall_LT"  "Pall_RT"  \
    # "Thal_LT"  "Thal_RT"  "Caud_LT"  "Caud_RT"  \
    # \
    # "18"  "54"  "12"  "51"  "13"  "52" \
    # "10"  "49"  "11"  "50"  \

    # eroded Thalamus labels
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_in_FOD} 10 -eq 0 -gt - | maskfilter - erode \
    ${ROIs_d}/custom_VOIs/Thal_LT_ero2_custom.nii.gz -npass 2 -quiet -nthreads ${ncpu} -force && mrcalc -force -datatype uint16 -quiet -force \
    -nthreads ${ncpu} ${subj_aparc_in_FOD} 49 -eq 0 -gt - | maskfilter - erode \
    ${ROIs_d}/custom_VOIs/Thal_RT_ero2_custom.nii.gz -npass 2 -quiet -force -nthreads ${ncpu}"
    task_exec &

    # smoothed and eroded Putamen labels
    task_in="mrfilter -force -nthreads ${ncpu} -quiet `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 12 -eq 0 -gt - ` \
    smooth -fwhm 3 - | mrcalc -force -datatype uint16 - 0.15 -ge ${ROIs_d}/custom_VOIs/s3Put_LT_custom.nii.gz -force -nthreads ${ncpu} -quiet \
    && mrfilter -force -nthreads ${ncpu} -quiet `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 51 -eq 0 -gt - ` \
    smooth -fwhm 3 - | mrcalc -force -datatype uint16 - 0.15 -ge ${ROIs_d}/custom_VOIs/s3Put_RT_custom.nii.gz -force -nthreads ${ncpu} -quiet \
    && maskfilter `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 12 -eq 0 -gt - ` erode ${ROIs_d}/custom_VOIs/e2Put_LT_custom.nii.gz -npass 2 -force -nthreads ${ncpu} \
    && maskfilter `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 51 -eq 0 -gt - ` erode ${ROIs_d}/custom_VOIs/e2Put_RT_custom.nii.gz -npass 2 -force -nthreads ${ncpu}"
    task_exec &

    # eroded caudate VOIs
    task_in="maskfilter -force -nthreads ${ncpu} `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_in_FOD} 11 -eq 0 -gt - ` \
    erode ${ROIs_d}/custom_VOIs/Caud_ero_LT_custom.nii.gz && maskfilter -force -nthreads ${ncpu} `mrcalc -force -datatype uint16 -quiet \
    -force ${subj_aparc_in_FOD} 50 -eq 0 -gt - ` erode ${ROIs_d}/custom_VOIs/Caud_ero_RT_custom.nii.gz"
    task_exec &

    # eroded Insula GMWM labels
    task_in="maskfilter `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Insula_WM_LT_FS.nii.gz ${ROIs_d}/custom_VOIs/Insula_GM_LT_FS.nii.gz -add 0 -gt - ` \
    erode -npass 2 ${ROIs_d}/custom_VOIs/Insula_GMWM_LT_ero2_custom.nii.gz -nthreads ${ncpu} -quiet -force \
    && maskfilter `mrcalc -force -datatype uint16 -force -quiet ${ROIs_d}/custom_VOIs/Insula_WM_RT_FS.nii.gz ${ROIs_d}/custom_VOIs/Insula_GM_RT_FS.nii.gz -add 0 -gt - `
    erode -npass 2 ${ROIs_d}/custom_VOIs/Insula_GMWM_RT_ero2_custom.nii.gz -nthreads ${ncpu} -quiet -force"
    task_exec &

    # Hemispheric and cerebellar excludes
    # GMhemi_LTr.nii.gz WMhemi_LTr.nii.gz vDC_LTr.nii.gz
    # "GMhemi_LT"  "GMhemi_RT"  "BStem"  "WMhemi_LT"  "WMhemi_RT" \
    # "Cerebellum_WM_LT"  "Cerebellum_WM_RT"  "Cerebellum_GM_LT"  "Cerebellum_GM_RT" \
    # "3"  "42"  "16"  "2"  "41" \
    # "7"  "46"  "8"  "47"
    # must also remove any BStem voxels from the cerebellar mask
    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 3 -eq `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 2 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 28 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 10 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 11 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 12 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 13 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 17 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 18 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 26 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 31 -eq - ` -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_nv.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_nv.nii.gz `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 4 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 5 -eq - ` \
    -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz"

    task_exec &

    task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 42 -eq `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 41 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 60 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 49 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 50 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 51 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 52 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 53 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 54 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 58 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_in_FOD} 63 -eq - ` -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_nv.nii.gz \
    && mrcalc -force -datatype uint16 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_nv.nii.gz `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 43 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_in_FOD} 44 -eq - ` -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz"

    task_exec &

    task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aparc_in_FOD} 10 -eq - ` \
    `maskfilter -force -npass 2 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/PD25_Pulvi_LT_custom.nii.gz dilate - ` -sub 0.5 -gt ${ROIs_d}/custom_VOIs/Thal_min_Pulvi_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aparc_in_FOD} 49 -eq - ` \
    `maskfilter -force -npass 2 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/PD25_Pulvi_RT_custom.nii.gz dilate - ` -sub 0.5 -gt ${ROIs_d}/custom_VOIs/Thal_min_Pulvi_RT_custom.nii.gz"

    task_exec &

    task_in="maskfilter -npass 3 -force -nthreads ${ncpu} -quiet ${tmpo_d}/SegWM_LT_TOV_custom.nii.gz dilate ${tmpo_d}/SegWM_LT_TOVc_dilx3.nii.gz \
    && maskfilter -npass 3 -force -nthreads ${ncpu} -quiet ${tmpo_d}/SegWM_RT_TOV_custom.nii.gz dilate ${tmpo_d}/SegWM_RT_TOVc_dilx3.nii.gz \
    && fslmaths ${tmpo_d}/SegWM_LT_TOVc_dilx3.nii.gz -binv ${tmpo_d}/SegWM_LT_TOVc_dx3_binv.nii.gz \
    && fslmaths ${tmpo_d}/SegWM_RT_TOVc_dilx3.nii.gz -binv ${tmpo_d}/SegWM_RT_TOVc_dx3_binv.nii.gz \
    && fslmaths ${ROIs_d}/custom_VOIs/SegWM_LT_PLIC_custom.nii.gz -mul \
    ${tmpo_d}/SegWM_LT_TOVc_dx3_binv.nii.gz ${ROIs_d}/custom_VOIs/SegWM_LT_PLIC_ex_custom.nii.gz \
    && fslmaths ${ROIs_d}/custom_VOIs/SegWM_RT_PLIC_custom.nii.gz -mul ${tmpo_d}/SegWM_RT_TOVc_dx3_binv.nii.gz ${ROIs_d}/custom_VOIs/SegWM_RT_PLIC_ex_custom.nii.gz"

    task_exec

    ## adding subsegmentation of the vDC
    task_in="mrcalc -force -datatype uint16 -quiet ${subj_aparc_in_FOD} 28 -eq 0 -gt 1 -mult ${tmpo_d}/vDC_LT_tmp.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${subj_aparc_in_FOD} 60 -eq 0 -gt 1 -mult ${tmpo_d}/vDC_RT_tmp.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${subj_aparc_in_FOD} 85 -eq - | maskfilter - dilate - \
    -npass 6 | mrcalc - 2 -mult ${tmpo_d}/optCH_dilt6_tmp.nii.gz -force \
    && maskfilter -npass 2 ${ROIs_d}/custom_VOIs/JuHA_LGN_LT_custom.nii.gz dilate ${tmpo_d}/JuLGN_dilt2_LT_tmp.nii.gz \
    && maskfilter -npass 2 ${ROIs_d}/custom_VOIs/JuHA_LGN_RT_custom.nii.gz dilate ${tmpo_d}/JuLGN_dilt2_RT_tmp.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${tmpo_d}/optCH_dilt6_tmp.nii.gz ${tmpo_d}/JuLGN_dilt2_LT_tmp.nii.gz -add ${ROIs_d}/custom_VOIs/LT_vDC_subseg_labels.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${tmpo_d}/optCH_dilt6_tmp.nii.gz ${tmpo_d}/JuLGN_dilt2_RT_tmp.nii.gz -add ${ROIs_d}/custom_VOIs/RT_vDC_subseg_labels.nii.gz"

    task_exec

    task_in="ImageMath 3 ${ROIs_d}/custom_VOIs/LT_vDC_subseg_output.nii.gz PropagateLabelsThroughMask ${tmpo_d}/vDC_LT_tmp.nii.gz ${ROIs_d}/custom_VOIs/LT_vDC_subseg_labels.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/RT_vDC_subseg_output.nii.gz PropagateLabelsThroughMask ${tmpo_d}/vDC_RT_tmp.nii.gz ${ROIs_d}/custom_VOIs/RT_vDC_subseg_labels.nii.gz"
    #${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz

    task_exec

    task_in="mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/LT_vDC_subseg_output.nii.gz 1 -eq ${ROIs_d}/custom_VOIs/LT_vDC_subseg1_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/LT_vDC_subseg_output.nii.gz 2 -eq ${ROIs_d}/custom_VOIs/LT_vDC_subseg2_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/RT_vDC_subseg_output.nii.gz 1 -eq ${ROIs_d}/custom_VOIs/RT_vDC_subseg1_custom.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${ROIs_d}/custom_VOIs/RT_vDC_subseg_output.nii.gz 2 -eq ${ROIs_d}/custom_VOIs/RT_vDC_subseg2_custom.nii.gz"

    task_exec

    if KUL_wait_all_bg_and_check; then
        touch ${pt2_done} && echo "Part 2 done" >> ${pt2_done}
    else
        echo "ERROR: one or more background steps failed before Part2.done — not marking done" | tee -a ${prep_log2}
        exit 1
    fi

else

    echo "Part 2 already done, skipping" | tee -a ${prep_log2}

fi

# exit 2
## Function for VOI separation and recombination to make includes and excludes

function make_VOIs {

    # we need an array with all includes
    # an array with all excludes also
    # each needs a distinctive suffix for identification of source labels

    echo "---------------------" | tee -a ${prep_log2}

    echo ${tck_VOIs_2seg} | tee -a ${prep_log2}

    # echo " Started @ $(date "+%Y-%m-%d_%H-%M-%S")" | tee -a ${prep_log2}

    # we need 4 arrays per tck (include labels, and values, exclude labels, and values)

    # https://stackoverflow.com/questions/16553089/dynamic-variable-names-in-bash
    # found out how to do dynamic variable naming

    # to use dynamic variable definitions in bash
    # eval v_array=( \${${tck}_array[@]})

    unset Vs_Ls Vs_Is source_map val Vs_1_str Vs_other_str VOIs_LUT

    eval Vs_Ls=( \${${tck_VOIs_2seg}_Ls[@]});
    eval Vs_Is=( \${${tck_VOIs_2seg}_Is[@]});

    ## par procs
    # pow="${ncpu}"

    # make TCK VOIs dir
    # tck_list
    VOIs_dir="${ROIs_d}/${tck_list[$q]}_VOIs/${tck_VOIs_2seg}"
    MNI_VOIs_dir="${ROIs_d}/${tck_list[$q]}_VOIs_inMNI"
    mkdir -p "${ROIs_d}/${tck_list[$q]}_VOIs"
    mkdir -p "${VOIs_dir}"
    mkdir -p "${MNI_VOIs_dir}"
    VOIs_LUT="${VOIs_dir}/${tck_VOIs_2seg}_LUT.csv"

    # do we need a long string or not?
    if [[ ${#Vs_Ls[@]} -gt 1 ]]; then

        declare -a Vs_other_str
        declare -a Vs_nms_other_str
        declare -a tmpo_Vs

    fi

    for z in ${!Vs_Ls[@]}; do

        echo ${Vs_Ls[$z]} | tee -a ${prep_log2}

        # ((pew++))

        # ((pew=${pew}%${pow}))

        # select source maps
        # one condition per source map
        # custom ones are made in step 1
        # removed the PD25 condition as it was redundant "elif [[ ${Vs_Ls[$z]} == *"PD25"* ]]; then"
        # we use the custom suffix for all PD25 labels anyway
        if [[ ${Vs_Ls[$z]} == *"MSBP"* ]]; then

            source_map="${subj_MSsc3_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"FS"* ]]; then
            # okay its from FS but GM or WM?
            if [[ ${Vs_Ls[$z]} == *"_WM_"* ]]; then
                source_map="${subj_FS_WMaparc_in_FOD}"
            else 
                source_map="${subj_aparc_in_FOD}"
            fi

        elif [[ ${Vs_Ls[$z]} == *"2009"* ]]; then

            source_map="${subj_FS_2009_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"Fx"* ]]; then

            source_map="${subj_FS_Fx_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"lobe"* ]]; then

            source_map="${subj_FS_lobes_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"aseg"* ]]; then

            source_map="${subj_aseg_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"SUIT"* ]]; then

            source_map="${SUIT_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"CIT"* ]]; then

            source_map="${CIT_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"DISTAL_STN"* ]]; then

            source_map="${DISTAL_STN_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"TMP_BStem"* ]]; then

            source_map="${TMP_BStem_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"MAN"* ]]; then

            source_map="${Man_VOIs_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"UKBB"* ]]; then

            source_map="${UKBB_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"JHU"* ]]; then

            source_map="${JHU_in_FOD}"

        elif [[ ${Vs_Ls[$z]} == *"custom"* ]]; then

            source_map=""

        fi

        # calc val to scale each VOI to
        ((val=${z}+1))

        # Vs_Is encodes the VOIs intensity in source map
        # no source map in case of a custom VOI
        # val encodes the new value we give it
        # first condition is a lone custom VOI

        if [[ ! -z ${source_map} ]]; then

            source_n=$(basename ${source_map});

        else

            source_n="Custom_VOIs";

        fi


        if [[ ${z} == 0 ]] && [[ -z ${source_map} ]]; then

            Vs_1_str=" ${ROIs_d}/custom_VOIs/${Vs_Ls[$z]}.nii.gz 0 -gt ${val} -mult "
            # Vs_nms_1_str=" ${Vs_Ls[$z]} is scaled to ${val} "

        elif [[ ${z} == 0 ]] && [[ ! -z ${source_map} ]]; then

            Vs_1_str=" ${source_map} ${Vs_Is[$z]} -eq 0 -gt ${val} -mult "
            # Vs_nms_1_str=" ${Vs_Ls[$z]} is scaled to ${val} from ${source_n}"

            # printf '%s, %s, %s, %s \n' "${Vs_Ls[$z]}" "${val}" "${source_n}" "${Vs_Is[$z]}" >> ${VOIs_LUT}
            # echo "${Vs_Ls[$z]} ${val} ${source_n} ${Vs_Is[$z]}" | tr " " "," >> ${VOIs_LUT}

        elif [[ ${z} -gt 0 ]] && [[ ! -z ${source_map} ]]; then

            tmpo_Vs[$z]="${tmpo_d}/${Vs_Ls[$z]}_tmp.nii.gz"
            task_in="mrcalc -force -datatype uint16 -quiet -nthreads 1 -force ${source_map} ${Vs_Is[$z]} -eq 0 -gt ${val} -mult ${tmpo_Vs[$z]}"
            task_exec &
            Vs_other_str[$z]=" 0 ${tmpo_Vs[$z]} -replace "
            # Vs_nms_other_str[$z]=" ${Vs_Ls[$z]} is scaled to ${val} from ${source_n}"

            # printf '%s, %s, %s, %s \n' "${Vs_Ls[$z]}" "${val}" "${source_n}" "${Vs_Is[$z]}" >> ${VOIs_LUT}
            # echo  "${Vs_Ls[$z]} ${val} ${source_n} ${Vs_Is[$z]}" | tr " " "," >> ${VOIs_LUT}

        elif [[ ${z} -gt 0 ]] && [[ -z ${source_map} ]]; then

            tmpo_Vs[$z]="${tmpo_d}/${Vs_Ls[$z]}_tmp.nii.gz"
            task_in="mrcalc -force -datatype uint16 -quiet -nthreads 1 -force ${ROIs_d}/custom_VOIs/${Vs_Ls[$z]}.nii.gz 0 -gt ${val} -mult ${tmpo_Vs[$z]}"
            task_exec &
            Vs_other_str[$z]=" 0 ${tmpo_Vs[$z]} -replace "
            # Vs_other_str[$z]=" 0 ${ROIs_d}/custom_VOIs/${Vs_Ls[$z]}.nii.gz -replace "
            # Vs_nms_other_str[$z]=" ${Vs_Ls[$z]} is scaled to ${val} "

            # printf '%s, %s, %s, %s \n' "${Vs_Ls[$z]}" "${val}" "Custom_VOI" "1" >> ${VOIs_LUT}
            # echo  "${Vs_Ls[$z]} ${val} Custom_VOI 1" | tr " " "," >> ${VOIs_LUT}

        fi

        # make the LUTs

        printf '%s, %s \n' "${Vs_Ls[$z]}" "${val}" >> ${VOIs_LUT}
        
        # insert subdivision workflow here

    done

    sleep 5

    # so the mrcalc -force -datatype uint16 command should read as follows

    # task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} -quiet ${Vs_1_str} ${ROIs_d}/${tck_VOIs_2seg}_VOIs/${tck_VOIs_2seg}.nii.gz"

    # task_exec

    # echo "${Vs_nms_1_str}" >> ${VOIs_LUT}

    # if with multiple constituent VOIs
    # remember to include a -datatype with 32bituint if using tck2conn and conn2tck
    # should include a transform to MNI step here

    task_in="mrcalc -force -datatype uint16 -force -nthreads 1 -quiet ${Vs_1_str} ${Vs_other_str[@]} ${VOIs_dir}/${tck_VOIs_2seg}_map.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads 1 -quiet ${VOIs_dir}/${tck_VOIs_2seg}_map.nii.gz 0 -gt ${VOIs_dir}/${tck_VOIs_2seg}_bin.nii.gz \
    && antsApplyTransforms -d 3 -i ${VOIs_dir}/${tck_VOIs_2seg}_map.nii.gz \
    -o ${MNI_VOIs_dir}/${tck_VOIs_2seg}_map_inMNI.nii.gz -r ${UKBB_temp} \
    -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
    -t ${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fod_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
    -n NearestNeighbor"

    task_exec &

    # task_in="mrcalc -force -datatype uint16 -force -nthreads 1 -quiet ${VOIs_dir}/${tck_VOIs_2seg}_map.nii.gz 0 -gt \
    # ${VOIs_dir}/${tck_VOIs_2seg}_bin.nii.gz"

    # task_exec

    # echo "${Vs_nms_other_str[@]}" > ${VOIs_LUT}

    if KUL_wait_all_bg_and_check; then
        echo "${tck_list[$q]}_VOIs done" >> "${ROIs_d}/${tck_list[$q]}_VOIs.done"
    else
        echo "ERROR: one or more background steps failed for ${tck_list[$q]} VOIs — not marking done" | tee -a ${prep_log2}
    fi

    unset z

    # use mrtrix tools (mrcalc -force -datatype uint16 -eq, 0 -gt, n -mult and 0 n -replace)

    ## need to add .done file generation per bundle

}


# part 2 of this workflow is bundle specific and depends on the config file
# use processing control

# define the VOIs for each TCK here

###

## could also rely on collected tables with decent organized values

# https://www.unix.com/shell-programming-and-scripting/170933-search-array-return-index-bash.html

# for (( i=1;i<=${#arr[*]};i++ ))
# do
#     if [ ${arr[$i]} == $srch ]
#         then
#             echo "$srch found at index $i"
#             break
#     fi
# done

echo " Bundle specific VOIs gen " | tee -a ${prep_log2}

declare -a dotdones

declare -a srch_dotdones

# parallelization

qs=0;

# for loop for tck VOIs

for q in ${!tck_list[@]}; do

    echo $q
    echo ${tck_list[$q]}

    ((qs++))
    ((qs=${qs}%${qo}))

    dotdones[$q]="${ROIs_d}/${tck_list[$q]}_VOIs.done"
    srch_dotdones[$q]=$(find ${ROIs_d} -not -path '*/\.*' -type f | grep "${tck_list[$q]}_VOIs.done")

    if [[ -z ${srch_dotdones[$q]} ]]; then

        if [[ ! ${tck_list[$q]} == *"none"* ]]; then

            # srch_dotdones[$q]=($(find ${ROIs_d} -not -path '*/\.*' -type f | grep "${tck_list[$q]}_VOIs.done"))
            # restructure CST/PMC/SMA are all redundant, doable from the PyT_all
            # can be done using -eq for each of those VOIs hardcoded even

            track_recipes_d="${function_path}/track_recipes"

            recipe_f="${track_recipes_d}/${tck_list[$q]}.txt"

            if [[ ! -f "${recipe_f}" ]]; then

                echo " ${tck_list[$q]}: no recipe file found in ${track_recipes_d}, skipping VOI creation" | tee -a ${prep_log2}

            else

                bname="${tck_list[$q]}"

                # Initialise all segment arrays empty
                eval "${bname}_incs1_Ls=()" ; eval "${bname}_incs1_Is=()"
                eval "${bname}_incs2_Ls=()" ; eval "${bname}_incs2_Is=()"
                eval "${bname}_incs3_Ls=()" ; eval "${bname}_incs3_Is=()"
                eval "${bname}_excs_Ls=()"  ; eval "${bname}_excs_Is=()"

                # Parse recipe file — format: <type>  <VOI_name>  <label>
                while IFS=" " read -r _seg _vname _vlabel _rest; do
                    [[ -z "${_seg}" || "${_seg}" == \#* ]] && continue
                    case "${_seg}" in
                        incs1) eval "${bname}_incs1_Ls+=(\"\${_vname}\")"; eval "${bname}_incs1_Is+=(\"\${_vlabel}\")" ;;
                        incs2) eval "${bname}_incs2_Ls+=(\"\${_vname}\")"; eval "${bname}_incs2_Is+=(\"\${_vlabel}\")" ;;
                        incs3) eval "${bname}_incs3_Ls+=(\"\${_vname}\")"; eval "${bname}_incs3_Is+=(\"\${_vlabel}\")" ;;
                        excs)  eval "${bname}_excs_Ls+=(\"\${_vname}\")";  eval "${bname}_excs_Is+=(\"\${_vlabel}\")"  ;;
                    esac
                done < "${recipe_f}"

                # Call make_VOIs for each segment present in the recipe
                eval "_n=\${#${bname}_incs1_Ls[@]}"
                [[ ${_n} -gt 0 ]] && tck_VOIs_2seg="${bname}_incs1" && make_VOIs

                eval "_n=\${#${bname}_incs2_Ls[@]}"
                [[ ${_n} -gt 0 ]] && tck_VOIs_2seg="${bname}_incs2" && make_VOIs

                eval "_n=\${#${bname}_incs3_Ls[@]}"
                [[ ${_n} -gt 0 ]] && tck_VOIs_2seg="${bname}_incs3" && make_VOIs

                eval "_n=\${#${bname}_excs_Ls[@]}"
                [[ ${_n} -gt 0 ]] && tck_VOIs_2seg="${bname}_excs" && make_VOIs

            fi

            sleep 5

        else

            echo ""

        fi

    else

        echo "${tck_list[$q]}_VOIs already generated, skip " | tee -a ${prep_log2}

    fi

    if [[ ${qs} == 0 ]]; then

        wait

    fi

done


# dotdones[$q]="${ROIs_d}/${tck_list[$q]}_VOIs.done"

#     srch_dotdones[$q]=($(find ${ROIs_d} -not -path '*/\.*' -type f | grep "${tck_list[$q]}_VOIs.done"))

#     if [[ ! -z ${srch_dotdones[$q]} ]]; then

#         echo "Generating VOIs for ${tck_list[$q]} " | tee -a ${prep_log2}

#         tck_VOIs_2seg="${tck_list[$q]}_inc"

#         # these need to include the list of VOIs and corresponding values
#         tck_VOIs_2seg_Ls=();

#         tck_VOIs_2seg_Is=();

#         make_VOIs

#         # so the mrcalc -force -datatype uint16 command should read as follows

#         task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} -quiet ${Vs_1_str} ${full_path}/given_name.nii.gz"

#         echo "${Vs_nms_1_str}" >> ${VOIs_LUT}

#         # if with multiple constituent VOIs
#         # remember to include a -datatype with 32bituint if using tck2conn and conn2tck

#         task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} -quiet ${Vs_1_str} ${Vs_other_str[@]} ${full_path}/given_name_map.nii.gz \
#         && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} -quiet ${full_path}/given_name.nii.gz"

#         # need to echo that a text file
#         echo "${Vs_nms_other_str[@]}" >> ${VOIs_LUT}

#         touch ${dotdones[$q]}

#     else

#         echo "This bundle's VOIs have already been generated" | tee -a ${prep_log2}

#     fi


# removed the divided Fx

# elif [[ ${tck_list[$q]} == "Fx_LT" ]]; then

#                 Fx_LT_incs1_Ls=("Fornix_Fx");

#                 Fx_LT_incs1_Is=("250");

#                 tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

#                 # leaving out the MedOF
#                 Fx_LT_incs2_Ls=("Hippocampus_FS_LT");

#                 Fx_LT_incs2_Is=("17");

#                 tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

#                 Fx_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "vDC_FS_LT" "iPCC_GM_FS_LT" "iPCC_WM_FS_LT" "Thal_FS_LT" "Front_lobeGM_LT" \
#                 "Occ_lobeGM_LT" "Occ_lobeWM_LT" "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Pari_lobeGM_LT" "Pari_lobeWM_LT" "Amyg_FS_LT" "rACC_GM_FS_LT");

#                 Fx_LT_excs_Is=("1" "16" "1" "28" "1010" "3010" "10" "1001" "1004" "3004" "1005" "3005" "1006" "3006" "18" "1026");

#                 tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

#             elif [[ ${tck_list[$q]} == "Fx_RT" ]]; then

#                 Fx_RT_incs1_Ls=("Fornix_Fx");

#                 Fx_RT_incs1_Is=("250");

#                 tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

#                 # leaving out the MedOF
#                 Fx_RT_incs2_Ls=("Hippocampus_FS_RT");

#                 Fx_RT_incs2_Is=("53");

#                 tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

#                 Fx_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "vDC_FS_RT" "iPCC_GM_FS_RT" "iPCC_WM_FS_RT" "Thal_FS_RT" "Front_lobeGM_RT" \
#                 "Occ_lobeGM_RT" "Occ_lobeWM_RT" "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Pari_lobeGM_RT" "Pari_lobeWM_RT" "Amyg_FS_RT" "rACC_GM_FS_RT");

#                 Fx_RT_excs_Is=("1" "16" "1" "60" "2010" "4010" "53" "2001" "2004" "4004" "2005" "4005" "2006" "4006" "54" "2026");

#                 tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

