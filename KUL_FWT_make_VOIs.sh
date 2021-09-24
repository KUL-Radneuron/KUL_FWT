#!/bin/bash

# set -x

# the point of this one is to make my life easier!
# when it comes to VOI gen

cwd="$(pwd)"

# function Usage
function Usage {

cat <<USAGE

    `basename $0` generates all inclusion and exclusion VOIs for fully automated fiber tractography according to an input config file

    Usage:

    `basename $0` -p pat001 -s 01  -F /path_to/FS_dir/aparc+aseg.mgz -M /path_to/MSBP_dir/sub-pat001_label-L2018_desc-scale3_atlas.nii.gz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output

    Examples:

    `basename $0` -p pat001 -s 01 -F /path_to/FS_dir/aparc+aseg.mgz -M /path_to/MSBP_dir/sub-pat001_label-L2018_desc-scale3_atlas.nii.gz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output -n 6 

    Purpose:

    This workflow generates the VOIs needed for fiber tracking by KUL_FWT_make_TCKs.sh from input FS and MSBP for all bundles specified in the input config file for single subject data

    Required arguments:

    -p:  BIDS participant name (anonymised name of the subject without the "sub-" prefix)
    -s:  BIDS participant session (session no. without the "ses-" prefix)
    -M:  full path and file name of scale 3 MSBP parcellation
    -F:  full path and file name of aparc+aseg.mgz from FreeSurfer
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
M_flag=0
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
        M) #MSBP scale parcellation
            M_flag=1
            MS_sc3_in=$OPTARG
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
srch_MS_str=($(basename ${MS_sc3_in})) ; MS_dir=($(dirname ${MS_sc3_in}))
srch_MS_c=($(find ${MS_dir} -type f | grep  ${srch_MS_str}))

if [[ ${p_flag} -eq 0 ]] || [[ ${F_flag} -eq 0 ]] || [[ ${M_flag} -eq 0 ]] || [[ ${c_flag} -eq 0 ]] || [[ ${d_flag} -eq 0 ]]; then
	
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

    if [[ -z "${srch_MS_c}" ]]; then
    
        echo
        echo " Incorrect path MSBP parcellation, please check the path and name "
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

    if [[ ! ${d_dir} == *"${subj}"* ]] || [[ ! ${FS_dir} == *"${subj}"* ]] || [[ ! ${MS_dir} == *"${subj}"* ]]; then

        echo
        echo " Subject string does not match input files, please double check your inputs "
        echo
        exit 2

    else

        if [[ ! -z ${ses} ]]; then

            if [[ ! ${d_dir} == *"ses-${ses}"* ]] || [[ ! ${FS_dir} == *"ses-${ses}"* ]] || [[ ! ${MS_dir} == *"ses-${ses}"* ]]; then

                echo
                echo " Session string does not match input files, please double check your inputs "
                echo
                exit 2

            fi

        fi

    fi

    echo "Inputs are -p  ${subj} -s ${ses} -c  ${conf_f} -d ${d_dir}  -F ${FS_dir}  -M ${MS_dir} "

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

prep_log2="${output_d}/KUL_FWT_VOIs_log_${subj}_${d}.txt";

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

echo "KUL_FWT_make_VOIs.sh @ ${d} with parent pid $$ and process pid $BASHPID " | tee -a ${prep_log2}
echo "Inputs are -p  sub-${subj} -s ses-${ses} -c  ${conf_f} -d ${d_dir}  -F ${FS_dir}  -M ${MS_dir} " | tee -a ${prep_log2}

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

    eval ${task_in} 2>&1 | tee -a ${prep_log2} &

    # echo " pid = $! basicPID = $BASHPID " | tee -a ${prep_log2}

    echo " pid = $! " | tee -a ${prep_log2}

    wait ${pid}

    sleep 5

    echo "exit status $?" | tee -a ${prep_log2}

    # if [ $? -eq 0 ]; then

    #     echo Success >> ${prep_log2}

    # else

    #     echo Fail >> ${prep_log2}

    #     exit 1

    # fi

    echo " Finished @ $(date "+%Y-%m-%d_%H-%M-%S")" | tee -a ${prep_log2}

    echo "-------------------------------------------------------------" | tee -a ${prep_log2}

    echo "" | tee -a ${prep_log2}

    unset task_in

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

RL_VOIs="${pr_d}/RL_hemi_masks.nii.gz" # done

####

# these we create
# will probably need some for the tckseg script

sub_FA_in_T1="${prep_d}/sub-${subj}${ses_str}_FA2T1brainMS_Warped.nii.gz"

sub_T1inFA="${prep_d}/sub-${subj}${ses_str}_T1brain_MSinFA_Warped.nii.gz"

T1_brain_mask_inFA="${prep_d}/sub-${subj}${ses_str}_T1bm_MSinFA_Warped.nii.gz"

MSBP_csf_mask="${prep_d}/sub-${subj}${ses_str}_MSBP_CSF_mask.nii.gz"

MSBP_csf_mask_binv="${ROIs_d}/custom_VOIs/sub-${subj}${ses_str}_MSBP_CSF_mask_binv.nii.gz"

T1_BM_inFA_minCSF="${prep_d}/sub-${subj}${ses_str}_T1bm_MSinFA_minCSF.nii.gz"

RL_in_FA="${prep_d}/sub-${subj}${ses_str}_RL_masks_inFA.nii.gz"

PD25_in_FA="${prep_d}/sub-${subj}${ses_str}_PD25_histological_inFA.nii.gz"

SUIT_in_FA="${prep_d}/sub-${subj}${ses_str}_SUIT_cerebellar_atlas_inFA.nii.gz"

UKBB_in_FA="${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFA.nii.gz"

JuHA_in_FA="${prep_d}/sub-${subj}${ses_str}_Juelich_VOIs_inFA.nii.gz"

JHU_in_FA="${prep_d}/sub-${subj}${ses_str}_JHU_VOIs_inFA.nii.gz"

Man_VOIs_in_FA="${prep_d}/sub-${subj}${ses_str}_Manual_VOIs_inFA.nii.gz"

subj_aparc_inFA="${prep_d}/sub-${subj}${ses_str}_aparc_inFA.nii.gz"

subj_aseg_inFA="${prep_d}/sub-${subj}${ses_str}_aseg_inFA.nii.gz"

subj_FS_WMaparc_inFA="${prep_d}/sub-${subj}${ses_str}_WMaparc_inFA.nii.gz"

subj_MSsc3_inFA="${prep_d}/sub-${subj}${ses_str}_MSBP_scale3_inFA.nii.gz"

CFP_aparc_inFA="${prep_d}/sub-${subj}${ses_str}_LC+spine_inFA.nii.gz"

# subj_MSsc1_inFA_uint8="${prep_d}/sub-${subj}${ses_str}_MSBP_scale1_inFA_uint8.nii.gz"

subj_FS_lobes_inFA="${prep_d}/sub-${subj}${ses_str}_FS_lobes_inFA.nii.gz"

subj_FS_2009_inFA="${prep_d}/sub-${subj}${ses_str}_FS_2009_inFA.nii.gz"

subj_FS_Fx_inFA="${prep_d}/sub-${subj}${ses_str}_FS_fornix_inFA.nii.gz"

# subj_T1MSregrid="${tmpo_d}/sub-${subj}${ses_str}_MS_T1w_regridded.nii.gz"

subj_MS_brain="${prep_d}/sub-${subj}${ses_str}_MS_T1w_brain.nii.gz"

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

            task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${PD25_in_FA} ${MSBP_csf_mask_binv} -mult ${PD25_vals_LT[$hl]} \
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

            task_in="mrcalc -force -datatype uint16 -force -nthreads 1 ${PD25_in_FA} ${MSBP_csf_mask_binv} -mult ${PD25_vals_RT[$hr]} \
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
        task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aparc_inFA} 10 -eq 0 -gt ${ROIs_d}/custom_VOIs/Thalamus_LT_FS_custom.nii.gz \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aparc_inFA} 49 -eq 0 -gt ${ROIs_d}/custom_VOIs/Thalamus_RT_FS_custom.nii.gz"

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
        # switched to -npass 2 dilation with maskfilter from mriflter only for the pulvies
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

subj_dwi=($(find ${d_dir} -type f -name "dwi_preproced_reg2T1w.mif"))

subj_fod=($(find ${d_dir} -type f -name "dhollander_wmfod_reg2T1w.mif"))

subj_dt=($(find ${d_dir} -type f -name "dwi_dt_reg2T1w.mif"))

subj_FA=($(find ${d_dir}/qa -type f -name "fa_reg2T1w.nii.gz"))

subj_ADC=($(find ${d_dir}/qa -type f -name "adc_reg2T1w.nii.gz"))

subj_dwi_bm=($(find ${d_dir} -type f -name "dwi_preproced_reg2T1w_mask.nii.gz"))

# find label images 

subj_aparc_nii=($(find ${MS_dir} -type f -name "*_desc-aparcaseg_dseg.nii.gz"))

subj_aseg_nii=($(find ${MS_dir} -type f -name "*_desc-aseg_dseg.nii.gz"))

subj_aparc_mgz=($(find ${FS_dir} -type f -name "aparc+aseg.mgz"))

subj_MS_sc3=($(find ${MS_dir} -type f -name "*_label-L2018_desc-scale3_atlas.nii.gz"))

subj_MS_sc1=($(find ${MS_dir} -type f -name "*_label-L2018_desc-scale1_atlas.nii.gz"))

subj_FS_lobes=($(find ${FS_dir} -type f -name "sub-${subj}${ses}_lobes.mgz"))

subj_FS_2009=($(find ${FS_dir} -type f -name "aparc.a2009s+aseg.mgz"))

subj_FS_Fx=($(find ${FS_dir} -type f -name "sub-${subj}${ses_str}_Fx_aseg.mgz"))

subj_FS_WMaparc=($(find ${FS_dir} -type f -name "wmparc.mgz"))

subj_FS_brain=($(find ${FS_dir} -type f -name "brain.nii.gz"))

subj_FS_bm=($(find ${FS_dir} -type f -name "brainmask.nii.gz"))

subj_MS_bm=($(find ${MS_dir} -type f -name "*_desc-brain_mask.nii.gz"))

subj_MS_T1=($(find ${MS_dir} -type f -name "*_desc-cmp_T1w.nii.gz"))

##

temp2subj_str="FS_2_UKBB_${subj}${ses_str}"

temp2subj="${prep_d}/${temp2subj_str}"

MS2FS_str="MS_2_FS_${subj}"

MS2FS="${prep_d}/${MS2FS_str}"

FA2FS_str="${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}"

FA2MS_str="${prep_d}/fa_2_UKBB_vMS_${subj}${ses_str}"

# split the JuHA labels apart already
GNs=("LGN_RT" "LGN_LT" "MGN_RT" "MGN_LT");

# find your dwis

if [[ ! -f ${subj_dwi} ]]; then

    subj_dwi=($(find ${d_dir} -type f -name "*dwi_prep*"))

    if [[ ! -f ${subj_dwi} ]]; then

        subj_dwi=($(find ${d_dir} -type f -name "*dwi_pp*"))

        if [[ ! -f ${subj_dwi} ]]; then

            subj_dwi=($(find ${d_dir} -type f -name "*dwi*"))

            if [[ ! -f ${subj_dwi} ]]; then

                echo "no DWI found, quitting" | tee -a ${prep_log2}
                exit 2

            else

                echo "Potentially unprocessed dwi being used -> ${subj_dwi}, results can be suboptimal" | tee -a ${prep_log2}

            fi

        else

            echo "preprocessed dwi found ${subj_dwi}" | tee -a ${prep_log2}

        fi

    fi

fi

# find FODs

if [[ -z ${subj_fod} ]]; then

    subj_fod=($(find ${d_dir} -type f -name "*wmfod_reg2T1w.mif"))

    if [[ -z ${subj_fod} ]]; then

        subj_fod=($(find ${d_dir} -type f -name "*wmfod*"))

        if [[ -z ${subj_fod} ]]; then

            echo "no FODs found, quitting" | tee -a ${prep_log2}
            exit 2

        fi

    fi

fi

# find diff brain mask

if [[ ! -f ${subj_dwi_bm} ]]; then

    subj_dwi_bm=($(find ${d_dir} -type f -name "dwi_mask.nii.gz"))

    if [[ ! -f ${subj_dwi_bm} ]]; then

        subj_dwi_bm=($(find ${d_dir} -type f -name "*brain_mask*"))

        if [[ ! -f ${subj_dwi_bm} ]]; then

            echo "no dwi brain mask found, quitting" | tee -a ${prep_log2}
            exit 2

        fi

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

    if [[ ! -f ${subj_MS_brain} ]]; then

        task_in="mrgrid -force -nthreads ${ncpu} -template ${subj_MS_bm} ${subj_MS_T1} \
        regrid - | mrcalc - ${subj_MS_bm} -mult ${subj_MS_brain} -force -nthreads ${ncpu}"

        task_exec

    fi

    if [[ ! -f ${subj_dt} ]]; then

        subj_dt=($(find ${d_dir} -type f -name "*_tensor*"))

        if [[ ! -f ${subj_dt} ]]; then

            subj_dt="${prep_d}/sub-${subj}_tensor.mif"

            subj_FA="${prep_d}/fa.nii.gz"

            subj_ADC="${prep_d}/adc.nii.gz"

            echo "no Diffusion tensor found, we will make it and its derivatives" | tee -a ${prep_log2}

            task_in="dwi2tensor -force -nthreads ${ncpu} -mask ${subj_dwi_bm} ${subj_dwi} ${subj_dt} \
            && tensor2metric -force -nthreads ${ncpu} -mask ${subj_dwi_bm} -fa ${subj_FA} -adc ${subj_ADC} \
            ${subj_dt}"

            task_exec

        else

            echo " Diffusion tensor found, this data is not preprocessed using KUL_NITs " | tee -a ${prep_log2}

            subj_FA=($(find ${d_dir} -type f -name "FA.nii.gz"));

            subj_ADC=($(find ${d_dir} -type f -name "ADC.nii.gz"));

            if [[ -z ${subj_FA} ]] || [[ -z ${subj_ADC} ]]; then

                subj_FA="${prep_d}/fa.nii.gz"

                subj_ADC="${prep_d}/adc.nii.gz"

                echo " FA and/or ADC not found, generating" | tee -a ${prep_log2}

                task_in="tensor2metric -force -nthreads ${ncpu} -mask ${subj_dwi_bm} -fa ${subj_FA} -adc ${subj_ADC} ${subj_dt}"

                task_exec

            fi

        fi

    else

        task_in="cp ${subj_FA} ${prep_d}/fa.nii.gz && cp ${subj_ADC} ${prep_d}/adc.nii.gz"

        task_exec

    fi

    if [[ ! -f ${subj_aparc_nii} ]] || [[ ! -f ${subj_aparc_mgz} ]] || [[ ! -f ${subj_MS_sc3} ]]; then

        echo " one of the required label volumes is missing or not found, quitting "
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

    # warp MS brain to FS brain

    MS2FS_str="MS_2_FS_${subj}"

    MS2FS="${prep_d}/${MS2FS_str}"

    # srch_MS2FS=($(find ${prep_d} -type f -name MS_2_FS_${subj}_inv_4TCKs.mif));

    if [[ ! -f "${MS2FS}_Warped.nii.gz" ]]; then

        echo "MSBP brain to FS brain affine warp starting" | tee -a ${prep_log2}

        task_in="antsRegistrationSyN.sh -d 3 -f ${subj_FS_brain} -m ${subj_MS_brain} -x ${subj_FS_bm},${subj_MS_bm} -o ${MS2FS}_ -t a -j 1 -p f -n ${ncpu}"

        task_exec

    else

        echo "MSBP brain to FS brain warping already done, skipping" | tee -a ${prep_log2}

    fi

    # combine gen affines to go from T1 MSBP to UKBB directly
    # copy the FS normalization warps for use on MSBP
    task_in="cp ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz ${prep_d}/MS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz && cp ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1InverseWarp.nii.gz ${prep_d}/MS_2_UKBB_${subj}${ses_str}_1InverseWarp.nii.gz"

    task_exec

    task_in="antsApplyTransforms -d 3 -i ${subj_MS_brain} -r ${UKBB_temp} \
    -o Linear[${prep_d}/MS_2_UKBB_${subj}_0GenericAffine.mat] -t [${MS2FS}_0GenericAffine.mat,0] -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0]"

    task_exec

    # Warp from FS brain to FA
    # srch_FS2FA=($(find ${prep_d} -type f -name "sub-${subj}${ses_str}_FA2T1brainFS_Warped.nii.gz"))

    if [[ ! -f ${subj_FS_WMaparc_inFA}  ]]; then

        # this generates a new CC and Fornix segmentation using the aseg.auto.noCCseg.mgz label file

        echo " FS to FA warp not found, generating" | tee -a ${prep_log2}

        FA2FS_str="${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}"

        if [[ ! -f "${FA2FS_str}_template.nii.gz" ]]; then

            task_in="antsIntermodalityIntrasubject.sh -d 3 -i ${subj_FA} -r ${subj_FS_brain} -x ${subj_FS_bm} -t 3 -w ${prep_d}/FS_2_UKBB_${subj}${ses_str}_ -T ${UKBB_temp} -o ${FA2FS_str}_"

            task_exec

            sleep 2

        fi

        # now all these become nonlinear
        task_in="antsApplyTransforms -d 3 -i ${subj_FS_lobes} -o ${subj_FS_lobes_inFA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_2009} -o ${subj_FS_2009_inFA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_Fx} -o ${subj_FS_Fx_inFA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FS_WMaparc} -o ${subj_FS_WMaparc_inFA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

    else

        echo "FS T1, lobes, and Fx warped to FA, skipping " | tee -a ${prep_log2}

    fi

    # time to warp MSBP T1 to FA

    FA2MS_str="${prep_d}/fa_2_UKBB_vMS_${subj}${ses_str}"

    if [[ ! -f ${T1_BM_inFA_minCSF} ]]; then

        echo "MSBP to FA warp not found, generating"  | tee -a ${prep_log2}

        if [[ ! -f "${FA2MS_str}_template.nii.gz" ]]; then

            task_in="antsIntermodalityIntrasubject.sh -d 3 -i ${subj_FA} -r ${subj_FS_brain} -x ${subj_FS_bm} -t 3 -w ${prep_d}/MS_2_UKBB_${subj}_ -T ${UKBB_temp} -o ${FA2MS_str}_"

            task_exec

        else

            echo "ANTs intermodality registration of FA to MSBP T1 already done, skipping "  | tee -a ${prep_log2}

        fi

        task_in="antsApplyTransforms -d 3 -i ${subj_MS_brain} -o ${sub_T1inFA} -r ${subj_FA} -t [${FA2MS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz"

        task_exec

        # Affine registration of T1 brain and brain mask to dMRI space
        # warp the MSBP aparc_aseg and MSBP scale3 to FA space

        task_in="antsApplyTransforms -d 3 -i ${subj_MS_bm} -o ${T1_brain_mask_inFA} -r ${subj_FA} -t [${FA2MS_str}_0GenericAffine.mat,1] -t ${FA2MS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_MS_sc3} -o ${subj_MSsc3_inFA} -r ${subj_FA} -t [${FA2MS_str}_0GenericAffine.mat,1] -t ${FA2MS_str}_1InverseWarp.nii.gz -n multilabel"

        task_exec

        # for connectome fingerprinting
        # we use the scale1 MSBP maps
        # these are contiguous, coarse enough and have the BStem

        task_in="antsApplyTransforms -d 3 -i ${subj_aparc_nii} -o ${subj_aparc_inFA} -r ${subj_FA} -t [${FA2MS_str}_0GenericAffine.mat,1] -t ${FA2MS_str}_1InverseWarp.nii.gz -n multilabel" 

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_aseg_nii} -o ${subj_aseg_inFA} -r ${subj_FA} -t [${FA2MS_str}_0GenericAffine.mat,1] -t ${FA2MS_str}_1InverseWarp.nii.gz -n multilabel" 

        task_exec

        #Make the CSF binv mask
        # to do: this bm_minCSF needs smoothing
        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} -force -quiet ${subj_aseg_inFA} 4 0 -replace - | mrcalc -force -datatype uint16 - 43 0 -replace - | mrcalc -force -datatype uint16 - 24 0 \
        -replace - | mrcalc -force -datatype uint16 - 14 0 -replace - | mrcalc -force -datatype uint16 - 31 0 -replace - | mrcalc -force -datatype uint16 - 63 0 -replace - | mrcalc -force -datatype uint16 - 15 0 -replace 0 -gt \
        ${T1_brain_mask_inFA} -sub -1 -eq 0.9 -ge ${MSBP_csf_mask} -force && fslmaths ${MSBP_csf_mask} -binv ${MSBP_csf_mask_binv} \
        && mrcalc -force -datatype uint16 -nthreads ${ncpu} ${T1_brain_mask_inFA} ${MSBP_csf_mask_binv} -mult ${T1_BM_inFA_minCSF}"

        task_exec

    else

        echo "Affine alignement of T1 brain mask, aparc+aseg, aseg, and MSBP_scale3 already done, skipping "  | tee -a ${prep_log2}

    fi

    # using last generated file
    srch_tck_warp=($(find ${prep_d} -type f -name UKBB_2_FA_${subj}_inv_4TCKs.mif));

    # split the JuHA labels apart already
    GNs=("LGN_RT" "LGN_LT" "MGN_RT" "MGN_LT");

    if [[ -z ${srch_tck_warp} ]]; then

        # from https://community.mrtrix.org/t/registration-using-transformations-generated-from-other-packages/2259
        # we use this to transform TCKs to MNI
        # antsApplyTransforms needs to be applied in the opposite direction
        task_in="warpinit ${UKBB_temp} ${tmpo_d}/TCKs_iw_[].nii.gz -f"

        task_exec

        for wi in {0..2}; do 

            task_in="antsApplyTransforms -d 3 -i ${tmpo_d}/TCKs_iw_${wi}.nii.gz \
            -o ${tmpo_d}/TCKs_iw_w_${wi}.nii.gz -r ${subj_FA} \
            -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,1] \
            -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1InverseWarp.nii.gz \
            -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,1] \
            -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1InverseWarp.nii.gz
            --default-value 2147483647"

            task_exec

        done

        task_in="warpcorrect ${tmpo_d}/TCKs_iw_w_[].nii.gz ${prep_d}/FS_2_UKBB_${subj}_inv_4TCKs.mif -force -marker 2147483647"

        task_exec

    else

        echo "Generating warps for already done, skipping " | tee -a ${prep_log2}

    fi

    
    if [[ ! -f ${ROIs_d}/priors_warped.done ]]; then

        ## UKBB VOIs

        # Limiting UKBB VOIs to Pons and providing eroded versions to use as excludes
        task_in="mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 16 -eq 0 -gt 1 -mult ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz \
        && mrcalc -force -datatype uint16 -force -quiet ${subj_MSsc3_inFA} 250 -eq 0 -gt ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz \
        && antsApplyTransforms -d 3 -i ${UKBB_labels} -o ${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFA.nii.gz \
        -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFA.nii.gz \
        ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz -mult ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz \
        && ImageMath 3 ${UKBB_in_FA} PropagateLabelsThroughMask ${ROIs_d}/custom_VOIs/Bs_MSBP_Ponsr.nii.gz ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz 2 \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz 1 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/LT_CST_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/LT_CST_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/LT_CST_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu} \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz 3 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/RT_CST_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/RT_CST_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/RT_CST_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu} \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz 2 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/LT_ML_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/LT_ML_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/LT_ML_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu} \
        && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz 4 -eq 0 -gt \
        ${ROIs_d}/custom_VOIs/RT_ML_pons_custom.nii.gz && maskfilter ${ROIs_d}/custom_VOIs/RT_ML_pons_custom.nii.gz erode \
        ${ROIs_d}/custom_VOIs/RT_ML_X_custom.nii.gz -npass 1 -force -nthreads ${ncpu}"

        task_exec &

        ## R/L labels also
        # right is 2 and left is 1
        task_in="antsApplyTransforms -d 3 -i ${RL_VOIs} -o ${RL_in_FA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel \
        && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${RL_in_FA} 1 -eq ${ROIs_d}/custom_VOIs/Left_hemir_custom.nii.gz \
        && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${RL_in_FA} 2 -eq ${ROIs_d}/custom_VOIs/Right_hemir_custom.nii.gz"
        task_exec &

        ## PD25
        task_in="antsApplyTransforms -d 3 -i ${PD25} -o ${PD25_in_FA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ##  SUIT
        task_in="antsApplyTransforms -d 3 -i ${SUIT} -o ${SUIT_in_FA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ## Manual VOIs
        task_in="antsApplyTransforms -d 3 -i ${Man_VOIs} -o ${Man_VOIs_in_FA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ## JHU VOIs
        task_in="antsApplyTransforms -d 3 -i ${JHU_labels} -o ${JHU_in_FA} -r ${subj_FA} -t [${FA2FS_str}_0GenericAffine.mat,1] -t ${FA2FS_str}_1InverseWarp.nii.gz \
        -t [${temp2subj}_0GenericAffine.mat,1] -t ${temp2subj}_1InverseWarp.nii.gz -n multilabel"
        task_exec &

        ## Juelich Histological Atlas
        # using WarpTimeSeriesImage for this one
        task_in="WarpTimeSeriesImageMultiTransform 4 ${JuHA_labels} ${JuHA_in_FA} -R ${subj_FA} -i ${FA2FS_str}_0GenericAffine.mat ${FA2FS_str}_1InverseWarp.nii.gz -i ${temp2subj}_0GenericAffine.mat ${temp2subj}_1InverseWarp.nii.gz"
        task_exec

        # this one is made for the connectivity finger printing
        task_in="labelconvert -force ${subj_aparc_inFA} ${function_path}/FreeSurferColorLUT.txt ${function_path}/fs_default.txt - | mrcalc - 0 \
        `mrcalc -force ${ROIs_d}/custom_VOIs/UKBB_in_FA_BStem_masked.nii.gz 84 -add 84 0 -replace - ` -replace -datatype uint8 -force ${CFP_aparc_inFA}"

        task_exec

        # use ncpu/4 to avoid flooding the CPU ;)
        for gn in {0..3}; do 

            task_in="mrcalc -force -datatype uint16 -force -nthreads $((ncpu/4)) `mrconvert -force -coord 3 ${gn} ${JuHA_in_FA} - ` 25 -gt \
            - | maskfilter - connect ${ROIs_d}/custom_VOIs/JuHA_${GNs[$gn]}_custom.nii.gz -largest -force"
            task_exec &

        done

        # use the PD25 labels function
        PD25_lab_gen

        touch ${ROIs_d}/priors_warped.done && echo "Priors warping done" >> ${ROIs_d}/priors_warped.done

    else

        echo "Applying warps to template label maps already done, skipping " | tee -a ${prep_log2}

    fi

    touch ${pt1_done} && echo "Part 1 done" >> ${pt1_done}

else

    echo " Part 1 already done, skipping" | tee -a ${prep_log2}

fi

pt2_done="${ROIs_d}/Part2.done"

srch_pt2_done=($(find ${ROIs_d} -not -path '*/\.*' -type f | grep "Part2.done"))

if [[ -z ${srch_pt2_done} ]]; then

    ## Unseg_WM/JHU work-around starts here

    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 5001 -eq 0 -gt \
    `mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 5002 -eq 0 -gt - ` -add 0 -gt ${ROIs_d}/custom_VOIs/Unseg_WM_bil_FS_custom.nii.gz \
    && ImageMath 3 ${ROIs_d}/custom_VOIs/Seg_unseg_WM_bil_FS.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/Unseg_WM_bil_FS_custom.nii.gz ${JHU_in_FA}"

    task_exec

    # need to split them up again
    # LT PLIC is 20, LT ALIC is 18
    # RT PLIC is 19, RT ALIC is 17
    # frontal PV LT is 24, frontal PV RT is 23.
    # mid PV LT is 26, mid PV RT is 25.
    # pari PV LT is 28, pari PV RT is 27.
    # LFP PV LT is 42, LFP PV RT is 41.
    # M_periAt LT is 48, M_periAt RT is 47.

    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 5001 -eq 0 -gt ${ROIs_d}/custom_VOIs/Seg_unseg_WM_bil_FS.nii.gz -mult ${ROIs_d}/custom_VOIs/Seg_unseg_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 5002 -eq 0 -gt ${ROIs_d}/custom_VOIs/Seg_unseg_WM_bil_FS.nii.gz -mult ${ROIs_d}/custom_VOIs/Seg_unseg_WM_RT_FS.nii.gz \
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

    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 224 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG1_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 225 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG2_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 226 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG3_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 227 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG4_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 228 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG5_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 3030 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG_LT_WM_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 100 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG1_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 101 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG2_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 102 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG3_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 103 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG4_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 104 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG5_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 4030 -eq 0 -gt ${ROIs_d}/custom_VOIs/STG_RT_WM_FS.nii.gz"

    task_exec

    # found small bug here
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
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 208 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi1_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 209 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi2_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 210 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi3_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 211 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi4_LT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 3007 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi_LT_WM_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 84 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi1_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 85 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi2_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 86 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi3_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 87 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi4_RT_MSBP.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 4007 -eq 0 -gt ${ROIs_d}/custom_VOIs/Fusi_RT_WM_FS.nii.gz"

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

    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 3035 -eq  0 -gt ${ROIs_d}/custom_VOIs/Insula_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 4035 -eq 0 -gt ${ROIs_d}/custom_VOIs/Insula_WM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 1014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_GM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 3014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 2014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_GM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 4014 -eq 0 -gt ${ROIs_d}/custom_VOIs/MedOF_WM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 1012 -eq 0 -gt ${ROIs_d}/custom_VOIs/LatOF_GM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_FS_WMaparc_inFA} 3012 -eq 0 -gt ${ROIs_d}/custom_VOIs/LatOF_WM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 1035 -eq 0 -gt ${ROIs_d}/custom_VOIs/Insula_GM_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 2035 -eq 0 -gt ${ROIs_d}/custom_VOIs/Insula_GM_RT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 230 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins1_LT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 231 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins2_LT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 232 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins3_LT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 106 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins1_RT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 107 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins2_RT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_MSsc3_inFA} 108 -eq 0 -gt ${ROIs_d}/custom_VOIs/Ins3_RT_MS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 18 -eq 0 -gt ${ROIs_d}/custom_VOIs/Amyg_LT_FS.nii.gz \
    && mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 54 -eq 0 -gt ${ROIs_d}/custom_VOIs/Amyg_RT_FS.nii.gz"

    task_exec

    # propagate the VOIs into Insular WM (level 1)
    # ${JHU_in_FA} 2
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Insula_WM_LT_FS.nii.gz ${ROIs_d}/custom_VOIs/Insula_WM_RT_FS.nii.gz -add 0 -gt \
    ${ROIs_d}/custom_VOIs/Insula_WM_Bil_FS.nii.gz && ImageMath 3 ${ROIs_d}/custom_VOIs/Ins_seg_z_Bil_custom.nii.gz PropagateLabelsThroughMask \
    ${ROIs_d}/custom_VOIs/Insula_WM_Bil_FS.nii.gz ${JHU_in_FA}"

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
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} ${subj_aparc_inFA} 7 -eq 0 -gt 1 -mult 0 \
    `mrcalc -force -datatype uint16 -quiet ${subj_aparc_inFA} 8 -eq 0 -gt 1 -mult - ` -replace ${tmpo_d}/LT_cerebellum_GMWM.nii.gz
    && mrcalc -force -datatype uint16 -quiet ${subj_aparc_inFA} 46 -eq 0 -gt 1 -mult 0 \
    `mrcalc -force -datatype uint16 -quiet ${subj_aparc_inFA} 47 -eq 0 -gt 1 -mult - ` -replace ${tmpo_d}/RT_cerebellum_GMWM.nii.gz"
    task_exec

    task_in="maskfilter -force -nthreads ${ncpu} -npass 2 ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz dilate - | mrcalc - -neg 0 -ge ${tmpo_d}/BStemr_dilx2inv.nii.gz -force -nthreads ${ncpu} -datatype uint16 && mrcalc -datatype uint16 -force -quiet ${tmpo_d}/LT_cerebellum_GMWM.nii.gz ${tmpo_d}/BStemr_dilx2inv.nii.gz -mult 0 -gt ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz \
    && mrcalc -datatype uint16 -force -quiet ${tmpo_d}/RT_cerebellum_GMWM.nii.gz ${tmpo_d}/BStemr_dilx2inv.nii.gz -mult 0 -gt ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz && mrcalc -quiet -force -nthreads ${ncpu} -datatype uint16 ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz \
    ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz -add 0 -gt ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz"
    task_exec &

    # To block hypothalamic region (WIP)
    # LT - RT : "248" "124" \
    task_in="mrcalc -force -datatype uint16 -quiet -nthreads ${ncpu} `mrcalc -datatype uint16 -force -quiet ${subj_MSsc3_inFA} 248 -eq - ` \
    `mrcalc -force -datatype uint16 -quiet ${subj_MSsc3_inFA} 124 -eq - ` -add 0.5 -gt \
    - | maskfilter - connect - -largest -connectivity -nthreads ${ncpu} | maskfilter - \
    dilate  ${ROIs_d}/custom_VOIs/hypothal_bildil_excr_custom.nii.gz -force -nthreads ${ncpu}"
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
    `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 247 -eq 0 -gt - ` -add ${ROIs_d}/custom_VOIs/Left_hemir_custom.nii.gz \
    -mult 0.5 -gt ${ROIs_d}/custom_VOIs/BStemr_exc_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz \
    `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 123 -eq 0 -gt - ` -add ${ROIs_d}/custom_VOIs/Right_hemir_custom.nii.gz \
    -mult 0.5 -gt ${ROIs_d}/custom_VOIs/BStemr_exc_RT_custom.nii.gz"
    task_exec &

    # make an exclude for SCPs
    task_in="maskfilter -force -quiet -npass 4 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Bs_Pons_LT_custom.nii.gz erode ${ROIs_d}/custom_VOIs/e4BsPons_LT_custom.nii.gz && maskfilter -force -quiet -npass 4 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/Bs_Pons_RT_custom.nii.gz erode ${ROIs_d}/custom_VOIs/e4BsPons_RT_custom.nii.gz"
    task_exec &

    # CC all
    # fslmaths is simpler here
    task_in="fslmaths ${subj_aparc_inFA} -thr 250 -uthr 255 ${ROIs_d}/custom_VOIs/CC_allr_custom.nii.gz"
    task_exec &

    # Thalami eroded
    # values for basal ganglia + thalami from FS aparc+aseg
    # "Amyg_LT"  "Amyg_RT"  "Put_LT"  "Put_RT"  "Pall_LT"  "Pall_RT"  \
    # "Thal_LT"  "Thal_RT"  "Caud_LT"  "Caud_RT"  \
    # \
    # "18"  "54"  "12"  "51"  "13"  "52" \
    # "10"  "49"  "11"  "50"  \

    # eroded Thalamus labels
    task_in="mrcalc -force -datatype uint16 -quiet -force -nthreads ${ncpu} ${subj_aparc_inFA} 10 -eq 0 -gt - | maskfilter - erode \
    ${ROIs_d}/custom_VOIs/Thal_LT_ero2_custom.nii.gz -npass 2 -quiet -nthreads ${ncpu} -force && mrcalc -force -datatype uint16 -quiet -force \
    -nthreads ${ncpu} ${subj_aparc_inFA} 49 -eq 0 -gt - | maskfilter - erode \
    ${ROIs_d}/custom_VOIs/Thal_RT_ero2_custom.nii.gz -npass 2 -quiet -force -nthreads ${ncpu}"
    task_exec &

    # smoothed and eroded Putamen labels
    task_in="mrfilter -force -nthreads ${ncpu} -quiet `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 12 -eq 0 -gt - ` \
    smooth -fwhm 3 - | mrcalc -force -datatype uint16 - 0.15 -ge ${ROIs_d}/custom_VOIs/s3Put_LT_custom.nii.gz -force -nthreads ${ncpu} -quiet \
    && mrfilter -force -nthreads ${ncpu} -quiet `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 51 -eq 0 -gt - ` \
    smooth -fwhm 3 - | mrcalc -force -datatype uint16 - 0.15 -ge ${ROIs_d}/custom_VOIs/s3Put_RT_custom.nii.gz -force -nthreads ${ncpu} -quiet \
    && maskfilter `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 12 -eq 0 -gt - ` erode ${ROIs_d}/custom_VOIs/e2Put_LT_custom.nii.gz -npass 2 -force -nthreads ${ncpu} \
    && maskfilter `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 51 -eq 0 -gt - ` erode ${ROIs_d}/custom_VOIs/e2Put_RT_custom.nii.gz -npass 2 -force -nthreads ${ncpu}"
    task_exec &

    # eroded caudate VOIs
    task_in="maskfilter -force -nthreads ${ncpu} `mrcalc -force -datatype uint16 -quiet -force ${subj_aparc_inFA} 11 -eq 0 -gt - ` \
    erode ${ROIs_d}/custom_VOIs/Caud_ero_LT_custom.nii.gz && maskfilter -force -nthreads ${ncpu} `mrcalc -force -datatype uint16 -quiet \
    -force ${subj_aparc_inFA} 50 -eq 0 -gt - ` erode ${ROIs_d}/custom_VOIs/Caud_ero_RT_custom.nii.gz"
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
    task_in="mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 3 -eq `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 2 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 28 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 10 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 11 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 12 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 13 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 17 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 18 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 26 -eq - ` -add \
    `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 31 -eq - ` -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_nv.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_nv.nii.gz `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 4 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 5 -eq - ` \
    -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz"

    task_exec &

    task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 42 -eq `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 41 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 60 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 49 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 50 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 51 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 52 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 53 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 54 -eq - ` -add `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 58 -eq - ` -add \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aseg_inFA} 63 -eq - ` -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_nv.nii.gz \
    && mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_nv.nii.gz `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 43 -eq - ` -add `mrcalc -force -datatype uint16 -force -nthreads ${ncpu} ${subj_aseg_inFA} 44 -eq - ` -add 0 -gt ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz"

    task_exec &

    task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aparc_inFA} 10 -eq - ` \
    `maskfilter -force -npass 2 -nthreads ${ncpu} ${ROIs_d}/custom_VOIs/PD25_Pulvi_LT_custom.nii.gz dilate - ` -sub 0.5 -gt ${ROIs_d}/custom_VOIs/Thal_min_Pulvi_LT_custom.nii.gz \
    && mrcalc -force -datatype uint16 -nthreads ${ncpu} \
    `mrcalc -force -datatype uint16 -nthreads ${ncpu} ${subj_aparc_inFA} 49 -eq - ` \
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
    task_in="mrcalc -force -datatype uint16 -quiet ${subj_aparc_inFA} 28 -eq 0 -gt 1 -mult ${tmpo_d}/vDC_LT_tmp.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${subj_aparc_inFA} 60 -eq 0 -gt ${tmpo_d}/vDC_RT_tmp.nii.gz \
    && mrcalc -force -datatype uint16 -quiet ${subj_aparc_inFA} 85 -eq - | maskfilter - dilate - \
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

    touch ${pt2_done} && echo "Part 2 done" >> ${pt2_done}

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

            source_map="${subj_MSsc3_inFA}"

        elif [[ ${Vs_Ls[$z]} == *"FS"* ]]; then
            # okay its from FS but GM or WM?
            if [[ ${Vs_Ls[$z]} == *"_WM_"* ]]; then
                source_map="${subj_FS_WMaparc_inFA}"
            else 
                source_map="${subj_aparc_inFA}"
            fi

        elif [[ ${Vs_Ls[$z]} == *"2009"* ]]; then

            source_map="${subj_FS_2009_inFA}"

        elif [[ ${Vs_Ls[$z]} == *"Fx"* ]]; then

            source_map="${subj_FS_Fx_inFA}"

        elif [[ ${Vs_Ls[$z]} == *"lobe"* ]]; then

            source_map="${subj_FS_lobes_inFA}"

        elif [[ ${Vs_Ls[$z]} == *"aseg"* ]]; then

            source_map="${subj_aseg_inFA}"

        elif [[ ${Vs_Ls[$z]} == *"SUIT"* ]]; then

            source_map="${SUIT_in_FA}"

        elif [[ ${Vs_Ls[$z]} == *"MAN"* ]]; then

            source_map="${Man_VOIs_in_FA}"

        elif [[ ${Vs_Ls[$z]} == *"UKBB"* ]]; then

            source_map="${UKBB_in_FA}"

        elif [[ ${Vs_Ls[$z]} == *"JHU"* ]]; then

            source_map="${JHU_in_FA}"

        elif [[ ${Vs_Ls[$z]} == *"custom"* ]]; then

            source_map=""

        fi

        # calc val to scale each VOI to
        ((val=${z}+1))

        # Vs_Is encodes the VOIs intensity in source map
        # no source map in case of a custom VOI
        # val encodes the new value we give it

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
    -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
    -n multilabel"

    task_exec &

    sleep 2

    # task_in="mrcalc -force -datatype uint16 -force -nthreads 1 -quiet ${VOIs_dir}/${tck_VOIs_2seg}_map.nii.gz 0 -gt \
    # ${VOIs_dir}/${tck_VOIs_2seg}_bin.nii.gz"

    # task_exec

    # echo "${Vs_nms_other_str[@]}" > ${VOIs_LUT}

    echo "${tck_list[$q]}_VOIs done" >> "${ROIs_d}/${tck_list[$q]}_VOIs.done"

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

            if [[ ${tck_list[$q]} == "CST_LT" ]]; then

                # CorticoSpinal tract left

                # make 1st include
                CST_LT_incs1_Ls=("CST_LT_UKBB");

                CST_LT_incs1_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # make 2nd include
                CST_LT_incs2_Ls=("M1_GM_LT_FS" "S1_GM_LT_FS" "ParaC_GM_LT_FS")

                CST_LT_incs2_Is=("1024" "1022" "1017")

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # for excluding part of BStem, use the LT/RT_ML/CST_X_custom VOIs (those are eroded twice)
                CST_LT_excs_Ls=("CC_allr_custom" "BStemr_exc_RT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" "LT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_LT_ero2_custom" \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Putamen_GM_LT_FS" \
                "Caudate_GM_LT_FS" "SFG_GM_LT_FS" "Occ_lobeGM_LT"  "Occ_lobeWM_LT");

                CST_LT_excs_Is=("1" "1" \
                "1003" "3003" "1" \
                "1" "1" \
                "1005" "3005" "12" \
                "11" "1028" "1004" "3004");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CST_RT" ]]; then

                # CorticoSpinal tract right

                CST_RT_incs1_Ls=("CST_RT_UKBB");

                CST_RT_incs1_Is=("3");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CST_RT_incs2_Ls=("M1_GM_RT_FS" "S1_GM_RT_FS" "ParaC_GM_RT_FS")

                CST_RT_incs2_Is=("2024" "2022" "2017")

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CST_RT_excs_Ls=("CC_allr_custom" "BStemr_exc_LT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" "RT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_RT_ero2_custom" \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Putamen_RT_FS" \
                "Caudate_GM_RT_FS" "SFG_GM_LT_FS" "Occ_lobeGM_RT"  "Occ_lobeWM_RT");

                CST_RT_excs_Is=("1" "1" \
                "2003" "4003" "1" \
                "1" "1" \
                "2005" "4005" "51" \
                "50" "1028" "2004" "4004");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "M1_CST_LT" ]]; then

                # CorticoSpinal tract left

                # make 1st include
                M1_CST_LT_incs1_Ls=("CST_LT_UKBB");

                M1_CST_LT_incs1_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # make 2nd include
                M1_CST_LT_incs2_Ls=("M1_GM_LT_FS" "ParaC_GM_LT_FS")

                M1_CST_LT_incs2_Is=("1024" "1017")

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # for excluding part of BStem, use the LT/RT_ML/CST_X_custom VOIs (those are eroded twice)
                M1_CST_LT_excs_Ls=("CC_allr_custom" "BStemr_exc_RT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" "LT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_LT_ero2_custom" \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Putamen_GM_LT_FS" \
                "Caudate_GM_LT_FS" "SFG_GM_LT_FS" "Occ_lobeGM_LT"  "Occ_lobeWM_LT" \
                "S1_GM_LT_FS");

                M1_CST_LT_excs_Is=("1" "1" \
                "1003" "3003" "1" \
                "1" "1" \
                "1005" "3005" "12" \
                "11" "1028" "1004" "3004" \
                "1022");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "M1_CST_RT" ]]; then

                # CorticoSpinal tract right

                M1_CST_RT_incs1_Ls=("CST_RT_UKBB");

                M1_CST_RT_incs1_Is=("3");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                M1_CST_RT_incs2_Ls=("M1_GM_RT_FS" "ParaC_GM_RT_FS")

                M1_CST_RT_incs2_Is=("2024" "2017")

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                M1_CST_RT_excs_Ls=("CC_allr_custom" "BStemr_exc_LT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" "RT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_RT_ero2_custom" \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Putamen_RT_FS" \
                "Caudate_GM_RT_FS" "SFG_GM_LT_FS" "Occ_lobeGM_RT" "Occ_lobeWM_RT" \
                "S1_GM_RT_FS");

                M1_CST_RT_excs_Is=("1" "1" \
                "2003" "4003" "1" \
                "1" "1" \
                "2005" "4005" "51" \
                "50" "1028" "2004" "4004" \
                "2022");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "PyT_all_LT" ]]; then

                # Pyramidal tract all left

                PyT_all_LT_incs1_Ls=("BStem_FS");

                PyT_all_LT_incs1_Is=("16");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                PyT_all_LT_incs2_Ls=("M1_GM_LT_FS" "S1_GM_LT_FS" "ParaC_GM_LT_FS" \
                "SFG5_LT_MSBP" "SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP" \
                "cMFG_GM_LT_FS" "SMG_GM_LT_FS" "SPL1_LT_MSBP" "SPL2_LT_MSBP" \
                "SPL3_LT_MSBP" "SPL4_LT_MSBP");

                PyT_all_LT_incs2_Is=("1024" "1022" "1017" \
                "148" "149" "150" "151" "1003" "1031" "178" "179" \
                "180" "181");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                PyT_all_LT_excs_Ls=("CC_allr_custom" "BStemr_exc_RT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "hypothal_bildil_excr_custom" "Thal_LT_ero2_custom" \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Putamen_GM_LT_FS" \
                "Caudate_GM_LT_FS" "rMFG_GM_LT_FS" \
                "Occ_lobeGM_LT"  "Occ_lobeWM_LT" \
                "SPL5_LT_MSBP" "SPL6_LT_MSBP" "SPL7_LT_MSBP");

                PyT_all_LT_excs_Is=("1" "1" \
                "1003" "3003" \
                "1" "1" \
                "1005" "3005" "12" \
                "11"  "1027" \
                "1004" "3004" \
                "182" "183" "184");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "PyT_all_RT" ]]; then

                # Pyramidal tract all right

                PyT_all_RT_incs1_Ls=("BStem_FS");

                PyT_all_RT_incs1_Is=("16");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                PyT_all_RT_incs2_Ls=("M1_GM_RT_FS" "S1_GM_RT_FS" "ParaC_GM_RT_FS" \
                "SFG5_RT_MSBP" "SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP" \
                "cMFG_GM_RT_FS" "SMG_GM_RT_FS" "SPL1_RT_MSBP" "SPL2_RT_MSBP" \
                "SPL3_RT_MSBP" "SPL4_RT_MSBP");

                PyT_all_RT_incs2_Is=("2024" "2022" "2017" \
                "24" "25" "26" "27" "2003" "2031" "54" "55" \
                "56" "57");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                PyT_all_RT_excs_Ls=("CC_allr_custom" "BStemr_exc_LT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "hypothal_bildil_excr_custom" "Thal_RT_ero2_custom" \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Putamen_RT_FS" \
                "Caudate_GM_RT_FS" "rMFG_GM_RT_FS" \
                "Occ_lobeGM_RT"  "Occ_lobeWM_RT" \
                "SPL5_RT_MSBP" "SPL6_RT_MSBP" "SPL7_RT_MSBP");

                PyT_all_RT_excs_Is=("1" "1" \
                "2003" "4003" \
                "1" "1" \
                "2005" "4005" "51" \
                "50" "2027" \
                "2004" "4004" \
                "58" "59" "60");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

             elif [[ ${tck_list[$q]} == "PyT_PMC_LT" ]]; then

                # Pyramidal tract PMC left

                PyT_PMC_LT_incs1_Ls=("BStem_FS");

                PyT_PMC_LT_incs1_Is=("16");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                PyT_PMC_LT_incs2_Ls=("cMFG_GM_LT_FS");

                PyT_PMC_LT_incs2_Is=("1003");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                PyT_PMC_LT_excs_Ls=("CC_allr_custom" "BStemr_exc_RT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" "LT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_LT_ero2_custom" \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Putamen_LT_FS" \
                "SFG_GM_LT_FS" "SFG_WM_LT_FS" "Caudate_GM_LT_FS" \
                "M1_GM_LT_FS" "M1_WM_LT_FS" "S1_GM_LT_FS" "S1_WM_LT_FS" \
                "Occ_lobeGM_LT"  "Occ_lobeWM_LT" "SegWM_LT_PPV_custom" \
                "rMFG5_MSBP_LT" "rMFG6_MSBP_LT");

                PyT_PMC_LT_excs_Is=("1" "1" \
                "1003" "2003" "1" \
                "1" "1" \
                "1005" "3005" "12" \
                "1028" "3028" "11" \
                "1024" "2024" "1022" "3022" \
                "1004" "3004" "1" \
                "142" "143");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "PyT_PMC_RT" ]]; then

                # Pyramidal tract PMC right

                PyT_PMC_RT_incs1_Ls=("BStem_FS");

                PyT_PMC_RT_incs1_Is=("16");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                PyT_PMC_RT_incs2_Ls=("cMFG_GM_RT_FS");

                PyT_PMC_RT_incs2_Is=("2003");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                PyT_PMC_RT_excs_Ls=("CC_allr_custom" "BStemr_exc_LT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" "RT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_RT_ero2_custom" \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Putamen_RT_FS" \
                "SFG_GM_RT_FS" "SFG_WM_RT_FS" "Caudate_GM_RT_FS" \
                "M1_GM_RT_FS" "M1_WM_RT_FS" "S1_GM_RT_FS" "S1_WM_RT_FS" \
                "Occ_lobeGM_RT"  "Occ_lobeWM_RT" "SegWM_RT_PPV_custom" \
                "rMFG5_MSBP_RT" "rMFG6_MSBP_RT");

                PyT_PMC_RT_excs_Is=("1" "1" \
                "2003" "4003" "1" \
                "1" "1" \
                "2005" "4005" "51" \
                "2028" "4028" "50" \
                "2024" "4024" "2022" "4022" \
                "2004" "4004" "1" \
                "18" "19");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "PyT_SMA_LT" ]]; then

                # Pyramidal tract SMA left

                PyT_SMA_LT_incs1_Ls=("BStem_FS");

                PyT_SMA_LT_incs1_Is=("16");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                PyT_SMA_LT_incs2_Ls=("SFG5_LT_MSBP" "SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP");

                PyT_SMA_LT_incs2_Is=("148" "149" "150" "151");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                PyT_SMA_LT_excs_Ls=("CC_allr_custom" "BStemr_exc_RT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" "LT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_LT_ero2_custom" \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Putamen_LT_FS" \
                "cMFG_GM_LT_FS" "rMFG_GM_LT_FS" "Caudate_GM_LT_FS" \
                "M1_GM_LT_FS" "M1_WM_LT_FS" "S1_GM_LT_FS" "S1_WM_LT_FS" \
                "Occ_lobeGM_LT"  "Occ_lobeWM_LT" \
                "SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" "SFG4_LT_MSBP");

                PyT_SMA_LT_excs_Is=("1" "1" \
                "1003" "2003" "1" \
                "1" "1" \
                "1005" "3005" "12" \
                "1003" "1027" "11" \
                "2024" "4024" "2022" "4022" \
                "1004" "3004" \
                "144" "145" "146" "147");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "PyT_SMA_RT" ]]; then

                # Pyramidal tract SMA right

                PyT_SMA_RT_incs1_Ls=("BStem_FS");

                PyT_SMA_RT_incs1_Is=("16");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                PyT_SMA_RT_incs2_Ls=("SFG5_RT_MSBP" "SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP");

                PyT_SMA_RT_incs2_Is=("24" "25" "26" "27");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                PyT_SMA_RT_excs_Ls=("CC_allr_custom" "BStemr_exc_LT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" "RT_ML_X_custom" \
                "hypothal_bildil_excr_custom" "Thal_RT_ero2_custom" \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Putamen_RT_FS" \
                "cMFG_GM_RT_FS" "rMFG_GM_RT_FS" "Caudate_GM_RT_FS" \
                "M1_GM_RT_FS" "M1_WM_RT_FS" "S1_GM_RT_FS" "S1_WM_RT_FS" \
                "Occ_lobeGM_RT"  "Occ_lobeWM_RT" \
                "SFG1_RT_MSBP" "SFG2_RT_MSBP" "SFG3_RT_MSBP" "SFG4_RT_MSBP");

                PyT_SMA_RT_excs_Is=("1" "1" \
                "2003" "4003" "1" \
                "1" "1" \
                "2005" "4005" "12" \
                "2003" "2027" "50" \
                "2024" "4024" "2022" "4022" \
                "2004" "4004" \
                "20" "21" "22" "23");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

                # make excludes
                # labels for lobes
                # \
                # "Front_lobeGM_LT"  "Front_lobeWM_LT"  "Front_lobeGM_RT"  "Front_lobeWM_RT"  \
                # "Occ_lobeGM_LT"  "Occ_lobeWM_LT"  "Occ_lobeGM_RT"  "Occ_lobeWM_RT" \
                # "Temp_lobeGM_LT"  "Temp_lobeWM_LT"  "Temp_lobeGM_RT"  "Temp_lobeWM_RT" \
                # "Cing_lobeGM_LT"  "Cing_lobeWM_LT"  "Cing_lobeGM_RT"  "Cing_lobeWM_RT"  \
                # "Pari_lobeGM_LT"  "Pari_lobeWM_LT"  "Pari_lobeGM_RT"  "Pari_lobeWM_RT"
                # \
                # "1001"  "3001"  "2001"  "4001"  \
                # "1004"  "3004"  "2004"  "4004"  \
                # "1005"  "3005"  "2005"  "4005"  \
                # "1003"  "3003"  "2003"  "4003"  \
                # "1006"  "3006"  "2006"  "4006"  \
                # \

            elif [[ ${tck_list[$q]} == "ML_LT" ]]; then

                # Medial lemniscus left

                ML_LT_incs1_Ls=("ML_LT_UKBB");

                ML_LT_incs1_Is=("2");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # VPL_rois_LT=("9600" "9700" "9800" "11500" "11700" "11800");
                # VPM_rois_LT=("9500" "11300");

                ML_LT_incs2_Ls=("PD25_VPL_VPM_LT_custom");

                ML_LT_incs2_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ML_LT_incs3_Ls=("S1_GM_LT_FS");

                ML_LT_incs3_Is=("1022");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # currently generating this till Thalamus only
                # so we have an ipsilateral hemispheric WM exclude here - remove it if you want the whole thing
                ML_LT_excs_Ls=("CC_allr_custom" "BStemr_exc_RT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" "LT_CST_X_custom" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_LT" "Temp_lobeWM_LT" \
                "Putamen_LT_FS" "Hippo_LT_FS" "cMFG_GM_LT_FS" "Caudate_GM_LT_FS");

                ML_LT_excs_Is=("1" "1" \
                "1003" "3003" "1" \
                "1" "1005" "3005" \
                "12" "17" "1003" "11");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ML_RT" ]]; then

                # Medial lemniscus right
                # remember to regenerate the PD25 labels with -n multilabel
                # this probably applies to all priors for this project - except JHU, RL nd UKBB, so PD25 and SUIT?

                ML_RT_incs1_Ls=("ML_RT_UKBB");

                ML_RT_incs1_Is=("4");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # VPL_rois_RT=("96" "97" "98" "115" "117" "118");
                # VPM_rois_RT=("95" "113");

                ML_RT_incs2_Ls=("PD25_VPL_VPM_RT_custom");

                ML_RT_incs2_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ML_RT_incs3_Ls=("S1_GM_RT_FS");

                ML_RT_incs3_Is=("2022");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # so we have an ipsilateral hemispheric WM exclude here - remove it if you want the whole thing
                ML_RT_excs_Ls=("CC_allr_custom" "BStemr_exc_LT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" "RT_CST_X_custom" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_RT" "Temp_lobeWM_RT" \
                "Putamen_RT_FS" "Hippo_RT_FS" "cMFG_GM_RT_FS" "Caudate_GM_RT_FS");

                ML_RT_excs_Is=("1" "1" \
                "2003" "4003" "1" \
                "1" "2005" "4005" \
                "51" "53" "2003" "50");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "AF_all_LT" ]]; then

                # AF all left

                AF_all_LT_incs1_Ls=("IFGpTr_GM_LT_FS" "IFGpOp_GM_LT_FS");

                AF_all_LT_incs1_Is=("1020" "1018");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                AF_all_LT_incs2_Ls=("STG1_LT_MSBP" "STG2_LT_MSBP" "STG3_LT_MSBP" "bSTS_GM_LT_FS" "SMG_GM_LT_FS");

                AF_all_LT_incs2_Is=("224" "225" "226" "1001" "1031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                AF_all_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "M1_GM_FS_LT" \
                "s3Put_LT_custom"  "Thal_LT_FS"  \
                "STG4_LT_MSBP" "STG5_LT_MSBP" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" \
                "Insula_GMWM_LT_ero2_custom" "Cing_lobeGM_LT" "Cing_lobeWM_LT" "SFG_GM_LT_FS" "SFG_WM_LT_FS");

                AF_all_LT_excs_Is=("1" "16" "1024" \
                "1" "10" \
                "227" "228" \
                "1016" "3016" \
                "1" "1003" "3003" "1028" "3028");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "AF_all_RT" ]]; then

                # AF all right

                AF_all_RT_incs1_Ls=("IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS");

                AF_all_RT_incs1_Is=("2020" "2018");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                AF_all_RT_incs2_Ls=("STG1_RT_MSBP" "STG2_RT_MSBP" "STG3_RT_MSBP" "bSTS_GM_RT_FS" "SMG_GM_RT_FS");

                AF_all_RT_incs2_Is=("100" "101" "102" "2001" "2031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                AF_all_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "M1_GM_FS_RT" \
                "s3Put_RT_custom"  "Thal_RT_FS"  \
                "STG4_RT_MSBP" "STG5_RT_MSBP" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" \
                "Insula_GMWM_RT_ero2_custom" "Cing_lobeGM_RT" "Cing_lobeWM_RT" "SFG_GM_RT_FS" "SFG_WM_RT_FS");

                AF_all_RT_excs_Is=("1" "16" "2024" \
                "1" "49" \
                "103" "104" \
                "2016" "4016" \
                "1" "2003" "4003" "2028" "4028");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "AF_wprecentral_LT" ]]; then

                # AF all left

                AF_wprecentral_LT_incs1_Ls=("IFGpTr_GM_LT_FS" "IFGpOp_GM_LT_FS" "PreC1_LT_MSBP" "PreC2_LT_MSBP" "PreC3_LT_MSBP");

                AF_wprecentral_LT_incs1_Is=("1020" "1018" "155" "156" "157");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                AF_wprecentral_LT_incs2_Ls=("STG1_LT_MSBP" "STG2_LT_MSBP" "STG3_LT_MSBP" "bSTS_GM_LT_FS" "SMG_GM_LT_FS");

                AF_wprecentral_LT_incs2_Is=("224" "225" "226" "1001" "1031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                AF_wprecentral_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "PreC4_LT_MSBP" "PreC5_LT_MSBP" "PreC6_LT_MSBP" \
                "s3Put_LT_custom"  "Thal_LT_FS"  \
                "STG4_LT_MSBP" "STG5_LT_MSBP" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" \
                "Insula_GMWM_LT_ero2_custom" "Cing_lobeGM_LT" "Cing_lobeWM_LT" "SFG_GM_LT_FS" "SFG_WM_LT_FS");

                AF_wprecentral_LT_excs_Is=("1" "16" \
                "158" "159" "160" \
                "1" "10" \
                "227" "228" \
                "1016" "3016" \
                "1" "1003" "3003" "1028" "3028");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "AF_wprecentral_RT" ]]; then

                # AF all right

                AF_wprecentral_RT_incs1_Ls=("IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS" "PreC1_RT_MSBP" "PreC2_RT_MSBP" "PreC3_RT_MSBP");

                AF_wprecentral_RT_incs1_Is=("2020" "2018" "31" "32" "33");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                AF_wprecentral_RT_incs2_Ls=("STG1_RT_MSBP" "STG2_RT_MSBP" "STG3_RT_MSBP" "bSTS_GM_RT_FS" "SMG_GM_RT_FS");

                AF_wprecentral_RT_incs2_Is=("100" "101" "102" "2001" "2031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                AF_wprecentral_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "PreC4_RT_MSBP" "PreC5_RT_MSBP" "PreC6_RT_MSBP" \
                "s3Put_RT_custom"  "Thal_RT_FS"  \
                "STG4_RT_MSBP" "STG5_RT_MSBP" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" \
                "Insula_GMWM_RT_ero2_custom" "Cing_lobeGM_RT" "Cing_lobeWM_RT" "SFG_GM_RT_FS" "SFG_WM_RT_FS");

                AF_wprecentral_RT_excs_Is=("1" "16" \
                "34" "35" "36" \
                "1" "49" \
                "103" "104" \
                "2016" "4016" \
                "1" "2003" "4003" "2028" "4028");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "FAT_LT" ]]; then

                FAT_LT_incs1_Ls=("IFG_POp_GM_FS_LT");

                FAT_LT_incs1_Is=("1018");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                FAT_LT_incs2_Ls=("SFG5_MSBP_LT" "SFG6_MSBP_LT");

                FAT_LT_incs2_Is=("148" "149");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                FAT_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "Insula_GM_FS_LT" "Insula_WM_FS_LT" \
                "M1_GM_FS_LT" "M1_WM_FS_LT" "Med_OF_GM_FS_LT" "Med_OF_WM_FS_LT" \
                "LatOF_GM_FS_LT" "LatOF_WM_FS_LT" "IFG_POr_GM_FS_LT" "IFG_POr_WM_FS_LT" \
                "Caudate_FS_LT" "SFG1_MSBP_LT" "SFG2_MSBP_LT" "SFG3_MSBP_LT" "SFG4_MSBP_LT")

                FAT_LT_excs_Is=("1" "16" "1035" "3035" \
                "1024" "3024" "1014" "3014" \
                "1012" "3012" "1019" "3019" \
                "11" "144" "145" "146" "147")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "FAT_RT" ]]; then

                FAT_RT_incs1_Ls=("IFG_POp_GM_FS_RT");

                FAT_RT_incs1_Is=("2018");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                FAT_RT_incs2_Ls=("SFG5_MSBP_RT" "SFG6_MSBP_RT");

                FAT_RT_incs2_Is=("24" "25");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                FAT_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "Insula_GM_FS_RT" "Insula_WM_FS_RT" \
                "M1_GM_FS_RT" "M1_WM_FS_RT" "Med_OF_GM_FS_RT" "Med_OF_WM_FS_RT" \
                "LatOF_GM_FS_RT" "LatOF_WM_FS_RT" "IFG_POr_GM_FS_RT" "IFG_POr_WM_FS_RT" \
                "Caudate_FS_RT" "SFG1_MSBP_RT" "SFG2_MSBP_RT" "SFG3_MSBP_RT" "SFG4_MSBP_RT")

                FAT_RT_excs_Is=("1" "16" "2035" "4035" \
                "2024" "4024" "2014" "4014" \
                "2012" "4012" "2019" "4019" \
                "50" "20" "21" "22" "23")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

                # elif [[ ${tck_list[$q]} == "SLF_II_LT" ]]; then

                #     SLF_II_LT_incs1_Ls=("cMFG_GM_LT_FS" "rMFG1_LT_MSBP");

                #     SLF_II_LT_incs1_Is=("1003" "138");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                #     SLF_II_LT_incs2_Ls=("SMG_GM_LT_FS" "IPL_GM_LT_FS");

                #     SLF_II_LT_incs2_Is=("1031" "1008");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                #     SLF_II_LT_excs_Ls=("SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" "SFG4_LT_MSBP" "SFG5_LT_MSBP" \
                #     "CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "Thal_LT_FS"  \
                #     "Temp_lobeGM_LT" "Temp_lobeWM_LT" \
                #     "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" "Insula_GM_LT_FS" \
                #     "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                #     "PCC_GM_LT_FS" "PCC_WM_LT_FS" "SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP" \
                #     "SPL_GM_LT_FS");

                #     SLF_II_LT_excs_Is=("144" "145" "146" "147" "148" \
                #     "1" "16" "1" "10" "1005" "3005" "1016" "3016" "1035" "3035" "1003" "3003" "1023" "3023" "149" "150" "151" "1029");

                #     tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_all_LT" ]]; then

                # SLF_all left

                SLF_all_LT_incs1_Ls=("SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP" "cMFG_GM_LT_FS" "rMFG1_LT_MSBP" \
                "IFGpTr_GM_LT_FS" "IFGpOp_GM_LT_FS" "IFGpOr_GM_LT_FS");

                SLF_all_LT_incs1_Is=("149" "150" "151" "1003" "138" "1020" "1018" "1019");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_all_LT_incs2_Ls=("SPL_GM_LT_FS" "IPL_GM_LT_FS" "SMG_GM_LT_FS");

                SLF_all_LT_incs2_Is=("1029" "1008" "1031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_all_LT_excs_Ls=("SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" "SFG4_LT_MSBP" "SFG5_LT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "Thal_LT_FS"  \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" "Insula_GM_LT_FS" \
                "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "PCC_GM_LT_FS" "PCC_WM_LT_FS");

                SLF_all_LT_excs_Is=("144" "145" "146" "147" "148" \
                "1" "16" "1" "10" \
                "1005" "3005" \
                "1016" "3016" "1035" \
                "3035" "1003" "3003" \
                "1023" "3023");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_all_RT" ]]; then

                # SLF_all right

                SLF_all_RT_incs1_Ls=("SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP" "cMFG_GM_RT_FS" "rMFG1_RT_MSBP" \
                "IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS" "IFGpOr_GM_RT_FS");

                SLF_all_RT_incs1_Is=("25" "26" "27" "2003" "14" "2020" "2018" "2019");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_all_RT_incs2_Ls=("SPL_GM_RT_FS" "IPL_GM_RT_FS" "SMG_GM_RT_FS");

                SLF_all_RT_incs2_Is=("2029" "2008" "2031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_all_RT_excs_Ls=("SFG1_RT_MSBP" "SFG2_RT_MSBP" "SFG3_RT_MSBP" "SFG4_RT_MSBP" "SFG5_RT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "Thal_RT_FS"  \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" "Insula_GM_RT_FS" \
                "Insula_WM_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "PCC_GM_RT_FS" "PCC_WM_RT_FS");

                SLF_all_RT_excs_Is=("20" "21" "22" "23" "24" \
                "1" "16" "1" "49" \
                "2005" "4005" \
                "2016" "4016" "2035" \
                "4035" "2003" "4003" \
                "2023" "4023");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_I_LT" ]]; then

                SLF_I_LT_incs1_Ls=("SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP");

                SLF_I_LT_incs1_Is=("149" "150" "151");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_I_LT_incs2_Ls=("SPL2_LT_MSBP");

                SLF_I_LT_incs2_Is=("179");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_I_LT_excs_Ls=("SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" \
                "SFG4_LT_MSBP" "SFG5_LT_MSBP" "S1_GM_LT_FS" "S1_WM_LT_FS" \
                "CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "Thal_LT_FS"  \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" "Insula_GM_LT_FS" \
                "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "PCC_GM_LT_FS" "PCC_WM_LT_FS" "cMFG_GM_LT_FS" "rMFG_GM_LT_FS" \
                "IFGpTr_GM_LT_FS" "IFGpOp_GM_LT_FS" "IFGpOr_GM_LT_FS" \
                "IPL_GM_LT_FS" "SMG_GM_LT_FS" "M1_GM_LT_FS" \
                "SPL3_LT_MSBP" "SPL4_LT_MSBP" "SPL5_LT_MSBP" "SPL6_LT_MSBP");

                SLF_I_LT_excs_Is=("144" "145" "146" \
                "147" "148" "1022" "3022" \
                "1" "16" "1" "10" \
                "1005" "3005" \
                "1016" "3016" "1035" \
                "3035" "1003" "3003" \
                "1023" "3023" "1003" "1027" \
                "1020" "1018" "1019" \
                "1008" "1031" "1024" \
                "180" "181" "182" "183");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_I_RT" ]]; then

                SLF_I_RT_incs1_Ls=("SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP");

                SLF_I_RT_incs1_Is=("25" "26" "27");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_I_RT_incs2_Ls=("SPL2_RT_MSBP");

                SLF_I_RT_incs2_Is=("55");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_I_RT_excs_Ls=("SFG1_RT_MSBP" "SFG2_RT_MSBP" "SFG3_RT_MSBP" "SFG4_RT_MSBP" \
                "SFG5_RT_MSBP" "S1_GM_RT_FS" "S1_WM_RT_FS" \
                "CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "Thal_RT_FS"  \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" "Insula_GM_RT_FS" \
                "Insula_WM_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "PCC_GM_RT_FS" "PCC_WM_RT_FS" "cMFG_GM_RT_FS" "cMFG_GM_RT_FS" \
                "IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS" "IFGpOr_GM_RT_FS" \
                "IPL_GM_RT_FS" "SMG_GM_RT_FS" "M1_GM_RT_FS" \
                "SPL3_RT_MSBP" "SPL4_RT_MSBP" "SPL5_RT_MSBP" "SPL6_RT_MSBP");

                SLF_I_RT_excs_Is=("20" "21" "22" "23" \
                "24" "2022" "4022" \
                "1" "16" "1" "49" \
                "2005" "4005" \
                "2016" "4016" "2035" \
                "4035" "2003" "4003" \
                "2023" "4023" "2003" "2027" \
                "2020" "2018" "2019" \
                "2008" "2031" "2024" \
                "56" "57" "58" "59");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_IId_LT" ]]; then

                SLF_IId_LT_incs1_Ls=("cMFG_GM_LT_FS" "rMFG1_LT_MSBP");

                SLF_IId_LT_incs1_Is=("1003" "138");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_IId_LT_incs2_Ls=("SMG_GM_LT_FS" "IPL_GM_LT_FS");

                SLF_IId_LT_incs2_Is=("1031" "1008");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_IId_LT_excs_Ls=("SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" "SFG4_LT_MSBP" "SFG5_LT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "Thal_LT_FS"  \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "rMFG_GM_LT_FS" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" "Insula_GM_LT_FS" \
                "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "PCC_GM_LT_FS" "PCC_WM_LT_FS" "SFG6_LT_MSBP" "SFG7_LT_MSBP" \
                "SFG8_LT_MSBP" "SPL_GM_LT_FS");

                SLF_IId_LT_excs_Is=("144" "145" "146" "147" "148" \
                "1" "16" "1" "10" \
                "1005" "3005" "1027" \
                "1016" "3016" "1035" \
                "3035" "1003" "3003" \
                "1023" "3023" "149" "150" \
                "151" "1029");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_IId_RT" ]]; then

                SLF_IId_RT_incs1_Ls=("cMFG_GM_RT_FS" "rMFG1_RT_MSBP");

                SLF_IId_RT_incs1_Is=("2003" "14");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_IId_RT_incs2_Ls=("IPL_GM_RT_FS" "SMG_GM_RT_FS");

                SLF_IId_RT_incs2_Is=("2008" "2031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_IId_RT_excs_Ls=("SFG1_RT_MSBP" "SFG2_RT_MSBP" "SFG3_RT_MSBP" "SFG4_RT_MSBP" "SFG5_RT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "Thal_RT_FS"  \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "rMFG_GM_RT_FS" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" "Insula_GM_RT_FS" \
                "Insula_WM_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "PCC_GM_RT_FS" "PCC_WM_RT_FS" "SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP" \
                "IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS" "IFGpOr_GM_RT_FS" "SPL_GM_RT_FS");

                SLF_IId_RT_excs_Is=("20" "21" "22" "23" "24" \
                "1" "16" "1" "49" \
                "2005" "4005" "2027" \
                "2016" "4016" "2035" \
                "4035" "2003" "4003" \
                "2023" "4023" "25" "26" "27" \
                "2020" "2018" "2019" "2029");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_IIv_LT" ]]; then

                SLF_IIv_LT_incs1_Ls=("rMFG_GM_LT_FS");

                SLF_IIv_LT_incs1_Is=("1027");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_IIv_LT_incs2_Ls=("SMG_GM_LT_FS" "IPL_GM_LT_FS");

                SLF_IIv_LT_incs2_Is=("1031" "1008");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_IIv_LT_excs_Ls=("SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" "SFG4_LT_MSBP" "SFG5_LT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "Thal_LT_FS"  \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "cMFG_GM_LT_FS" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" "Insula_GM_LT_FS" \
                "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "PCC_GM_LT_FS" "PCC_WM_LT_FS" "SFG6_LT_MSBP" "SFG7_LT_MSBP" \
                "SFG8_LT_MSBP" "SPL_GM_LT_FS");

                SLF_IIv_LT_excs_Is=("144" "145" "146" "147" "148" \
                "1" "16" "1" "10" \
                "1005" "3005" "1003" \
                "1016" "3016" "1035" \
                "3035" "1003" "3003" \
                "1023" "3023" "149" "150" \
                "151" "1029");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_IIv_RT" ]]; then

                SLF_IIv_RT_incs1_Ls=("rMFG_GM_RT_FS");

                SLF_IIv_RT_incs1_Is=("2027" "14");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_IIv_RT_incs2_Ls=("IPL_GM_RT_FS" "SMG_GM_RT_FS");

                SLF_IIv_RT_incs2_Is=("2008" "2031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_IIv_RT_excs_Ls=("SFG1_RT_MSBP" "SFG2_RT_MSBP" "SFG3_RT_MSBP" "SFG4_RT_MSBP" "SFG5_RT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "Thal_RT_FS"  \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "cMFG_GM_RT_FS" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" "Insula_GM_RT_FS" \
                "Insula_WM_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "PCC_GM_RT_FS" "PCC_WM_RT_FS" "SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP" \
                "IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS" "IFGpOr_GM_RT_FS" "SPL_GM_RT_FS");

                SLF_IIv_RT_excs_Is=("20" "21" "22" "23" "24" \
                "1" "16" "1" "49" \
                "2005" "4005" "2003" \
                "2016" "4016" "2035" \
                "4035" "2003" "4003" \
                "2023" "4023" "25" "26" "27" \
                "2020" "2018" "2019" "2029");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_III_LT" ]]; then

                SLF_III_LT_incs1_Ls=("IFGpTr_GM_LT_FS" "IFGpOp_GM_LT_FS" "IFGpOr_GM_LT_FS");

                SLF_III_LT_incs1_Is=("1020" "1018" "1019");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_III_LT_incs2_Ls=("SMG_GM_LT_FS" "IPL_GM_LT_FS");

                SLF_III_LT_incs2_Is=("1031" "1008");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_III_LT_excs_Ls=("SFG1_LT_MSBP" "SFG2_LT_MSBP" "SFG3_LT_MSBP" "SFG4_LT_MSBP" "SFG5_LT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_LT_custom" "Thal_LT_FS"  \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" "Insula_GM_LT_FS" \
                "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "PCC_GM_LT_FS" "PCC_WM_LT_FS" "SFG6_LT_MSBP" "SFG7_LT_MSBP" \
                "SFG8_LT_MSBP" "cMFG_GM_LT_FS" "rMFG1_LT_MSBP" "SPL_GM_LT_FS");

                SLF_III_LT_excs_Is=("144" "145" "146" "147" "148" \
                "1" "16" "1" "10" \
                "1005" "3005" \
                "1016" "3016" "1035" \
                "3035" "1003" "3003" \
                "1023" "3023" "149" "150" \
                "151" "1003" "138" "1029");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SLF_III_RT" ]]; then

                SLF_III_RT_incs1_Ls=("IFGpTr_GM_RT_FS" "IFGpOp_GM_RT_FS" "IFGpOr_GM_RT_FS");

                SLF_III_RT_incs1_Is=("2020" "2018" "2019");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SLF_III_RT_incs2_Ls=("IPL_GM_RT_FS" "SMG_GM_RT_FS");

                SLF_III_RT_incs2_Is=("2008" "2031");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SLF_III_RT_excs_Ls=("SFG1_RT_MSBP" "SFG2_RT_MSBP" "SFG3_RT_MSBP" "SFG4_RT_MSBP" "SFG5_RT_MSBP" \
                "CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "Thal_RT_FS"  \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" "Insula_GM_RT_FS" \
                "Insula_WM_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "PCC_GM_RT_FS" "PCC_WM_RT_FS" "SFG6_RT_MSBP" "SFG7_RT_MSBP" \
                "SFG8_RT_MSBP" "cMFG_GM_RT_FS" "rMFG1_RT_MSBP" "SPL_GM_RT_FS");

                SLF_III_RT_excs_Is=("20" "21" "22" "23" "24" \
                "1" "16" "1" "49" \
                "2005" "4005" \
                "2016" "4016" "2035" \
                "4035" "2003" "4003" \
                "2023" "4023" "25" "26" \
                "27" "2003" "14" "2029");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "IFOF_LT" ]]; then

                IFOF_LT_incs1_Ls=("SPL_GM_LT_FS" "IPL_GM_LT_FS" "Occ_lobeGM_LT" "Pc_GM_LT_FS" "Fusi1_LT_MSBP" "Fusi2_LT_MSBP");

                IFOF_LT_incs1_Is=("1029" "1008" "1004" "1025" "208" "209");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                IFOF_LT_incs2_Ls=("rMFG5_LT_MSBP" "rMFG6_LT_MSBP" "FP_GM_LT_FS" "IFGpTr_GM_LT_FS" "MedOF1_LT_MSBP" "LatOF_GM_LT_FS");

                IFOF_LT_incs2_Is=("141" "142" "1032" "1020" "131" "1012");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # add pOp and the cMFGs to the excludes
                IFOF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "STG5_GMWM_LT_custom" "e2Put_LT_custom" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" "SFG_GM_LT_FS"  "SFG_WM_LT_FS" \
                "M1_GM_LT_FS" "M1_WM_LT_FS" "TempP_GM_LT_FS" "TempP_WM_LT_FS" \
                "ITG_GM_LT_FS" "AC_midL_MAN" "Acc_GM_LT_FS" \
                "Pall_GM_LT_FS" "Amyg_GM_LT_FS" "Thal_GM_LT_FS" "Hippo_GM_LT_FS" \
                "vDC_LT_FS" "caudate_LT_FS" "OptCh_FS" "SegWM_LT_MPV_custom" \
                "SegWM_LT_PLIC_custom" "SegWM_LT_ALIC_custom" "Ins_supL_wm_LT_custom" \
                "cMFG_GM_LT_FS" "cMFG_WM_LT_FS" "IFGpOp_GM_LT_FS" "IFGpOp_WM_LT_FS" \
                "Fusi4_GMWM_LT_custom" "TempP_GM_FS_LT" "TempP_WM_FS_LT" "ITG_GM_FS_LT" "ITG_WM_FS_LT" \
                "MedOF2_LT_MSBP" "MedOF3_LT_MSBP");

                IFOF_LT_excs_Is=("1" "16" \
                "1" "1" \
                "1016" "3016" \
                "1003" "3003" "1028"  "3028" \
                "1024" "3024" "1033" "3033" \
                "1009" "1" "26" \
                "13" "18" "10" "17" \
                "28" "11" "85" "1" \
                "1" "1" "1" \
                "1003" "3003" "1018" "3018" \
                "1" "1033" "3033" "1009" "3009" \
                "132" "133");

                # removed
                # "ITG_WM_LT_FS" 
                # "3009"

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "IFOF_RT" ]]; then

                IFOF_RT_incs1_Ls=("SPL_GM_RT_FS" "IPL_GM_RT_FS" "Occ_lobeGM_RT" "Pc_GM_RT_FS" "Fusi1_RT_MSBP" "Fusi2_RT_MSBP");

                IFOF_RT_incs1_Is=("2029" "2008" "2004" "2025" "84" "85");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                IFOF_RT_incs2_Ls=("rMFG5_LT_MSBP" "rMFG6_LT_MSBP" "FP_GM_LT_FS" "IFGpTr_GM_LT_FS" "MedOF1_LT_MSBP" "LatOF_GM_LT_FS");

                IFOF_RT_incs2_Is=("18" "19" "2032" "2020" "7" "2012");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                IFOF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "STG5_GMWM_RT_custom" "e2Put_RT_custom" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" "SFG_GM_RT_FS" "SFG_WM_RT_FS" \
                "M1_GM_RT_FS" "M1_WM_RT_FS" "TempP_GM_RT_FS" "TempP_WM_RT_FS" \
                "ITG_GM_RT_FS" "AC_midL_MAN" "Acc_GM_RT_FS" \
                "Pall_GM_RT_FS" "Amyg_GM_RT_FS" "Thal_GM_RT_FS" "Hippo_GM_RT_FS" \
                "vDC_RT_FS" "caudate_RT_FS" "OptCh_FS" "SegWM_RT_MPV_custom" \
                "SegWM_RT_PLIC_custom" "SegWM_RT_ALIC_custom" "Ins_supL_wm_RT_custom" \
                "cMFG_GM_RT_FS" "cMFG_WM_RT_FS" "IFGpOp_GM_RT_FS" "IFGpOp_WM_RT_FS" \
                "Fusi4_GMWM_RT_custom" "TempP_GM_FS_RT" "TempP_WM_FS_RT" "ITG_GM_FS_RT" "ITG_WM_FS_RT" \
                "MedOF2_RT_MSBP" "MedOF3_RT_MSBP");

                # must handle unseg WM if this is gonna work
                # also the STG subseg for WM and the Insular WM

                IFOF_RT_excs_Is=("1" "16" \
                "1" "1" \
                "2016" "4016" \
                "2003" "4003" "2028" "4028" \
                "2024" "4024" "2033" "4033" \
                "2009" "1" "58" \
                "52" "54" "49" "53" \
                "60" "50" "85" "1" \
                "1" "1" "1" \
                "2003" "4003" "2018" "4018" \
                "1" "2033" "4033" "2009" "4009" \
                "8" "9");

                # removed 
                # "ITG_WM_RT_FS"
                # "4009"

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ILF_LT" ]]; then

                ILF_LT_incs1_Ls=("Occ_lobeGM_LT");

                ILF_LT_incs1_Is=("1004");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # this is not specific enough
                ILF_LT_incs2_Ls=("ITG1_MSBP_LT" "ITG2_MSBP_LT" "MTG4_MSBP_LT" "TempP_GM_FS_LT" "Fusi4_MSBP_LT");

                ILF_LT_incs2_Is=("215" "216" "222" "1033" "211");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ILF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "STG_GM_LT_FS" "G_OSup_GM_LT_2009" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "AC_midL_MAN" "Hippo_GM_LT_FS" "vDC_LT_FS" \
                "OptCh_FS" "Insula_GM_LT_FS" "Insula_WM_LT_FS" \
                "Front_lobeGM_FS" "Front_lobeWM_FS" "Pari_lobeGM_FS" "Pari_lobeWM_FS" \
                "SegWM_LT_MPV_custom" "M1_GM_LT_FS" "M1_WM_LT_FS");
                # must handle unseg WM if this is gonna work
                # also the STG subseg for WM and the Insular WM

                ILF_LT_excs_Is=("1" "16" \
                "1030" "1116" \
                "1016" "3016" \
                "1003" "3003" \
                "1" "17" "28" \
                "85" "1035" "3035" \
                "1001" "3001" "1006" "3006" \
                "1" "1024" "3024");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ILF_RT" ]]; then

                ILF_RT_incs1_Ls=("Occ_lobeGM_RT");

                ILF_RT_incs1_Is=("2004");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ILF_RT_incs2_Ls=("ITG1_MSBP_RT" "ITG2_MSBP_RT" "MTG4_MSBP_RT" "TempP_GM_FS_RT" "Fusi4_MSBP_RT");

                ILF_RT_incs2_Is=("91" "92" "98" "2033" "87");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ILF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "STG_GM_RT_FS" "G_OSup_GM_RT_2009" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "AC_midL_MAN" "Hippo_GM_RT_FS" "vDC_RT_FS" \
                "OptCh_FS" "Insula_GM_RT_FS" "Insula_WM_RT_FS" \
                "Front_lobeGM_RT" "Front_lobeWM_RT" "Pari_lobeGM_RT" "Pari_lobeWM_RT" \
                "SegWM_RT_MPV_custom" "M1_GM_RT_FS" "M1_WM_RT_FS");
                # must handle unseg WM if this is gonna work
                # also the STG subseg for WM and the Insular WM

                ILF_RT_excs_Is=("1" "16" \
                "2030" "2116" \
                "2016" "4016" \
                "2003" "4003" \
                "1" "53" "60" \
                "85" "2035" "4035" \
                "2001" "4001" "2006" "4006" \
                "1" "2024" "4024");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "MdLF_LT" ]]; then

                MdLF_LT_incs1_Ls=("SPL_GM_LT_FS" "IPL_GM_LT_FS" "G_OSup_GM_LT_2009" "Cun_GM_LT_FS" "Pc_GM_LT_FS");

                MdLF_LT_incs1_Is=("1029" "1008" "1116" "1005" "1025");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                MdLF_LT_incs2_Ls=("STG5_MSBP_LT" "STG4_MSBP_LT" "STG3_MSBP_LT" "Temp_P_GM_LT_FS");

                MdLF_LT_incs2_Is=("228" "227" "226" "1033");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # add SMGs as excludes
                MdLF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "Phippo_GM_LT_FS" "Phippo_WM_LT_FS" \
                "Ins_IFOF_exc_LT_custom" "s3Put_LT_custom" \
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "AC_midL_MAN" "Hippo_GM_LT_FS" "vDC_LT_FS" \
                "OptCh_FS" "Insula_GM_LT_FS" "Insula_WM_LT_FS" \
                "Front_lobeGM_LT" "Front_lobeWM_LT" \
                "Fusi_GM_LT_FS" "Fusi_WM_LT_FS" "SegWM_LT_LPV_custom" \
                "ITG_GM_LT_FS" "ITG_WM_LT_FS");

                # must handle unseg WM if this is gonna work
                # also the STG subseg for WM and the Insular WM

                MdLF_LT_excs_Is=("1" "16" \
                "1016" "3016" \
                "1" "1" \
                "1003" "3003" \
                "1" "17" "28" \
                "85" "1035" "3035" \
                "1001" "3001" \
                "1007" "3007" "1" \
                "1009" "3009");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "MdLF_RT" ]]; then

                MdLF_RT_incs1_Ls=("SPL_GM_RT_FS" "IPL_GM_RT_FS" "G_OSup_GM_RT_2009" "Cun_GM_RT_FS" "Pc_GM_RT_FS");

                MdLF_RT_incs1_Is=("2029" "2008" "2116" "2005" "2025");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                MdLF_RT_incs2_Ls=("STG5_MSBP_RT" "STG4_MSBP_RT" "STG3_MSBP_RT" "Temp_P_GM_RT_FS");

                MdLF_RT_incs2_Is=("104" "103" "102" "2033");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                MdLF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "Phippo_GM_RT_FS" "Phippo_WM_RT_FS" \
                "Ins_IFOF_exc_RT_custom" "s3Put_RT_custom" \
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "AC_midL_MAN" "Hippo_GM_RT_FS" "vDC_RT_FS" \
                "OptCh_FS" "Insula_GM_RT_FS" "Insula_WM_RT_FS" \
                "Front_lobeGM_RT" "Front_lobeWM_RT" \
                "Fusi_GM_RT_FS" "Fusi_WM_RT_FS" "SegWM_RT_LPV_custom" \
                "ITG_GM_RT_FS" "ITG_WM_RT_FS");
                # must handle unseg WM if this is gonna work
                # also the STG subseg for WM and the Insular WM
                # might need to add ITG WM here...

                MdLF_RT_excs_Is=("1" "16" \
                "2016" "4016" \
                "1" "1" \
                "2003" "4003" \
                "1" "53" "60" \
                "85" "2035" "4035" \
                "2001" "4001" \
                "2007" "4007" "1" \
                "2009" "4009");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "OR_LT" ]]; then
                # consider adding iPCC_min_thal to the mix if results are unsatisfactory

                OR_LT_incs1_Ls=("PD25_Pulvi_LT_custom" "JuHA_LGN_LT_custom");
                # REMOVED "JuHA_LGN_LT_custom"

                OR_LT_incs1_Is=("1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                OR_LT_incs2_Ls=("Calc_S_LT_2009" "PeriCal_LT_GM_FS");

                OR_LT_incs2_Is=("11145" "1021");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # removed PD25_VPALPLPM_LT_custom from excludes
                # removed Thal_min_pulv
                # removed "vDC_FS_LT" "28"
                OR_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "Phippo_GM_LT_FS" "LT_vDC_subseg2_custom" \
                "Ins_IFOF_exc_LT_custom" "PD25_VA_VL_LT_custom"\
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "AC_midL_MAN" "Hippo_GM_LT_FS" \
                "OptCh_FS" "Insula_GM_LT_FS" "SegWM_LT_PLIC_ex_custom" \
                "Front_lobeGM_LT" "Pari_lobeGM_LT" \
                "iPCC_GM_LT_FS" "Caudate_GM_LT_FS" "SegWM_LT_ALIC_custom" \
                "SegWM_LT_MPV_custom" "SegWM_LT_mIPV_custom" "Ins_subseg3_LT_custom" \
                "Fusi4_MSBP_LT" "TempP_GM_FS_LT" "TempP_WM_FS_LT" "ITG_GM_FS_LT" "ITG_WM_FS_LT" \
                "Ins_infL_wm_LT_custom" "Ins_subseg5_LT_custom");
                
                #"Fusi4_GMWM_LT_custom" replaced by Fusi4 MSBP

                OR_LT_excs_Is=("1" "16" \
                "1016" "1" \
                "1" "1" \
                "1003" "3003" \
                "1" "17" \
                "85" "1035" \
                "1001" "1006" "1" \
                "1010" "11" "1" \
                "1" "1" "1" \
                "211" "1033" "3033" "1009" "3009" \
                "1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "OR_RT" ]]; then
                # consider adding iPCC_min_thal to the mix if results are unsatisfactory

                OR_RT_incs1_Ls=("PD25_Pulvi_RT_custom" "JuHA_LGN_RT_custom");
                # removed LGN from incs2 "JuHA_LGN_RT_custom"

                OR_RT_incs1_Is=("1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                OR_RT_incs2_Ls=("Calc_S_RT_2009" "PeriCal_RT_GM_FS");

                OR_RT_incs2_Is=("12145" "2021");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # consider removing the vDC as an exclude
                # also removed PD25_VPALPLPM_RT_custom from excludes
                # removed frontal lobe white matter exclude
                # removed "vDC_FS_RT" "60"

                OR_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "Phippo_GM_RT_FS" "RT_vDC_subseg2_custom" \
                "Ins_IFOF_exc_RT_custom" "PD25_VA_VL_LT_custom"\
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "AC_midL_MAN" "Hippo_GM_RT_FS" \
                "OptCh_FS" "Insula_GM_RT_FS" \
                "Front_lobeGM_RT" "Pari_lobeGM_RT" "SegWM_RT_PLIC_ex_custom" \
                "iPCC_GM_RT_FS" "Caudate_GM_RT_FS" "SegWM_RT_ALIC_custom" \
                "SegWM_RT_MPV_custom" "SegWM_RT_mIPV_custom" "Ins_subseg3_RT_custom" \
                "Fusi4_MSBP_RT" "TempP_GM_FS_RT" "TempP_WM_FS_RT" "ITG_GM_FS_RT" "ITG_WM_FS_RT" \
                "Ins_infL_wm_RT_custom" "Ins_subseg5_RT_custom");

                OR_RT_excs_Is=("1" "16" \
                "2016" "1" \
                "1" "1" \
                "2003" "4003" \
                "1" "53" \
                "85" "2035" \
                "2001" "2006" "1" \
                "2010" "50" "1" \
                "1" "1" "1" \
                "87" "2033" "4033" "2009" "4009" \
                "1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "OR_occlobe_LT" ]]; then

                # Here we use whole thalamus and whole occipital lobe

                OR_occlobe_LT_incs1_Ls=("Occ_lobeGM_LT");

                OR_occlobe_LT_incs1_Is=("1004");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                OR_occlobe_LT_incs2_Ls=("PD25_Pulvi_LT_custom");

                OR_occlobe_LT_incs2_Is=("10");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # removed PD25_VPALPLPM_LT_custom from excludes
                OR_occlobe_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "Phippo_GM_LT_FS" "LT_vDC_subseg2_custom" \
                "Ins_IFOF_exc_LT_custom" "PD25_VA_VL_LT_custom"\
                "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "AC_midL_MAN" "Hippo_GM_LT_FS" \
                "OptCh_FS" "Insula_GM_LT_FS" "SegWM_LT_PLIC_ex_custom" \
                "Front_lobeGM_LT" "Pari_lobeGM_LT" \
                "iPCC_GM_LT_FS" "Caudate_GM_LT_FS" "SegWM_LT_ALIC_custom" \
                "SegWM_LT_MPV_custom" "SegWM_LT_mIPV_custom" "Ins_subseg3_LT_custom" \
                "Fusi4_MSBP_LT" "TempP_GM_FS_LT" "TempP_WM_FS_LT" "ITG_GM_FS_LT" "ITG_WM_FS_LT" \
                "Ins_infL_wm_LT_custom" "Ins_subseg5_LT_custom");

                OR_occlobe_LT_excs_Is=("1" "16" \
                "1016" "1" \
                "1" "1" \
                "1003" "3003" \
                "1" "17" \
                "85" "1035" \
                "1001" "1006" "1" \
                "1010" "11" "1" \
                "1" "1" "1" \
                "211" "1033" "3033" "1009" "3009" \
                "1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "OR_occlobe_RT" ]]; then

                # Here we use whole thalamus and whole occipital lobe

                OR_occlobe_RT_incs1_Ls=("Occ_lobeGM_RT");

                OR_occlobe_RT_incs1_Is=("2004");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                OR_occlobe_RT_incs2_Ls=("PD25_Pulvi_RT_custom");

                OR_occlobe_RT_incs2_Is=("49");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # removed PD25_VPALPLPM_RT_custom from excludes
                OR_occlobe_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "Phippo_GM_RT_FS" "RT_vDC_subseg2_custom" \
                "Ins_IFOF_exc_RT_custom" "PD25_VA_VL_LT_custom"\
                "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "AC_midL_MAN" "Hippo_GM_RT_FS" \
                "OptCh_FS" "Insula_GM_RT_FS" \
                "Front_lobeGM_RT" "Pari_lobeGM_RT" "SegWM_RT_PLIC_ex_custom" \
                "iPCC_GM_RT_FS" "Caudate_GM_RT_FS" "SegWM_RT_ALIC_custom" \
                "SegWM_RT_MPV_custom" "SegWM_RT_mIPV_custom" "Ins_subseg3_RT_custom" \
                "Fusi4_MSBP_RT" "TempP_GM_FS_RT" "TempP_WM_FS_RT" "ITG_GM_FS_RT" "ITG_WM_FS_RT" \
                "Ins_infL_wm_RT_custom" "Ins_subseg5_RT_custom");

                # "Pari_exc_OR_RT_custom"

                OR_occlobe_RT_excs_Is=("1" "16" \
                "2016" "1" \
                "1" "1" \
                "2003" "4003" \
                "1" "53" \
                "85" "2035" \
                "2001" "2006" "1" \
                "2010" "50" "1" \
                "1" "1" "1" \
                "87" "2033" "4033" "2009" "4009" \
                "1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "OT_LT" ]]; then
                # consider adding iPCC_min_thal to the mix if results are unsatisfactory

                OT_LT_incs1_Ls=("OptCh_FS");

                OT_LT_incs1_Is=("85");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                OT_LT_incs2_Ls=("PD25_Pulvi_LT_custom");

                OT_LT_incs2_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                OT_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "Putamen_FS_LT" "Hippo_FS_LT" \
                "Caudate_FS_LT" "CGM_aseg_LT" "Front_lobeWM_LT" "Fornix_Fx" \
                "PD25_DM_LT_custom" "PD25_DL_LT_custom" "Pari_lobeGM_LT" "Pari_lobeWM_LT" \
                "M1_GM_FS_LT" "M1_WM_FS_LT" "Thal_min_Pulvi_LT_custom");

                OT_LT_excs_Is=("1" "16" "12" "17" \
                "11" "3" "3001" "250" \
                "1" "1" "1006" "3006" \
                "1024" "3024" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "OT_RT" ]]; then

                OT_RT_incs1_Ls=("OptCh_FS");

                OT_RT_incs1_Is=("85");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                OT_RT_incs2_Ls=("PD25_Pulvi_RT_custom");

                OT_RT_incs2_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # consider removing the vDC as an exclude
                OT_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "Putamen_FS_RT" "Hippo_FS_RT" \
                "Caudate_FS_RT" "CGM_aseg_RT" "Front_lobeWM_RT" "Fornix_Fx" \
                "PD25_DM_RT_custom" "PD25_DL_RT_custom" "Pari_lobeGM_RT" "Pari_lobeWM_RT" \
                "M1_GM_FS_RT" "M1_WM_FS_RT" "Thal_min_Pulvi_RT_custom");

                OT_RT_excs_Is=("1" "16" "51" "53" \
                "50" "42" "4001" "250" \
                "1" "1" "2006" "4006" \
                "2024" "4024" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "IPLFus_LT" ]]; then

                IPLFus_LT_incs1_Ls=("IPL1_MSBP_LT" "IPL2_MSBP_LT" "IPL3_MSBP_LT" "IPL4_MSBP_LT");

                IPLFus_LT_incs1_Is=("185" "186" "187" "188");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                IPLFus_LT_incs2_Ls=("ITG4_MSBP_LT" "Fusi1_MSBP_LT" "Fusi2_MSBP_LT");

                IPLFus_LT_incs2_Is=("218" "208" "209");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                IPLFus_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHip_GM_FS_LT" "PHip_WM_FS_LT" "Front_lobeGM_LT" "Front_lobeWM_LT" \
                "STG_GM_FS_LT" "STG_WM_FS_LT" "Cune_GM_FS_LT" "Cune_WM_FS_LT" "Pc_GM_FS_LT" "SPL_GM_FS_LT" \
                "ITG1_MSBP_LT" "ITG2_MSBP_LT" "ITG3_MSBP_LT" "MTG_GM_FS_LT" "S1_GM_FS_LT")

                IPLFus_LT_excs_Is=("1" "16" "1016" "3016" "1001" "3001" \
                "2030" "4030" "1005" "3005" "1025" "1029" \
                "215" "216" "217" "1015" "1022")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "IPLFus_RT" ]]; then

                IPLFus_RT_incs1_Ls=("IPL1_MSBP_RT" "IPL2_MSBP_RT" "IPL3_MSBP_RT" "IPL4_MSBP_RT");

                IPLFus_RT_incs1_Is=("61" "62" "63" "64");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                IPLFus_RT_incs2_Ls=("ITG4_MSBP_RT" "Fusi1_MSBP_RT" "Fusi2_MSBP_RT");

                IPLFus_RT_incs2_Is=("94" "84" "85");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                IPLFus_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHip_GM_FS_RT" "PHip_WM_FS_RT" "Front_lobeGM_RT" "Front_lobeWM_RT" \
                "STG_GM_FS_RT" "STG_WM_FS_RT" "Cune_GM_FS_RT" "Cune_WM_FS_RT" "Pc_GM_FS_RT" "SPL_GM_FS_RT" \
                "ITG1_MSBP_RT" "ITG2_MSBP_RT" "ITG3_MSBP_RT" "MTG_GM_FS_RT" "S1_GM_FS_RT")

                IPLFus_RT_excs_Is=("1" "16" "2016" "4016" "2001" "4001" \
                "2030" "4030" "2005" "4005" "2025" "2029" \
                "91" "92" "93" "2015" "2022")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "VOFc_LT" ]]; then

                VOFc_LT_incs1_Ls=("Cun2_MSBP_LT" "SPL7_MSBP_LT" "IPL3_MSBP_LT");

                VOFc_LT_incs1_Is=("197" "184" "187");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                VOFc_LT_incs2_Ls=("LOcc5_MSBP_LT" "LOcc5_MSBP_LT" "Fusi1_MSBP_LT");

                VOFc_LT_incs2_Is=("204" "203" "208");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                VOFc_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHip_GM_FS_LT" "PHip_WM_FS_LT" "Front_lobeGM_LT" "Front_lobeWM_LT" \
                "STG_GM_FS_LT" "STG_WM_FS_LT" "Pc_GM_FS_LT" \
                "ITG1_MSBP_LT" "ITG2_MSBP_LT" "ITG3_MSBP_LT" "MTG_GM_FS_LT" "S1_GM_FS_LT" \
                "Fusi3_MSBP_LT" "Fusi4_GMWM_LT_custom")

                VOFc_LT_excs_Is=("1" "16" "1016" "3016" "1001" "3001" \
                "1030" "4030" "1025" \
                "215" "216" "217" "1015" "1022" \
                "210" "1")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "VOFc_RT" ]]; then

                VOFc_RT_incs1_Ls=("Cun2_MSBP_RT" "SPL7_MSBP_RT" "IPL3_MSBP_RT");

                VOFc_RT_incs1_Is=("73" "60" "63");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                VOFc_RT_incs2_Ls=("LOcc5_MSBP_RT" "LOcc5_MSBP_RT" "Fusi1_MSBP_RT");

                VOFc_RT_incs2_Is=("80" "79" "84");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                VOFc_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHip_GM_FS_RT" "PHip_WM_FS_RT" "Front_lobeGM_RT" "Front_lobeWM_RT" \
                "STG_GM_FS_RT" "STG_WM_FS_RT" "Pc_GM_FS_RT" \
                "ITG1_MSBP_RT" "ITG2_MSBP_RT" "ITG3_MSBP_RT" "MTG_GM_FS_RT" "S1_GM_FS_RT" \
                "Fusi3_MSBP_RT" "Fusi4_GMWM_RT_custom")

                VOFc_RT_excs_Is=("1" "16" "2016" "4016" "2001" "4001" \
                "2030" "4030" "2025" \
                "91" "92" "93" "2015" "2022" \
                "86" "1")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SRF_LT" ]]; then

                SRF_LT_incs1_Ls=("Ling3_MSBP_LT" "Fusi2_MSBP_LT" "Fusi3_MSBP_LT" "Fusi4_MSBP_LT");

                SRF_LT_incs1_Is=("207" "209" "210" "211");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SRF_LT_incs2_Ls=("SPL5_MSBP_LT" "Pc4_MSBP_LT");

                SRF_LT_incs2_Is=("182" "194");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SRF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHip_GM_FS_LT" "PHip_WM_FS_LT" "Front_lobeGM_LT" "Front_lobeWM_LT" \
                "STG_GM_FS_LT" "STG_WM_FS_LT" "Fusi1_MSBP_LT" \
                "ITG1_MSBP_LT" "ITG2_MSBP_LT" "ITG3_MSBP_LT" "MTG_GM_FS_LT" "S1_GM_FS_LT")

                SRF_LT_excs_Is=("1" "16" "1016" "3016" "1001" "3001" \
                "2030" "4030" "208" \
                "215" "216" "217" "1015" "1022")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SRF_RT" ]]; then

                SRF_RT_incs1_Ls=("Ling3_MSBP_RT" "Fusi2_MSBP_RT" "Fusi3_MSBP_RT" "Fusi4_MSBP_RT");

                SRF_RT_incs1_Is=("83" "86" "87" "88");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                SRF_RT_incs2_Ls=("SPL5_MSBP_RT" "Pc4_MSBP_RT");

                SRF_RT_incs2_Is=("58" "70");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SRF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHip_GM_FS_RT" "PHip_WM_FS_RT" "Front_lobeGM_RT" "Front_lobeWM_RT" \
                "STG_GM_FS_RT" "STG_WM_FS_RT" "Fusi1_MSBP_RT" \
                "ITG1_MSBP_RT" "ITG2_MSBP_RT" "ITG3_MSBP_RT" "MTG_GM_FS_RT" "S1_GM_FS_RT")

                SRF_RT_excs_Is=("1" "16" "2016" "4016" "2001" "4001" \
                "2030" "4030" "84" \
                "91" "92" "93" "2015" "2022")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "UF_LT" ]]; then

                UF_LT_incs1_Ls=("MTG4_MSBP_LT" "ITG1_MSBP_LT" "TempP_GM_FS_LT" "EntoR_MSBP_LT");

                UF_LT_incs1_Is=("222" "215" "1033" "213");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                UF_LT_incs2_Ls=("IFG_PTr_GM_FS_LT" "IFG_POr_GM_FS_LT" "FrontP_GM_FS_LT"  "LatOF_GM_FS_LT");

                UF_LT_incs2_Is=("1020" "1019" "1032" "1012");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                UF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "Acc_FS_LT" "Thal_FS_LT" \
                "Caud_FS_LT" "Amyg_FS_LT" "Hippo_FS_LT" "Unseg_WM_LT" \
                "Pari_lobeGM_LT" "Pari_lobeWM_LT" "Occ_lobeGM_LT" "Occ_lobeWM_LT" \
                "rACC_GM_FS_LT" "rACC_WM_FS_LT" "IFG_POp_GM_LT" "IFG_POp_WM_RT" \
                "M1_GM_FS_LT" "M1_WM_FS_LT" "Ins1_MSBP_LT" "Ins2_MSBP_LT" \
                "Ins3_MSBP_LT" "UF_Ins_exc_LT_custom" "MedOF_GM_FS_LT")

                UF_LT_excs_Is=("1" "16" "26" "10" \
                "11" "18" "17" "5001" \
                "1006" "3006" "1004" "3004" \
                "1026" "3026" "1018" "3018" \
                "1024" "3024" "230" "231" \
                "232" "1" "1014")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "UF_RT" ]]; then

                UF_RT_incs1_Ls=("MTG4_MSBP_RT" "ITG1_MSBP_RT" "TempP_GM_FS_RT" "EntoR_MSBP_RT");

                UF_RT_incs1_Is=("98" "91" "2033" "89");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                UF_RT_incs2_Ls=("IFG_PTr_GM_FS_RT" "IFG_POr_GM_FS_RT" "FrontP_GM_FS_RT"  "LatOF_GM_FS_RT");

                UF_RT_incs2_Is=("2020" "2019" "2032" "2012");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                UF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "Acc_FS_RT" "Thal_FS_RT" \
                "Caud_FS_RT" "Amyg_FS_RT" "Hippo_FS_RT" "Unseg_WM_RT" \
                "Pari_lobeGM_RT" "Pari_lobeWM_RT" "Occ_lobeGM_RT" "Occ_lobeWM_RT" \
                "rACC_GM_FS_RT" "rACC_WM_FS_RT" "IFG_POp_GM_RT" "IFG_POp_WM_RT" \
                "M1_GM_FS_RT" "M1_WM_FS_RT" "Ins1_MSBP_RT" "Ins2_MSBP_RT" \
                "Ins3_MSBP_RT" "UF_Ins_exc_RT_custom" "MedOF_GM_FS_RT")

                UF_RT_excs_Is=("1" "16" "58" "49" \
                "50" "54" "53" "5002" \
                "2006" "4006" "2004" "4004" \
                "2026" "4026" "2018" "4018" \
                "2024" "4024" "106" "107" \
                "108" "1" "2014")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CCing_LT" ]]; then

                CCing_LT_incs1_Ls=("rACC_GM_FS_LT" "cACC_GM_FS_LT");

                CCing_LT_incs1_Is=("1026" "1002");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                CCing_LT_incs2_Ls=("PCC_GM_FS_LT" "iPCC_GM_FS_LT" "Pc_GM_FS_LT");

                CCing_LT_incs2_Is=("1023" "1010" "1025");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CCing_LT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "STG_GM_FS_LT" "Unseg_WM_FS_LT" \
                "vDC_FS_LT" "IFG_POp_GM_FS_LT" "IFG_POp_WM_FS_LT" \
                "IFG_PTr_GM_FS_LT" "IFG_PTr_WM_FS_LT" \
                "Phippo_GM_FS_LT" "Phipp_WM_FS_LT" "SFG_GM_FS_LT" \
                "Hippo_LT_FS" "Temp_lobeGM_LT" "Temp_lobeWM_LT" \
                "AC_midline_MAN" "Insula_GM_FS_LT" "Insula_WM_FS_LT");

                CCing_LT_excs_Is=("1" "16" \
                "1030" "5001" \
                "28" "1018" "3018" \
                "1020" "3020" \
                "1016" "3016" "1028" \
                "17" "1005" "3005" \
                "1" "1035" "3035");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CCing_RT" ]]; then

                CCing_RT_incs1_Ls=("rACC_GM_FS_RT" "cACC_GM_FS_RT");

                CCing_RT_incs1_Is=("2026" "2002");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                CCing_RT_incs2_Ls=("PCC_GM_FS_LT" "iPCC_GM_FS_LT" "Pc_GM_FS_LT");

                CCing_RT_incs2_Is=("2023" "2010" "2025");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CCing_RT_excs_Ls=("CC_allr_custom" "BStem_FS" \
                "STG_GM_FS_RT" "Unseg_WM_FS_RT" \
                "vDC_FS_RT" "IFG_POp_GM_FS_RT" "IFG_POp_WM_FS_RT" \
                "IFG_PTr_GM_FS_RT" "IFG_PTr_WM_FS_RT" \
                "Phippo_GM_FS_RT" "Phipp_WM_FS_RT" "SFG_GM_FS_RT" \
                "Hippo_RT_FS" "Temp_lobeGM_RT" "Temp_lobeWM_RT" \
                "AC_midline_MAN" "Insula_GM_FS_LT" "Insula_WM_FS_LT");

                CCing_RT_excs_Is=("1" "16" \
                "2030" "5002" \
                "60" "2018" "4018" \
                "2020" "4020" \
                "2016" "4016" "2028" \
                "53" "2005" "4005" \
                "1" "2035" "4035");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "TCing_LT" ]]; then
                # need to fix this still
                # removed PHippo from includes

                TCing_LT_incs1_Ls=("Hippo_FS_LT");

                TCing_LT_incs1_Is=("17");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                TCing_LT_incs2_Ls=("Pc_GM_FS_LT" "iPCC_GM_FS_LT");

                TCing_LT_incs2_Is=("1025" "1010");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                TCing_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "PCC_GM_FS_LT" "PCC_WM_FS_LT" \
                "Fusi_GM_FS_LT" "Fusi_WM_FS_LT" "Unseg_WM_FS_LT" \
                "Insula_GM_FS_LT" "Insula_WM_FS_LT" "MedOF_GM_FS_LT" "MedOF_WM_FS_LT" \
                "LatOF_GM_FS_LT" "LatOF_WM_FS_LT" "Amyg_FS_LT");

                TCing_LT_excs_Is=("1" "16" "1023" "3023" \
                "1026" "3026" "5001" \
                "1035" "3035" "1014" "3014" \
                "1012" "3012" "18")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "TCing_RT" ]]; then

                TCing_RT_incs1_Ls=("Hippo_FS_RT");

                TCing_RT_incs1_Is=("53");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                TCing_RT_incs2_Ls=("Pc_GM_FS_RT" "iPCC_GM_FS_RT");

                TCing_RT_incs2_Is=("2025" "2010");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                TCing_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "PCC_GM_FS_RT" "PCC_WM_FS_RT" \
                "Fusi_GM_FS_RT" "Fusi_WM_FS_RT" "Unseg_WM_FS_RT" \
                "Insula_GM_FS_RT" "Insula_WM_FS_RT" "MedOF_GM_FS_RT" "MedOF_WM_FS_RT" \
                "LatOF_GM_FS_RT" "LatOF_WM_FS_RT" "Amyg_FS_RT");

                TCing_RT_excs_Is=("1" "16" "2023" "4023" \
                "2026" "4026" "5002" \
                "2035" "4035" "2014" "4014" \
                "2012" "4012" "54")

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

                # elif [[ ${tck_list[$q]} == "SCing_LT" ]]; then
                #     # need to add the SFGs to excludes, probably also the MPFC

                #     SCing_LT_incs1_Ls=("cACC_GM_FS_LT");

                #     SCing_LT_incs1_Is=("1002");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                #     # leaving out the MedOF
                #     SCing_LT_incs2_Ls=("rACC_GM_FS_LT");

                #     SCing_LT_incs2_Is=("1026");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                #     SCing_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "PCC_GM_FS_LT" "PCC_WM_FS_LT" "Unseg_WM_FS_LT" "SFG_GM_LT_FS" "SFG_WM_LT_FS" \
                #     "Insula_GM_FS_LT" "Insula_WM_FS_LT" "MedOF_GM_FS_LT" "MedOF_WM_FS_LT" "LatOF_GM_FS_LT" "LatOF_WM_FS_LT" "Amyg_FS_LT");

                #     SCing_LT_excs_Is=("1" "16" "1023" "3023" "5001" "1028" "3028" \
                #     "1035" "3035" "1014" "3014" "1012" "3012" "18")

                #     tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

                # elif [[ ${tck_list[$q]} == "SCing_RT" ]]; then

                # SCing_RT_incs1_Ls=("cACC_GM_FS_RT");

                # SCing_RT_incs1_Is=("2002");

                # tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # # leaving out the MedOF
                # SCing_RT_incs2_Ls=("rACC_GM_FS_RT");

                # SCing_RT_incs2_Is=("2026");

                # tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # SCing_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "PCC_GM_FS_RT" "PCC_WM_FS_RT" "Unseg_WM_FS_RT" "SFG_GM_LT_FS" "SFG_WM_LT_FS" \
                # "Insula_GM_FS_RT" "Insula_WM_FS_RT" "MedOF_GM_FS_RT" "MedOF_WM_FS_RT" "LatOF_GM_FS_RT" "LatOF_WM_FS_RT" "Amyg_FS_RT");

                # SCing_RT_excs_Is=("1" "16" "2023" "4023" "5002" "2028" "4028" \
                # "2035" "4035" "2014" "4014" "2012" "4012" "54")

                # tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

                # elif [[ ${tck_list[$q]} == "Fx_Bil" ]]; then

                #     Fx_Bil_incs1_Ls=("Fornix_Fx");

                #     Fx_Bil_incs1_Is=("250");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                #     # leaving out the MedOF
                #     Fx_Bil_incs2_Ls=("Hippocampus_FS_RT");

                #     Fx_Bil_incs2_Is=("53");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                #     Fx_Bil_incs3_Ls=("Hippocampus_FS_LT");

                #     Fx_Bil_incs3_Is=("17");

                #     tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                #     Fx_Bil_excs_Ls=("CC_allr_custom" "BStem_FS" "s3Put_RT_custom" "iPCC_GM_FS_RT" "iPCC_WM_FS_RT" "Thal_RT_ero2_custom" \
                #     "Front_lobeGM_RT" "Occ_lobeGM_RT" "Occ_lobeWM_RT" "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Pari_lobeGM_RT" "Pari_lobeWM_RT" \
                #     "Amyg_FS_RT" "rACC_GM_FS_RT" "s3Put_LT_custom" "iPCC_GM_FS_LT" "iPCC_WM_FS_LT" "Thal_LT_ero2_custom" "Front_lobeGM_LT" \
                #     "Occ_lobeGM_LT" "Occ_lobeWM_LT" "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Pari_lobeGM_LT" "Pari_lobeWM_LT" "Amyg_FS_LT" "rACC_GM_FS_LT");

                #     Fx_Bil_excs_Is=("1" "16" "1" "2010" "4010" "1" \
                #     "2001" "2004" "4004" "2005" "4005" "2006" "4006" \
                #     "54" "2026" "1" "1010" "3010" "1" "1001" \
                #     "1004" "3004" "1005" "3005" "1006" "3006" "18" "1026");

                #     tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "Fx_LT" ]]; then

                Fx_LT_incs1_Ls=("Fornix_Fx");

                Fx_LT_incs1_Is=("250");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                Fx_LT_incs2_Ls=("Hippocampus_FS_LT");

                Fx_LT_incs2_Is=("17");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs
                # add caudates and something to block the WM 
                Fx_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "Putamen_FS_LT" "iPCC_GM_FS_LT" \
                "iPCC_WM_FS_LT" "Thal_LT_ero2_custom" "OptCh_FS" \
                "Front_lobeGM_LT" "Occ_lobeGM_LT" "Occ_lobeWM_LT" \
                "Temp_lobeGM_LT" "Temp_lobeWM_LT" "Pari_lobeGM_LT" "Pari_lobeWM_LT" \
                "Amyg_FS_LT" "rACC_GM_FS_LT" "ChorP_FS_LT" "ChorP_FS_RT" \
                "SegWM_LT_ALIC_custom" "Caudate_FS_LT" "vDC_FS_RT" \
                "Insula_GM_LT_FS" "Insula_WM_LT_FS");

                Fx_LT_excs_Is=("1" "16" "12" "1010" \
                "3010" "1" "85" \ 
                "1001" "1004" "3004" \
                "1005" "3005" "1006" "3006" \
                "18" "1026" "31" "63" \
                "1" "11" "60" \
                "2035" "4035");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "Fx_RT" ]]; then

                Fx_RT_incs1_Ls=("Fornix_Fx");

                Fx_RT_incs1_Is=("250");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                Fx_RT_incs2_Ls=("Hippocampus_FS_RT");

                Fx_RT_incs2_Is=("53");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                Fx_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "Putamen_FS_RT" "iPCC_GM_FS_RT" \
                "iPCC_WM_FS_RT" "Thal_RT_ero2_custom" "OptCh_FS" \
                "Front_lobeGM_RT" "Occ_lobeGM_RT" "Occ_lobeWM_RT" \
                "Temp_lobeGM_RT" "Temp_lobeWM_RT" "Pari_lobeGM_RT" "Pari_lobeWM_RT" \
                "Amyg_FS_RT" "rACC_GM_FS_RT" "ChorP_FS_LT" "ChorP_FS_RT" \
                "SegWM_LT_ALIC_custom" "Caudate_FS_RT" "vDC_FS_LT" \
                "Insula_GM_RT_FS" "Insula_WM_RT_FS");

                Fx_RT_excs_Is=("1" "16" "51" "2010" \
                "4010" "1" "85" \
                "2001" "2004" "4004" \
                "2005" "4005" "2006" "4006" \
                "54" "2026" "31" "63" \
                "1" "50" "28" \
                "1035" "3035");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SAF_LT" ]]; then

                SAF_LT_incs1_Ls=("SFG1_MSBP_LT" "SFG2_MSBP_LT" "MedOF_GM_LT_FS" "LatOF_GM_LT_FS");

                SAF_LT_incs1_Is=("144" "145" "1014" "1012");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                SAF_LT_incs2_Ls=("SFG5_MSBP_LT" "SFG6_MSBP_LT" "SFG7_MSBP_LT" "SFG8_MSBP_LT");

                SAF_LT_incs2_Is=("148" "149" "150" "151");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SAF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "Insula_GM_LT_FS" "Insula_WM_LT_FS" "M1_GM_LT_FS" "M1_WM_LT_FS" \
                "IFG_POp_GM_LT_FS" "IFG_POp_WM_LT_FS" "IFG_PTr_GM_LT_FS" "IFG_PTr_WM_LT_FS" "putamen_LT_FS" "caudate_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" \
                "Thal_FS_LT" "cMFG_GM_LT_FS");

                SAF_LT_excs_Is=("1" "16" "1035" "3035" "1024" "3024" "1018" "3018" "1020" "3020" "12" "11" "1005" "3005" "10" "1003");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "SAF_RT" ]]; then

                SAF_RT_incs1_Ls=("SFG1_MSBP_RT" "SFG2_MSBP_RT" "MedOF_GM_RT_FS" "LatOF_GM_RT_FS");

                SAF_RT_incs1_Is=("20" "21" "2014" "2012");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                # leaving out the MedOF
                SAF_RT_incs2_Ls=("SFG5_MSBP_RT" "SFG6_MSBP_RT" "SFG7_MSBP_RT" "SFG8_MSBP_RT");

                SAF_RT_incs2_Is=("24" "25" "26" "27");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                SAF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "Insula_GM_RT_FS" "Insula_WM_RT_FS" "M1_GM_RT_FS" "M1_WM_RT_FS" \
                "IFG_POp_GM_RT_FS" "IFG_POp_WM_RT_FS" "IFG_PTr_GM_RT_FS" "IFG_PTr_WM_RT_FS" "putamen_RT_FS" "caudate_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" \
                "Thal_FS_RT" "cMFG_GM_RT_FS");

                SAF_RT_excs_Is=("1" "16" "2035" "4035" "2024" "4024" "2018" "4018" "2020" "4020" "51" "50" "2005" "4005" "49" "2003");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "TIF_LT" ]]; then

                TIF_LT_incs1_Ls=("Ins1_MSBP_LT" "Ins2_MSBP_LT" "Ins3_MSBP_LT");

                TIF_LT_incs1_Is=("230" "231" "232");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                TIF_LT_incs2_Ls=("Amygdala_LT_FS" "TempP_GM_LT_FS" "EntoR_MSBP_LT");

                TIF_LT_incs2_Is=("18" "1033" "213");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                TIF_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHipp_GM_LT_FS" "PHipp_WM_FS_LT" "vDC_FS_LT" "Fusi_GM_LT_FS" "Fusi_WM_LT_FS" \
                "e2Put_LT_custom" "Pall_LT_FS" "Front_lobeGM_LT" "Front_lobeWM_LT" "Acc_LT_FS" "AC_midline_MAN" "OptCh_FS" "Pari_lobeGM_LT" \
                "Pari_lobeWM_LT" "Occ_lobeGM_LT" "Occ_lobeWM_LT" "STG_GM_LT_FS" "STG_WM_LT_FS");

                TIF_LT_excs_Is=("1" "16" "1016" "3016" "28" "1007" "3007" "1" "13" "1001" "3001" "26" "1" "85" "1006" "3006" "1004" "3004" "1030" "3030");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "TIF_RT" ]]; then

                TIF_RT_incs1_Ls=("Ins1_MSBP_RT" "Ins2_MSBP_RT" "Ins3_MSBP_RT");

                TIF_RT_incs1_Is=("106" "107" "108");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                TIF_RT_incs2_Ls=("Amygdala_RT_FS" "TempP_GM_RT_FS" "EntoR_MSBP_RT");

                TIF_RT_incs2_Is=("54" "2033" "89");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                TIF_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "PHipp_GM_RT_FS" "PHipp_WM_FS_RT" "vDC_FS_RT" "Fusi_GM_RT_FS" "Fusi_WM_RT_FS" \
                "e2Put_RT_custom" "Pall_RT_FS" "Front_lobeGM_RT" "Front_lobeWM_RT" "Acc_RT_FS" "AC_midline_MAN" "OptCh_FS" "Pari_lobeGM_RT" \
                "Pari_lobeWM_RT" "Occ_lobeGM_RT" "Occ_lobeWM_RT" "STG_GM_RT_FS" "STG_WM_RT_FS");

                TIF_RT_excs_Is=("1" "16" "2016" "4016" "60" "2007" "4007" "1" "52" "2001" "4001" "58" "1" "85" "2006" "4006" "2004" "4004" "2030" "4030");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Sup_LT" ]]; then
                # still need to add midline exclude

                ThR_Sup_LT_incs1_Ls=("Thal_FS_LT");

                ThR_Sup_LT_incs1_Is=("10");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Sup_LT_incs2_Ls=("M1_GM_LT_FS" "ParaC_GM_LT_FS" \
                "SFG5_LT_MSBP" "SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP" \
                "cMFG_GM_LT_FS");

                ThR_Sup_LT_incs2_Is=("1024" "1017" \
                "148" "149" "150" "151" \
                "1003");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ThR_Sup_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "vDC_LT" "AC_midline_MAN" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_LT" "Putamen_GM_LT_FS" \
                "Caudate_GM_LT_FS" "PD25_Pulvi_LT_custom" "Caud_ero_LT_custom" "SFG1_MSBP_LT" \
                "SFG2_MSBP_LT" "SFG3_MSBP_LT" "SFG4_MSBP_LT" "cACC_GM_FS_LT" "PD25_DM_LT_custom" "PD25_DL_LT_custom" "Fornix_Fx" \
                "Pari_lobeGM_LT" "Pari_lobeWM_LT" "rMFG_GM_LT_FS" "rMFG_WM_LT_FS");

                ThR_Sup_LT_excs_Is=("1" "16" "28" "1" \
                "1" "1005" "12" "11" \
                "1" "1" "144" \
                "145" "146" "147" "1002" \
                "1" "1" "250" \
                "1006" "3006" "1027" "3027");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Sup_RT" ]]; then

                ThR_Sup_RT_incs1_Ls=("Thal_FS_RT");

                ThR_Sup_RT_incs1_Is=("49");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Sup_RT_incs2_Ls=("M1_GM_RT_FS" "S1_GM_RT_FS" "ParaC_GM_RT_FS" \
                "SFG5_RT_MSBP" "SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP" \
                "cMFG_GM_RT_FS");

                ThR_Sup_RT_incs2_Is=("2024" "2022" "2017" \
                "24" "25" "26" "27" \
                "2003");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ThR_Sup_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "vDC_RT" "AC_midline_MAN" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_RT" "Putamen_GM_RT_FS" \
                "Caudate_GM_RT_FS" "PD25_Pulvi_RT_custom" "Caud_ero_RT_custom" "SFG1_MSBP_RT" \
                "SFG2_MSBP_RT" "SFG3_MSBP_RT" "SFG4_MSBP_RT" "cACC_GM_FS_RT" "PD25_DM_RT_custom" "PD25_DL_RT_custom" "Fornix_Fx" \
                "Pari_lobeGM_RT" "Pari_lobeWM_RT" "rMFG_GM_RT_FS" "rMFG_WM_RT_FS");

                ThR_Sup_RT_excs_Is=("1" "16" "60" "1" \
                "1" "2005" "12" "11" \
                "1" "1" "20" \
                "21" "22" "23" "2002" \
                "1" "1" "250" \
                "2006" "4006" "2027" "4027");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Ant_LT" ]]; then
                # WIP

                ThR_Ant_LT_incs1_Ls=("Thal_FS_LT");

                ThR_Ant_LT_incs1_Is=("10");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Ant_LT_incs2_Ls=("SFG1_MSBP_LT" "SFG2_MSBP_LT" "SFG3_MSBP_LT" \
                "SFG4_MSBP_LT" "MedOF_GM_LT_FS" "LatOF_GM_LT_FS" "FrP_GM_LT_FS");

                ThR_Ant_LT_incs2_Is=("144" "145" "146" \
                "147" "1014" "1012" "1032");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ThR_Ant_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "AC_midline_MAN" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_LT" "Putamen_GM_LT_FS" \
                "Caudate_GM_LT_FS" "PD25_Pulvi_LT_custom" "Fornix_Fx" \
                "cACC_GM_FS_LT" "Occ_lobeGM_LT" "Pari_lobeGM_LT" \
                "PD25_VPALPLPM_LT_custom" "M1_GM_FS_LT" "M1_WM_FS_LT" \
                "SFG5_LT_MSBP" "cMFG_GM_LT_FS" "PHipp_GM_LT_FS" "PHipp_WM_LT_FS" \
                "Insula_GM_LT_FS" "Insula_WM_LT_FS" "Cing_lobeGM_LT" "Cing_lobeWM_LT" "vDC_FS_LT");

                ThR_Ant_LT_excs_Is=("1" "16" "1" \
                "1" "1003" "12" \
                "11" "1" "250" \
                "1002" "1004" "1006" \
                "1" "1024" "3024" \
                "148" "1003" "1016" "3016" \
                "1035" "3035" "1003" "3003" "28");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Ant_RT" ]]; then

                ThR_Ant_RT_incs1_Ls=("Thal_FS_RT");

                ThR_Ant_RT_incs1_Is=("49");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Ant_RT_incs2_Ls=("SFG1_MSBP_RT" "SFG2_MSBP_RT" "SFG3_MSBP_RT" "SFG4_MSBP_RT" "MedOF_GM_LT_FS" "LatOF_GM_LT_FS" "FrP_GM_RT_FS");

                ThR_Ant_RT_incs2_Is=("20" "21" "22" "23" "2014" "2012" "2032");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ThR_Ant_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "AC_midline_MAN" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_RT" "Putamen_GM_RT_FS" \
                "Caudate_GM_RT_FS" "PD25_Pulvi_RT_custom" "Fornix_Fx" \
                "cACC_GM_FS_RT" "Occ_lobeGM_RT" "Pari_lobeGM_RT" \
                "PD25_VPALPLPM_RT_custom" "M1_GM_FS_RT" "M1_WM_FS_RT" \
                "SFG5_RT_MSBP" "cMFG_GM_RT_FS" "PHipp_GM_RT_FS" "PHipp_WM_RT_FS" \
                "Insula_GM_RT_FS" "Insula_WM_RT_FS" "Cing_lobeGM_RT" "Cing_lobeWM_RT" "vDC_FS_RT");

                ThR_Ant_RT_excs_Is=("1" "16" "1" \
                "1" "2003" "51" \
                "50" "1" "250" \
                "2002" "2004" "2006" \
                "1" "2024" "4024" \
                "24" "2003" "2016" "4016" \
                "2035" "4035" "1003" "3003" "60");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Inf_LT" ]]; then
                # WIP remove TO WM exc, exclude par lobe GMWM and insula subseg

                ThR_Inf_LT_incs1_Ls=("Thal_FS_LT" "JuHA_MGN_LT_custom");

                ThR_Inf_LT_incs1_Is=("10" "1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Inf_LT_incs2_Ls=("TTG_MSBP_LT" "STG3_MSBP_LT");

                ThR_Inf_LT_incs2_Is=("229" "226");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # trying without wm lobar excludes
                # "SegWM_LT_TOpV_custom" "1"

                ThR_Inf_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "AC_midline_MAN" \
                "e2Put_LT_custom" \
                "Caudate_GM_LT_FS" "Front_lobeGM_LT" \
                "cACC_GM_FS_LT" "Occ_lobeGM_LT" "Occ_lobeWM_LT" \
                "Pari_lobeGM_LT" "Pari_lobeWM_LT"  \
                "Ins_subseg1_LT_custom");

                ThR_Inf_LT_excs_Is=("1" "16" "1" \
                "1" \
                "11" "1001" \
                "1002" "1004" "3004" \
                "1006" "3006" \
                "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Inf_RT" ]]; then
                # WIP

                ThR_Inf_RT_incs1_Ls=("Thal_FS_RT" "JuHA_MGN_RT_custom");

                ThR_Inf_RT_incs1_Is=("49" "1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Inf_RT_incs2_Ls=("TTG_MSBP_RT" "STG3_MSBP_RT");

                ThR_Inf_RT_incs2_Is=("105" "102");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                # trying without WM lobar excludes
                # "SegWM_RT_TOpV_custom" "1"
                ThR_Inf_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "AC_midline_MAN" \
                "e2Put_RT_custom" \
                "Caudate_GM_RT_FS" "Front_lobeGM_RT" \
                "cACC_GM_FS_RT" "Occ_lobeGM_RT" "Occ_lobeWM_RT"  \
                "Pari_lobeGM_RT" "Pari_lobeWM_RT" \
                "Ins_subseg1_RT_custom");

                ThR_Inf_RT_excs_Is=("1" "16" "1" \
                "1" \
                "50" "2001" \
                "2002" "2004" "4004" \
                "2006" "4006" \
                "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Par_LT" ]]; then
                # this should actually be the ThR_PPC_LT
                # remove the occipital lobe as we already generate it

                ThR_Par_LT_incs1_Ls=("Thal_FS_LT");

                ThR_Par_LT_incs1_Is=("10");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Par_LT_incs2_Ls=("Pari_lobeGM_LT");

                ThR_Par_LT_incs2_Is=("1006");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ThR_Par_LT_excs_Ls=("CC_allr_custom" "BStem_FS" "vDC_LT" "AC_midline_MAN" "SegWM_LT_ALIC_custom" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_LT" "Putamen_GM_LT_FS" "Front_lobeGM_LT" "Fornix_Fx" "Occ_lobeGM_LT" \
                "Caudate_GM_LT_FS" "PD25_Pulvi_LT_custom" "Caud_ero_LT_custom" "SFG1_MSBP_LT" \
                "SFG2_MSBP_LT" "SFG3_MSBP_LT" "SFG4_MSBP_LT" "cACC_GM_FS_LT" "PD25_DM_LT_custom" \
                "PD25_DL_LT_custom" "SegWM_LT_mIPV_custom");

                ThR_Par_LT_excs_Is=("1" "16" "28" "1" \
                "1" \
                "1" "1005" "12" "1001" \
                "250" "1004" \
                "11" "1" "1" "144" \
                "145" "146" "147" "1002" "1" \
                "1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ThR_Par_RT" ]]; then

                ThR_Par_RT_incs1_Ls=("Thal_FS_RT");

                ThR_Par_RT_incs1_Is=("49");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ThR_Par_RT_incs2_Ls=("Pari_lobeGM_RT");

                ThR_Par_RT_incs2_Is=("2006");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ThR_Par_RT_excs_Ls=("CC_allr_custom" "BStem_FS" "vDC_RT" "AC_midline_MAN" "SegWM_RT_ALIC_custom" \
                "hypothal_bildil_excr_custom" "Temp_lobeGM_RT" "Putamen_GM_RT_FS" "Front_lobeGM_RT" \
                "Fornix_Fx" "Occ_lobeGM_RT" \
                "Caudate_GM_RT_FS" "PD25_Pulvi_RT_custom" "Caud_ero_RT_custom" "SFG1_MSBP_RT" \
                "SFG2_MSBP_RT" "SFG3_MSBP_RT" "SFG4_MSBP_RT" "cACC_GM_FS_RT" "PD25_DM_RT_custom" \
                "PD25_DL_RT_custom" "SegWM_RT_mIPV_custom");

                ThR_Par_RT_excs_Is=("1" "16" "60" "1" \
                "1" \
                "1" "2005" "51" "2001" \
                "250" "2004" \
                "50" "1" "1" "20" \
                "21" "22" "23" "2002" "1" \
                "1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "MCP_LT" ]]; then

                MCP_LT_incs1_Ls=("Bs_Pons_RT_custom");

                MCP_LT_incs1_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                MCP_LT_incs2_Ls=("cVI_LT_SUIT" "cI_LT_SUIT" "cVIIb_LT_SUIT");

                MCP_LT_incs2_Is=("5" "8" "14");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                MCP_LT_excs_Ls=("Occ_lobeGM_LT" "Occ_lobeWM_LT" "Midbrain_MSBP" \
                "Medulla_MSBP" "vDC_LT_FS" "vDC_RT_FS" "cIX_LT_SUIT");

                MCP_LT_excs_Is=("1004" "3004" "249" \
                "251" "28" "60" "23");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "MCP_RT" ]]; then

                MCP_RT_incs1_Ls=("Bs_Pons_LT_custom");

                MCP_RT_incs1_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                MCP_RT_incs2_Ls=("cVI_RT_SUIT" "cI_RT_SUIT" "cVIIb_RT_SUIT");

                MCP_RT_incs2_Is=("7" "10" "16");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                MCP_RT_excs_Ls=("Occ_lobeGM_RT" "Occ_lobeWM_RT" "Midbrain_MSBP" "Medulla_MSBP" "vDC_LT_FS" "vDC_RT_FS" "cIX_RT_SUIT");

                MCP_RT_excs_Is=("2004" "4004" "249" "251" "28" "60" "25");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ICP_LT" ]]; then
                # the MCP is supposed to cross the midline

                ICP_LT_incs1_Ls=("Medulla_MSBP");

                ICP_LT_incs1_Is=("251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ICP_LT_incs2_Ls=("cFas_LT_SUIT" "cIp_LT_SUIT" "Dent_LT_SUIT");

                ICP_LT_incs2_Is=("33" "31" "29");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ICP_LT_excs_Ls=("Occ_lobeGM_LT" "Occ_lobeWM_LT" "Midbrain_MSBP" \
                "vDC_LT_FS" "vDC_RT_FS" "Pons_MSBP" \
                "cX_LT_SUIT" "cIX_LT_SUIT" "cI_IV_LT_SUIT");

                ICP_LT_excs_Is=("1004" "3004" "249" \
                "28" "60" "250" \
                "26" "23" "1");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "ICP_RT" ]]; then

                ICP_RT_incs1_Ls=("Medulla_MSBP");

                ICP_RT_incs1_Is=("251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                ICP_RT_incs2_Ls=("cFas_RT_SUIT" "cIp_RT_SUIT" "Dent_RT_SUIT");

                ICP_RT_incs2_Is=("34" "32" "30");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                ICP_RT_excs_Ls=("Occ_lobeGM_RT" "Occ_lobeWM_RT" "Midbrain_MSBP" \
                "vDC_LT_FS" "vDC_RT_FS" "Pons_MSBP" \
                "cX_RT_SUIT" "cIX_RT_SUIT" "cI_IV_RT_SUIT");

                ICP_RT_excs_Is=("2004" "4004" "249" \
                "28" "60" "250" \
                "28" "25" "2");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "DRT_LT" ]]; then

                DRT_LT_incs1_Ls=("Dent_RT_SUIT");

                DRT_LT_incs1_Is=("30");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                DRT_LT_incs2_Ls=("PD25_RN_LT_custom");

                DRT_LT_incs2_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                DRT_LT_incs3_Ls=("PD25_VL_LT_custom");

                DRT_LT_incs3_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                DRT_LT_incs4_Ls=("M1_GM_FS_LT");

                DRT_LT_incs4_Is=("1024");

                tck_VOIs_2seg="${tck_list[$q]}_incs4" && make_VOIs

                DRT_LT_excs_Ls=("CC_allr_custom" "Medulla_MSBP" "cIX_RT_SUIT");

                DRT_LT_excs_Is=("1" "251" "25");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "DRT_RT" ]]; then

                DRT_RT_incs1_Ls=("Dent_LT_SUIT");

                DRT_RT_incs1_Is=("29");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                DRT_RT_incs2_Ls=("PD25_RN_RT_custom");

                DRT_RT_incs2_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                DRT_RT_incs3_Ls=("PD25_VL_RT_custom");

                DRT_RT_incs3_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                DRT_RT_incs4_Ls=("M1_GM_FS_RT");

                DRT_RT_incs4_Is=("2024");

                tck_VOIs_2seg="${tck_list[$q]}_incs4" && make_VOIs

                DRT_RT_excs_Ls=("CC_allr_custom" "Medulla_MSBP" "cIX_LT_SUIT");

                DRT_RT_excs_Is=("1" "251" "23");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "Ant_Comm" ]]; then

                Ant_Comm_incs1_Ls=("AC_MAN");

                Ant_Comm_incs1_Is=("1");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                Ant_Comm_incs2_Ls=("Temp_lobeGM_LT" "Occ_lobeGM_LT");

                Ant_Comm_incs2_Is=("1005" "1004");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                Ant_Comm_incs3_Ls=("Temp_lobeGM_RT" "Occ_lobeGM_RT");

                Ant_Comm_incs3_Is=("2005" "2004");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                Ant_Comm_excs_Ls=("CC_allr_custom" "PC_MAN" "BStem_FS" "OptCh_FS" "Thal_LT_FS" "Thal_RT_FS");

                Ant_Comm_excs_Is=("1" "2" "16" "85" "10" "49");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "Post_Comm" ]]; then

                Post_Comm_incs1_Ls=("PC_MAN");

                Post_Comm_incs1_Is=("2");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                Post_Comm_incs2_Ls=("JuHA_MGN_LT_custom" "JuHA_LGN_LT_custom");

                Post_Comm_incs2_Is=("1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                Post_Comm_incs3_Ls=("JuHA_MGN_LT_custom" "JuHA_LGN_LT_custom");

                Post_Comm_incs3_Is=("1" "1");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                Post_Comm_excs_Ls=("CC_allr_custom" "Medulla_MSBP" "Pons_MSBP" "AC_MAN" "OptCh_FS" "hypoTh_LT_MSBP" "hypoTh_RT_MSBP" "Unseg_WM_bil_FS_custom" "Pari_lobeGM_LT" "Pari_lobeWM_LT" "Pari_lobeGM_RT" "Pari_lobeWM_RT");

                Post_Comm_excs_Is=("1" "251" "250" "1" "85" "248" "124" "1" "1006" "3006" "2006" "4006");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_PreF_Comm" ]]; then

                CC_PreF_Comm_incs1_Ls=("CC_genu_FS" "CC_ant_FS");

                CC_PreF_Comm_incs1_Is=("255" "254");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_PreF_Comm_incs2_Ls=("IFG_PTr_GM_FS_LT" "IFG_POr_GM_FS_LT" \
                "FrontP_GM_FS_LT" "LatOF_GM_FS_LT" "MedOF_GM_FS_LT" \
                "cMFG_GM_LT_FS" "rMFG_GM_LT_FS" "SFG_GM_LT_FS");

                CC_PreF_Comm_incs2_Is=("1020" "1019" \
                "1032" "1012" "1014" \
                "1003" "1027" "1028");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_PreF_Comm_incs3_Ls=("IFG_PTr_GM_FS_RT" "IFG_POr_GM_FS_RT" \
                "FrontP_GM_FS_RT" "LatOF_GM_FS_RT" "MedOF_GM_FS_RT" \
                "cMFG_GM_RT_FS" "rMFG_GM_RT_FS" "SFG_GM_RT_FS" "");

                CC_PreF_Comm_incs3_Is=("2020" "2019" \
                "2032" "2012" "2014" \
                "2003" "2027" "2028");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_PreF_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_mid_FS" \
                "CC_isth_FS" "CC_splen_FS" "Fornix_Fx" \
                "cMFG_GM_LT_FS" "cMFG_GM_RT_FS" "M1_GM_LT_FS" \
                "M1_GM_RT_FS" "Pari_lobeGM_LT" "Pari_lobeGM_RT" \
                "BStem_FS" "Cing_lobeGM_LT" "Cing_lobeGM_RT" \
                "Thal_LT_FS" "Thal_RT_FS" "Insula_lobeGM_LT" "Insula_lobeWM_LT" \
                "Insula_lobeGM_RT" "Insula_lobeWM_RT" "SegWM_LT_ALIC_custom" "SegWM_RT_ALIC_custom" \
                "vDC_FS_LT" "vDC_FS_RT");

                CC_PreF_Comm_excs_Is=("1" "2" "253" \
                "252" "251" "250" \
                "1003" "2003" "1024" \
                "2024" "1006" "2006" \
                "16" "1003" "2003" \
                "10" "49" "1007" "3007" \
                "2007" "4007" "1" "1" \
                "28" "60");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_PMandSM_Comm" ]]; then

                CC_PMandSM_Comm_incs1_Ls=("CC_mid_FS");

                CC_PMandSM_Comm_incs1_Is=("253");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_PMandSM_Comm_incs2_Ls=("cMFG_GM_LT_FS" "SFG5_LT_MSBP" "SFG6_LT_MSBP" "SFG7_LT_MSBP" "SFG8_LT_MSBP");

                CC_PMandSM_Comm_incs2_Is=("1003" "148" "149" "150" "151");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_PMandSM_Comm_incs3_Ls=("cMFG_GM_RT_FS" "SFG5_RT_MSBP" "SFG6_RT_MSBP" "SFG7_RT_MSBP" "SFG8_RT_MSBP");

                CC_PMandSM_Comm_incs3_Is=("2003" "24" "25" "26" "27");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_PMandSM_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" "CC_ant_FS" "CC_isth_FS" "CC_splen_FS" "Fornix_Fx" "BStem_FS" \
                "Cing_lobeGM_LT" "Cing_lobeGM_RT" "SegWM_LT_ALIC_custom" "SegWM_RT_ALIC_custom" "vDC_FS_LT" "vDC_FS_RT");

                CC_PMandSM_Comm_excs_Is=("1" "2" "255" "254" "252" "251" "250" "16" \
                "1003" "2003" "1" "1" "28" "60");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_Motor_Comm" ]]; then

                CC_Motor_Comm_incs1_Ls=("CC_isth_FS");

                CC_Motor_Comm_incs1_Is=("252");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_Motor_Comm_incs2_Ls=("M1_GM_FS_LT");

                CC_Motor_Comm_incs2_Is=("1024");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_Motor_Comm_incs3_Ls=("M1_GM_FS_RT");

                CC_Motor_Comm_incs3_Is=("2024");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_Motor_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" \
                "CC_ant_FS" "CC_mid_FS" "CC_splen_FS" \
                "Fornix_Fx" "cMFG_GM_LT_FS" "cMFG_GM_RT_FS" \
                "SFG_GM_LT_FS" "SFG_GM_RT_FS" "Pari_lobeGM_LT" \
                "Pari_lobeGM_RT" "BStem_FS" \
                "Cing_lobeGM_LT" "Cing_lobeGM_RT");

                CC_Motor_Comm_excs_Is=("1" "2" "255" \
                "254" "253" "251" \
                "250" "1003" "2003" \
                "1028" "2028" "1006" \
                "2006" "16" \
                "1003" "2003");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_Sensory_Comm" ]]; then

                CC_Sensory_Comm_incs1_Ls=("CC_isth_FS" "CC_splen_FS");

                CC_Sensory_Comm_incs1_Is=("252" "251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_Sensory_Comm_incs2_Ls=("S1_GM_FS_LT");

                CC_Sensory_Comm_incs2_Is=("1022");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_Sensory_Comm_incs3_Ls=("S1_GM_FS_RT");

                CC_Sensory_Comm_incs3_Is=("2022");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_Sensory_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" \
                "CC_ant_FS" "CC_mid_FS" "Fornix_Fx" \
                "cMFG_GM_LT_FS" "cMFG_GM_RT_FS" \
                "SFG_GM_LT_FS" "SFG_GM_RT_FS" \
                "M1_GM_FS_LT" "M1_GM_FS_RT" \
                "BStem_FS" "Occ_lobeGM_LT" "Occ_lobeGM_LT" \
                "Cing_lobeGM_LT" "Cing_lobeGM_RT");

                CC_Sensory_Comm_excs_Is=("1" "2" "255" \
                "254" "253" "250" \
                "1003" "2003" \
                "1028" "2028" \
                "1024" "2024" \
                "16" "1004" "2004" \
                "1003" "2003");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_Parietal_Comm" ]]; then

                CC_Parietal_Comm_incs1_Ls=("CC_splen_FS");

                CC_Parietal_Comm_incs1_Is=("251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_Parietal_Comm_incs2_Ls=("Pari_lobeGM_LT");

                CC_Parietal_Comm_incs2_Is=("1006");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_Parietal_Comm_incs3_Ls=("Pari_lobeGM_RT");

                CC_Parietal_Comm_incs3_Is=("2006");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_Parietal_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" \
                "CC_ant_FS" "CC_mid_FS" "CC_isth_FS" \
                "Fornix_Fx" "Front_lobeGM_LT" "Front_lobeGM_RT" \
                "S1_GM_FS_LT" "S1_GM_FS_RT" \
                "BStem_FS" "Cing_lobeGM_LT" "Cing_lobeGM_RT" \
                "Occ_lobeGM_LT" "Occ_lobeWM_LT" \
                "Occ_lobeGM_RT" "Occ_lobeWM_RT");

                CC_Parietal_Comm_excs_Is=("1" "2" "255" \
                "254" "253" "252" \
                "250" "1001" "2001" \
                "1022" "2022" \
                "16" "1003" "2003" \
                "1004" "3004" \
                "2004" "4004");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_Occipital_Comm" ]]; then

                CC_Occipital_Comm_incs1_Ls=("CC_splen_FS");

                CC_Occipital_Comm_incs1_Is=("251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_Occipital_Comm_incs2_Ls=("Occ_lobeGM_LT");

                CC_Occipital_Comm_incs2_Is=("1004");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_Occipital_Comm_incs3_Ls=("Occ_lobeGM_RT");

                CC_Occipital_Comm_incs3_Is=("2004");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_Occipital_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" \
                "CC_ant_FS" "CC_mid_FS" "CC_isth_FS" \
                "Fornix_Fx" "Front_lobeGM_LT" "Front_lobeGM_RT" \
                "Pari_lobeGM_LT" "Pari_lobeGM_RT" \
                "Temp_lobeGM_LT" "Temp_lobeGM_RT" "BStem_FS" \
                "Cing_lobeGM_LT" "Cing_lobeGM_RT");

                CC_Occipital_Comm_excs_Is=("1" "2" "255" \
                "254" "253" "252" \
                "250" "1001" "2001" \
                "1006" "2006" \
                "1005" "2005" "16" \
                "1003" "2003");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "CC_Temporal_Comm" ]]; then

                CC_Temporal_Comm_incs1_Ls=("CC_splen_FS");

                CC_Temporal_Comm_incs1_Is=("251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                CC_Temporal_Comm_incs2_Ls=("ITG_GM_LT_FS" "MTG_GM_LT_FS" "STG_GM_LT_FS" "TempP_GM_LT_FS");

                CC_Temporal_Comm_incs2_Is=("1009" "1015" "1030" "1033");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                CC_Temporal_Comm_incs3_Ls=("ITG_GM_RT_FS" "MTG_GM_RT_FS" "STG_GM_RT_FS" "TempP_GM_RT_FS");

                CC_Temporal_Comm_incs3_Is=("2009" "2015" "2030" "2033");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                CC_Temporal_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" \
                "CC_ant_FS" "CC_mid_FS" "CC_midpost_FS" "Fornix_Fx" \
                "Front_lobeGM_LT" "Front_lobeGM_RT" "Pari_lobeGM_LT" \
                "Pari_lobeGM_RT" "Occ_lobeGM_LT" "Occ_lobeGM_RT" \
                "BStem_FS" "Cing_lobeGM_LT" "Cing_lobeGM_RT" \
                "Thal_FS_LT" "Thal_FS_RT" \
                "Phippo_GM_LT_FS" "Phippo_GM_RT_FS" \
                "Phippo_WM_LT_FS" "Phippo_WM_RT_FS" \
                "Hippo_LT_FS" "Hippo_RT_FS" "Amyg_FS_LT" "Amyg_FS_RT");

                CC_Temporal_Comm_excs_Is=("1" "2" "255" \
                "254" "253" "252" "250" \
                "1001" "2001" "1006" \
                "2006" "1004" "2004" \
                "16" "1003" "2003" \
                "10" "49" \
                "1016" "2016" \
                "3016" "4016" \
                "17" "53" "18" "54");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

            elif [[ ${tck_list[$q]} == "dHippo_Comm" ]]; then

                dHippo_Comm_incs1_Ls=("CC_splen_FS");

                dHippo_Comm_incs1_Is=("251");

                tck_VOIs_2seg="${tck_list[$q]}_incs1" && make_VOIs

                dHippo_Comm_incs2_Ls=("Phippo_GM_LT_FS" "Hippo_LT_FS" "Amyg_FS_LT");

                dHippo_Comm_incs2_Is=("1016" "17" "18");

                tck_VOIs_2seg="${tck_list[$q]}_incs2" && make_VOIs

                dHippo_Comm_incs3_Ls=("Phippo_GM_RT_FS" "Hippo_RT_FS" "Amyg_FS_RT");

                dHippo_Comm_incs3_Is=("2016" "53" "54");

                tck_VOIs_2seg="${tck_list[$q]}_incs3" && make_VOIs

                # should probably add an AC_min_Fx VOI as well
                dHippo_Comm_excs_Ls=("AC_MAN" "PC_MAN" "CC_genu_FS" \
                "CC_ant_FS" "CC_mid_FS" "CC_midpost_FS" "Fornix_Fx" \
                "Front_lobeGM_LT" "Front_lobeGM_RT" "Pari_lobeGM_LT" \
                "Pari_lobeGM_RT" "Occ_lobeGM_LT" "Occ_lobeGM_RT" \
                "BStem_FS" "Cing_lobeGM_LT" "Cing_lobeGM_RT" \
                "Thal_FS_LT" "Thal_FS_RT" \
                "ITG_GM_LT_FS" "MTG_GM_LT_FS" "STG_GM_LT_FS" "TempP_GM_LT_FS" \
                "ITG_GM_RT_FS" "MTG_GM_RT_FS" "STG_GM_RT_FS" "TempP_GM_RT_FS");

                dHippo_Comm_excs_Is=("1" "2" "255" \
                "254" "253" "252" "250" \
                "1001" "2001" "1006" \
                "2006" "1004" "2004" \
                "16" "1003" "2003" \
                "10" "49" \
                "1009" "1015" "1030" "1033" \
                "2009" "2015" "2030" "2033");

                tck_VOIs_2seg="${tck_list[$q]}_excs" && make_VOIs

                # Dorsal hippocampal commissure
                # https://doi.org/10.1093/cercor/bhz143

            else

                echo "${tck_list[$q]} is not recognized, please check the example config file in ${function_path} " | tee -a ${prep_log2}

                # elif [[ ${tck_list[$q]} == "OT_LT" ]]; then
                # elif [[ ${tck_list[$q]} == "OT_RT" ]]; then
                # cerebellar bundles and commissural ones remain

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

