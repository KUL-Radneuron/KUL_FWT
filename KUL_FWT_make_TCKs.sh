#!/bin/bash

# set -x

# the point of this one is to make my life easier!
# when it comes to VOI gen

cwd="$(pwd)"

# conda init bash
# conda deactivate
# pip install 'numpy==1.18'
# pip install 'nibabel==3.0.2'

# function Usage
function Usage {

cat <<USAGE

    `basename $0` part of the KUL_FWT package of fully automated workflows for fiber tracking

    Usage:

    `basename $0` -p pat001 -s 01  -F /path_to/FS_dir/aparc+aseg.mgz -M /path_to/MSBP_dir/sub-pat001_label-L2018_desc-scale3_atlas.nii.gz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output -T 2 -f 2

    Examples:

    `basename $0` -p pat001 -s 01 -F /path_to/FS_dir/aparc+aseg.mgz -M /path_to/MSBP_dir/sub-pat001_label-L2018_desc-scale3_atlas.nii.gz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output -n 6 -T 1 -f 1 -S -Q

    Purpose:

    This workflow creates all bundles specified in the input config file using the inclusion and exclusion VOIs created by KUL_FWT_make_VOIs.sh for single subject data

    Required arguments:

    -p:  BIDS participant name (anonymised name of the subject without the "sub-" prefix)
    -s:  BIDS participant session (session no. without the "ses-" prefix)
    -T:  Tracking and segmentation approach (1 = Bundle-specific tckgen, 2 = Whole brain tckgen & bundle segmentation)
    -M:  Full path and file name of scale 3 MSBP parcellation
    -F:  Full path and file name of aparc+aseg.mgz from FreeSurfer
    -c:  Path to config file with list of tracks to segment from the whole brain tractogram
    -d:  Path to directory with diffusion data (specific to subject and run)
    -o:  Full path to output dir (if not set reverts to default output ./sub-*_ses-*_KUL_FWT_output)

    Optional arguments:

    -a:  Specify algorithm for tckgen fiber tractography (tckgen -algorithm options are: iFOD2, iFOD1, SD_STREAM, Tensor_Det, Tensor_Prob)
    -f:  Specify filtering approach (0 = No filtering, 1 = conservative, 2 = liberal)
    -Q:  If set quantitative and qualitative analyses will be done
    -S:  If set screenshots will taken of each bundle
    -n:  Number of cpu for parallelisation (default is 6)
    -h:  Prints help menu

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
T_flag=0
F_flag=0
M_flag=0
c_flag=0
d_flag=0
o_flag=0
a_flag=0
Q_flag=0
S_flag=0
filt_fl1=0

if [ "$#" -lt 1 ]; then
    Usage >&2
    exit 1

else

    while getopts "p:s:T:M:F:c:d:o:a:n:f:hQS" OPT; do

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
        T) #Tractography approach
            T_flag=1
            T_app=$OPTARG
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
        a) #algorithm flag
            a_flag=1
            algo_f=$OPTARG
        ;;
        f) #filtering flag
            filt_fl1=1
            filt_fl2=$OPTARG
        ;;
        Q) #Quant and Qual flag
            Q_flag=1
        ;;
        S) #Screenshots flag
            S_flag=1
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

if [[ ${p_flag} -eq 0 ]] || [[ ${F_flag} -eq 0 ]] || [[ ${T_flag} -eq 0 ]] || [[ ${M_flag} -eq 0 ]] || [[ ${c_flag} -eq 0 ]] || [[ ${d_flag} -eq 0 ]]; then
	
    echo
    echo "Inputs to -p -F -M -d and -c must be set." >&2
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

    echo "Inputs are -p  ${subj} -s ${ses} -c  ${conf_f} -d ${d_dir} -F ${FS_dir} -M ${MS_dir} -T ${T_app}"

fi

# set this manually for debugging
# this is now searching for the genVOIs script
function_path=($(which KUL_FWT_make_TCKs.sh | rev | cut -d"/" -f2- | rev))
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

TCKs_prepd="${output_d}/sub-${subj}${ses_str}_TCKs_prep"

TCKs_outd="${output_d}/sub-${subj}${ses_str}_TCKs_output"

# make your dirs

mkdir -p ${output_d} >/dev/null 2>&1

mkdir -p ${TCKs_outd} >/dev/null 2>&1

mkdir -p ${TCKs_prepd} >/dev/null 2>&1

# make your log file

prep_log2="${output_d}/KUL_FWT_TCKs_log_${subj}_${d}.txt";

if [[ ! -f ${prep_log2} ]] ; then

    touch ${prep_log2}

else

    echo "${prep_log2} already created"

fi

# deal with tracking algorithm

if [[ "$T_app" -eq 0 ]]; then

    echo " -T flag is not set, exitting"
    echo " Please specify the fiber tracking approach to use"
    exit 2

else

    if [[ "$T_app" -eq 1 ]]; then

        Tracto=1

    elif [[ "$T_app" -eq 2 ]]; then

        Tracto=2

    else

        echo " Incorrect choice of fiber tracking approach, please select 1 or 2"
        exit 2

    fi

fi

# # filtering scheme selection

if [[ "${filt_fl1}" -eq 0 ]]; then 
    
    filt_fl2=2
    echo " No filtering scheme selected, we will do liberal filtering by default " | tee -a ${prep_log2}
    Alfa=0.48

else

    if [[ ${filt_fl2} =~ ^[+-]?[0-9]+$ ]]; then 

        if [[ ${filt_fl2} -eq 0 ]]; then
            
            echo " No filtering selected " | tee -a ${prep_log2}
        
        elif [[ ${filt_fl2} -eq 1 ]]; then
            
            echo " Conservative filtering selected " | tee -a ${prep_log2}
            Alfa=0.48
        
        elif [[ ${filt_fl2} -eq 2 ]]; then
            
            echo " Liberal filtering selected " | tee -a ${prep_log2}
            Alfa=0.38

        else
            
            echo "incorrect input to -f flag (filtering option selection), exiting "
            exit 2

        fi

    else
        
        echo "incorrect input to -f flag (filtering option selection), exiting "
        exit 2

    fi

fi

# Report on quanti, quali and screenshot workflows

if [[ "${Q_flag}" -eq 0 ]]; then 

    echo "Quantitative and qualitative analysis switched on" | tee -a ${prep_log2}

fi

if [[ "${S_flag}" -eq 0 ]]; then 

    echo "Screenshots switched on" | tee -a ${prep_log2}

fi

# set mrtrix tmp dir to prep_d

rm -rf ${TCKs_prepd}/tmp_dir_*

tmpo_d="${TCKs_prepd}/tmp_dir_${d}"

mkdir -p "${tmpo_d}" >/dev/null 2>&1

export MRTRIX_TMPFILE_DIR="${tmpo_d}"

# report pid

processId=$(ps -ef | grep 'ABCD' | grep -v 'grep' | awk '{ printf $2 }')
echo $processId

echo "KUL_FWT_make_TCKs.sh @ ${d} with parent pid $$ and process pid $BASHPID " | tee -a ${prep_log2}
echo "Inputs are -p  sub-${subj} -s ses-${ses} -c  ${conf_f} -d ${d_dir}  -F ${FS_dir}  -M ${MS_dir} " | tee -a ${prep_log2}

# read the config file
# if a hash is found this cell is populated with ##

declare -a tck_lst1

declare -a tck_list

declare -a nosts_list

# tck_lst1=($(cat  ${conf_f}))

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


# function for tckedit or tckgen for each bundle

function make_bundle {


    echo "---------------------" | tee -a ${prep_log2}

    echo ${tcks_2_make} | tee -a ${prep_log2}

    # echo " Started @ $(date "+%Y-%m-%d_%H-%M-%S")" | tee -a ${prep_log2}

    # we need 2 - 3 arrays per tck (includes labels, and excludes, and hemi excludes)

    # https://stackoverflow.com/questions/16553089/dynamic-variable-names-in-bash
    # found out how to do dynamic variable naming

    # to use dynamic variable definitions in bash
    # eval v_array=( \${${tck}_array[@]})

    # updated this line to clear local vars at the start
    unset TCK_I TCK_X auto_X tracking_mask

    TCK_2_make=${TCK_to_make}

    # Handle dirs for prep and output of TCK

    # TCK_prep="${TCKs_prepd}/${TCK_2_make}_prep"

    TCK_out="${TCKs_outd}/${TCK_2_make}_output"

    # mkdir -p "${TCK_prep}" >/dev/null 2>&1

    mkdir -p "${TCK_out}" >/dev/null 2>&1

    # define includes and excludes

    TCK_I_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_bin.nii.gz));

    TCK_I_m=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_map.nii.gz));

    TCK_X_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_excs/${TCK_2_make}_excs_bin.nii.gz));

    # these guys say map but they r actually binary
    TCK_Is_MNI=($(find ${ROIs_d}/${TCK_2_make}_VOIs_inMNI/${TCK_2_make}_incs*_map_inMNI.nii.gz));

    # define auto_excludes based on laterality

    if [[ ${TCK_2_make} == *"DRT_LT"* ]]; then

        echo " Right DRT " | tee -a ${prep_log2}
        auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz -exclude ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz "
        auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz any exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz any exclude"

    elif [[ ${TCK_2_make} == *"DRT_RT"* ]]; then

        echo " Left DRT " | tee -a ${prep_log2}
        auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz -exclude ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz "
        auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz any exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz any exclude"

    elif [[ ${TCK_2_make} == *"Fx_LT"* ]]; then

        echo " Left Fornix " | tee -a ${prep_log2}
            # removed -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_nv.nii.gz
            # removed --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_nv.nii.gz any exclude
        auto_X="  -exclude ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz "
        auto_X_f="  --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz any exclude"

    elif [[ ${TCK_2_make} == *"Fx_RT"* ]]; then

        echo " Right Fornix " | tee -a ${prep_log2}
            # removed -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_nv.nii.gz
            # removed --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_nv.nii.gz any exclude
        auto_X="  -exclude ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz "
        auto_X_f="  --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz any exclude"
    

    else

        if [[ ${TCK_2_make} == *"_Comm" ]] ; then

            echo " ${TCK_2_make} a commissural or midline bundle " | tee -a ${prep_log2}
            auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz "
            auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz any exclude"

        elif [[ ${TCK_2_make} == *"CP_LT"* ]] ; then

            echo " Cerebellar bundle " | tee -a ${prep_log2}
            auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz \
            -exclude ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz"
            auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz any exclude --drawn_roi \
            ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz any exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz any exclude"

        elif [[ ${TCK_2_make} == *"CP_RT"* ]] ; then

            echo " Cerebellar bundle " | tee -a ${prep_log2}
            auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz \
            -exclude ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz"
            auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz any exclude --drawn_roi \
            ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz any exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz any exclude"

        elif [[ ${TCK_2_make} == *"LT"* ]] ; then

            echo " Left sided bundle " | tee -a ${prep_log2}
            auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz -exclude ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz "
            auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz any exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz any exclude"

        elif [[ ${TCK_2_make} == *"RT"* ]]; then

            echo " Right sided bundle " | tee -a ${prep_log2}
            auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz -exclude ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz "
            auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz any exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_Bil_X.nii.gz any exclude "

        else

            echo " ${TCK_2_make} will not need hemispheric excludes " | tee -a ${prep_log2}
            auto_X=""
            auto_X_f=""

        fi


    fi
    # define include and exclude strings for tckgen &/or tckedit

    includes_str=$(printf " -include %s"  "${TCK_I_b[@]}")

    seeds_str=$(printf " -seed_image %s"  "${TCK_I_b[@]}")

    excludes_str=$(printf " -exclude %s"  "${TCK_X_b[@]}")

    # run tckgen or tckedit depending on the ${T_app}
    # Must differentiate between BST and WBTS

    tracking_mask="${T1_brain_mask_inFA}"

    # if it's an OR or AF use the minCSF
    if [[ ${TCK_2_make} == *"OR_"* ]] || [[ ${TCK_2_make} == *"AF_"* ]] || [[ ${TCK_2_make} == *"CP_"* ]] || [[ ${TCK_2_make} == *"DRT_"* ]] ; then

        tracking_mask="${T1_BM_inFA_minCSF}"

    else

        tracking_mask="${T1_brain_mask_inFA}"

    fi

    if [[ ${TCK_2_make} == *"CP_"* ]] || [[ ${TCK_2_make} == *"DRT_"* ]]; then

        excludes_str+=$(printf " -exclude %s"  "${MSBP_csf_mask}")

    fi

    if [[ ${T_app} == 1 ]]; then 

        T="BT"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        # cmd_str="tckgen -force -nthreads ${ncpu} -algorithm ${algo_f} -angle 45 \
        # -select ${ns} -maxlength 280 -minlength 20 \
        # -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

        cmd_str="tckgen -force -nthreads ${ncpu} -algorithm ${algo_f} \
        -select ${ns} -maxlength 280 -minlength 20 \
        -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

    elif [[ ${T_app} == 2 ]]; then 

        T="WB"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        cmd_str="tckedit -force -nthreads ${ncpu} -maxlength 280 -minlength 10 -tck_weights_in ${TCKs_outd}/sub-${subj}${ses_str}_sift2_ws.txt \
        -mask ${tracking_mask} -minweight 0.08 ${includes_str} ${excludes_str} ${auto_X} ${WB_tck} ${tck_init}"

    fi


    # define scilpy filtering strings
    # we only use the start and end includes, i.e. the first and last for the includes array
    # need to add condition for bilateral - commissural bundles

    if [[ ${TCK_2_make} == *"_Comm" ]]; then
        # should ensure that all bundles of this kind start with the midline VOI as inc1, and incs2 & 3 as the cortical VOIs

      drawn_incs_str=$(printf " --drawn_roi %s any include "  "${TCK_I_b[0]}")

      drawn_incs_str+=$(printf " --drawn_roi %s either_end include "  "${TCK_I_b[${#TCK_I_b[@]}-1]}")

      drawn_incs_str+=$(printf " --drawn_roi %s either_end include "  "${TCK_I_b[${#TCK_I_b[@]}-2]}")

    else

        if [[ ${TCK_2_make} == *"CST"* ]] || [[ ${TCK_2_make} == *"PyT"* ]] || [[ ${TCK_2_make} == *"ML_"* ]]; then

            drawn_incs_str=$(printf " --drawn_roi %s any include "  "${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz")

        else

            drawn_incs_str=$(printf " --drawn_roi %s any include "  "${TCK_I_b[0]}")

        fi

        # it's better to define this differently depending on the number of VOIs
        # i.e. if only 2 incs then easy, end to inc, if more then end for inc1 then any for middle and end for inc(N)
        # trying with either_end for both includes if only 2 are selected
        # this deals with the rest of the filtering string

        unset vsz
        vsz="${#TCK_I_b[@]}"

        if [[ ${vsz} -eq 2 ]]; then

            if [[ ${TCK_2_make} == *"OR_LT"* ]] || [[ ${TCK_2_make} == *"OR_RT"* ]]; then

                drawn_incs_str+=$(printf " --drawn_roi %s any include "  "${TCK_I_b[1]}")

            else

                drawn_incs_str+=$(printf " --drawn_roi %s any include "  "${TCK_I_b[1]}")

            fi

        elif [[ ${vsz} -gt 2 ]]; then

            for vi in ${TCK_I_b[@]:1:$((vsz-2))}; do

                drawn_incs_str+=$(printf " --drawn_roi %s any include "  "${TCK_I_b[$vi]}")

            done

            drawn_incs_str+=$(printf " --drawn_roi %s any include "  "${TCK_I_b[${vsz}-1]}")

        fi

    fi

    # excludes will always be the same
    drawn_excs_str=$(printf " --drawn_roi %s any exclude "  "${TCK_X_b[@]}")

    # processing control for initial tracking/segmentation

    if [[ ! -f "${tck_init}" ]]; then

        task_in="${cmd_str}"

        task_exec

        task_in="tcktransform -force ${tck_init} ${TCKs_w2temp} ${tck_init_inT}"

        task_exec

        count=($(tckstats -force -nthreads ${ncpu} -output count ${tck_init} -quiet ));

    else

        count=($(tckstats -force -nthreads ${ncpu} -output count ${tck_init} -quiet ));

        if [[ ! -f ${tck_init_inT} ]]; then
          
            task_in="tcktransform -force ${tck_init} ${TCKs_w2temp} ${tck_init_inT}"

            task_exec
        fi

        if [[ ${count} -gt 10 ]]; then

            echo " ${TCK_2_make}_initial.tck already done, skipping " | tee -a ${prep_log2}

            # count=($(tckstats -force -nthreads ${ncpu} -output count ${tck_init} -quiet ));

            # report initial yield
            echo " ${TCK_2_make} has ${count} streamlines initially " | tee -a ${prep_log2}

        else

            task_in="${cmd_str}"

            task_exec

            count=($(tckstats -force -nthreads ${ncpu} -output count ${tck_init} -quiet ));

        fi

    fi

    # need to create combined incs_bin maps for QQ
    # loop from 2nd element in incs_bin array
    if [[ ! -f "${TCK_out}/${TCK_2_make}_incs_map_agg_inMNI.nii.gz" ]]; then

        ((funn=${#TCK_I_b[@]}-1));
        mrcal_strs=$(printf " %s "  "${TCK_I_b[0]}")
        for fun in $(seq 1 ${funn}); do
            ((funme=${fun}+1))
            task_in="mrcalc -force -quiet -nthreads ${ncpu} ${TCK_I_b[$fun]} 0 -gt ${funme} -mult \
            ${tmpo_d}/${TCK_2_make}_incs_map_init${funme}.nii.gz"
            task_exec
            mrcal_strs+=$(printf " %s -add "  "${tmpo_d}/${TCK_2_make}_incs_map_init${funme}.nii.gz")
        done

        # WIP we mult the result agg map by 10 to ease separating heads from toes
        task_in="mrcalc -force -quiet -nthreads ${ncpu} ${mrcal_strs} 0 -gt ${tmpo_d}/${TCK_2_make}_incs_map_agg_bin.nii.gz"

        task_exec

        task_in="mrcalc -force -quiet -nthreads ${ncpu} ${mrcal_strs} ${tmpo_d}/${TCK_2_make}_incs_map_agg_bin.nii.gz -mult 10 -mult ${TCK_out}/${TCK_2_make}_incs_map_agg.nii.gz"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${TCK_out}/${TCK_2_make}_incs_map_agg.nii.gz -o ${TCK_out}/${TCK_2_make}_incs_map_agg_inMNI.nii.gz -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz \
        -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz \
        -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0]"

        task_exec

    fi

    # including scil_filter_tracts by default as soon as the initial bundle is generated
    # with the exception of the ORs where FBC is used
    # if the bundle has more than 0 streamlines, look whether filt1.tck has already been generated
    # then look at whether it is an OR or not

    tck_filt1="${TCK_out}/${TCK_2_make}_filt1_${T}_${algo_f}.tck"

    tck_filt2="${TCK_out}/${TCK_2_make}_filt2_${T}_${algo_f}.tck"

    tck_filt3="${TCK_out}/${TCK_2_make}_filt3_${T}_${algo_f}.tck"

    tck_filt5="${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck"

    tck_filt5_centroid1="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_centroid1.tck"

    tck_filt1_inT="${TCK_out}/${TCK_2_make}_filt1_${T}_${algo_f}_inMNI.tck"

    tck_filt3_inT="${TCK_out}/${TCK_2_make}_filt3_${T}_${algo_f}_inMNI.tck"

    tck_filt5_inT="${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck"

    tck_rs1_inT="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_inMNI.tck"

    # MNI_segs1="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs51_segments1_inMNI.nii.gz"

    tck_cent1_HT_map="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_mapped_inMNI.nii.gz"

    MNI_segs="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_segments_inMNI.nii.gz"

    # MNI_segsd="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_segments_inMNI_debug.nii.gz"

    # MNI_segs3="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs50_segments3_inMNI.nii.gz"

    MNI_agg="${TCK_out}/QQ/${TCK_2_make}_incs_map_agg_inMNI.nii.gz"

    TCKs_curve="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_curve_inMNI.nii.gz"

    TCKs_tdi="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi_inMNI.nii.gz"

    TCKs_length="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_length_inMNI.nii.gz"

    # tck_4QQ_inT="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_4QQ.tck"

    # tck_segs1="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs51_segments1_inMNI.nii.gz"
    lego_1="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_lego1.nii.gz"
    lego_2="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_lego2.nii.gz"
    tckp1_4QQ_inT="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_4QQ_seg1.tck"

    tck_reor="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_rTCK.tck"
    tckc_reor="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_centroid_rTCK.tck"

    if [[ ${count} -gt 10 ]] && [[ ! ${filt_fl2} == 0 ]]; then

        if [[ ! -f "${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}_inMNI.nii.gz" ]]; then

            if [[ ! ${TCK_2_make} == "O"* ]]; then

                echo " We use scilpy filtering and outlier rejection for ${TCK_2_make} " | tee -a ${prep_log2}

                if [[ ! -f ${tck_filt1} ]]; then

                    task_in="scil_filter_tractogram.py -f --reference ${subj_FA} ${drawn_incs_str} ${drawn_excs_str} ${auto_X_f} ${tck_init} ${tck_filt1}"

                    task_exec

                    sleep 2

                    count2=($(tckstats -force -nthreads ${ncpu} -output count ${tck_filt1} -quiet ));

                else

                    echo " ${TCK_2_make} initial filtering already done, skipping " | tee -a ${prep_log2}

                fi

                if [[ -f ${tck_filt1} ]] && [[ ! -f ${tck_filt5} ]] && [[ ${count2} -gt 10 ]]; then

                    task_in="tckmap -precise -force -nthreads ${ncpu} -template ${subj_FA} ${tck_filt1} \
                    ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz && mrcalc -datatype uint16 -force -nthreads ${ncpu} \
                    ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz 0 -gt ${TCK_out}/${TCK_2_make}_filt1_map_mask_${T}_${algo_f}.nii.gz"

                    task_exec &

                    task_in="scil_detect_streamlines_loops.py -f --reference ${subj_FA} ${tck_filt1} ${tck_filt2}"

                    task_exec

                    task_in="scil_outlier_rejection.py -f --alpha ${Alfa} --reference ${subj_FA} ${tck_filt2} ${tck_filt3}"

                    task_exec

                    task_in="scil_smooth_streamlines.py -f --gaussian 5 --reference ${subj_FA} ${tck_filt3} ${tck_filt5}"

                    task_exec

                    task_in="tcktransform -force ${tck_filt3} ${TCKs_w2temp} ${tck_filt3_inT}"

                    task_exec

                else

                    echo " ${TCK_2_make} initial filtering failed, skipping " | tee -a ${prep_log2}

                fi

            elif [[ ${TCK_2_make} == "O"* ]]; then

                echo " We use FBC filtering for the optic radiations " | tee -a ${prep_log2}

                if [[ ! -f ${tck_filt1} ]]; then

                    task_in="KUL_FWT_FBC_4TCKs.py -i ${tck_init} -r ${subj_FA} -o ${tck_filt1}"

                    task_exec

                    sleep 2

                    count2=($(tckstats -force -nthreads ${ncpu} -output count ${tck_filt1} -quiet ));

                else

                    echo " ${TCK_2_make} FBC filtering already finished, skipping " | tee -a ${prep_log2}

                fi

                if [[ -f ${tck_filt1} ]] && [[ ! -f ${tck_filt5} ]] && [[ ${count2} -gt 10 ]]; then

                    task_in="tckmap -precise -force -nthreads ${ncpu} -template ${subj_FA} ${tck_filt1} \
                    ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz && mrcalc -datatype uint16 -force -nthreads ${ncpu} \
                    ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz 0 -gt ${TCK_out}/${TCK_2_make}_filt1_map_mask_${T}_${algo_f}.nii.gz"

                    task_exec &

                    task_in="scil_smooth_streamlines.py -f --gaussian 5 --reference ${subj_FA} ${tck_filt1} ${tck_filt5}"

                    task_exec

                    task_in="tcktransform -force ${tck_filt1} ${TCKs_w2temp} ${tck_filt1_inT}"

                    task_exec

                    sleep 5

                    task_in="tckmap -precise -force -nthreads ${ncpu} -template ${UKBB_temp} ${tck_filt5_inT} \
                    ${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}_inMNI.nii.gz"

                    task_exec

                else

                    echo " ${TCK_2_make} FBC filtering failed, skipping " | tee -a ${prep_log2}

                fi

            fi

            if [[ -f ${tck_filt5} ]]; then

                task_in="tckmap -precise -force -nthreads ${ncpu} -template ${subj_FA} ${tck_filt5} \
                ${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}.nii.gz && mrcalc -datatype uint16 -force -nthreads ${ncpu} \
                ${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}.nii.gz 0 -gt ${TCK_out}/${TCK_2_make}_fin_map_mask_${T}_${algo_f}.nii.gz"

                task_exec &

                task_in="tcktransform -nthreads ${ncpu} -force ${tck_filt5} ${TCKs_w2temp} ${tck_filt5_inT}"

                task_exec

                sleep 5

                task_in="tckmap -precise -force -nthreads ${ncpu} \
                -template ${UKBB_temp} ${tck_filt5_inT} \
                ${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}_inMNI.nii.gz"

                task_exec

            else

                echo " Streamlines filtering failed " | tee -a ${prep_log2}

            fi

        else

            echo " ${TCK_2_make} filtering already done, skipping filtering " | tee -a ${prep_log2}

        fi

    else
        if [[ ${count} -gt 10 ]]; then
            echo " ${TCK_2_make} has less than 10 fibers initially, skipping filtering " | tee -a ${prep_log2}
        fi

        if [[ ! ${filt_fl2} == 0 ]]; then
            echo " Streamline filtering is disabled by the user, skipping filtering " | tee -a ${prep_log2}
        fi


    fi

    # now we see whether screenshots and qq are needed
    # we use native space bundles for QQ
    # additions:
    # 1- QQ will use tckresample -npoints 100
    # 2- tcksample per metric
    # 3- resulting csv can be plotted per row (for per streamlines)
    # 4- find out how to calc sd from mean, median, min and max
    # 5- incorporate tckstats also
    # 6- add scil_vis_mosaic to SCs
    # 7- *** QQ happens in native space
    # 8- keep the --nb_points at 50?
    
    if [[ "${Q_flag}" -eq 1 ]] && [[ ! ${filt_fl2} == 0 ]]; then

        # metrics+=("${MNI_segs}" "${MNI_agg}")

        if [[ -f "${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck" ]] && [[ ! -f "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_QQ_done.done" ]]; then 

            mkdir -p "${TCK_out}/QQ"

            mkdir -p "${TCK_out}/QQ/tmp"

            task_in="tckresample -force -nthreads ${ncpu} -num_points 101 ${tck_filt5_inT} ${tck_rs1_inT}"

            task_exec

            task_in="scil_compute_centroid.py -f --reference ${UKBB_temp} --nb_points 101 ${tck_filt5_inT} ${tck_filt5_centroid1}"

            task_exec

            task_in="tckmap -force -nthreads ${ncpu} -template ${UKBB_temp} ${tck_filt5_centroid1} - | mrcalc - 0 -gt - | maskfilter - dilate - -npass 2 | mrcalc - ${TCK_out}/${TCK_2_make}_incs_map_agg_inMNI.nii.gz -mult ${tck_cent1_HT_map} -force -nthreads ${ncpu}"

            task_exec

            task_in="tckmap -precise -force -stat_vox max -contrast length -template ${UKBB_temp} ${tck_filt5_inT} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_length_inMNI.nii.gz \
            && tckmap -precise -force -stat_vox max -contrast curvature -template ${UKBB_temp} ${tck_filt5_inT} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_curve_inMNI.nii.gz \
            && tckmap -precise -force -stat_vox sum -contrast tdi -template ${UKBB_temp} ${tck_filt5_inT} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi_inMNI.nii.gz"

            task_exec

            # new heads and tails work, forget about the center

            if [[ "${#TCK_Is_MNI[@]}" -eq 2 ]]; then

                # we want the first inc as the start and the second as the end
                task_in="KUL_FWT_reorientTCKs.py -i ${tck_rs1_inT} -c ${tck_filt5_centroid1} -m ${prep_d} -s ${TCK_Is_MNI[0]} -e ${TCK_Is_MNI[1]}"

                task_exec

            elif [[ "${#TCK_Is_MNI[@]}" -eq 3 ]]; then

                if [[ ${TCK_2_make} == *"_Comm" ]]; then

                    # we want the second inc as the start and the last as the end

                    task_in="KUL_FWT_reorientTCKs.py -i ${tck_rs1_inT} -c ${tck_filt5_centroid1} -m ${prep_d} -s ${TCK_Is_MNI[1]} -e ${TCK_Is_MNI[-1]}"

                    task_exec

                else

                    # we want the first inc as the start and the last as the end
                    task_in="KUL_FWT_reorientTCKs.py -i ${tck_rs1_inT} -c ${tck_filt5_centroid1} -m ${prep_d} -s ${TCK_Is_MNI[0]} -e ${TCK_Is_MNI[-1]}"

                    task_exec

                fi

            elif [[ "${#TCK_Is_MNI[@]}" -gt 3 ]]; then

                # task_in="mrcalc -force -nthreads ${ncpu} ${tck_cent1_HT_map} 10 -eq 0 -gt ${lego_1} \
                # && mrcalc -force -nthreads ${ncpu} ${tck_cent1_HT_map} 40 -eq 0 -gt ${lego_2}"

                # task_exec

                # # we want the first inc as the start and the last as the end
                task_in="KUL_FWT_reorientTCKs.py -i ${tck_rs1_inT} -c ${tck_filt5_centroid1} -m ${prep_d} -s ${TCK_Is_MNI[0]} -e ${TCK_Is_MNI[-1]}"

                task_exec


            fi

            # grab em by the scruff of their necks
            # make new map of reoriented bundle, this should now be consistent
            task_in="scil_compute_bundle_voxel_label_map.py -f --reference ${UKBB_temp} --out_labels_npz ${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_labels_inMNI.npz --out_distances_npz ${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_distances_inMNI.npz ${tck_reor} ${tckc_reor} ${MNI_segs}"

            task_exec

            # task_in="scil_compute_bundle_voxel_label_map.py -f --reference ${UKBB_temp} --out_labels_npz ${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_labels_inMNI_d.npz --out_distances_npz ${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_distances_inMNI_d.npz ${tck_filt5_inT} ${tck_filt5_centroid1} ${MNI_segsd}"

            task_exec

            task_in="antsApplyTransforms -d 3 -i ${CFP_aparc_inFA} \
            -o ${CFP_aparc_inMNI} -r ${UKBB_temp} \
            -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
            -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] -n MultiLabel"

            task_exec

            
            task_in="KUL_FWT_TCKsm_cap.py -i ${MNI_segs}"

            task_exec &

            # for debugging
            # task_in="KUL_FWT_TCKsm_cap.py -i ${MNI_segsd}"

            # task_exec &

            # for met in metrics
            # this list is conditional, if DTI only FA and MD 
            # if CSD add FD, disp and peaks

            task_in="tckstats -force -nthreads ${ncpu} ${tck_reor} -histogram ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_lengths_histogram.csv | tee -a ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_lengths_report.csv"

            task_exec

            metrics=("FA" "ADC" "AD" "RD" "TDI" "Length" "Curve")
            mets_fs=("${subj_FA_MNI}" "${subj_ADC_MNI}" "${subj_AD_MNI}" "${subj_RD_MNI}" "${TCKs_tdi}" "${TCKs_length}" "${TCKs_curve}")

            if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

                metrics+=("FD" "Disp" "Peaks")
                mets_fs+=("${subj_vfd_MNI}" "${subj_vdisp_MNI}" "${subj_vpk_MNI}")

            fi

            for mets in ${!metrics[@]}; do

                met_name=${metrics[$mets]}

                task_in="tcksample -nointerp -force -nthreads ${ncpu} ${tck_reor} ${mets_fs[$mets]} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_${met_name}.csv"

                task_exec

            done

            sleep 10

            # new KUL_QQ_TCKs.py should be in the for loop above
            # this will take as input the resampled bundle, the centroid?, the metric of choice and the prep_d
            # no need to make the QQ dir in there anymore
            # csvs need to be read in then plotted line by line

            task_in="KUL_FWT_TCKsQQ.py -i ${tck_reor} -m ${prep_d}"

            task_exec

            touch "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_QQ_done.done" && echo "${TCK_2_make}_fin_${T}_${algo_f} QQ work is done" | tee -a ${prep_log2}

        fi

    fi

    # Screenshots workflow
    # we use template warped TCKs for SCs
    if [[ "${S_flag}" -eq 1 ]] && [[ ! ${filt_fl2} == 0 ]]; then

        if [[ -f "${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck" ]] && [[ ! -f "${TCK_out}/Screenshots/${TCK_2_make}_fin_${T}_${algo_f}_Sc_done.done" ]]; then

            # WIP, need to adapt to non-MNI registered data
            # this means we must apply a warp to the bundles
            # and use the T1 in MNI space
            # luckily the UKBB template we're using is already in MNI space
            task_in="KUL_FWT_SCs_TCKs.py -i ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck -m ${prep_d} -v ${ROIs_d}/${TCK_2_make}_VOIs_inMNI"

            task_exec

            # scil SCs need an explicit mentioning of laterality
            # furthermore, we have other scil tools to use for visualization purposes
            # e.g. mosaic

            if [[ ${TCK_2_make} == *"_RT_"* ]]; then

                task_in="scil_screenshot_bundle.py -f --right --local_coloring 
                --out_dir ${TCK_out}/Screenshots --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f}+anat \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck ${subj_T1_in_UKBB} \
                && scil_screenshot_bundle.py -f --right --local_coloring --out_dir \
                ${TCK_out}/Screenshots --anat_opacity 0 --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f} \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck ${subj_T1_in_UKBB}"

                task_exec

            else

                task_in="scil_screenshot_bundle.py -f --local_coloring \
                --out_dir ${TCK_out}/Screenshots --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f}+anat \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck ${subj_T1_in_UKBB} \
                && scil_screenshot_bundle.py -f --local_coloring --out_dir \
                ${TCK_out}/Screenshots --anat_opacity 0 --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f} \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck ${subj_T1_in_UKBB}"

                task_exec

            fi

            mkdir -p "${TCK_out}/Screenshots/mosaic"

            task_in="scil_visualize_bundles_mosaic.py -f --zoom 1.5 --reference ${subj_T1_in_UKBB} --opacity_background 0.3 --resolution_of_thumbnails 600 \
            ${subj_T1_in_UKBB} ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck \
            ${TCK_out}/Screenshots/mosaic/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_mosaic.pdf "

            task_exec

        fi

        touch "${TCK_out}/Screenshots/${TCK_2_make}_fin_${T}_${algo_f}_Sc_done.done" && echo "${TCK_2_make}_fin_${T}_${algo_f} screenshots work is done" | tee -a ${prep_log2}

    fi

    unset TCK_out TCK_2_make

}


###################################################################################
# script start here
# part 1 of this workflow is general purpose and should be run for all bundles
# use processing control

# find your priors
# all priors are in MNI space

ROIs_d="${output_d}/sub-${subj}${ses_str}_VOIs"

prep_d="${output_d}/sub-${subj}${ses_str}_prep"

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

RL_VOIs="${pr_d}/RL_hemi_masks.nii.gz" # done

TCKs_w2temp="${prep_d}/FS_2_UKBB_${subj}_inv_4TCKs.mif"

subj_fpk="sub-${subj}_fixel_peaks.mif"

subj_ffd="sub-${subj}_fixel_fd.mif"

subj_fdisp="sub-${subj}_fixel_disp.mif"

subj_vpk="${prep_d}/peaks.nii.gz"

subj_vfd="${prep_d}/fd.nii.gz"

subj_vdisp="${prep_d}/disp.nii.gz"

subj_FA="${prep_d}/fa.nii.gz"

subj_ADC="${prep_d}/adc.nii.gz"

subj_RD="${prep_d}/RD.nii.gz"

subj_AD="${prep_d}/AD.nii.gz"

subj_vpk_MNI="${prep_d}/peaks_MNI.nii.gz"

subj_vfd_MNI="${prep_d}/fd_MNI.nii.gz"

subj_vdisp_MNI="${prep_d}/disp_MNI.nii.gz"

subj_FA_MNI="${prep_d}/FA_MNI.nii.gz"

subj_ADC_MNI="${prep_d}/ADC_MNI.nii.gz"

subj_RD_MNI="${prep_d}/RD_MNI.nii.gz"

subj_AD_MNI="${prep_d}/AD_MNI.nii.gz"

WB_tck="${TCKs_outd}/sub-${subj}${ses_str}_WB_TCKs.tck"

####

# subj_FA=($(find ${prep_d} -type f -name "fa.nii.gz"))

# if [[ -z ${subj_FA} ]]; then

#     subj_FA=($(find ${d_dir}/qa -type f -name "fa_reg2T1w.nii.gz"))

#     if [[ -z ${subj_FA} ]]; then

#         subj_FA=($(find ${d_dir} -type f -name "FA.nii.gz"));

#         if [[ -z ${subj_FA} ]]; then

#             subj_FA=($(find ${d_dir} -type f -name "fa.nii.gz"));

#         fi

#     fi

#     if [[ -z ${subj_FA} ]]; then

#         echo "Unable to find FA map, quitting"
#         exit 2
#     fi

# fi

# switched the above search for the metric maps in prepd
# makes it simpler to use later, along with more metrics



####

# We can start this workflow if pt1 & 2 of genVOIs is done

if [[ -z "${ROIs_d}/Part1.done" ]] && [[ -z "${ROIs_d}/Part2.done" ]]; then

    echo " General purpose VOIs are not yet generated, please run KUL_genVOIs.sh first"
    exit 2

elif [[ ! -z "${ROIs_d}/Part1.done" ]] && [[ ! -z "${ROIs_d}/Part2.done" ]]; then

    # these should all be created by the genVOIs script
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

    CIT_in_FA="${prep_d}/sub-${subj}${ses_str}_CIT_inFA.nii.gz"

    UKBB_in_FA="${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFA.nii.gz"

    JuHA_in_FA="${prep_d}/sub-${subj}${ses_str}_Juelich_VOIs_inFA.nii.gz"

    JHU_in_FA="${prep_d}/sub-${subj}${ses_str}_JHU_VOIs_inFA.nii.gz"

    Man_VOIs_in_FA="${prep_d}/sub-${subj}${ses_str}_Manual_VOIs_inFA.nii.gz"

    subj_aparc_inFA="${prep_d}/sub-${subj}${ses_str}_aparc_inFA.nii.gz"

    subj_aseg_inFA="${prep_d}/sub-${subj}${ses_str}_aseg_inFA.nii.gz"

    subj_FS_WMaparc_inFA="${prep_d}/sub-${subj}${ses_str}_WMaparc_inFA.nii.gz"

    subj_MSsc3_inFA="${prep_d}/sub-${subj}${ses_str}_MSBP_scale3_inFA.nii.gz"

    CFP_aparc_inFA="${prep_d}/sub-${subj}${ses_str}_LC+spine_inFA.nii.gz"

    CFP_aparc_inMNI="${prep_d}/sub-${subj}${ses_str}_LC+spine_inMNI.nii.gz"

    subj_FS_lobes_inFA="${prep_d}/sub-${subj}${ses_str}_FS_lobes_inFA.nii.gz"

    subj_FS_2009_inFA="${prep_d}/sub-${subj}${ses_str}_FS_2009_inFA.nii.gz"

    subj_FS_Fx_inFA="${prep_d}/sub-${subj}${ses_str}_FS_fornix_inFA.nii.gz"

    # will use MS_2_UKBB here, as it will be normal in case of a lesion free brain
    # and will be lesioned if using VBG filled FS input (as long as MSBP was run after VBG_FS recon-all)
    subj_T1_in_UKBB="${prep_d}/MS_2_UKBB_${subj}${ses_str}_Warped.nii.gz"

    # account for different tracking algorithms

    subj_dwi=($(find ${d_dir} -type f -name "dwi_preproced_reg2T1w.mif"))

    subj_fod=($(find ${d_dir} -type f -name "dhollander_wmfod_reg2T1w.mif"))

    subj_dt=($(find ${d_dir} -type f -name "dwi_dt_reg2T1w.mif"))

    subj_dwi_bm=($(find ${d_dir} -type f -name "dwi_preproced_reg2T1w_mask.nii.gz"))

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

    # Find your FODs

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

    # find your brain mask in FA

    if [[ -z ${T1_brain_mask_inFA} ]]; then

        subj_dwi_bm=($(find ${prep_d} -type f -name "*T1bm_MSinFA_Warped*"))

        if [[ -z ${subj_dwi_bm} ]]; then

            echo "no dwi brain mask found, quitting" | tee -a ${prep_log2}
            exit 2

        fi

    fi

    # find your tensors

    if [[ -z ${subj_dt} ]]; then

        subj_dt=($(find ${d_dir} -type f -name "*_tensor*"))

        if [[ -z ${subj_dt} ]]; then

            subj_dt=($(find ${prep_d} -type f -name "*_tensor*"))

            if [[ -z ${subj_dt} ]]; then

                echo "no Diffusion tensor found, quitting" | tee -a ${prep_log2}
                exit 2
            fi

        fi

    fi

    subj_DT_vecs=($(find ${d_dir} -type f -name "sub-${subj}_dwi_dt_vecs_reg2T1w.mif"))

    # metrics=("${subj_FA_MNI}" "${subj_ADC_MNI}" "${subj_AD_MNI}" "${subj_RD_MNI}")

    # if we want to quantify we should add rd and ad
    if [[ "${Q_flag}" -eq 1 ]] && [[ ! -f "${subj_RD_MNI}" ]]; then

        task_in="tensor2metric -force -mask ${T1_brain_mask_inFA} -rd ${subj_RD} -ad ${subj_AD} ${subj_dt}"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_FA} \
        -o ${subj_FA_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        && antsApplyTransforms -d 3 -i ${subj_ADC} \
        -o ${subj_ADC_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        && antsApplyTransforms -d 3 -i ${subj_AD} \
        -o ${subj_AD_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        && antsApplyTransforms -d 3 -i ${subj_RD} \
        -o ${subj_RD_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0]"

        task_exec

    fi

    # make some CSD based metrics

    if [[ ! -f "${subj_vdisp_MNI}"  ]]; then

        if [[ -d "${prep_d}/fixel_metrics" ]]; then

            echo "removing old fixels dir" | tee -a ${prep_log2}
            rm -rf "${prep_d}/fixel_metrics"

        fi

        task_in="fod2fixel -force -quiet -nthreads ${ncpu} -afd ${subj_ffd} -disp ${subj_fdisp} -peak_amp ${subj_fpk} ${subj_fod} ${prep_d}/fixel_metrics"

        task_exec

        task_in="fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_ffd} mean ${subj_vfd} -weighted ${prep_d}/fixel_metrics/${subj_ffd} \
        && fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_fdisp} mean ${subj_vdisp} -weighted ${prep_d}/fixel_metrics/${subj_fdisp} \
        && fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_fpk} mean ${subj_vpk} -weighted ${prep_d}/fixel_metrics/${subj_fpk}"

        task_exec

        task_in="antsApplyTransforms -d 3 -i ${subj_vpk} \
        -o ${subj_vpk_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        && antsApplyTransforms -d 3 -i ${subj_vfd} \
        -o ${subj_vfd_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        && antsApplyTransforms -d 3 -i ${subj_vdisp} \
        -o ${subj_vdisp_MNI} -r ${UKBB_temp} \
        -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0]"

        task_exec

    fi

    if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

        tracking_string=" -algorithm ${algo_f} -seed_dynamic ${subj_fod} "

        tracking_source=" ${subj_fod} "

        # metrics+=("${subj_vfd_MNI}" "${subj_vdisp_MNI}" "${subj_vpk_MNI}")

        # # add the maps to metric for plotting if Q_flag is set
        # if [[ "${Q_flag}" -eq 1 ]]; then

        # fi

    elif [[ ${algo_f} == "FACT" ]]; then

        if [[ -z ${subj_DT_vecs} ]]; then

            # Not using the actual B0 for anything

            subj_dt="${prep_d}/sub-${subj}_tensor.mif"

            subj_DT_vecs="${prep_d}/sub-${subj}_dwi_dt_vecs_reg2T1w.mif"

            subj_FA="${prep_d}/fa.nii.gz"

            subj_ADC="${prep_d}/sub-${subj}_dwi_dt_vecs_reg2T1w.mif"

            echo " DT vectors file not found, we will make it" | tee -a ${prep_log2}

            task_in="tensor2metric -force -nthreads ${ncpu} -mask ${T1_BM_inFA_minCSF} -vec ${subj_DT_vecs} \
            ${subj_dt}"

            task_exec

        else

            echo " DT vectors file found " | tee -a ${prep_log2}

            subj_FA=($(find ${d_dir} -type f -name "fa_reg2T1w.nii.gz"));

            subj_ADC=($(find ${d_dir} -type f -name "adc_reg2T1w.nii.gz"));

            if [[ -z ${subj_FA} ]]; then

                echo " This data is not preprocessed using KUL_NITs" | tee -a ${prep_log2}

                subj_FA=($(find ${d_dir} -type f -name "*fa*.nii.gz" -o -name "*FA*.nii.gz" -o -name "fa.nii.gz"));

                subj_ADC=($(find ${d_dir} -type f -name "*adc*.nii.gz" -o -name "*ADC*.nii.gz" -o -name "adc.nii.gz"));

            fi

        fi

        tracking_string=" -algorithm ${algo_f} -seed_image ${subj_dwi_bm} "
        tracking_source=" ${subj_DT_vecs} "

    elif [[ ${algo_f} == "Tensor_Det" ]] || [[ ${algo_f} == "Tensor_Prob" ]]; then

        tracking_string=" -algorithm ${algo_f} -seed_image ${subj_dwi_bm} "
        tracking_source=" ${subj_dwi} "

    fi

    # Find out tracking method of choice

    if [[ ${T_app} -eq 2 ]]; then

        echo " You have asked for whole brain tractography followed by segmentation " | tee -a ${prep_log2}

        WB_tck_srch=($(find ${TCKs_outd} -type f -name "sub-${subj}${ses_str}_WB_TCKs.tck"));

        SIFT_srch=($(find ${TCKs_outd} -type f -name "sub-${subj}${ses_str}_sift2_ws.txt"));

        if [[ -z ${WB_tck_srch} ]]; then

            echo " Whole brain tractogram not found, generating " | tee -a ${prep_log2}

            # task_in="tckgen -force -nthreads ${ncpu} ${tracking_string} -mask ${T1_BM_inFA_minCSF} -select 10000000 -angle 45 -maxlength 300 -minlength 20 ${tracking_source} ${WB_tck}"

            # task_exec

            task_in="tckgen -force -nthreads ${ncpu} ${tracking_string} -mask ${T1_BM_inFA_minCSF} -select 10000000 -maxlength 300 -minlength 20 ${tracking_source} ${WB_tck}"

            task_exec

        else

            echo " Whole brain tractogram found, skipping to SIFT weights " | tee -a ${prep_log2}

        fi

        if [[ -z ${SIFT_srch} ]]; then

            if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

                echo " You have selected ${algo_f}, so we perform SIFT2 and use the weights during filtering " | tee -a ${prep_log2}

                task_in="tcksift2 -force -nthreads ${ncpu} ${WB_tck} ${subj_fod} ${TCKs_outd}/sub-${subj}${ses_str}_sift2_ws.txt"

                task_exec

                sift_str=" -tck_weights_in ${TCKs_outd}/sub-${subj}_sift2_ws.txt "

            else

                echo " You have selected ${algo_f}, so we will not use SIFT2 " | tee -a ${prep_log2}

                sift_str=" "

            fi

        else

            echo " SIFT weights found, skipping to segmentation " | tee -a ${prep_log2}

        fi


        # bundle segmentation here
        # need to use functions to keep things clean

        echo " Starting whole brain tractogram segmentation stage  " | tee -a ${prep_log2}

        declare -a dotdones

        declare -a srch_dotdones

        for q in ${!tck_list[@]}; do

            echo $q
            echo ${tck_list[$q]}

            dotdones[$q]="${ROIs_d}/${tck_list[$q]}_VOIs.done"
            srch_dotdones[$q]=$(find ${ROIs_d} -not -path '*/\.*' -type f | grep "${tck_list[$q]}_VOIs.done")

            if [[ ! -z ${srch_dotdones[$q]} ]]; then

                TCK_to_make="${tck_list[$q]}"

                ns="${nosts_list[$q]}"

                make_bundle

                unset TCK_to_make ns

            fi

        done


    elif [[ ${T_app} -eq 1 ]]; then

        echo " You have asked for inidividual bundle tractography  " | tee -a ${prep_log2}

        declare -a dotdones

        declare -a srch_dotdones

        for q in ${!tck_list[@]}; do

            echo $q
            echo ${tck_list[$q]}

            dotdones[$q]="${ROIs_d}/${tck_list[$q]}_VOIs.done"
            srch_dotdones[$q]=$(find ${ROIs_d} -not -path '*/\.*' -type f | grep "${tck_list[$q]}_VOIs.done")

            if [[ ! -z ${srch_dotdones[$q]} ]]; then

                TCK_to_make="${tck_list[$q]}"

                ns="${nosts_list[$q]}"

                make_bundle

                unset TCK_to_make ns

            fi

        done

    fi

fi
