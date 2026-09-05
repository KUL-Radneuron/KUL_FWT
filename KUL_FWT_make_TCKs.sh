#!/bin/bash

# set -x

# This workflow belongs to the manuscript (under review) https://doi.org/10.1101/2021.10.13.464139, please consider citing if you will use it
# KUL_FWT_make_TCKs.sh automatically generates fiber bundles for single subjects

# version = v2.0_01072026

# to do:
# add a fourth filtering method (relying on reconbundle with CSD templates)

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

    `basename $0` -p pat001 -s 01  -F /path_to/FS_dir/aparc+aseg.mgz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output -T 2 -f 2

    Examples:

    `basename $0` -p pat001 -s 01 -F /path_to/FS_dir/aparc+aseg.mgz -d /path_to/dMRI_dir -c /path_to/KUL_FWT_tracks_list.txt -o /fullpath/output -n 6 -T 1 -f 1 -S -Q

    Purpose:

    This workflow creates all bundles specified in the input config file using the inclusion and exclusion VOIs created by KUL_FWT_make_VOIs.sh for single subject data

    Required arguments:

    -p:  BIDS participant name (anonymised name of the subject without the "sub-" prefix)
    -s:  BIDS participant session (session no. without the "ses-" prefix)
    -T:  Tracking and segmentation approach (1 = Bundle-specific tckgen, 2 = Whole brain tckgen & bundle segmentation, 3 = whole brain tckgen with mrtrix3 freesurfer ACT, 4 = Bundle specific seeding from the grey-white matter interface, 5 = Bundle specific: seeds from the subcortical WM one voxel past the grey-white matter interface, includes against a tightened WM-ring+interface+cortex-rim band instead of the raw VOI)
    -F:  Full path and file name of aparc+aseg.mgz from FreeSurfer
    -c:  Path to config file with list of tracks to segment from the whole brain tractogram
    -d:  Path to directory with diffusion data (specific to subject and run)
    -o:  Full path to output dir (if not set reverts to default output ./sub-*_ses-*_KUL_FWT_output)

    Optional arguments:

    -a:  Specify algorithm for tckgen fiber tractography (tckgen -algorithm options are: iFOD2, iFOD1, SD_STREAM, Tensor_Det, Tensor_Prob, FACT, default is iFOD2)
    -f:  Specify filtering approach; sets how hard outlier rejection cuts
         0 = none
         1 = standard (default): score floor 0.40, at most 10% of a bundle dropped
         2 = lenient:            score floor 0.30, at most  5% of a bundle dropped
         3 = legacy strict:      score floor 0.58, no ceiling -- the pre-2026-09
             behaviour, which removed the cortical fan of fanning bundles (UF,
             CCing, ILF, TCing) on some subjects. Kept only to reproduce older runs.
         Every level also enforces a hard floor of 65% retention; if outlier
         rejection would go below it the cut is relaxed and the bundle log says so.
         Levels 1 and 2 were previously labelled "conservative" and "liberal",
         with level 1 in fact being the most aggressive of the three.
    -Q:  If set quantitative and qualitative analyses will be done
    -S:  If set screenshots will taken of each bundle
    -X val: EXPERIMENTAL opt-in: explicit tckgen -cutoff (FOD amplitude at which a
         streamline terminates; an FA threshold for the tensor/FACT algorithms).
         Applies to every tckgen this script runs, bundle-specific and whole-brain
         alike. Unlike the built-in default it is honoured whatever the algorithm --
         you get a warning, not a silent override, if the scale looks wrong for the
         algorithm chosen. Without -X, the script's own default is used.
    -n:  Number of cpu for parallelisation (default is 6)
    -h:  Prints help menu

    dMRI input overrides (for pipelines other than KUL_dwiprep):

    -W:  Full path to WM FOD file; must be in the same space as the FA provided to KUL_FWT_make_VOIs.sh (which determines the output space of all VOIs); overrides auto-discovery from -d dir
    -G:  Full path to FA map co-registered with the FOD (.nii.gz); overrides default \${prep_d}/fa.nii.gz
    -B:  Full path to brain mask co-registered with the FOD (.nii.gz); overrides auto-discovery from -d dir
    -L:  Full path to LoRE-SD ODF file (same space as VOI masks); overrides -W when provided
    -C:  Full path to LoRE-SD contrasts directory; overrides auto-discovery from -d dir
    -U:  EXPERIMENTAL opt-in: if an rfa-modulated lore_sd FOD (rfa_modulated_fod_reg2T1w.mif,
         from KUL_dwiprep.sh) is found, prefer it over the plain lore_sd ODF. Without -U,
         behavior is unchanged (plain lore_sd ODF, if present, is still preferred over CSD).
    -R:  EXPERIMENTAL opt-in: reordered filtering chain. Default order is
         filt1(ROI) -> loop-detect -> outlier-reject -> smooth -> RecoBundles -> fin;
         with -R it becomes filt1(ROI) -> smooth -> RecoBundles -> loop-detect ->
         outlier-reject -> fin. RecoBundles shape-validates against the model right
         after smoothing (models are themselves smoothed, so this keeps the comparison
         smoothed-vs-smoothed) and before the two filters whose thresholds are computed
         relative to the current population's own distribution -- intended for bundles
         where off-target streamlines surviving the ROI filter skew what those filters
         treat as "normal". Without -R, behavior is unchanged.
    -K:  EXPERIMENTAL opt-in: dilate cortical inclusion VOIs (identified via the
         _ctx marker in track_recipes_v2/) inward into WM by one pass before tckgen,
         to tolerate normal T1-to-FA registration imprecision at the GM/CSF boundary
         without jumping across a sulcus into a neighboring gyrus. Independent of -R
         (affects tckgen itself, used by both the default and -R chains). Without -K,
         VOIs are used exactly as make_VOIs.sh built them.
    -O:  EXPERIMENTAL opt-in: use tckgen's -include_ordered instead of -include, i.e.
         a streamline must traverse a bundle's inclusion VOIs in the order its recipe
         lists them, not just touch all of them in any order. Meaningful for a real
         multi-stop chain (e.g. DRT: dentate -> red nucleus -> VL thalamus -> M1);
         for a 2-VOI bundle order is close to meaningless either way. Without -O,
         behavior is unchanged (-include, any order).
    -Z mm: EXPERIMENTAL opt-in: override tckgen's default step size (0.5x voxelsize
         for iFOD2) with an explicit value in mm. Smaller steps bound the streamline's
         curvature per step more tightly, which should help tracing through sharp
         turns (e.g. Meyer's loop's hook, DRT's dentate/red-nucleus segment) at the
         cost of more steps -- and more compute -- per streamline. Without -Z, tckgen's
         own default is used.
    -Y:  EXPERIMENTAL opt-in: use tckgen's -seed_random_per_voxel instead of
         -seed_voxels, with a per-VOI seed count deliberately weighted inversely to
         each VOI's voxel count (targeting ~50000 attempts from every seed VOI a
         bundle has, regardless of size) rather than proportionally to it. Plain
         -seed_voxels pools multiple seed masks and draws roughly proportional to
         voxel count, so a bundle's small/precise VOI (e.g. LGN+pulvinar) gets far
         fewer attempts than its large/loose one (e.g. occipital cortex) purely from
         size -- this tests whether deliberately balancing that helps. Note: unlike
         -seed_voxels with -seeds 0, this has a fixed total seed budget (voxels x n
         per VOI) and will not retry indefinitely to hit -select, so a bundle may come
         back under target even if otherwise trackable. Without -Y, behavior is
         unchanged (-seed_voxels, proportional).
    -M:  EXPERIMENTAL opt-in: exclude the outermost N-voxel rind from tckgen's tracking
         -mask (N = the argument, e.g. -M 1 or -M 2), for -T 1/4/5 only (-T 2/3 track a
         separate whole-brain substrate and are untouched). Built by eroding the whole
         CSF-stripped brain mask by N passes rather than eroding the cortex ribbon
         specifically -- cortex is often only 1-2 voxels thick at this resolution, so
         eroding it directly doesn't shave a surface layer, it eats the whole local
         ribbon in most places. Eroding the whole brain mask only has that failure mode
         at genuinely thin whole-brain structures, so those are added back explicitly
         afterward: corpus callosum, fornix, brainstem, and the periventricular zone
         (ventricles dilated by N passes, matching the erosion depth, into the
         uneroded mask). Without -M, the tracking mask is
         unchanged.

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
c_flag=0
d_flag=0
o_flag=0
a_flag=0
Q_flag=0
S_flag=0
W_flag=0
G_flag=0
B_flag=0
L_flag=0
C_flag=0
R_flag=0
K_flag=0
O_flag=0
Z_flag=0
Y_flag=0
M_flag=0
M_val=""
step_val=""
X_flag=0
cutoff_val=""
use_rfa_mod_fod=0
filt_fl1=0
algo_f="iFOD2"

if [ "$#" -lt 1 ]; then
    Usage >&2
    exit 1

else

    while getopts "p:s:T:F:c:d:o:a:n:f:W:G:B:L:C:hQSURKOZ:YM:X:" OPT; do

        case $OPT in
        p) #participant
            p_flag=1
            subj=$OPTARG
        ;;
        s) #session
            s_flag=1
            ses=$OPTARG
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
        W) # WM FOD file override
            W_flag=1
            subj_fod=$OPTARG
        ;;
        G) # FA map override
            G_flag=1
            subj_FA=$OPTARG
        ;;
        B) # brain mask override
            B_flag=1
            T1_brain_mask_inFA=$OPTARG
        ;;
        L) # LoRE-SD ODF override
            L_flag=1
            subj_lore_fod=$OPTARG
        ;;
        C) # LoRE-SD contrasts dir override
            C_flag=1
            subj_lore_contrasts_dir=$OPTARG
        ;;
        U) # opt-in: prefer the experimental rfa-modulated lore_sd FOD, when found,
           # over the plain lore_sd ODF (see KUL_dwiprep.sh rfa_modulated_fod.mif)
            use_rfa_mod_fod=1
        ;;
        R) # opt-in: reordered filtering chain -- RecoBundles shape-validates against
           # the (also smoothed) model right after ROI filtering + smoothing, before
           # loop-detection/outlier-rejection, instead of after them as in the default
           # chain. Purifies the population before the two filters whose thresholds are
           # computed relative to the current population's own distribution, at the
           # cost of running RecoBundles on a not-yet-loop/outlier-cleaned input.
            R_flag=1
        ;;
        K) # opt-in: dilate cortical inclusion VOIs inward into WM before tckgen sees
           # them. A recipe's cortical inclusion VOI (now identifiable via the _ctx
           # marker track_recipes_v2/ tags on every cortical entry) is an exact-label
           # match with zero tolerance for T1-to-FA registration imprecision at the
           # thin, curved GM/CSF boundary -- a legitimate endpoint one voxel outside
           # the labeled ribbon fails -include/-seed_voxels. Dilating isotropically
           # then keeping only the newly-added voxels that are also WM avoids jumping
           # across a sulcus into an unrelated neighboring gyrus (a sulcus separates
           # two gyri all the way down near the WM, so "toward WM" from one gyrus's
           # cortex can't reach the other side). Independent of -R: TCK_I_b feeds both
           # the default and -R chains identically (tckgen itself, before any of
           # -R's post-hoc filtering), so this can't be scoped inside -R without
           # duplicating the tracking step. Affects inclusions only, never excludes --
           # dilating an exclude would make it more aggressive, the opposite of the
           # tolerance this is meant to buy. Without -K, VOIs are used exactly as
           # make_VOIs.sh built them.
            K_flag=1
        ;;
        O) # opt-in: tckgen -include_ordered instead of -include -- a streamline must
           # traverse a bundle's inclusion VOIs in recipe order, not just touch all of
           # them in any order. Only meaningful for a genuine multi-stop chain (DRT);
           # harmless but pointless for a 2-VOI bundle. Without -O, -include (any order).
            O_flag=1
        ;;
        Z) # opt-in: explicit tckgen -step override (mm), replacing its own default
           # (0.5x voxelsize for iFOD2). Smaller steps bound per-step curvature more
           # tightly, at the cost of more steps per streamline. Without -Z, tckgen's
           # own default.
            Z_flag=1
            step_val="$OPTARG"
        ;;
        Y) # opt-in: tckgen -seed_random_per_voxel instead of -seed_voxels, per-VOI n
           # deliberately weighted inversely to voxel count (~50000 attempts per seed
           # VOI regardless of size) rather than proportionally to it -- tests whether
           # a bundle's small/precise VOI being size-starved of seed attempts under
           # plain -seed_voxels actually matters. Fixed total budget (voxels x n), not
           # open-ended like -seed_voxels + -seeds 0. Without -Y, -seed_voxels (proportional).
            Y_flag=1
        ;;
        M) # opt-in: exclude the outermost N-voxel rind (N = OPTARG) from the tckgen
           # tracking mask, for -T 1/4/5 only. Erodes the whole CSF-stripped brain mask
           # by N passes rather than the cortex ribbon specifically -- cortex is often
           # only 1-2 voxels thick at this resolution, so eroding it directly eats the
           # whole local ribbon in most places rather than shaving a surface layer.
           # Corpus callosum, fornix, brainstem, and periventricular WM are added back
           # explicitly afterward, since a whole-brain erosion would otherwise also eat
           # into those wherever they happen to sit close to the brain's exterior.
           # Without -M, the tracking mask is unchanged (CSF-stripped, cortex included).
            M_flag=1
            M_val="$OPTARG"
        ;;
        X) # explicit tckgen -cutoff override (FOD amplitude, or FA for the tensor/FACT
           # algorithms). Applies to every FOD tckgen this script runs -- bundle-specific
           # and whole-brain alike -- and, unlike the built-in default, is honoured
           # whatever the algorithm, on the assumption that someone passing it explicitly
           # knows which scale their chosen algorithm puts it on.
            X_flag=1
            cutoff_val="$OPTARG"
            if [[ ! ${cutoff_val} =~ ^[0-9]*\.?[0-9]+$ ]]; then
                echo "incorrect input to -X flag (tckgen cutoff): '${cutoff_val}' is not a number, exiting "
                exit 2
            fi
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

if [[ ${p_flag} -eq 0 ]] || [[ ${F_flag} -eq 0 ]] || [[ ${T_flag} -eq 0 ]] || [[ ${c_flag} -eq 0 ]] || [[ ${d_flag} -eq 0 ]]; then

    echo
    echo "Inputs to -p -F -d and -c must be set." >&2
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

    echo "Inputs are -p  ${subj} -s ${ses} -c  ${conf_f} -d ${d_dir} -F ${FS_dir} -T ${T_app}"

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

    elif [[ "$T_app" -eq 3 ]]; then

        Tracto=3
    
    elif [[ "$T_app" -eq 4 ]]; then

        Tracto=4

    elif [[ "$T_app" -eq 5 ]]; then

        Tracto=5

    else

        echo " Incorrect choice of fiber tracking approach, please select 1, 2, 3, 4 or 5"
        exit 2

    fi

fi

# # filtering scheme selection
#
# These levels set how hard the outlier-rejection step (filt3, and the -R
# chain's rord_outlier) cuts. Two knobs, both passed to
# KUL_FWT_reject_outliers.py, which needs both to be safe across bundle shapes:
#
#   Alfa      absolute score floor -- nothing scoring above it is ever dropped,
#             so a clean bundle pays no fixed tithe
#   Drop_pct  ceiling on the share of the bundle dropped, whatever the scores
#             look like -- this is what keeps a fanning bundle (UF, CCing, ILF,
#             TCing) from losing its cortical fan when the score distribution
#             shifts down relative to a fixed floor
#
# Level 1 used to mean Alfa=0.58 with no ceiling, and that is what deleted the
# UF's frontal limb on a subset of subjects: across one cohort's uncinate
# bundles the median score ran 0.55-0.78, so a 0.58 cut swung retention between
# 40% and 92% on anatomically comparable bundles, and on the worst of them it
# discarded half of the streamlines that connected both of the recipe's
# terminal VOIs. That exact behaviour is still reachable as level 3, for
# reproducing runs made before this change; it is no longer any run's default.
if [[ ${filt_fl1} -eq 0 ]]; then

    filt_fl2=1
    echo " No filtering scheme selected, defaulting to standard filtering (-f 1) " | tee -a ${prep_log2}

fi

if [[ ! ${filt_fl2} =~ ^[+-]?[0-9]+$ ]]; then

    echo "incorrect input to -f flag (filtering option selection), exiting "
    exit 2

fi

# Normalise before matching: the old chain compared with -eq (arithmetic), so
# "-f 01" and "-f +1" were accepted and meant 1. case matches strings, which
# would silently turn those into "incorrect input". $(( )) restores the old
# tolerance and canonicalises the value for the ${filt_fl2} == 0 string tests
# further down this script.
filt_fl2=$((filt_fl2))

# Hard floor on what outlier rejection may leave behind, at every level. Inert
# whenever Drop_pct already bounds the damage above it -- it is the backstop for
# level 3's bare Alfa, and a warning channel: when it fires, the helper says so
# loudly in the bundle log and the bundle is worth a look.
Min_retention=0.65

case ${filt_fl2} in

    0)
        echo " No filtering selected " | tee -a ${prep_log2}
    ;;

    1)
        echo " Standard filtering selected (outlier rejection: score floor 0.40, at most 10% of a bundle dropped) " | tee -a ${prep_log2}
        Alfa=0.40
        Drop_pct=10
    ;;

    2)
        echo " Lenient filtering selected (outlier rejection: score floor 0.30, at most 5% of a bundle dropped) " | tee -a ${prep_log2}
        Alfa=0.30
        Drop_pct=5
    ;;

    3)
        echo " Legacy strict filtering selected (outlier rejection: score floor 0.58, no ceiling on what is dropped -- pre-2026-09 behaviour, kept for reproducibility) " | tee -a ${prep_log2}
        Alfa=0.58
        Drop_pct=""
    ;;

    *)
        echo "incorrect input to -f flag (filtering option selection), exiting "
        exit 2
    ;;

esac

# Assembled once here rather than at each of the two call sites below (default
# chain and -R chain), so the two can never drift apart. Left empty at level 0,
# where no filtering runs at all and Alfa is deliberately never set.
if [[ -n "${Alfa}" ]]; then

    Outlier_opts="--alpha ${Alfa} --min_retention ${Min_retention}"

    if [[ -n "${Drop_pct}" ]]; then

        Outlier_opts+=" --drop_percentile ${Drop_pct}"

    fi

fi

# Report on quanti, quali and screenshot workflows
# (conditions were inverted -- printed "switched on" when the flag was actually 0/off)

if [[ "${Q_flag}" -eq 1 ]]; then

    echo "Quantitative and qualitative analysis switched on" | tee -a ${prep_log2}

fi

if [[ "${S_flag}" -eq 1 ]]; then

    echo "Screenshots switched on" | tee -a ${prep_log2}

fi

# set mrtrix tmp dir to prep_d

rm -rf ${TCKs_prepd}/tmp_dir*

tmpo_d="${TCKs_prepd}/tmp_dir"

mkdir -p "${tmpo_d}" >/dev/null 2>&1

export MRTRIX_TMPFILE_DIR="${tmpo_d}"

# report pid

processId=$(ps -ef | grep 'ABCD' | grep -v 'grep' | awk '{ printf $2 }')
echo $processId

echo "KUL_FWT_make_TCKs.sh @ ${d} with parent pid $$ and process pid $BASHPID " | tee -a ${prep_log2}
echo "Inputs are -p  sub-${subj} -s ses-${ses} -c  ${conf_f} -d ${d_dir}  -F ${FS_dir} " | tee -a ${prep_log2}
echo "Tool versions: $(mrconvert --version 2>&1 | head -1) | scilpy $(python -c 'import scilpy; print(scilpy.__version__)' 2>/dev/null || echo 'not found')" | tee -a ${prep_log2}

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

# tckgen renamed -seed_image to -seed_voxels (mrtrix3 dev commit ca77f843d, Oct 2025).
# The dev branch's git-describe numbering isn't stable/comparable across installs
# (different clones report against different reachable tags, e.g. "3.0.8-2097-g..."
# vs "nightly-dev-365-g..." for the same commit), so a version-number threshold isn't
# reliable here -- probe the actual installed binary's supported option instead.
# -help renders option names bold via backspace-overstrike (each char as X<BS>X), which
# breaks a plain substring grep -- col -b strips that before matching.
if tckgen -help 2>&1 | col -b | grep -q -- '-seed_voxels'; then
    tckgen_seed_opt="-seed_voxels"
else
    tckgen_seed_opt="-seed_image"
fi

# --- auto-scheduling: hold at most $max_parallel_bundles bundles in flight,
# split $ncpu evenly between them as a per-bundle floor, then dynamically
# re-derive the actual per-bundle thread count at EVERY dispatch as jobs finish (see
# KUL_dispatch_bundles / running_threads ledger below). Replaces the old
# static once-computed split, which pinned every bundle (incl. the last few
# large/slow ones) to whatever thread count it started with, leaving cores
# idle near the end of the run.
#
# oversubscribe_pct deliberately lets the SUM of live -nthreads across
# concurrent bundles exceed physical ncpu, applied only to the per-dispatch
# thread math (free_threads below) -- NOT to bundles_simultaneous, which is a
# hard cap, and NOT to any single bundle, which is clamped to ncpu at dispatch;
# only the aggregate is inflated. tckgen threads aren't 100% CPU-bound
# (mutex contention on the shared streamline-output queue, periodic waits),
# so a modest oversubscription tends to fill those gaps rather than genuinely
# demand more cores than exist; too high a value risks cache thrashing.
n_bundles_total=${#tck_list[@]}
# Concurrency is capped FIRST and the thread split derived from it, not the
# other way round. The old order (8-thread floor -> ncpu/8 concurrent bundles)
# meant a heavy bundle -- e.g. one asking for 10k streamlines -- could sit on
# just 8 threads while the rest of the machine churned through trivial ones,
# and it dominated total wall-clock because tckgen's tail is set by the single
# slowest bundle, not by aggregate throughput. Two fat jobs beat N thin ones.
max_parallel_bundles=2
bundles_simultaneous=$max_parallel_bundles
[ "$bundles_simultaneous" -gt "$ncpu" ] && bundles_simultaneous=$ncpu
[ "$bundles_simultaneous" -lt 1 ] && bundles_simultaneous=1
# Even split of $ncpu across the cap, and simultaneously the per-bundle floor:
# no bundle ever launches thinner than its fair share of the machine.
min_threads_per_bundle=$(( ncpu / bundles_simultaneous ))
[ "$min_threads_per_bundle" -lt 1 ] && min_threads_per_bundle=1
ncpu_per_bundle=$min_threads_per_bundle
oversubscribe_pct=25
echo "[auto] cores=$ncpu bundles=$n_bundles_total -> at most $bundles_simultaneous concurrent, $min_threads_per_bundle threads/bundle even split (floor), capped at $ncpu, ${oversubscribe_pct}% thread oversubscription (recomputed dynamically per dispatch)" | tee -a ${prep_log2}

function KUL_throttle {
    # Block until fewer than $1 background jobs are running.
    # Portable: uses `wait -n` when available (bash>=4.3), else polls.
    local max="$1"
    [ "$max" -lt 1 ] && max=1
    while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$max" ]; do
        wait -n 2>/dev/null || sleep 0.5
    done
}

# Builds the runnable-bundle set, dispatches smallest-workload-first, and
# dynamically re-splits $ncpu across whatever bundles are actually still
# running at each dispatch point (not a static one-time split). Called once
# from each of the two mutually-exclusive T_app branches below; encapsulates
# the entire loop body so each call site is a single line.
function KUL_dispatch_bundles {

    # pass 1: which indices are runnable (VOIs .done marker present)? Same
    # check as before, just split out of the dispatch step so we can sort
    # before dispatching.
    declare -a dotdones
    declare -a srch_dotdones
    declare -a runnable_idx=()

    for q in ${!tck_list[@]}; do
        dotdones[$q]="${ROIs_d}/${tck_list[$q]}_VOIs.done"
        srch_dotdones[$q]=$(find ${ROIs_d} -not -path '*/\.*' -type f | grep "${tck_list[$q]}_VOIs.done")
        if [[ ! -z ${srch_dotdones[$q]} ]]; then
            runnable_idx+=("$q")
        fi
    done

    # pass 2: sort runnable indices ascending by seed count (nosts_list) --
    # small/fast bundles dispatch first, large/slow ones last, so
    # concurrency has already thinned out (more free cores) by the time the
    # big ones launch. "none"/commented config rows never produce a
    # matching .done file, so they're already excluded from runnable_idx
    # before this sort runs.
    declare -a sorted_idx=()
    if [ "${#runnable_idx[@]}" -gt 0 ]; then
        while IFS=' ' read -r _ idx; do
            sorted_idx+=("$idx")
        done < <(
            for q in "${runnable_idx[@]}"; do
                printf '%s %s\n' "${nosts_list[$q]}" "$q"
            done | sort -n -k1,1
        )
    fi

    # pass 3: dispatch in sorted order, recomputing the thread split live at
    # each dispatch from a ledger of currently-running bundles. This never
    # touches an already-launched tckgen/tckedit process's thread count --
    # that's fixed for its whole lifetime once started. It only decides the
    # -nthreads value baked into the NEXT bundle about to be launched.
    local -A running_threads=()
    local n_remaining="${#sorted_idx[@]}"
    local pos=0

    for q in "${sorted_idx[@]}"; do

        pos=$((pos+1))
        TCK_to_make="${tck_list[$q]}"
        ns="${nosts_list[$q]}"

        echo "Bundle ${TCK_to_make}: see ${output_d}/KUL_FWT_TCKs_log_${subj}_${TCK_to_make}_${d}.txt" | tee -a ${prep_log2}
        prep_log2="${output_d}/KUL_FWT_TCKs_log_${subj}_${TCK_to_make}_${d}.txt"

        KUL_throttle "$bundles_simultaneous"

        # reap PIDs of bundles that finished while we were waiting
        for pid in "${!running_threads[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                unset "running_threads[$pid]"
            fi
        done

        local used_threads=0
        for pid in "${!running_threads[@]}"; do
            used_threads=$(( used_threads + running_threads[$pid] ))
        done
        local ncpu_budget=$(( ncpu * (100 + oversubscribe_pct) / 100 ))
        local free_threads=$(( ncpu_budget - used_threads ))

        local remaining_to_dispatch=$(( n_remaining - pos + 1 ))
        local concurrency_cap_remaining=$remaining_to_dispatch
        [ "$concurrency_cap_remaining" -gt "$bundles_simultaneous" ] && concurrency_cap_remaining=$bundles_simultaneous
        [ "$concurrency_cap_remaining" -lt 1 ] && concurrency_cap_remaining=1

        ncpu_per_bundle=$(( free_threads / concurrency_cap_remaining ))
        [ "$ncpu_per_bundle" -lt "$min_threads_per_bundle" ] && ncpu_per_bundle=$min_threads_per_bundle
        # Ceiling: a lone bundle may grow past the even split as its partner
        # finishes, but never past the physical core count -- the thread budget
        # exists to fill gaps ACROSS concurrent bundles, not to inflate one
        # process beyond the hardware.
        [ "$ncpu_per_bundle" -gt "$ncpu" ] && ncpu_per_bundle=$ncpu

        echo "[auto] dispatch ${TCK_to_make}: used=${used_threads} free=${free_threads} cap=${concurrency_cap_remaining} -> ${ncpu_per_bundle} threads" | tee -a ${prep_log2}

        make_bundle &
        running_threads[$!]=$ncpu_per_bundle

    done

    wait   # barrier: all backgrounded bundles from this call finish before continuing

}

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

    # -K: dilate cortical inclusion VOIs inward into WM by one pass, before tckgen sees
    # them (this feeds -include/-seed_voxels AND scilpy's --drawn_roi filt1 step
    # downstream, both of which read TCK_I_b -- reassigning it here keeps generation
    # and post-hoc filtering criteria consistent instead of diverging). Detected
    # per-VOI by ribbon-style overlap against ctx_mask_inFA rather than by name, since
    # a single incsN slot can merge multiple recipe entries (some cortical, some not)
    # into one compiled mask -- overlap fraction handles that gracefully where a
    # filename check couldn't. Excludes are untouched: dilating an exclude would make
    # it more aggressive, the opposite of the tolerance this is meant to buy.
    if [[ "${K_flag}" -eq 1 ]] && [[ -f ${ctx_mask_inFA} ]] && [[ -f ${WM_mask_inFA} ]]; then

        for _ki in ${!TCK_I_b[@]}; do

            _ki_voi="${TCK_I_b[$_ki]}"
            _ki_dilated="$(dirname ${_ki_voi})/$(basename ${_ki_voi} .nii.gz)_ctxdil.nii.gz"
            _ki_overlap_tmp="${TCK_out}/${TCK_2_make}_incs$((_ki+1))_ctxoverlap_tmp.nii.gz"

            if [[ ! -f ${_ki_dilated} ]]; then

                _ki_total=$(mrstats -force -output count -mask ${_ki_voi} ${_ki_voi} -quiet)

                if [[ ${_ki_total} -gt 0 ]]; then

                    task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu_per_bundle} -quiet ${_ki_voi} 0 -gt ${ctx_mask_inFA} 0 -gt -mult ${_ki_overlap_tmp}"

                    task_exec

                    _ki_overlap=$(mrstats -force -output count -mask ${_ki_overlap_tmp} ${_ki_overlap_tmp} -quiet)

                    if [[ $(( _ki_overlap * 100 / _ki_total )) -ge 50 ]]; then

                        echo " ${TCK_2_make} incs$((_ki+1)): ${_ki_overlap}/${_ki_total} voxels overlap cortex -- dilating inward into WM (-K)" | tee -a ${prep_log2}

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 1 ${_ki_voi} dilate - | mrcalc - ${WM_mask_inFA} -mult ${_ki_voi} -add 0 -gt ${_ki_dilated} -datatype uint16 -force"

                        task_exec

                    else

                        task_in="cp ${_ki_voi} ${_ki_dilated}"

                        task_exec

                    fi

                else

                    task_in="cp ${_ki_voi} ${_ki_dilated}"

                    task_exec

                fi

            fi

            TCK_I_b[$_ki]="${_ki_dilated}"

        done

    fi

    # if we're using a DTI based method

    if [[ ${algo_f} == "FACT" ]] || [[ ${algo_f} == "Tensor_Det" ]] || [[ ${algo_f} == "Tensor_Prob" ]]; then

        if [[ ${T_app} -eq 4 ]]; then

            for aw in ${!TCK_I_b[@]}; do

                _t4_gwi="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_gwi_4DTI.nii.gz"

                if [[ ! -f ${_t4_gwi} ]]; then

                    # Cortical-overlap gate, same check -K already uses (ctx_mask_inFA,
                    # >=50%) -- see the non-DTI branch's comment below for why the old
                    # <250-voxel floor alone wasn't enough (verified on DRT's
                    # VL-thalamus incs3 surviving it despite not being cortex).
                    _t4_total=$(mrstats -force -ignorezero -output count ${TCK_I_b[$aw]} -quiet)
                    _t4_is_ctx=0

                    if [[ ${_t4_total} -gt 0 ]] && [[ -f ${ctx_mask_inFA} ]]; then

                        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu_per_bundle} -quiet ${TCK_I_b[$aw]} 0 -gt ${ctx_mask_inFA} 0 -gt -mult ${_t4_gwi}.ctxoverlap_tmp.nii.gz"

                        task_exec

                        _t4_overlap=$(mrstats -force -ignorezero -output count ${_t4_gwi}.ctxoverlap_tmp.nii.gz -quiet)

                        rm -f "${_t4_gwi}.ctxoverlap_tmp.nii.gz"

                        [[ $(( _t4_overlap * 100 / _t4_total )) -ge 50 ]] && _t4_is_ctx=1

                    fi

                    if [[ ${_t4_is_ctx} -eq 0 ]]; then

                        # Non-cortical: GMWMI/subcortical-WM narrowing is only meaningful
                        # for cortical VOIs. Leave this VOI unchanged -- do NOT fall back
                        # to a WM outline for subcortical VOIs.
                        echo "This VOI ${TCK_I_b[$aw]} is not cortical (< 50% overlap with ctx_mask_inFA), so -T 4 uses the original VOI without GMWMI-narrowing it" | tee -a ${prep_log2}

                        task_in="cp ${TCK_I_b[$aw]} ${_t4_gwi}"

                        task_exec

                    else

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 2 ${TCK_I_b[$aw]} dilate - | mrcalc - ${subj_gmwmi_inFA} -mult 0 -gt \
                        ${_t4_gwi} -datatype uint16 -force"

                        task_exec

                        vol_i_test=$(mrstats -force -ignorezero -output count ${_t4_gwi})

                        # if the resulting VOI has less than 250 voxels we use the original one
                        if [[ ${vol_i_test} -lt 250 ]]; then

                            echo "This VOI ${TCK_I_b[$aw]} has ${vol_i_test} nonzero voxels less than the permitted min of 250 voxels for GMWMI seeding so we use the original VOI" | tee -a ${prep_log2}

                            task_in="cp ${TCK_I_b[$aw]} ${_t4_gwi}"

                            task_exec

                        fi

                    fi

                fi

            done

            TCK_I_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_gwi_4DTI.nii.gz));

        # -T 5, DTI-family algorithms: same two-mask idea as the iFOD/SD_Stream branch
        # below (see its comment for the full rationale) -- both TCK_I_seed_b (seeding,
        # pure WM one voxel past the interface) and TCK_I_b (including, reassigned to
        # WM ring + interface + a thin cortical rim, not the raw wide VOI) get built.
        elif [[ ${T_app} -eq 5 ]]; then

            for aw in ${!TCK_I_b[@]}; do

                _voi_orig="${TCK_I_b[$aw]}"
                _voi_gwi="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_gwi_4DTI.nii.gz"
                _voi_shell="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_shell_4DTI.nii.gz"
                _voi_wmr="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_wmr_4DTI.nii.gz"
                _voi_incl="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_incl5_4DTI.nii.gz"

                if [[ ! -f ${_voi_wmr} ]] || [[ ! -f ${_voi_incl} ]]; then

                    # Cortical-overlap gate, same check -K/-T 4 use (ctx_mask_inFA,
                    # >=50%) -- see the iFOD/SD_Stream branch's comment for why.
                    _t5_total=$(mrstats -force -ignorezero -output count ${_voi_orig} -quiet)
                    _t5_is_ctx=0

                    if [[ ${_t5_total} -gt 0 ]] && [[ -f ${ctx_mask_inFA} ]]; then

                        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu_per_bundle} -quiet ${_voi_orig} 0 -gt ${ctx_mask_inFA} 0 -gt -mult ${_voi_gwi}.ctxoverlap_tmp.nii.gz"

                        task_exec

                        _t5_overlap=$(mrstats -force -ignorezero -output count ${_voi_gwi}.ctxoverlap_tmp.nii.gz -quiet)

                        rm -f "${_voi_gwi}.ctxoverlap_tmp.nii.gz"

                        [[ $(( _t5_overlap * 100 / _t5_total )) -ge 50 ]] && _t5_is_ctx=1

                    fi

                    if [[ ${_t5_is_ctx} -eq 0 ]]; then

                        # Non-cortical: GMWMI/subcortical-WM narrowing is only meaningful
                        # for cortical VOIs. Leave both seed and include as the raw VOI --
                        # do NOT fall back to a WM outline for subcortical VOIs.
                        echo "This VOI ${_voi_orig} is not cortical (< 50% overlap with ctx_mask_inFA), so -T 5 seeds and includes against the original VOI without GMWMI-narrowing it" | tee -a ${prep_log2}

                        task_in="cp ${_voi_orig} ${_voi_wmr} && cp ${_voi_orig} ${_voi_incl}"

                        task_exec

                    else

                    if [[ ! -f ${_voi_gwi} ]]; then

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 2 ${_voi_orig} dilate - | mrcalc - ${subj_gmwmi_inFA} -mult 0 -gt \
                        ${_voi_gwi} -datatype uint16 -force"

                        task_exec

                        vol_i_test=$(mrstats -force -ignorezero -output count ${_voi_gwi})

                        if [[ ${vol_i_test} -lt 250 ]]; then

                            echo "This VOI ${_voi_orig} has ${vol_i_test} nonzero voxels less than the permitted min of 250 voxels at the GMWMI interface, so -T 5's interface patch falls back to the raw VOI" | tee -a ${prep_log2}

                            task_in="cp ${_voi_orig} ${_voi_gwi}"

                            task_exec

                        fi

                    fi

                    if [[ ! -f ${_voi_shell} ]]; then

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 1 ${_voi_gwi} dilate ${_voi_shell}"

                        task_exec

                    fi

                    task_in="mrcalc -force -datatype uint16 ${_voi_shell} ${WM_mask_inFA} -mult ${_voi_gwi} -sub 0 -gt ${_voi_wmr}"

                    task_exec

                    vol_wmr_test=$(mrstats -force -ignorezero -output count ${_voi_wmr})

                    if [[ ${vol_wmr_test} -lt 250 ]]; then

                        echo "This VOI ${_voi_orig} has ${vol_wmr_test} nonzero voxels one voxel past the GMWMI interface, less than the permitted min of 250, so -T 5 seeds from the interface patch instead" | tee -a ${prep_log2}

                        task_in="cp ${_voi_gwi} ${_voi_wmr}"

                        task_exec

                    fi

                    task_in="mrcalc -force -datatype uint16 ${WM_mask_inFA} ${_voi_orig} -add 0 -gt ${_voi_shell} -mult ${_voi_gwi} -add 0 -gt ${_voi_incl}"

                    task_exec

                    vol_incl_test=$(mrstats -force -ignorezero -output count ${_voi_incl})

                    if [[ ${vol_incl_test} -lt 250 ]]; then

                        echo "This VOI ${_voi_orig} has ${vol_incl_test} nonzero voxels in -T 5's WM-ring+interface+cortex-rim band, less than the permitted min of 250, so -T 5 includes against the raw VOI instead" | tee -a ${prep_log2}

                        task_in="cp ${_voi_orig} ${_voi_incl}"

                        task_exec

                    fi

                    fi

                fi

            done

            TCK_I_seed_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_bin_wmr_4DTI.nii.gz));

            TCK_I_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_bin_incl5_4DTI.nii.gz));

        else

            for zw in ${!TCK_I_b[@]}; do

                if [[ ! -f "${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((zw+1))/${TCK_2_make}_incs$((zw+1))_bin_DTI.nii.gz" ]]; then

                    task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 2 ${TCK_I_b[$zw]} dilate - | mrcalc - ${T1_BM_inFA_minCSF} \
                    -mult 0 -gt ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((zw+1))/${TCK_2_make}_incs$((zw+1))_bin_4DTI.nii.gz -datatype uint16 -force"

                    task_exec

                fi

            done

            # for ew in ${!TCK_X_b[@]}; do

            task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 1 ${TCK_X_b} erode - | mrcalc - ${T1_BM_inFA_minCSF} \
            -mult 0 -gt ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_excs/${TCK_2_make}_excs_bin_4DTI.nii.gz -datatype uint16 -force"

            task_exec

            # done

            TCK_I_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_bin_4DTI.nii.gz));

            TCK_X_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_excs/${TCK_2_make}_excs_bin_4DTI.nii.gz));

        fi

    else

        # dilate along the gmwmi
        if [[ ${T_app} -eq 4 ]]; then

            for aw in ${!TCK_I_b[@]}; do

                _t4_gwi="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_gwi.nii.gz"

                if [[ ! -f ${_t4_gwi} ]]; then

                    # Cortical-overlap gate, same check -K already uses (ctx_mask_inFA,
                    # >=50%): the 5ttgen/5tt2gmwmi interface is not exclusively the
                    # cortical ribbon in practice, and the old <250-voxel floor alone let
                    # non-cortical VOIs (verified on DRT's VL-thalamus incs3) survive the
                    # GMWMI dilate+intersect anyway, narrowing a deep GM relay nucleus as
                    # if it were cortex -- anatomically wrong, not what -T 4 was for.
                    _t4_total=$(mrstats -force -ignorezero -output count ${TCK_I_b[$aw]} -quiet)
                    _t4_is_ctx=0

                    if [[ ${_t4_total} -gt 0 ]] && [[ -f ${ctx_mask_inFA} ]]; then

                        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu_per_bundle} -quiet ${TCK_I_b[$aw]} 0 -gt ${ctx_mask_inFA} 0 -gt -mult ${_t4_gwi}.ctxoverlap_tmp.nii.gz"

                        task_exec

                        _t4_overlap=$(mrstats -force -ignorezero -output count ${_t4_gwi}.ctxoverlap_tmp.nii.gz -quiet)

                        rm -f "${_t4_gwi}.ctxoverlap_tmp.nii.gz"

                        [[ $(( _t4_overlap * 100 / _t4_total )) -ge 50 ]] && _t4_is_ctx=1

                    fi

                    if [[ ${_t4_is_ctx} -eq 0 ]]; then

                        # Non-cortical: GMWMI/subcortical-WM narrowing is only meaningful
                        # for cortical VOIs. Leave this VOI unchanged -- do NOT fall back
                        # to a WM outline for subcortical VOIs.
                        echo "This VOI ${TCK_I_b[$aw]} is not cortical (< 50% overlap with ctx_mask_inFA), so -T 4 uses the original VOI without GMWMI-narrowing it" | tee -a ${prep_log2}

                        task_in="cp ${TCK_I_b[$aw]} ${_t4_gwi}"

                        task_exec

                    else

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 2 ${TCK_I_b[$aw]} dilate - | mrcalc - ${subj_gmwmi_inFA} \
                        -mult 0.05 -gt ${_t4_gwi} -datatype uint16 -force"

                        task_exec

                        vol_i_test=$(mrstats -force -ignorezero -output count ${_t4_gwi})

                        # if the resulting VOI has less than 250 voxels we use the original one
                        if [[ ${vol_i_test} -lt 250 ]]; then

                            echo "This VOI ${TCK_I_b[$aw]} has ${vol_i_test} nonzero voxels less than the permitted min of 250 voxels for GMWMI seeding so we use the original VOI" | tee -a ${prep_log2}

                            task_in="cp ${TCK_I_b[$aw]} ${_t4_gwi}"

                            task_exec

                        fi

                    fi

                fi

            done

            TCK_I_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_gwi.nii.gz));

        # -T 5: WM-rind seeding AND a tightened -include band. -T 4's own reassignment
        # of TCK_I_b (used for both roles) is right for THAT mode, but wrong to copy
        # here verbatim in one direction: seeding from the raw VOI still puts seeds in
        # GM, while -include staying on the raw VOI leaves it as wide as ever, so -stop
        # (see cmd_str) wouldn't fire until a streamline has already wandered deep into
        # a gyrus -- doing nothing for the tunneling problem, only for seeding. Both
        # roles get their own tight mask instead, sharing one interface patch
        # (_voi_gwi, same construction as -T 4: dilate 2 passes, keep overlap with the
        # tissue-probability interface) and one 1-pass shell around it:
        #   TCK_I_seed_b (seeding): shell AND unambiguous WM, minus the interface patch
        #     itself -- pure WM, one voxel past the ribbon, no GM.
        #   TCK_I_b (including, reassigned): interface patch UNION (shell AND (WM OR the
        #     original VOI)) -- the WM ring, the interface, and a thin ~1-voxel rim of
        #     the true cortical VOI, so it still genuinely touches GM (this was the
        #     concern with a WM-only include) without being the whole wide parcel that
        #     let -stop fire only after deep gyral penetration.
        # Both fall back to the interface patch (which itself falls back to the raw VOI)
        # under the same 250-voxel floor -T 4 uses, so VOIs with little/no cortical
        # overlap -- deep GM nuclei -- degrade gracefully to ordinary raw-VOI behavior
        # for both seeding and including.
        elif [[ ${T_app} -eq 5 ]]; then

            for aw in ${!TCK_I_b[@]}; do

                _voi_orig="${TCK_I_b[$aw]}"
                _voi_gwi="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_gwi.nii.gz"
                _voi_shell="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_shell.nii.gz"
                _voi_wmr="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_wmr.nii.gz"
                _voi_incl="${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs$((aw+1))/${TCK_2_make}_incs$((aw+1))_bin_incl5.nii.gz"

                if [[ ! -f ${_voi_wmr} ]] || [[ ! -f ${_voi_incl} ]]; then

                    # Cortical-overlap gate, same check -K/-T 4 use (ctx_mask_inFA,
                    # >=50%): without it, a non-cortical VOI (e.g. DRT's VL-thalamus)
                    # can still have enough raw overlap with the 5ttgen GMWMI interface
                    # to survive the 250-voxel floor below, getting narrowed toward a
                    # "ribbon" that doesn't anatomically exist for a deep GM nucleus.
                    # Skips the whole gwi/shell/wmr/incl construction for those VOIs --
                    # both seeding and including just use the raw VOI, same as -T 1.
                    _t5_total=$(mrstats -force -ignorezero -output count ${_voi_orig} -quiet)
                    _t5_is_ctx=0

                    if [[ ${_t5_total} -gt 0 ]] && [[ -f ${ctx_mask_inFA} ]]; then

                        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu_per_bundle} -quiet ${_voi_orig} 0 -gt ${ctx_mask_inFA} 0 -gt -mult ${_voi_gwi}.ctxoverlap_tmp.nii.gz"

                        task_exec

                        _t5_overlap=$(mrstats -force -ignorezero -output count ${_voi_gwi}.ctxoverlap_tmp.nii.gz -quiet)

                        rm -f "${_voi_gwi}.ctxoverlap_tmp.nii.gz"

                        [[ $(( _t5_overlap * 100 / _t5_total )) -ge 50 ]] && _t5_is_ctx=1

                    fi

                    if [[ ${_t5_is_ctx} -eq 0 ]]; then

                        # Non-cortical: GMWMI/subcortical-WM narrowing is only meaningful
                        # for cortical VOIs. Leave both seed and include as the raw VOI --
                        # do NOT fall back to a WM outline for subcortical VOIs.
                        echo "This VOI ${_voi_orig} is not cortical (< 50% overlap with ctx_mask_inFA), so -T 5 seeds and includes against the original VOI without GMWMI-narrowing it" | tee -a ${prep_log2}

                        task_in="cp ${_voi_orig} ${_voi_wmr} && cp ${_voi_orig} ${_voi_incl}"

                        task_exec

                    else

                    if [[ ! -f ${_voi_gwi} ]]; then

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 2 ${_voi_orig} dilate - | mrcalc - ${subj_gmwmi_inFA} \
                        -mult 0.05 -gt ${_voi_gwi} -datatype uint16 -force"

                        task_exec

                        vol_i_test=$(mrstats -force -ignorezero -output count ${_voi_gwi})

                        if [[ ${vol_i_test} -lt 250 ]]; then

                            echo "This VOI ${_voi_orig} has ${vol_i_test} nonzero voxels less than the permitted min of 250 voxels at the GMWMI interface, so -T 5's interface patch falls back to the raw VOI" | tee -a ${prep_log2}

                            task_in="cp ${_voi_orig} ${_voi_gwi}"

                            task_exec

                        fi

                    fi

                    if [[ ! -f ${_voi_shell} ]]; then

                        task_in="maskfilter -force -nthreads ${ncpu_per_bundle} -npass 1 ${_voi_gwi} dilate ${_voi_shell}"

                        task_exec

                    fi

                    task_in="mrcalc -force -datatype uint16 ${_voi_shell} ${WM_mask_inFA} -mult ${_voi_gwi} -sub 0 -gt ${_voi_wmr}"

                    task_exec

                    vol_wmr_test=$(mrstats -force -ignorezero -output count ${_voi_wmr})

                    if [[ ${vol_wmr_test} -lt 250 ]]; then

                        echo "This VOI ${_voi_orig} has ${vol_wmr_test} nonzero voxels one voxel past the GMWMI interface, less than the permitted min of 250, so -T 5 seeds from the interface patch instead" | tee -a ${prep_log2}

                        task_in="cp ${_voi_gwi} ${_voi_wmr}"

                        task_exec

                    fi

                    task_in="mrcalc -force -datatype uint16 ${WM_mask_inFA} ${_voi_orig} -add 0 -gt ${_voi_shell} -mult ${_voi_gwi} -add 0 -gt ${_voi_incl}"

                    task_exec

                    vol_incl_test=$(mrstats -force -ignorezero -output count ${_voi_incl})

                    if [[ ${vol_incl_test} -lt 250 ]]; then

                        echo "This VOI ${_voi_orig} has ${vol_incl_test} nonzero voxels in -T 5's WM-ring+interface+cortex-rim band, less than the permitted min of 250, so -T 5 includes against the raw VOI instead" | tee -a ${prep_log2}

                        task_in="cp ${_voi_orig} ${_voi_incl}"

                        task_exec

                    fi

                    fi

                fi

            done

            TCK_I_seed_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_bin_wmr.nii.gz));

            TCK_I_b=($(find ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs*/${TCK_2_make}_incs*_bin_incl5.nii.gz));

        fi

    fi

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

    elif [[ ${TCK_2_make} == *"CPCT_LT"* ]] ; then

        echo " Left Corticopontocerebellar bundle " | tee -a ${prep_log2}
        auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz \
        -exclude ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz"
        auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_RT_X_wv.nii.gz any \
        exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_LT_X.nii.gz any exclude"

    elif [[ ${TCK_2_make} == *"CPCT_RT"* ]] ; then

        echo " Right Corticopontocerebellar bundle " | tee -a ${prep_log2}
        auto_X=" -exclude ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz \
        -exclude ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz"
        auto_X_f=" --drawn_roi ${ROIs_d}/custom_VOIs/cerebrum_hemi_LT_X_wv.nii.gz any \
        exclude --drawn_roi ${ROIs_d}/custom_VOIs/cerebellum_RT_X.nii.gz any exclude"

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

    if [[ "${O_flag}" -eq 1 ]]; then
        includes_str=$(printf " -include_ordered %s"  "${TCK_I_b[@]}")
    else
        includes_str=$(printf " -include %s"  "${TCK_I_b[@]}")
    fi

    # -include_ordered needs a well-defined start->end direction to check
    # "order" against -- tckgen refuses it outright without -seed_unidirectional
    # ("[ERROR] -include_ordered requires that -seed_unidirectional is set").
    # But seeding from every VOI in the chain (the normal multi-VOI seeds_str
    # below) and then forcing unidirectional growth would make a seed in a
    # middle VOI (e.g. DRT's red nucleus) only capture HALF the pathway --
    # growing toward one end or the other, never both, unlike today's
    # bidirectional growth which covers the whole thing from any seed. So -O
    # also narrows seeding to just the chain's first VOI (its actual anatomical
    # start, e.g. DRT's dentate), tracking unidirectionally toward the rest in
    # the order the recipe lists them.
    # -T 5 seeds from TCK_I_seed_b (pure WM, one voxel past the interface) rather than
    # TCK_I_b -- which -T 5 has itself already reassigned above to the WM-ring +
    # interface + cortex-rim -include band, not the raw VOI. Every other T_app seeds
    # from TCK_I_b same as always.
    if [[ "${T_app}" -eq 5 ]]; then
        _seed_src=("${TCK_I_seed_b[@]}")
    else
        _seed_src=("${TCK_I_b[@]}")
    fi

    if [[ "${O_flag}" -eq 1 ]]; then
        _seed_vois=("${_seed_src[0]}")
        seed_direction_opt=" -seed_unidirectional"
    else
        _seed_vois=("${_seed_src[@]}")
        seed_direction_opt=""
    fi

    if [[ "${Y_flag}" -eq 1 ]]; then
        # Deliberately inverse-weighted per-VOI n (see -Y in Usage): plain
        # -seed_voxels pools every seed VOI and draws roughly proportional to
        # voxel count, so a bundle's small/precise VOI is size-starved of
        # attempts relative to its large/loose one. Target ~50000 attempts from
        # EVERY seed VOI regardless of size instead.
        _y_target=50000
        unset seeds_str
        for _y_voi in "${_seed_vois[@]}"; do
            _y_count=$(mrstats -force -ignorezero -output count -quiet "${_y_voi}")
            _y_n=$(( _y_target / _y_count ))
            [[ ${_y_n} -lt 1 ]] && _y_n=1
            seeds_str+=$(printf " -seed_random_per_voxel %s %s"  "${_y_voi}" "${_y_n}")
        done
    else
        seeds_str=$(printf " ${tckgen_seed_opt} %s"  "${_seed_vois[@]}")
    fi

    excludes_str=$(printf " -exclude %s"  "${TCK_X_b[@]}")

    # -Z: explicit tckgen -step override (see Usage). Empty string when unset,
    # so it drops out of cmd_str cleanly wherever it's interpolated.
    step_opt=""
    [[ "${Z_flag}" -eq 1 ]] && step_opt=" -step ${step_val}"

    # Bundle-specific tckgen's own -seeds budget: 10000x -select rather than 0
    # (unlimited). tckgen's stock default when -seeds is unset is 1000x -select --
    # too tight, which is why this was 0 in the first place (some hard bundles were
    # coming back under target). But 0 means "keep trying forever, however long that
    # takes", which under -M/-T 5's tighter masks and includes can now genuinely run
    # away on a bundle whose constraints make -select unreachable. 10000x keeps 10x
    # tckgen's own default headroom while guaranteeing termination.
    seeds_cap=$(( 10000 * ns ))

    # run tckgen or tckedit depending on the ${T_app}
    # Must differentiate between BST and WBTS

    # The CSF-stripped mask is the default for every bundle. It used to be reached only by
    # OR_/AF_/CP_/DRT_ and by T_app 4, so everything else -- UF, ILF, IFOF, SLF, CST, FAT,
    # ThR, MdLF -- tracked inside the full brain mask with sulcal CSF included, and nothing
    # prevented a streamline crossing a sulcus as long as there was FOD amplitude on the
    # far side. The include/exclude VOIs do not help here: they constrain where a bundle
    # ends, not what it does between the inclusions. That also matters more now the FOD
    # cutoff is 0.05 for every reconstruction rather than 0.10, because bridging a thin CSF
    # gap is exactly what a lower termination threshold permits.
    #
    # Falls back to the full brain mask if the minCSF image is missing: this is now every
    # bundle's mask rather than four families', so an absent file should degrade the run
    # rather than break all of it.
    if [[ -f "${T1_BM_inFA_minCSF}" ]]; then

        tracking_mask="${T1_BM_inFA_minCSF}"

    else

        echo " WARNING: ${T1_BM_inFA_minCSF} not found — using the full brain mask for ${TCK_2_make}; streamlines may cross sulcal CSF" | tee -a ${prep_log2}

        tracking_mask="${T1_brain_mask_inFA}"

    fi

    # -M: swap in the rind-excluded mask built once per subject above, for -T 1/4/5
    # only -- -T 2/3 track a separate whole-brain substrate and are untouched.
    if [[ "${M_flag}" -eq 1 ]] && [[ ( "${T_app}" -eq 1 || "${T_app}" -eq 4 || "${T_app}" -eq 5 ) ]] && [[ -f "${tracking_mask_norind_inFA}" ]]; then

        tracking_mask="${tracking_mask_norind_inFA}"

    fi

    # Peduncular and dentato-rubro-thalamic bundles additionally exclude CSF
    # outright: they run beside the fourth ventricle and the cerebellopontine
    # cistern, where a streamline that strays into fluid can still terminate
    # plausibly.
    #
    # This must be a CSF mask, i.e. positive INSIDE the fluid. Do not be tempted
    # to hand it T1_BM_inFA_minCSF (brain MINUS CSF) -- that would exclude the
    # whole brain and yield an empty bundle, which looks identical to the failure
    # this replaced.
    #
    # Guarded, because a missing -exclude is fatal rather than degrading: tckgen
    # cannot parse the path as either an image or a sphere and aborts the bundle
    # entirely. That is how ICP_LT/ICP_RT came out empty for every subject since
    # MSBP was dropped, with the reason buried in a per-bundle log.
    if [[ ${TCK_2_make} == *"CP_"* ]] || [[ ${TCK_2_make} == *"DRT_"* ]]; then

        if [[ -f "${FS_csf_mask}" ]]; then

            excludes_str+=$(printf " -exclude %s"  "${FS_csf_mask}")

        else

            echo " WARNING: ${FS_csf_mask} not found — tracking ${TCK_2_make} without the CSF exclude; streamlines may enter the ventricles and cisterns" | tee -a ${prep_log2}

        fi

    fi

    # T = 1 is bundle specific, 2 = WBTCK wo ACT, 3 = WBTCK w ACT, 4 = bundle specific with GMWMI seeding

    if [[ ${T_app} == 1 ]]; then 

        T="BT"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_rs="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_rs.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        # cmd_str="tckgen -force -nthreads ${ncpu_per_bundle} -algorithm ${algo_f} -angle 60 \
        # -select ${ns} -maxlength 280 -minlength 20 \
        # -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

        # No algo_f branch here: the cutoff is the only thing that ever differed
        # between FOD and tensor/FACT tracking, and it now lives in fod_cutoff_opt,
        # which is emptied for FACT/Tensor_Det/Tensor_Prob where -cutoff means an FA
        # threshold rather than an FOD amplitude. An if/else on algo_f at this point
        # would expand to the same command either way.
        cmd_str="tckgen -force -nthreads ${ncpu_per_bundle} -algorithm ${algo_f} \
        -select ${ns} -seeds ${seeds_cap} ${step_opt} ${seed_direction_opt} -angle 60 -maxlength 280 -minlength 20 ${fod_cutoff_opt} -stop \
        -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

    elif [[ ${T_app} == 2 ]]; then

        T="WB"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_rs="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_rs.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        cmd_str="tckedit -force -nthreads ${ncpu_per_bundle} -maxlength 280 -minlength 10 ${sift_str} \
        -mask ${tracking_mask} -minweight 0.08 ${includes_str} ${excludes_str} ${auto_X} ${WB_tck} ${tck_init}"

    elif [[ ${T_app} == 3 ]]; then 

        T="WB_ACT"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_rs="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_rs.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        cmd_str="tckedit -force -nthreads ${ncpu_per_bundle} -maxlength 280 -minlength 10 ${sift_str} \
        -mask ${tracking_mask} -minweight 0.08 ${includes_str} ${excludes_str} ${auto_X} ${WB_tck} ${tck_init}"

    elif [[ ${T_app} == 4 ]]; then 

        T="BT_ACT"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_rs="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_rs.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        # cmd_str="tckgen -force -nthreads ${ncpu_per_bundle} -algorithm ${algo_f} -angle 60 \
        # -select ${ns} -maxlength 280 -minlength 20 \
        # -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

        # T_app 4 never passed the cutoff, so it tracked at MRtrix's 0.10 default even
        # for lore_sd. Its name says ACT but it does not pass -act -- the anatomical
        # constraint here is the minCSF mask -- so nothing halved it either.
        #
        # No algo_f branch here either (see -T 1 above): fod_cutoff_opt is already
        # empty for FACT/Tensor_Det/Tensor_Prob, so branching on algo_f would produce
        # the same command on both arms.
        cmd_str="tckgen -force -nthreads ${ncpu_per_bundle} -algorithm ${algo_f} \
        -select ${ns} -seeds ${seeds_cap} ${step_opt} ${seed_direction_opt} -angle 60 -maxlength 280 -minlength 20 ${fod_cutoff_opt} -stop \
        -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

    elif [[ ${T_app} == 5 ]]; then

        T="BT_WMR"

        tck_init="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}.tck"

        tck_init_rs="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_rs.tck"

        tck_init_inT="${TCK_out}/${TCK_2_make}_initial_${T}_${algo_f}_inMNI.tck"

        # WM-rind seeding (see TCK_I_seed_b/TCK_I_b above): seeds_str draws from pure
        # WM one voxel past the GMWMI interface, includes_str from the tightened
        # WM-ring+interface+cortex-rim band. Same -stop as -T 1/4 -- once a streamline
        # has traversed every include region it stops rather than continuing to
        # wander, and here that fires right at the ribbon instead of after the
        # streamline has already crossed deep into a gyrus.
        # No algo_f branch here either (see -T 1 above): fod_cutoff_opt is already
        # empty for FACT/Tensor_Det/Tensor_Prob, so branching on algo_f would produce
        # the same command on both arms.
        cmd_str="tckgen -force -nthreads ${ncpu_per_bundle} -algorithm ${algo_f} \
        -select ${ns} -seeds ${seeds_cap} ${step_opt} ${seed_direction_opt} -angle 60 -maxlength 280 -minlength 20 ${fod_cutoff_opt} -stop \
        -mask ${tracking_mask} ${seeds_str} ${includes_str} ${excludes_str} ${auto_X} ${tracking_source} ${tck_init}"

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

        # Needed before VOI[0]'s own mode below. either_end was dead code for
        # this pipeline's whole history (an OR-specific branch and its else
        # both silently said "any"), so no VOI here was ever built or sized
        # expecting strict endpoint filtering. Turning it on for BOTH VOIs of
        # a 2-VOI bundle exposed that broadly, not just on one hard bundle --
        # AF_all, CST and OR each lost 50-75% of their filt1 population at the
        # second either_end check alone, and IFOF collapsed to near zero,
        # because requiring both ends to land in a precise patch is a much
        # harder bar than requiring just one.
        #
        # Fix: apply either_end to only ONE of the two VOIs -- whichever is
        # anatomically smaller/more precise (fewer voxels), since that's the
        # one actually worth enforcing exactly (e.g. LGN+pulvinar for OR, M1
        # for CST) -- and leave the other (typically a broad cortical patch)
        # at any. This is independent of -K: -K only dilates _ctx-tagged
        # cortical VOIs, which is usually the *any* side of this pair, so it
        # never touches the VOI either_end is actually checking.
        unset vsz
        vsz="${#TCK_I_b[@]}"

        # scil_tractogram_filter_by_roi takes an optional third DISTANCE value
        # per condition (voxels): "either_end include 2" means within 2 voxels
        # of the VOI, not just exactly inside it. Applying that tolerance to
        # the either_end side (not the any side, which doesn't need it) gives
        # registration/reconstruction imprecision some room without going back
        # to unconstrained any -- any is left bare on purpose here.
        _either_end_dist=2

        if [[ ${TCK_2_make} == *"CST"* ]] || [[ ${TCK_2_make} == *"PyT"* ]] || [[ ${TCK_2_make} == *"ML_"* ]]; then

            drawn_incs_str=$(printf " --drawn_roi %s any include "  "${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz")

        elif [[ ${vsz} -eq 2 ]]; then

            _vsz2_c0=$(mrstats -force -ignorezero -output count -quiet "${TCK_I_b[0]}")
            _vsz2_c1=$(mrstats -force -ignorezero -output count -quiet "${TCK_I_b[1]}")

            _vsz2_cond0="any include"; _vsz2_cond1="either_end include ${_either_end_dist}"
            if [[ ${_vsz2_c0} -le ${_vsz2_c1} ]]; then
                _vsz2_cond0="either_end include ${_either_end_dist}"; _vsz2_cond1="any include"
            fi

            drawn_incs_str=$(printf " --drawn_roi %s %s "  "${TCK_I_b[0]}" "${_vsz2_cond0}")

        else

            drawn_incs_str=$(printf " --drawn_roi %s any include "  "${TCK_I_b[0]}")

        fi

        # it's better to define this differently depending on the number of VOIs
        # i.e. if only 2 incs then easy, end to inc, if more then end for inc1 then any for middle and end for inc(N)
        # this deals with the rest of the filtering string

        if [[ ${TCK_2_make} == *"CST"* ]] || [[ ${TCK_2_make} == *"PyT"* ]] || [[ ${TCK_2_make} == *"ML_"* ]]; then

            # Cortical terminus: the precise, worth-enforcing end of this
            # pathway, unlike the brainstem waypoint above -- unconditional,
            # not gated on VOI size or -K.
            drawn_incs_str+=$(printf " --drawn_roi %s either_end include %s "  "${TCK_I_b[1]}" "${_either_end_dist}")

        elif [[ ${vsz} -eq 2 ]]; then

            drawn_incs_str+=$(printf " --drawn_roi %s %s "  "${TCK_I_b[1]}" "${_vsz2_cond1}")

        elif [[ ${vsz} -gt 2 ]]; then

            # ${TCK_I_b[@]:offset:len} yields the array's VALUES (VOI paths), not indices --
            # vi already holds the path itself, so re-indexing with ${TCK_I_b[$vi]} tried to
            # arithmetically evaluate a filesystem path as an array subscript ("syntax error:
            # operand expected"), silently dropping this middle inclusion VOI from
            # drawn_incs_str for any bundle with more than 2 inclusion VOIs (e.g. ML_LT/ML_RT).
            for vi in ${TCK_I_b[@]:1:$((vsz-2))}; do

                drawn_incs_str+=$(printf " --drawn_roi %s any include "  "${vi}")

            done

            drawn_incs_str+=$(printf " --drawn_roi %s any include "  "${TCK_I_b[${vsz}-1]}")

        fi

    fi

    # excludes will always be the same
    drawn_excs_str=$(printf " --drawn_roi %s any exclude "  "${TCK_X_b[@]}")

    # processing control for initial tracking/segmentation

    if [[ ! -f "${tck_init_rs}" ]]; then

        if [[ ! -f "${tck_init}" ]]; then
        
            task_in="${cmd_str}"

            task_exec
            
        fi

        task_in="tckresample -force -nthreads ${ncpu_per_bundle} -num_points 101 ${tck_init} ${tck_init_rs}"

        task_exec

        task_in="tcktransform -force ${tck_init_rs} ${TCKs_w2temp} ${tck_init_inT}"

        task_exec

        count=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_init_rs} -quiet ));

    else

        count=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_init_rs} -quiet ));

        if [[ ! -f ${tck_init_inT} ]]; then
          
            task_in="tcktransform -force ${tck_init_rs} ${TCKs_w2temp} ${tck_init_inT}"

            task_exec
        fi

        if [[ ${count} -gt 10 ]]; then

            echo " ${TCK_2_make}_initial.tck already done, skipping " | tee -a ${prep_log2}

            # count=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_init} -quiet ));

            # report initial yield
            echo " ${TCK_2_make} has ${count} streamlines initially " | tee -a ${prep_log2}

        else

            task_in="${cmd_str}"

            task_exec

            # cmd_str only regenerates tck_init (raw) -- tck_init_rs/tck_init_inT
            # above are a *stale* leftover from whatever prior run left ${count}
            # at <=10 (that's what routed us here). Without refreshing them,
            # every step downstream of this point (count itself, filtering, QQ)
            # keeps reading that old near-empty file instead of the retry's
            # actual output.
            task_in="tckresample -force -nthreads ${ncpu_per_bundle} -num_points 101 ${tck_init} ${tck_init_rs}"

            task_exec

            task_in="tcktransform -force ${tck_init_rs} ${TCKs_w2temp} ${tck_init_inT}"

            task_exec

            count=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_init_rs} -quiet ));

        fi

    fi

    # need to create combined incs_bin maps for QQ
    # loop from 2nd element in incs_bin array
    #
    # Always regenerated (no "already exists" guard): TCK_I_b's own construction
    # above is independently cached (its per-VOI _gwi/_wmr/_incl outputs each
    # have their own -f guard), and tckgen itself is skipped separately if
    # tck_init already has enough streamlines -- so a rerun can legitimately
    # recompute TCK_I_b's content without either of those steps re-running.
    # A file-existence guard here would then keep serving a map baked from
    # whatever TCK_I_b pointed to on some earlier run, silently out of sync
    # with the actual current VOIs. This step is cheap relative to tckgen, so
    # just always rebuild it from whatever TCK_I_b currently is.
    ((funn=${#TCK_I_b[@]}-1));
    mrcal_strs=$(printf " %s "  "${TCK_I_b[0]}")
    for fun in $(seq 1 ${funn}); do
        ((funme=${fun}+1))
        task_in="mrcalc -force -quiet -datatype uint16 -nthreads ${ncpu_per_bundle} ${TCK_I_b[$fun]} 0 -gt ${funme} -mult \
        ${tmpo_d}/${TCK_2_make}_incs_map_init${funme}.nii.gz"
        task_exec
        mrcal_strs+=$(printf " %s -add "  "${tmpo_d}/${TCK_2_make}_incs_map_init${funme}.nii.gz")
    done

    # WIP we mult the result agg map by 10 to ease separating heads from toes
    task_in="mrcalc -force -quiet -datatype uint16 -nthreads ${ncpu_per_bundle} ${mrcal_strs} 0 -gt ${tmpo_d}/${TCK_2_make}_incs_map_agg_bin.nii.gz"

    task_exec

    task_in="mrcalc -force -quiet -datatype uint16 -nthreads ${ncpu_per_bundle} ${mrcal_strs} ${tmpo_d}/${TCK_2_make}_incs_map_agg_bin.nii.gz -mult 10 -mult ${TCK_out}/${TCK_2_make}_incs_map_agg.nii.gz"

    task_exec

    task_in="antsApplyTransforms -d 3 -i ${TCK_out}/${TCK_2_make}_incs_map_agg.nii.gz -o ${TCK_out}/${TCK_2_make}_incs_map_agg_inMNI.nii.gz -r ${UKBB_temp} \
    -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz \
    -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
    -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz \
    -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0]"

    task_exec

    # including scil_filter_tracts by default as soon as the initial bundle is generated
    # with the exception of the ORs where FBC is used
    # if the bundle has more than 0 streamlines, look whether filt1.tck has already been generated
    # then look at whether it is an OR or not

    tck_filt1="${TCK_out}/${TCK_2_make}_filt1_${T}_${algo_f}.tck"

    tck_filt2="${TCK_out}/${TCK_2_make}_filt2_${T}_${algo_f}.tck"

    tck_filt3="${TCK_out}/${TCK_2_make}_filt3_${T}_${algo_f}.tck"

    # What outlier rejection threw away, and the record of why. Written every
    # run: this step is the single biggest streamline loss in the chain and used
    # to be invisible -- you could only find out it had eaten a bundle's
    # cortical fan by loading filt2 and filt3 side by side and looking.
    tck_filt3_rejects="${TCK_out}/${TCK_2_make}_filt3_rejected_${T}_${algo_f}.tck"

    tck_filt3_json="${TCK_out}/${TCK_2_make}_filt3_${T}_${algo_f}_outlier_rejection.json"

    tck_filt4="${TCK_out}/${TCK_2_make}_filt4_${T}_${algo_f}.tck"

    tck_filt5="${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck"

    tck_filt5_centroid1_raw="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_centroid1_raw.tck"

    tck_filt5_centroid1_inT="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_centroid1_inT.tck"

    tck_filt5_centroid1_inT_uniform="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_centroid1_inT_uniform.tck"

    tck_filt5_centroid1="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_inMNI_centroid1_uniform.tck"

    tck_filt1_inT="${TCK_out}/${TCK_2_make}_filt1_${T}_${algo_f}_inMNI.tck"

    tck_filt3_inT="${TCK_out}/${TCK_2_make}_filt3_${T}_${algo_f}_inMNI.tck"

    tck_filt4_inT="${TCK_out}/${TCK_2_make}_filt4_${T}_${algo_f}_inMNI.tck"

    tck_filt5_inT="${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck"

    # -R (augmented default chain) intermediates -- distinct names so a -R and a
    # non-R run of the same bundle never mistake each other's leftovers for
    # already-done work. Chain: filt1 -> anatomy-filter -> loop-detect ->
    # outlier-reject -> smooth -> [N-run bootstrap RecoBundles + occurrence vote] -> fin
    tck_rfilt_anat_dir="${TCK_out}/${TCK_2_make}_rord_anat_${T}_${algo_f}"

    tck_rfilt_anat="${tck_rfilt_anat_dir}/${TCK_2_make}_filt1_${T}_${algo_f}_filtered.tck"

    tck_rfilt_loop="${TCK_out}/${TCK_2_make}_rord_loop_${T}_${algo_f}.tck"

    tck_rfilt_outlier="${TCK_out}/${TCK_2_make}_rord_outlier_${T}_${algo_f}.tck"

    tck_rfilt_outlier_rejects="${TCK_out}/${TCK_2_make}_rord_outlier_rejected_${T}_${algo_f}.tck"

    tck_rfilt_outlier_json="${TCK_out}/${TCK_2_make}_rord_outlier_${T}_${algo_f}_outlier_rejection.json"

    tck_rfilt_smooth="${TCK_out}/${TCK_2_make}_rord_smooth_${T}_${algo_f}.tck"

    tck_rfilt_smooth_inT="${TCK_out}/${TCK_2_make}_rord_smooth_${T}_${algo_f}_inMNI.tck"

    tck_rfilt_vote_prefix="${TCK_out}/${TCK_2_make}_rord_vote_${T}_${algo_f}_"

    tck_rfilt_vote_trk="${tck_rfilt_vote_prefix}streamlines.trk"

    # how many bootstrap-resampled RecoBundles runs to vote across, and what
    # fraction of the population each run samples (without replacement).
    # A majority vote (2-of-3) turned out to be an OR-ish criterion that let
    # more through than a single full-population RecoBundles run does -- each
    # run only sees a subsample, so its own clustering/pruning is individually
    # weaker, and "kept in any 2 of 3" doesn't require surviving one strong
    # decision the way the default chain's single run does. Requiring
    # unanimity (3-of-3) turns it into an AND-like criterion instead: a
    # streamline must independently survive under three different reduced
    # views of the population, not just one lenient view twice. 70% (down
    # from 80%) makes the three runs less redundant with each other so
    # unanimity is a real bar and not something almost everything clears
    # anyway. Tradeoff: a genuinely real but sparsely-represented minority
    # sub-branch of the bundle has a higher chance of being randomly absent
    # from at least one of the three subsamples, which now fails it outright
    # -- if a bundle comes back missing a specific fanning direction rather
    # than being uniformly thinner, that's this effect, and it argues for
    # raising _reco_subsample_pct back toward 80.
    _reco_n_iter=3
    _reco_subsample_pct=70
    # int(ratio*n) truncates in scilpy's vote-count conversion, so this needs
    # to be exactly 1.0 for int(ratio*3)=3 (true unanimity); anything less
    # (even 0.99) truncates to 2-of-3 again
    _reco_vote_ratio=1.0

    tck_rs1_inT="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_inMNI.tck"

    tck_rs1_innat="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_rs1c.tck"


    tck_cent1_HT_map="${TCK_out}/QQ/tmp/${TCK_2_make}_fin_${T}_${algo_f}_mapped_inMNI.nii.gz"

    Bundle_segs_dir="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_segments_inMNI"

    # MNI_segsd="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs1c_segments_inMNI_debug.nii.gz"

    # MNI_segs3="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_rs50_segments3_inMNI.nii.gz"

    MNI_agg="${TCK_out}/QQ/${TCK_2_make}_incs_map_agg_inMNI.nii.gz"

    TCKs_curve="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_curve.nii.gz"

    TCKs_tdi="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi.nii.gz"

    TCKs_length="${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_length.nii.gz"

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

                    task_in="scil_tractogram_filter_by_roi -f --reference ${subj_FA} ${drawn_incs_str} ${drawn_excs_str} ${auto_X_f} -v DEBUG ${tck_init_rs} ${tck_filt1}"

                    task_exec

                    sleep 2

                    count2=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_filt1} -quiet ));
                    
                else

                    echo " ${TCK_2_make} initial filtering already done, skipping " | tee -a ${prep_log2}

                    count2=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_filt1} -quiet ));
                    # enter checker for count here
                    # mv filt1 to filt5/fin if count < 500 
                fi

                if [[ -f ${tck_filt1} ]] && [[ ! -f ${tck_filt5} ]] && [[ ${count2} -gt 10 ]]; then

                    if [[ ! -f "${TCK_out}/${TCK_2_make}_filt1_map_mask_${T}_${algo_f}.nii.gz" ]]; then
                    
                        task_in="tckmap -precise -force -nthreads ${ncpu_per_bundle} -template ${subj_FA} ${tck_filt1} \
                        ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz && mrcalc -datatype uint16 -force -nthreads ${ncpu_per_bundle} \
                        ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz 0 -gt ${TCK_out}/${TCK_2_make}_filt1_map_mask_${T}_${algo_f}.nii.gz"

                        task_exec

                    fi

                    if [[ "${R_flag}" -eq 1 ]]; then

                        echo " ${TCK_2_make}: using the -R augmented chain (default order + anatomy-endpoint filter + N-run RecoBundles voting) " | tee -a ${prep_log2}

                        # Anatomy-endpoint filter right after ROI filtering: a deterministic,
                        # per-streamline rule check (must reach cortex, must not end in CSF),
                        # not a population-statistics or shape-registration method, so unlike
                        # the earlier reordering attempt it can only remove genuinely bad
                        # streamlines -- no risk of distorting what loop-detect/outlier-reject/
                        # RecoBundles see downstream. minL/maxL/angle left unset so this does one
                        # job; length is already handled at tckgen/tckedit and looping is handled
                        # by the dedicated scil_tractogram_detect_loops step below.
                        if [[ ! -f ${tck_rfilt_anat} ]]; then

                            if [[ -f ${subj_aparc_inFA_int} ]]; then

                                # dilate_ctx: undilated, the cortex-reaching check (step 3) requires an
                                # endpoint to land on the exact labeled cortical voxel, with zero tolerance
                                # for normal registration/resolution imprecision at the GM boundary --
                                # thinning out valid streamlines whose true endpoint sits one voxel short
                                # of the labeled ribbon, not because they're anatomically wrong
                                task_in="scil_tractogram_filter_by_anatomy -f --reference ${subj_FA} --dilate_ctx 2 ${tck_filt1} ${subj_aparc_inFA_int} ${tck_rfilt_anat_dir}"

                                task_exec

                            else

                                echo " ${TCK_2_make} -R: subj_aparc_inFA_int not found — skipping anatomy filter, using filt1 as-is " | tee -a ${prep_log2}

                                mkdir -p ${tck_rfilt_anat_dir}
                                cp ${tck_filt1} ${tck_rfilt_anat}

                            fi

                        fi

                        if [[ ! -f ${tck_rfilt_loop} ]]; then

                            task_in="scil_tractogram_detect_loops -f --reference ${subj_FA} ${tck_rfilt_anat} ${tck_rfilt_loop}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_rfilt_outlier} ]]; then

                            # Same helper and same bounds as the default chain's
                            # filt3 step -- see the comment there.
                            task_in="KUL_FWT_reject_outliers.py -f ${Outlier_opts} --reference ${subj_FA} \
                            --remaining_bundle ${tck_rfilt_outlier_rejects} --json_out ${tck_rfilt_outlier_json} \
                            ${tck_rfilt_loop} ${tck_rfilt_outlier}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_rfilt_smooth} ]]; then

                            task_in="scil_tractogram_smooth -f --gaussian 5 --reference ${subj_FA} ${tck_rfilt_outlier} ${tck_rfilt_smooth}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_rfilt_smooth_inT} ]]; then

                            task_in="tcktransform -force ${tck_rfilt_smooth} ${TCKs_w2temp} ${tck_rfilt_smooth_inT}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_filt5} ]]; then

                            if [[ -f "${pr_d}/TCK_models/${tck_list[$q]}_GN_symmetrical.tck" ]] && \
                               [[ -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat" ]]; then

                                # N-run bootstrap RecoBundles ensemble: each run sees a different
                                # random ${_reco_subsample_pct}% subsample (without replacement) of
                                # the candidate population, so a streamline that only survives
                                # RecoBundles' clustering/pruning in one particular subsample --
                                # rather than because it genuinely matches the model -- gets voted
                                # out by scil_bundle_filter_by_occurrence below instead of silently
                                # deciding the whole bundle on one run's registration quirks.
                                _reco_native_outs=()

                                _reco_total=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_rfilt_smooth_inT} -quiet))
                                _reco_sub_n=$(( ${_reco_total[0]} * ${_reco_subsample_pct} / 100 ))

                                for ((_reco_i=1; _reco_i<=_reco_n_iter; _reco_i++)); do

                                    _reco_shuf="${TCK_out}/${TCK_2_make}_rord_reco${_reco_i}_shuf_${T}_${algo_f}_inMNI.tck"
                                    _reco_sub="${TCK_out}/${TCK_2_make}_rord_reco${_reco_i}_sub_${T}_${algo_f}_inMNI.tck"
                                    _reco_out_inT="${TCK_out}/${TCK_2_make}_rord_reco${_reco_i}_${T}_${algo_f}_inMNI.tck"
                                    _reco_out_native="${TCK_out}/${TCK_2_make}_rord_reco${_reco_i}_${T}_${algo_f}.tck"

                                    if [[ ! -f ${_reco_out_native} ]]; then

                                        task_in="scil_tractogram_shuffle -f --seed ${_reco_i} --reference ${UKBB_temp} ${tck_rfilt_smooth_inT} ${_reco_shuf}"

                                        task_exec

                                        task_in="tckedit -force -nthreads ${ncpu_per_bundle} -number ${_reco_sub_n} ${_reco_shuf} ${_reco_sub}"

                                        task_exec

                                        task_in="scil_tractogram_segment_with_recobundles -f \
                                        --in_tractogram_ref ${UKBB_temp} \
                                        --in_model_ref ${UKBB_temp} \
                                        --tractogram_clustering_thr 8 \
                                        --model_clustering_thr 4 \
                                        --pruning_thr 8 \
                                        --slr_threads ${ncpu_per_bundle} \
                                        --inverse \
                                        -v INFO \
                                        ${_reco_sub} \
                                        ${pr_d}/TCK_models/${tck_list[$q]}_GN_symmetrical.tck \
                                        ${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat \
                                        ${_reco_out_inT}"

                                        task_exec

                                        task_in="tcktransform -force ${_reco_out_inT} ${TCKs_wfromtemp} ${_reco_out_native}"

                                        task_exec

                                    fi

                                    _reco_native_outs+=("${_reco_out_native}")

                                done

                                task_in="scil_bundle_filter_by_occurrence -f --ratio_streamlines ${_reco_vote_ratio} --reference ${subj_FA} ${_reco_native_outs[@]} ${tck_rfilt_vote_prefix}"

                                task_exec

                                # tckinfo can't read .trk (scilpy's occurrence-vote output format);
                                # use scilpy's own counter instead
                                _reco_vote_count=$(scil_tractogram_count_streamlines ${tck_rfilt_vote_trk} --print_count_alone 2>/dev/null)

                                if [[ -f ${tck_rfilt_vote_trk} ]] && [[ ${_reco_vote_count:-0} -gt 0 ]]; then

                                    task_in="scil_tractogram_convert -f --reference ${subj_FA} ${tck_rfilt_vote_trk} ${tck_filt5}"

                                    task_exec

                                else

                                    echo " ${TCK_2_make} -R RecoBundles voting left nothing — using pre-RecoBundles smoothed streamlines as fin " | tee -a ${prep_log2}

                                    task_in="cp ${tck_rfilt_smooth} ${tck_filt5}"

                                    task_exec

                                fi

                            else

                                if [[ ! -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat" ]]; then
                                    echo " MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat not found — skipping recobundles, using smoothed streamlines as fin" | tee -a ${prep_log2}
                                fi

                                task_in="cp ${tck_rfilt_smooth} ${tck_filt5}"

                                task_exec

                            fi

                        fi

                        # Safety net matching the default chain's: never leave fin missing if we
                        # have anything usable further up this branch
                        if [[ ! -f ${tck_filt5} ]] && [[ -f ${tck_rfilt_smooth} ]]; then
                            echo " ${TCK_2_make} -R chain failed past smoothing — using smoothed streamlines as fin " | tee -a ${prep_log2}
                            task_in="cp ${tck_rfilt_smooth} ${tck_filt5}"
                            task_exec
                        fi

                        if [[ -f ${tck_filt5} ]] && [[ ! -f ${tck_filt5_inT} ]]; then

                            task_in="tcktransform -force ${tck_filt5} ${TCKs_w2temp} ${tck_filt5_inT}"

                            task_exec

                        fi

                    else

                        if [[ ! -f ${tck_filt2} ]]; then

                            task_in="scil_tractogram_detect_loops -f --reference ${subj_FA} ${tck_filt1} ${tck_filt2}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_filt3} ]]; then

                            # KUL_FWT_reject_outliers.py, not scilpy's
                            # scil_bundle_reject_outliers: same scoring (it calls
                            # scilpy's own library function), but the cut is
                            # bounded by a share of the bundle as well as by an
                            # absolute score, and it never exits nonzero on a
                            # degenerate input -- task_exec aborts the bundle on
                            # any nonzero status, and a missing filt3 breaks the
                            # smoothing step below it.
                            task_in="KUL_FWT_reject_outliers.py -f ${Outlier_opts} --reference ${subj_FA} \
                            --remaining_bundle ${tck_filt3_rejects} --json_out ${tck_filt3_json} \
                            ${tck_filt2} ${tck_filt3}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_filt4} ]]; then

                            task_in="scil_tractogram_smooth -f --gaussian 5 --reference ${subj_FA} ${tck_filt3} ${tck_filt4}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_filt4_inT} ]]; then

                            task_in="tcktransform -force ${tck_filt4} ${TCKs_w2temp} ${tck_filt4_inT}"

                            task_exec

                        fi

                        if [[ ! -f ${tck_filt5} ]]; then

                            if [[ -f "${pr_d}/TCK_models/${tck_list[$q]}_GN_symmetrical.tck" ]] && \
                               [[ -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat" ]]; then

                                # task_in="scil_tractogram_segment_with_recobundles -f --reference ${UKBB_temp} --model_clustering_thr 4 --pruning_thr 8 --slr_threads ${ncpu_per_bundle} -v \
                                # ${tck_filt4_inT} ${pr_d}/TCK_models/${tck_list[$q]}_GN_symmetrical.tck ${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat ${tck_filt5_inT}"
                                # --tractogram_clustering_thr: scilpy's own default-filling logic for this
                                # flag is inverted (elif ...is not None: sets 8.0 -- backwards for "fill in
                                # a default when unset"), so an unset flag stays None and crashes
                                # RecoBundles' clust_thr formatting downstream. Passing any value here
                                # (scilpy will coerce it to its documented default of 8.0 regardless) avoids
                                # that crash without needing a scilpy patch.
                                # --inverse: MNI_2_MNI_..._0GenericAffine.mat (KUL_FWT_make_VOIs.sh) is
                                # computed as antsRegistrationSyN.sh -f ${UKBB_temp} -m <subject-in-template>,
                                # i.e. fixed=template/moving=subject -- the opposite orientation from what
                                # this script's own docstring prescribes (-m MODEL_REF -f SUBJ_REF, used with
                                # --inverse). Applying it without --inverse previously increased the
                                # pre/post-registration barycenter distance (0.0 -> 0.817 in a real run) --
                                # exactly the symptom the docstring says --inverse should fix.
                                task_in="scil_tractogram_segment_with_recobundles -f \
                                --in_tractogram_ref ${UKBB_temp} \
                                --in_model_ref ${UKBB_temp} \
                                --tractogram_clustering_thr 8 \
                                --model_clustering_thr 4 \
                                --pruning_thr 8 \
                                --slr_threads ${ncpu_per_bundle} \
                                --inverse \
                                -v INFO \
                                ${tck_filt4_inT} \
                                ${pr_d}/TCK_models/${tck_list[$q]}_GN_symmetrical.tck \
                                ${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat \
                                ${tck_filt5_inT}"

                                task_exec

                                task_in="tcktransform -force ${tck_filt5_inT} ${TCKs_wfromtemp} ${tck_filt5}"

                                task_exec

                                count_checker=($(tckinfo ${tck_filt5} | grep "count:" | cut -d ":" -f2))

                                # If recobundles ran but left nothing, fall back to filt4
                                if [[ ${count_checker[0]} -eq 0 ]]; then

                                    task_in="mv ${tck_filt5} $(dirname ${tck_filt5})/$(basename ${tck_filt5} .tck)_failed.tck && \
                                    mv ${tck_filt4} ${tck_filt5} && mv ${tck_filt4_inT} ${tck_filt5_inT}"

                                    task_exec

                                fi

                            else

                                # no template model or MNI_2_MNI mat not yet available — use filt4 as fin
                                if [[ ! -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat" ]]; then
                                    echo " MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat not found — skipping recobundles, using filt4 as fin" | tee -a ${prep_log2}
                                fi

                                task_in="mv ${tck_filt4} ${tck_filt5} && mv ${tck_filt4_inT} ${tck_filt5_inT}"

                                task_exec

                            fi

                        fi

                        # Safety net: if filt5/fin still absent (e.g. recobundles crashed silently),
                        # use filt4 as fin so downstream steps are not blocked
                        if [[ ! -f ${tck_filt5} ]] && [[ -f ${tck_filt4} ]]; then
                            echo " ${TCK_2_make} filt5/fin still missing after recobundles — falling back to filt4 as fin" | tee -a ${prep_log2}
                            task_in="mv ${tck_filt4} ${tck_filt5}"
                            task_exec
                            if [[ -f ${tck_filt4_inT} ]]; then
                                task_in="mv ${tck_filt4_inT} ${tck_filt5_inT}"
                                task_exec
                            fi
                        fi

                    fi

                else

                    echo " ${TCK_2_make} initial filtering failed, skipping " | tee -a ${prep_log2}

                fi

            elif [[ ${TCK_2_make} == "O"* ]]; then

                # OR had neither an endpoint check nor shape validation: FBC alone
                # doesn't verify where a streamline terminates (so it tolerated
                # thalamic overextension) or compare its shape against real OR
                # anatomy (so ILF/temporal-stem streamlines merely grazing both
                # VOIs went uncaught instead of being rejected for lacking a
                # genuine Meyer's-loop trajectory). Now mirrors the standard
                # chain's own bookends -- ROI either_end filter first, RecoBundles
                # last -- with FBC standing in for loop-detect/outlier-reject.
                echo " We use ROI filtering + FBC + RecoBundles for the optic radiations " | tee -a ${prep_log2}

                if [[ ! -f ${tck_filt1} ]]; then

                    task_in="scil_tractogram_filter_by_roi -f --reference ${subj_FA} ${drawn_incs_str} ${drawn_excs_str} ${auto_X_f} -v DEBUG ${tck_init_rs} ${tck_filt1}"

                    task_exec

                    sleep 2

                fi

                if [[ -f ${tck_filt1} ]] && [[ ! -f ${tck_filt2} ]]; then

                    task_in="KUL_FWT_FBC_4TCKs.py -i ${tck_filt1} -r ${subj_FA} -o ${tck_filt2}"

                    task_exec

                    sleep 2

                fi

                if [[ -f ${tck_filt2} ]]; then
                    count2=($(tckstats -force -nthreads ${ncpu_per_bundle} -output count ${tck_filt2} -quiet ));
                else
                    count2=0
                fi

                if [[ -f ${tck_filt2} ]] && [[ ! -f ${tck_filt5} ]] && [[ ${count2} -gt 10 ]]; then

                    if [[ ! -f "${TCK_out}/${TCK_2_make}_filt1_map_mask_${T}_${algo_f}.nii.gz" ]]; then

                        task_in="tckmap -precise -force -nthreads ${ncpu_per_bundle} -template ${subj_FA} ${tck_filt2} \
                        ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz && mrcalc -datatype uint16 -force -nthreads ${ncpu_per_bundle} \
                        ${TCK_out}/${TCK_2_make}_filt1_map_${T}_${algo_f}.nii.gz 0 -gt ${TCK_out}/${TCK_2_make}_filt1_map_mask_${T}_${algo_f}.nii.gz"

                        task_exec

                    fi

                    if [[ ! -f ${tck_filt4} ]]; then

                        task_in="scil_tractogram_smooth -f --gaussian 5 --reference ${subj_FA} ${tck_filt2} ${tck_filt4}"

                        task_exec

                    fi

                    if [[ ! -f ${tck_filt4_inT} ]]; then

                        task_in="tcktransform -nthreads ${ncpu_per_bundle} -force ${tck_filt4} ${TCKs_w2temp} ${tck_filt4_inT}"

                        task_exec

                    fi

                    if [[ ! -f ${tck_filt5} ]]; then

                        if [[ -f "${pr_d}/TCK_models/${TCK_2_make}_GN_symmetrical.tck" ]] && \
                           [[ -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat" ]]; then

                            task_in="scil_tractogram_segment_with_recobundles -f \
                            --in_tractogram_ref ${UKBB_temp} \
                            --in_model_ref ${UKBB_temp} \
                            --tractogram_clustering_thr 8 \
                            --model_clustering_thr 4 \
                            --pruning_thr 8 \
                            --slr_threads ${ncpu_per_bundle} \
                            --inverse \
                            -v INFO \
                            ${tck_filt4_inT} \
                            ${pr_d}/TCK_models/${TCK_2_make}_GN_symmetrical.tck \
                            ${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat \
                            ${tck_filt5_inT}"

                            task_exec

                            task_in="tcktransform -force ${tck_filt5_inT} ${TCKs_wfromtemp} ${tck_filt5}"

                            task_exec

                            count_checker=($(tckinfo ${tck_filt5} | grep "count:" | cut -d ":" -f2))

                            # If recobundles ran but left nothing, fall back to the pre-RecoBundles stage
                            if [[ ${count_checker[0]} -eq 0 ]]; then

                                task_in="mv ${tck_filt5} $(dirname ${tck_filt5})/$(basename ${tck_filt5} .tck)_failed.tck && \
                                mv ${tck_filt4} ${tck_filt5} && mv ${tck_filt4_inT} ${tck_filt5_inT}"

                                task_exec

                            fi

                        else

                            if [[ ! -f "${prep_d}/MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat" ]]; then
                                echo " MNI_2_MNI_${subj}${ses_str}_0GenericAffine.mat not found — skipping recobundles, using smoothed streamlines as fin" | tee -a ${prep_log2}
                            fi

                            task_in="mv ${tck_filt4} ${tck_filt5} && mv ${tck_filt4_inT} ${tck_filt5_inT}"

                            task_exec

                        fi

                    fi

                    # Safety net: if fin still absent (e.g. recobundles crashed silently),
                    # use filt4 as fin so downstream steps are not blocked
                    if [[ ! -f ${tck_filt5} ]] && [[ -f ${tck_filt4} ]]; then
                        echo " ${TCK_2_make} filt5/fin still missing after recobundles — falling back to filt4 as fin" | tee -a ${prep_log2}
                        task_in="mv ${tck_filt4} ${tck_filt5}"
                        task_exec
                        if [[ -f ${tck_filt4_inT} ]]; then
                            task_in="mv ${tck_filt4_inT} ${tck_filt5_inT}"
                            task_exec
                        fi
                    fi

                else

                    echo " ${TCK_2_make} FBC filtering failed, skipping " | tee -a ${prep_log2}

                fi

            fi

            if [[ ! -f "${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}_inMNI.nii.gz" ]]; then

                task_in="tckmap -precise -force -nthreads ${ncpu_per_bundle} -template ${subj_FA} ${tck_filt5} \
                ${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}.nii.gz && mrcalc -datatype uint16 -force -nthreads ${ncpu_per_bundle} \
                ${TCK_out}/${TCK_2_make}_fin_map_${T}_${algo_f}.nii.gz 0 -gt ${TCK_out}/${TCK_2_make}_fin_map_mask_${T}_${algo_f}.nii.gz"

                task_exec 

                # task_in="tcktransform -nthreads ${ncpu_per_bundle} -force ${tck_filt5} ${TCKs_w2temp} ${tck_filt5_inT}"

                # task_exec

                # sleep 5

                task_in="tckmap -precise -force -nthreads ${ncpu_per_bundle} \
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
            echo " ${TCK_2_make} has less than 10 fibers initially, skipping filtering and excluding from screenshots and QQ analysis" | tee -a ${prep_log2}
        fi

        if [[ ${filt_fl2} == 0 ]]; then

            echo " Streamline filtering is disabled by the user, skipping filtering " | tee -a ${prep_log2}

            task_in="mv ${tck_init_rs} ${tck_filt5} && mv ${tck_init_inT} ${tck_filt5_inT}"

            task_exec
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

    # this only runs if the user chooses -Q
    if [[ "${Q_flag}" -eq 1 ]]; then

        # metrics+=("${MNI_segs}" "${MNI_agg}")

        if [[ -f "${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck" ]] && [[ ! -f "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_QQ_done.done" ]]; then

            mkdir -p "${TCK_out}/QQ"

            mkdir -p "${TCK_out}/QQ/tmp"

            # resample the bundle (native space) — feeds the centroid, the connectivity
            # plot below, and every KUL_FWT_buan_profile.py call in the tractometry function
            task_in="tckresample -force -nthreads ${ncpu_per_bundle} -num_points 101 ${tck_filt5} ${tck_rs1_innat}"

            task_exec

            if [[ ! -f "${tck_filt5_centroid1}" ]]; then

                task_in="scil_bundle_compute_centroid -f --reference ${subj_FA} --nb_points 50 ${tck_rs1_innat} ${tck_filt5_centroid1_raw}"
                task_exec

                # Orient the centroid consistently so node 1 means the same anatomical end
                # across every run/session/subject/side, instead of depending on
                # scil_bundle_compute_centroid's own (streamline-order-dependent, therefore
                # non-reproducible under multi-threaded tckgen) choice of reference streamline.
                # Prefer the shared population model when this bundle has one -- LT/RT pairs
                # are built symmetrically ("_GN_symmetrical"), so this also guarantees
                # side-consistency for free. Fall back to this subject's own incs1 VOI (always
                # present -- every track_recipes/*.txt needs at least one incs1 entry to
                # seed/include the bundle in the first place) for a newly-added bundle that
                # doesn't have a model yet.
                if [[ -f "${pr_d}/TCK_models/${TCK_2_make}_GN_symmetrical.tck" ]]; then

                    # Round-trip through UKBB_temp space (where the model lives) via
                    # TCKs_w2temp/TCKs_wfromtemp -- computed unconditionally, unlike
                    # MNI_2_MNI_*, which gates RecoBundles and can be missing. Flip/no-flip is
                    # a pure point-order decision, so it survives the round trip unchanged.
                    task_in="tcktransform -force ${tck_filt5_centroid1_raw} ${TCKs_w2temp} ${tck_filt5_centroid1_inT}"
                    task_exec

                    task_in="scil_bundle_uniformize_endpoints -f --centroid ${pr_d}/TCK_models/${TCK_2_make}_GN_symmetrical.tck --reference ${UKBB_temp} ${tck_filt5_centroid1_inT} ${tck_filt5_centroid1_inT_uniform}"
                    task_exec

                    task_in="tcktransform -force ${tck_filt5_centroid1_inT_uniform} ${TCKs_wfromtemp} ${tck_filt5_centroid1}"
                    task_exec

                else

                    echo " no TCK_models/${TCK_2_make}_GN_symmetrical.tck -- orienting ${TCK_2_make} centroid by its own incs1 VOI instead" | tee -a ${prep_log2}

                    task_in="scil_bundle_uniformize_endpoints -f --target_roi ${ROIs_d}/${TCK_2_make}_VOIs/${TCK_2_make}_incs1/${TCK_2_make}_incs1_bin.nii.gz --reference ${subj_FA} ${tck_filt5_centroid1_raw} ${tck_filt5_centroid1}"
                    task_exec

                fi

            fi

            # length/curve/tdi as plain scalar volumes (not fixel data).
            # length and curvature are per-streamline scalars (curvature reduced
            # to one value per streamline via the default -stat_tck mean), scattered
            # into every voxel that streamline touches -- -stat_vox sum then just
            # reproduces streamline density (more streamlines through a voxel ->
            # bigger sum, regardless of the actual length/curvature values), making
            # both maps shaped like TDI no matter what. -stat_vox mean divides that
            # out, giving the actual average value independent of density -- this is
            # the documented, published convention for length (Pannek et al.'s
            # "average pathlength map", cited directly in `tckmap -help`).
            # tdi itself stays sum: that summation is the literal definition of
            # track density, not a confound to remove.
            task_in="tckmap -precise -force -stat_vox mean -contrast length -template ${subj_FA} ${tck_filt5} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_length.nii.gz \
            && tckmap -precise -force -stat_vox mean -contrast curvature -template ${subj_FA} ${tck_filt5} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_curve.nii.gz \
            && tckmap -precise -force -stat_vox sum -contrast tdi -template ${subj_FA} ${tck_filt5} ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi.nii.gz"

            task_exec

            # --- connectivity matrix (unrelated to tractometry, unchanged) ---
            task_in="antsApplyTransforms -d 3 -i ${CFP_aparc_inFA} \
            -o ${CFP_aparc_inMNI} -r ${UKBB_temp} \
            -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
            -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] -n MultiLabel"

            task_exec

            task_in="KUL_FWT_plot_bundle_connectivity.py ${tck_rs1_innat} ${CFP_aparc_inFA} ${TCK_out}/QQ"

            task_exec

            # --- unified along-tract tractometry (dipy.stats.analysis.afq_profile) ---
            # See KUL_FWT_tractometry_functions.sh: replaces the previous two-track design
            # (MRtrix fixel-based 50-segment sampler + a separate additive BUAN pass) with
            # one profiling path over whichever of the candidate metrics below actually
            # exist for this subject (KUL_FWT_add_metric_if_present skips, doesn't fail,
            # on anything missing -- DTI scalars, fixel metrics and LoRE-SD contrasts are
            # all independently optional; the QQ_done.done marker still requires only that
            # whatever was profiled has succeeded).
            source "$(dirname "$0")/KUL_FWT_tractometry_functions.sh"

            tractometry_reference_nii="${subj_FA}"
            buan_metrics=()
            buan_scalars=()
            KUL_FWT_add_metric_if_present "FA" "${subj_FA}"
            KUL_FWT_add_metric_if_present "ADC" "${subj_ADC}"
            KUL_FWT_add_metric_if_present "AD" "${subj_AD}"
            KUL_FWT_add_metric_if_present "RD" "${subj_RD}"
            KUL_FWT_add_metric_if_present "TDI" "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi.nii.gz"
            KUL_FWT_add_metric_if_present "Length" "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_length.nii.gz"
            KUL_FWT_add_metric_if_present "Curve" "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_curve.nii.gz"
            KUL_FWT_add_metric_if_present "PeakCount" "${subj_vpkcount}"
            KUL_FWT_add_metric_if_present "LoRE_RFA" "${prep_d}/lore_sd_rfa.nii.gz"
            KUL_FWT_add_metric_if_present "LoRE_IntraAx" "${prep_d}/lore_sd_intra_axonal_contrast.nii.gz"
            KUL_FWT_add_metric_if_present "LoRE_ExtraAx" "${prep_d}/lore_sd_extra_axonal_contrast.nii.gz"
            KUL_FWT_add_metric_if_present "LoRE_FreeWater" "${prep_d}/lore_sd_free_water_contrast.nii.gz"

            if KUL_FWT_run_tractometry; then
                touch "${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_QQ_done.done" && echo "${TCK_2_make}_fin_${T}_${algo_f} QQ work is done" | tee -a ${prep_log2}

                # Regenerate the spider pages now, over whatever bundles have QQ_done
                # so far -- so a run can be checked bundle-by-bundle instead of only
                # once every bundle has finished (spider_plot's cross-bundle axis
                # normalization only needs "every bundle done up to now", not "every
                # bundle ever"). flock serializes this against sibling bundles
                # finishing QQ at the same moment; non-fatal like the end-of-run call,
                # since a report hiccup here shouldn't cost this bundle its QQ_done.
                if [[ "${Q_flag}" -eq 1 ]] && command -v KUL_FWT_bundle_spider_plot.py >/dev/null 2>&1; then
                    (
                        flock -w 120 202 || exit 0
                        KUL_FWT_bundle_spider_plot.py "${TCKs_outd}" "${subj}" "${ses_str}"
                    ) 202>"${TCKs_outd}/.spider_plot.lock" >> ${prep_log2} 2>&1
                fi
            else
                echo "ERROR: ${TCK_2_make}_fin_${T}_${algo_f} QQ tractometry failed, not marking QQ done" | tee -a ${prep_log2}
            fi

        fi

    fi

    # TrackVis .trk beside the .tck, so the bundle can be loaded in freeview
    # (which reads .trk but not MRtrix .tck) as well as mrview.
    #
    # Reference is subj_FA, NOT the -F parcellation: KUL_FWT_make_VOIs.sh
    # registers FS to FA itself (antsIntermodalityIntrasubject.sh) and warps
    # every label *into FA space*, so tracking -- and therefore these
    # streamlines -- happen in FA space. FS space only coincides with it when
    # the dwiprep _reg2T1w step has already made that registration near
    # identity; feed FWT a dMRI series that was never aligned to the T1 (a
    # separate session, say) and the two frames genuinely differ, at which
    # point an FS-space reference would write a .trk that renders offset.
    # .tck carries no reference at all, which is why this only bites here.
    #
    # Optional: skipped with a warning if scilpy is not on PATH, in keeping
    # with how the other add-on outputs here degrade rather than fail.
    #
    # Placed before Screenshots (not after, where this used to sit): a fury
    # crash in scil_viz_bundle_screenshot_mni (a --local_coloring bug, seen
    # repeatedly on CST) is caught by task_exec, which exits this bundle's
    # whole subshell -- so anything placed after Screenshots silently never
    # runs once that crash hits, and CST's .trk was consistently missing as
    # a result even though its fin.tck existed. .trk generation doesn't
    # depend on screenshots succeeding, so it shouldn't be able to be blocked
    # by them.
    _fwt_fin_tck="${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck"
    _fwt_out_trk="${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.trk"
    if [[ -f "${_fwt_fin_tck}" ]] && [[ ! -f "${_fwt_out_trk}" ]]; then

        if command -v scil_tractogram_convert >/dev/null 2>&1; then

            if scil_tractogram_convert "${_fwt_fin_tck}" "${_fwt_out_trk}" \
                --reference "${subj_FA}" -f >/dev/null 2>&1; then
                echo "${TCK_2_make}_fin_${T}_${algo_f} .trk written for freeview" | tee -a ${prep_log2}
            else
                echo "WARNING: .trk conversion failed for ${TCK_2_make}_fin_${T}_${algo_f}" | tee -a ${prep_log2}
            fi

        else

            echo "WARNING: scil_tractogram_convert not found, skipping .trk for ${TCK_2_make}" | tee -a ${prep_log2}

        fi

    fi

    # Screenshots workflow
    # we use template warped TCKs for SCs
    if [[ "${S_flag}" -eq 1 ]]; then

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
            # export QT_QPA_PLATFORM=offscreen

            # Native-space bundle + native T1 (sub_T1inFA), not the MNI/UKBB-warped
            # versions: the _inMNI.tck used here previously is the output of a
            # nonlinear ANTs warp into UKBB template space, which genuinely deforms
            # streamline geometry (more so wherever the warp is locally large, e.g.
            # this being a clinical subject) -- that's what read as "warped"
            # renderings, not a rendering-tool defect. --target_template is required
            # even so: scil_viz_bundle_screenshot_mni's own camera framing assumes
            # its input is either already MNI152-shaped or told how to get there
            # (per its --help) -- tested feeding it a bare native-space volume with
            # neither, and its auto-framing badly cropped every view. With
            # --target_template it does its own light AFFINE-only registration
            # instead of reusing the pipeline's full nonlinear one, which frames
            # correctly *and* keeps the rendering closer to this subject's true
            # anatomical proportions than the nonlinear-warped version did.
            mni_target="${FSLDIR}/data/standard/MNI152_T1_1mm_brain.nii.gz"

            if [[ ${TCK_2_make} == *"_RT_"* ]]; then

                task_in="scil_viz_bundle_screenshot_mni -f --right --local_coloring
                --target_template ${mni_target} \
                --out_dir ${TCK_out}/Screenshots --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f}+anat \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck ${sub_T1inFA} \
                && scil_viz_bundle_screenshot_mni -f --right --local_coloring \
                --target_template ${mni_target} --out_dir \
                ${TCK_out}/Screenshots --anat_opacity 0 --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f} \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck ${sub_T1inFA}"

                task_exec

            else

                task_in="scil_viz_bundle_screenshot_mni -f --local_coloring \
                --target_template ${mni_target} \
                --out_dir ${TCK_out}/Screenshots --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f}+anat \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck ${sub_T1inFA} \
                && scil_viz_bundle_screenshot_mni -f --local_coloring \
                --target_template ${mni_target} --out_dir \
                ${TCK_out}/Screenshots --anat_opacity 0 --output_suffix \
                ${TCK_2_make}_fin_${T}_${algo_f} \
                ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}.tck ${sub_T1inFA}"

                task_exec

            fi

            mkdir -p "${TCK_out}/Screenshots/mosaic_${T}_${algo_f}"

            task_in="scil_viz_bundle_screenshot_mosaic -f --zoom 1.5 --reference ${subj_T1_in_UKBB} --opacity_background 0.3 --resolution_of_thumbnails 600 \
            ${subj_T1_in_UKBB} ${TCK_out}/${TCK_2_make}_fin_${T}_${algo_f}_inMNI.tck \
            ${TCK_out}/Screenshots/mosaic_${T}_${algo_f}/sub-${subj}${ses_str}_${TCK_2_make}_fin_${T}_${algo_f}_inMNI_mosaic.pdf "

            task_exec

            touch "${TCK_out}/Screenshots/${TCK_2_make}_fin_${T}_${algo_f}_Sc_done.done" && echo "${TCK_2_make}_fin_${T}_${algo_f} screenshots work is done" | tee -a ${prep_log2}

            # Same incremental idea as the QQ spider regen above, for the contact
            # sheet: rebuild it now over whatever bundles have screenshots so far.
            if command -v KUL_FWT_bundle_report.py >/dev/null 2>&1; then
                (
                    flock -w 120 203 || exit 0
                    KUL_FWT_bundle_report.py "${TCKs_outd}" "${subj}" "${ses_str}"
                ) 203>"${TCKs_outd}/.bundle_report.lock" >> ${prep_log2} 2>&1
            fi

        fi

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

RL_VOIs="${pr_d}/RL_hemi_masks.nii.gz" # done

TCKs_w2temp="${prep_d}/FS_2_UKBB_${subj}_inv_4TCKs.mif"

TCKs_wfromtemp="${prep_d}/FS_2_UKBB_${subj}_forward_4TCKs.mif"

subj_fpk="sub-${subj}_fixel_peaks.mif"

subj_ffd="sub-${subj}_fixel_fd.mif"

subj_fdisp="sub-${subj}_fixel_disp.mif"

subj_vpk="${prep_d}/peaks.nii.gz"

subj_vfd="${prep_d}/fd.nii.gz"

subj_vdisp="${prep_d}/disp.nii.gz"

subj_vpkcount="${prep_d}/peakcount.nii.gz"

if [[ -z "${subj_FA}" ]]; then
    subj_FA="${prep_d}/fa.nii.gz"
fi

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

WB_tck="${TCKs_outd}/sub-${subj}${ses_str}_WB_TCKs_${T}_${algo_f}.tck"

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

if [[ ! -f "${ROIs_d}/Part1.done" ]] && [[ ! -f "${ROIs_d}/Part2.done" ]]; then

    echo " General purpose VOIs are not yet generated, please run KUL_genVOIs.sh first"
    exit 2

elif [[ -f "${ROIs_d}/Part1.done" ]] && [[ -f "${ROIs_d}/Part2.done" ]]; then

    # these should all be created by the genVOIs script
    # will probably need some for the tckseg script

    sub_FA_in_T1="${prep_d}/sub-${subj}${ses_str}_FA2T1brainMS_Warped.nii.gz"

    sub_T1inFA="${prep_d}/sub-${subj}${ses_str}_T1brain_MSinFA_Warped.nii.gz"

    T1_brain_mask_inFA="${prep_d}/sub-${subj}${ses_str}_T1bm_MSinFA_Warped.nii.gz"

    # The MSBP-derived CSF mask this used to name (sub-X_MSBP_CSF_mask.nii.gz) is
    # never produced by anything: MSBP was dropped in favour of the Lausanne
    # parcellation plus FreeSurfer subfields, and nothing was left writing that
    # file. KUL_FWT_make_VOIs.sh builds an equivalent from the FreeSurfer aseg
    # (labels 4/43/14/15/24/31/63 intersected with the brain mask), so use that.
    FS_csf_mask="${prep_d}/sub-${subj}${ses_str}_FS_CSF_mask.nii.gz"

    FS_csf_mask_binv="${ROIs_d}/custom_VOIs/sub-${subj}${ses_str}_FS_CSF_mask_binv.nii.gz"

    T1_BM_inFA_minCSF="${prep_d}/sub-${subj}${ses_str}_T1bm_MSinFA_minCSF.nii.gz"

    RL_in_FA="${prep_d}/sub-${subj}${ses_str}_RL_masks_inFA.nii.gz"

    PD25_in_FA="${prep_d}/sub-${subj}${ses_str}_PD25_histological_inFA.nii.gz"

    SUIT_in_FA="${prep_d}/sub-${subj}${ses_str}_SUIT_cerebellar_atlas_inFA.nii.gz"

    UKBB_in_FA="${prep_d}/sub-${subj}${ses_str}_UKBB_Bstem_VOIs_inFA.nii.gz"

    JuHA_in_FA="${prep_d}/sub-${subj}${ses_str}_Juelich_VOIs_inFA.nii.gz"

    JHU_in_FA="${prep_d}/sub-${subj}${ses_str}_JHU_VOIs_inFA.nii.gz"

    Man_VOIs_in_FA="${prep_d}/sub-${subj}${ses_str}_Manual_VOIs_inFA.nii.gz"

    subj_aparc_inFA="${prep_d}/sub-${subj}${ses_str}_aparc_inFA.nii.gz"

    subj_5tt_inFA="${prep_d}/sub-${subj}${ses_str}_5tt_inFA.nii.gz"

    subj_gmwmi_inFA="${prep_d}/sub-${subj}${ses_str}_gmwmi_inFA.nii.gz"

    subj_aseg_inFA="${prep_d}/sub-${subj}${ses_str}_aseg_inFA.nii.gz"

    subj_FS_WMaparc_inFA="${prep_d}/sub-${subj}${ses_str}_WMaparc_inFA.nii.gz"

    subj_MSsc3_inFA="${prep_d}/sub-${subj}${ses_str}_MSBP_scale3_inFA.nii.gz"

    CFP_aparc_inFA="${prep_d}/sub-${subj}${ses_str}_LC+spine_inFA.nii.gz"

    CFP_aparc_inMNI="${prep_d}/sub-${subj}${ses_str}_LC+spine_inMNI.nii.gz"

    subj_FS_lobes_inFA="${prep_d}/sub-${subj}${ses_str}_FS_lobes_inFA.nii.gz"

    subj_FS_2009_inFA="${prep_d}/sub-${subj}${ses_str}_FS_2009_inFA.nii.gz"

    subj_FS_Fx_inFA="${prep_d}/sub-${subj}${ses_str}_FS_fornix_inFA.nii.gz"

    # MS_2_UKBB is lesioned when VBG-filled FS was used; falls back to FS_2_UKBB otherwise

    if [[ ! -f "${prep_d}/MS_2_UKBB_${subj}${ses_str}_Warped.nii.gz" ]]; then
        
        subj_T1_in_UKBB="${prep_d}/FS_2_UKBB_${subj}${ses_str}_Warped.nii.gz"
    
    else
        
        subj_T1_in_UKBB="${prep_d}/MS_2_UKBB_${subj}${ses_str}_Warped.nii.gz"

    fi

    # account for different tracking algorithms

    subj_dwi=($(find ${d_dir} -type f -name "dwi_preproced_reg2T1w.mif"))

    subj_fod=($(find ${d_dir} -type f -name "dhollander_wmfod_reg2T1w.mif"))

    if [[ -z "${subj_lore_fod}" ]]; then
        subj_lore_fod=($(find ${d_dir} -type f -name "odf_reg2T1w.mif" -path "*/lore_sd/*"))
    fi
    if [[ -z "${subj_lore_contrasts_dir}" ]]; then
        subj_lore_contrasts_dir=$(find ${d_dir} -type d -name "lore_sd_contrasts" 2>/dev/null | head -1)
    fi
    subj_rfa_mod_fod=""
    if [[ $use_rfa_mod_fod -eq 1 ]]; then
        subj_rfa_mod_fod=($(find ${d_dir} -type f -name "rfa_modulated_fod_reg2T1w.mif" -path "*/lore_sd/*"))
    fi

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

    # Find your FODs — fallback chain for dhollander/CSD variants
    if [[ -z ${subj_fod} ]]; then

        subj_fod=($(find ${d_dir} -type f -name "*wmfod_reg2T1w.mif"))

        if [[ -z ${subj_fod} ]]; then

            subj_fod=($(find ${d_dir} -type f -name "*wmfod_noGM.mif"))

            if [[ -z ${subj_fod} ]]; then

                subj_fod=($(find ${d_dir} -type f -name "*wmfod.mif"))

                if [[ -z ${subj_fod} ]]; then

                    echo "no FODs found, quitting" | tee -a ${prep_log2}
                    exit 2

                fi

            fi

        fi

    fi

    # If LoRE-SD ODF is available, prefer it over CSD-based FOD. If the experimental
    # rfa-modulated FOD is available AND opted into (-U), prefer that over the plain
    # lore_sd ODF instead.
    _using_lore_sd=0

    if [[ -n ${subj_rfa_mod_fod} ]]; then
        echo "rfa-modulated lore_sd FOD found (${subj_rfa_mod_fod}), using it (opt-in -U)" | tee -a ${prep_log2}
        subj_fod=${subj_rfa_mod_fod}
        _using_lore_sd=1
    elif [[ -n ${subj_lore_fod} ]]; then
        echo "LoRE-SD ODF found (${subj_lore_fod}), using it instead of CSD FOD" | tee -a ${prep_log2}
        subj_fod=${subj_lore_fod}
        _using_lore_sd=1
    fi

    # FOD amplitude cutoff for terminating tracks. Decided here, AFTER the
    # reconstruction above has been chosen, because the right value depends on which
    # one it is -- the cutoff is an absolute amplitude, and different reconstructions
    # do not put their amplitudes on the same scale.
    #
    # Default: leave it unset, i.e. take MRtrix's own default (0.10, Defaults::cutoff_fod;
    # halved to 0.05 only when -act is genuinely in use, which none of the
    # bundle-specific modes do -- T_app 4 is pseudo-ACT via the minCSF mask, not the
    # real thing). MRtrix's default is tuned for ordinary CSD FODs, so for a CSD run
    # that is the value that has actually been validated by its authors.
    #
    # 0.05 for lore_sd: this number was derived from LoRE-SD's amplitude scale, not
    # from CSD's. An earlier version of this block applied it to every reconstruction
    # on the reasoning that a reconstruction-dependent threshold is a confound when
    # comparing them. That reasoning had the premise backwards: applying a
    # LoRE-SD-tuned number to CSD is not removing a confound, it is using a threshold
    # on a reconstruction it was never tuned for. Matching the threshold to the
    # reconstruction is the adaptive choice; if you specifically want a fixed cutoff
    # across reconstructions -- which is a legitimate thing to want when comparing
    # methods -- pass it with -X and it applies to all of them.
    if [[ "${_using_lore_sd}" -eq 1 ]]; then

        fod_cutoff_opt="-cutoff 0.05"

    else

        fod_cutoff_opt=""

    fi

    # For the tensor and FACT algorithms -cutoff is an FA threshold, not an FOD amplitude,
    # and the two are not on the same scale: 0.05 FA would track through almost anything.
    # Those stay on the MRtrix default (0.10 FA).
    if [[ ${algo_f} == "FACT" ]] || [[ ${algo_f} == "Tensor_Det" ]] || [[ ${algo_f} == "Tensor_Prob" ]]; then

        fod_cutoff_opt=""

    fi

    # -X: explicit user override, and the last word -- it wins over the reconstruction
    # default above and over the tensor/FACT exception. That exception exists to stop an
    # FOD-scale value being applied silently as an FA threshold; someone passing -X has
    # said the value out loud, so warn rather than ignore them.
    #
    # Safe under ACT too: Tractography::load only writes the option into
    # properties["threshold"], and Properties::set lets a user-supplied value win over the
    # algorithm's computed default, so an explicit value stays put rather than being
    # halved again for T_app 3.
    if [[ "${X_flag}" -eq 1 ]]; then

        if [[ ${algo_f} == "FACT" ]] || [[ ${algo_f} == "Tensor_Det" ]] || [[ ${algo_f} == "Tensor_Prob" ]]; then

            echo " WARNING: -X ${cutoff_val} will be passed to ${algo_f}, where -cutoff is an FA threshold rather than an FOD amplitude — check the value is on the intended scale " | tee -a ${prep_log2}

        fi

        fod_cutoff_opt="-cutoff ${cutoff_val}"

        echo " tckgen cutoff set explicitly to ${cutoff_val} (-X) " | tee -a ${prep_log2}

    elif [[ -n "${fod_cutoff_opt}" ]]; then

        echo " tckgen cutoff set to 0.05 for the lore_sd reconstruction in use; pass -X to override " | tee -a ${prep_log2}

    else

        echo " tckgen cutoff left at MRtrix's own default for this reconstruction/algorithm; pass -X to override " | tee -a ${prep_log2}

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
    # This block (fod2fixel + derived fixel2voxel) feeds the 3 fixel-only tractometry
    # metrics (FD/Disp/Peaks) profiled in KUL_FWT_tractometry_functions.sh -- nothing
    # else in the pipeline reads any of these outputs. Gated on Q_flag so a -Q-less run
    # skips it entirely. FC/logFC/FDC (warp2metric -fc against the ANTs-derived warp)
    # were dropped: that metric is the log-Jacobian of the warp to a *population*
    # template (Raffelt et al. FBA) and is only interpretable against a cohort, which a
    # single clinical subject doesn't have -- and it kept failing warp2metric besides.
    if [[ "${Q_flag}" -eq 1 ]] && [[ ! -f "${prep_d}/fixel_metrics/${subj_ffd}" ]]; then

        if [[ -d "${prep_d}/fixel_metrics" ]]; then

            echo "removing old fixels dir" | tee -a ${prep_log2}
            rm -rf "${prep_d}/fixel_metrics"

        fi

        task_in="fod2fixel -force -quiet -nthreads ${ncpu} -afd ${subj_ffd} -disp ${subj_fdisp} -peak_amp ${subj_fpk} ${subj_fod} ${prep_d}/fixel_metrics"
        task_exec

        task_in="fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_ffd} mean ${subj_vfd} -weighted ${prep_d}/fixel_metrics/${subj_ffd} \
        && fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_fdisp} mean ${subj_vdisp} -weighted ${prep_d}/fixel_metrics/${subj_fdisp} \
        && fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_fpk} mean ${subj_vpk} -weighted ${prep_d}/fixel_metrics/${subj_fpk} \
        && fixel2voxel -force -quiet -nthreads ${ncpu} ${prep_d}/fixel_metrics/${subj_ffd} count ${subj_vpkcount}"

        task_exec

        # task_in="antsApplyTransforms -d 3 -i ${subj_vpk} \
        # -o ${subj_vpk_MNI} -r ${UKBB_temp} \
        # -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        # -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        # && antsApplyTransforms -d 3 -i ${subj_vfd} \
        # -o ${subj_vfd_MNI} -r ${UKBB_temp} \
        # -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        # -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0] \
        # && antsApplyTransforms -d 3 -i ${subj_vdisp} \
        # -o ${subj_vdisp_MNI} -r ${UKBB_temp} \
        # -t ${prep_d}/FS_2_UKBB_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/FS_2_UKBB_${subj}${ses_str}_0GenericAffine.mat,0] \
        # -t ${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_1Warp.nii.gz -t [${prep_d}/fa_2_UKBB_vFS_${subj}${ses_str}_0GenericAffine.mat,0]"

        # task_exec

    fi

    # LoRE-SD contrasts (rfa/intra_axonal/extra_axonal/free_water), if this subject has
    # them (see KUL_dwiprep.sh's lore_decomposition2contrast + KUL_dwiprep_anat.sh's
    # _reg2T1w registration). Converted once to .nii.gz and cached in prep_d since
    # KUL_FWT_buan_profile.py reads scalars via nibabel, which can't open .mif. Purely
    # additive to tractometry's candidate metric set -- see KUL_FWT_add_metric_if_present
    # in KUL_FWT_tractometry_functions.sh for how missing ones are skipped, not fatal.
    if [[ "${Q_flag}" -eq 1 ]] && [[ -n "${subj_lore_contrasts_dir}" ]]; then

        for lore_contrast in rfa intra_axonal_contrast extra_axonal_contrast free_water_contrast; do

            lore_mif="${subj_lore_contrasts_dir}/${lore_contrast}_reg2T1w.mif"
            lore_nii="${prep_d}/lore_sd_${lore_contrast}.nii.gz"

            if [[ -f "${lore_mif}" ]] && [[ ! -f "${lore_nii}" ]]; then
                task_in="mrconvert -force ${lore_mif} ${lore_nii}"
                task_exec
            fi

        done

    fi

    if [[ ${T_app} -gt 2 ]]; then
        if [[ ! -f "${subj_gmwmi_inFA}" ]]; then
        
            task_in="5ttgen freesurfer ${subj_aparc_inFA} ${subj_5tt_inFA} -force && 5tt2gmwmi -force ${subj_5tt_inFA} - | \
            mrgrid - regrid - -template ${subj_FA} | mrcalc - 0.05 -gt ${subj_gmwmi_inFA} -force"

            task_exec
        
        fi

    fi

    if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

        if [[ ${T_app} -gt 2 ]]; then
            
            tracking_string=" -algorithm ${algo_f} -seed_gmwmi ${subj_gmwmi_inFA} -act ${subj_5tt_inFA} -angle 60 "

            tracking_source=" ${subj_fod} "

            # elif [[ ${T_app} -eq 2 ]]; then
        else

            tracking_string=" -algorithm ${algo_f} -seed_dynamic ${subj_fod} -angle 60 "

            tracking_source=" ${subj_fod} "

        fi

        # metrics+=("${subj_vfd_MNI}" "${subj_vdisp_MNI}" "${subj_vpk_MNI}")

        # # add the maps to metric for plotting if Q_flag is set
        # if [[ "${Q_flag}" -eq 1 ]]; then

        # fi

    elif [[ ${algo_f} == "FACT" ]]; then

        if [[ -z ${subj_DT_vecs} ]]; then

            # Not using the actual B0 for anything

            subj_dt="${prep_d}/sub-${subj}_tensor.mif"

            subj_DT_vecs="${prep_d}/sub-${subj}_dwi_dt_vecs_reg2T1w.mif"

            if [[ -z "${subj_FA}" ]]; then
                subj_FA="${prep_d}/fa.nii.gz"
            fi

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

        tracking_string=" -algorithm ${algo_f} ${tckgen_seed_opt} ${T1_BM_inFA_minCSF} "
        tracking_source=" ${subj_DT_vecs} "

    elif [[ ${algo_f} == "Tensor_Det" ]] || [[ ${algo_f} == "Tensor_Prob" ]]; then

        tracking_string=" -algorithm ${algo_f} ${tckgen_seed_opt} ${T1_BM_inFA_minCSF} "
        tracking_source=" ${subj_dwi} "

    fi

    # One-time per-subject cast of subj_aparc_inFA to an integer datatype, for
    # -R's scil_tractogram_filter_by_anatomy step. subj_aparc_inFA comes from
    # KUL_FWT_make_VOIs.sh's antsApplyTransforms -n multilabel warp, which
    # preserves exact label values but writes them out as float -- scilpy's
    # get_data_as_labels refuses a float image outright regardless of whether
    # its values are integer-valued. This is a pure datatype recast (no
    # resampling/blending happens here, multilabel interpolation already
    # guaranteed the values are exact integers), done once per subject rather
    # than once per bundle since every bundle's -R chain needs the same file.
    subj_aparc_inFA_int="${prep_d}/sub-${subj}${ses_str}_aparc_inFA_int.nii.gz"

    if [[ "${R_flag}" -eq 1 ]] && [[ -f ${subj_aparc_inFA} ]] && [[ ! -f ${subj_aparc_inFA_int} ]]; then

        task_in="mrconvert -force -nthreads ${ncpu} -datatype int32 ${subj_aparc_inFA} ${subj_aparc_inFA_int}"

        task_exec

    fi

    # One-time per-subject cortical-ribbon and WM masks. Originally built only for -K's
    # inward-only dilation of cortical inclusion VOIs; T_app 2's whole-brain generation
    # (below) also needs ctx_mask_inFA now, to -stop streamlines at first cortex contact.
    # Cortical mask uses the same FreeSurfer ctx-* label ranges (1000-1035 excluding the
    # unused 1004 gap, 2000-2035 excluding 2004) that scilpy's own
    # dk_aggregate_structures.json uses for the same purpose elsewhere in this pipeline --
    # range-tested rather than enumerated label-by-label, but equivalent. WM mask is aseg
    # 2/41 (Left/Right-Cerebral-White-Matter). Both done once per subject, not per caller.
    ctx_mask_inFA="${prep_d}/sub-${subj}${ses_str}_ctx_mask_inFA.nii.gz"

    WM_mask_inFA="${prep_d}/sub-${subj}${ses_str}_WM_mask_inFA.nii.gz"

    if [[ ( "${K_flag}" -eq 1 || "${T_app}" -eq 2 || "${T_app}" -eq 4 || "${T_app}" -eq 5 ) ]] && [[ -f ${subj_aparc_inFA} ]] && [[ ! -f ${ctx_mask_inFA} ]]; then

        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} -quiet \
        ${subj_aparc_inFA} 1000 -ge ${subj_aparc_inFA} 1035 -le -mult ${subj_aparc_inFA} 1004 -neq -mult \
        ${subj_aparc_inFA} 2000 -ge ${subj_aparc_inFA} 2035 -le -mult ${subj_aparc_inFA} 2004 -neq -mult \
        -add 0 -gt ${ctx_mask_inFA}"

        task_exec

    fi

    if [[ ( "${K_flag}" -eq 1 || "${T_app}" -eq 5 || "${M_flag}" -eq 1 ) ]] && [[ -f ${subj_aseg_inFA} ]] && [[ ! -f ${WM_mask_inFA} ]]; then

        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} -quiet \
        ${subj_aseg_inFA} 2 -eq ${subj_aseg_inFA} 41 -eq -add 0 -gt ${WM_mask_inFA}"

        task_exec

    fi

    # -M: one-time per-subject rind-excluded tracking mask. Erodes the WHOLE
    # CSF-stripped brain mask by M_val passes rather than the cortex ribbon
    # specifically -- an earlier version eroded ctx_mask_inFA (cerebral + cerebellar
    # cortex) directly, and it was visually confirmed to be unusable: real cortex is
    # frequently only 1-2 voxels thick at 1.3mm, so eroding it doesn't shave a surface
    # layer, it eats the ENTIRE local ribbon cross-section wherever it's already thin
    # (most places), producing a patchy, wildly uneven mask rather than a clean shell.
    # Eroding the whole brain mask instead only has that same failure mode at
    # genuinely thin WHOLE-BRAIN structures -- corpus callosum, fornix, brainstem,
    # periventricular WM -- so those are added back explicitly afterward:
    #   - BStemr_custom / CC_allr_custom: existing custom_VOIs (aseg 16; FS CC labels
    #     250-255), already built by make_VOIs.sh and used throughout track_recipes_v2.
    #   - subj_FS_Fx_inFA: fornix, FreeSurfer's dedicated sub-segmentation, already a
    #     variable in this script (used for FS_fornix-atlas recipe VOIs).
    #   - periventric_protect_inFA: the ventricular system (lateral ventricles 4/43,
    #     inf-lat-vent 5/44, 3rd/4th ventricle 14/15, choroid plexus 31/63 -- the same
    #     label set already used elsewhere in this pipeline for ventricle/CSF
    #     identification) dilated by M_val passes -- matching the erosion depth exactly,
    #     since erosion reaches inward from the ventricular (internal CSF) boundary
    #     just as much as from the outer pial surface, and a fixed protection margin
    #     undershoots that at -M 2/3 (visually confirmed: growing gaps around the
    #     ventricles as M_val increased) -- intersected with the UNERODED base mask so
    #     it restores whatever tissue was there, not just WM specifically.
    brain_erode_inFA="${prep_d}/sub-${subj}${ses_str}_brain_erode${M_val}_inFA.nii.gz"

    periventric_protect_inFA="${prep_d}/sub-${subj}${ses_str}_periventric_protect${M_val}_inFA.nii.gz"

    tracking_mask_norind_inFA="${prep_d}/sub-${subj}${ses_str}_trackmask_norind${M_val}_inFA.nii.gz"

    if [[ "${M_flag}" -eq 1 ]] && [[ -f ${subj_aseg_inFA} ]] && [[ ! -f ${tracking_mask_norind_inFA} ]]; then

        if [[ -f "${T1_BM_inFA_minCSF}" ]]; then
            _tm_base="${T1_BM_inFA_minCSF}"
        else
            echo " WARNING: ${T1_BM_inFA_minCSF} not found — building -M's rind-excluded mask from the full brain mask instead" | tee -a ${prep_log2}
            _tm_base="${T1_brain_mask_inFA}"
        fi

        task_in="maskfilter -force -nthreads ${ncpu} -npass ${M_val} ${_tm_base} erode ${brain_erode_inFA}"

        task_exec

        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} -quiet \
        ${subj_aseg_inFA} 4 -eq ${subj_aseg_inFA} 43 -eq -add ${subj_aseg_inFA} 5 -eq -add ${subj_aseg_inFA} 44 -eq -add \
        ${subj_aseg_inFA} 14 -eq -add ${subj_aseg_inFA} 15 -eq -add ${subj_aseg_inFA} 31 -eq -add ${subj_aseg_inFA} 63 -eq -add \
        0 -gt - | maskfilter -force -nthreads ${ncpu} -npass ${M_val} - dilate - | mrcalc -force -datatype uint16 -quiet \
        ${_tm_base} - -mult 0 -gt ${periventric_protect_inFA}"

        task_exec

        # subj_FS_Fx_inFA is not itself a binary fornix mask -- it's the full
        # aseg-style label volume FS_fornix-atlas recipe entries are resolved
        # against, with fornix at label 250 specifically (see Fx_LT/RT.txt's own
        # "Fornix_Fx 250 FS_fornix" row). Treating any-nonzero as fornix here
        # first pulled in 635k voxels (more than the whole brain mask) and
        # silently undid nearly the entire erosion -- caught by comparing sizes
        # against the individual protective masks before trusting this task_in.
        task_in="mrcalc -force -datatype uint16 -nthreads ${ncpu} -quiet \
        ${brain_erode_inFA} ${ROIs_d}/custom_VOIs/BStemr_custom.nii.gz -add \
        ${ROIs_d}/custom_VOIs/CC_allr_custom.nii.gz -add ${subj_FS_Fx_inFA} 250 -eq -add \
        ${periventric_protect_inFA} -add 0 -gt ${_tm_base} -mult ${tracking_mask_norind_inFA}"

        task_exec

    fi

    # Find out tracking method of choice

    # echo "tracking application is ${T_app}"

    if [[ ! ${T_app} -eq 1 ]] && [[ ! ${T_app} -eq 4 ]] && [[ ! ${T_app} -eq 5 ]]; then

        echo " You have asked for whole brain tractography followed by segmentation " | tee -a ${prep_log2}

        if [[ ${T_app} -eq 2 ]]; then
            T="WB"
        elif [[ ${T_app} -eq 3 ]]; then
            T="WB_ACT"
        fi
        
        WB_tck="${TCKs_outd}/sub-${subj}${ses_str}_WB_TCKs_${T}_${algo_f}.tck"

        WB_tck_srch=($(find ${TCKs_outd} -type f -name "sub-${subj}${ses_str}_WB_TCKs_${T}_${algo_f}.tck"));

        SIFT_srch=($(find ${TCKs_outd} -type f -name "sub-${subj}${ses_str}_sift2_ws.txt"));

        if [[ -z ${WB_tck_srch} ]]; then

            echo " Whole brain tractogram not found, generating " | tee -a ${prep_log2}

            # task_in="tckgen -force -nthreads ${ncpu} ${tracking_string} -mask ${T1_BM_inFA_minCSF} -select 10000000 -angle 60 -maxlength 300 -minlength 20 ${tracking_source} ${WB_tck}"

            # task_exec

            if [[ ${T_app} -eq 3 ]]; then

                task_in="tckgen -force -nthreads ${ncpu} ${tracking_string} -mask ${T1_brain_mask_inFA} -select 10000000 -maxlength 300 -minlength 20 ${fod_cutoff_opt} ${tracking_source} ${WB_tck}"

                task_exec

            elif [[ ${T_app} -eq 2 ]]; then

                # No -act here (that's T_app 3), so nothing stops a streamline tunneling
                # through cortex once it reaches it -- same exposure bundle-specific
                # tracking has. Unlike a bundle's own VOIs (which include subcortical
                # waypoints like the dentate/thalamus/caudate that streamlines must be
                # able to pass through, not just terminate at), ctx_mask_inFA covers
                # cortex only, so -stop here only forces termination at the cortical
                # ribbon -- subcortical GM stays a pass-through waypoint for whichever
                # per-bundle -include chain filters this WB_tck afterward.
                task_in="tckgen -force -nthreads ${ncpu} ${tracking_string} -mask ${T1_BM_inFA_minCSF} -select 10000000 -maxlength 300 -minlength 20 ${fod_cutoff_opt} -include ${ctx_mask_inFA} -stop ${tracking_source} ${WB_tck}"

                task_exec
                
            fi

        else

            echo " Whole brain tractogram found, skipping to SIFT weights " | tee -a ${prep_log2}

        fi

        if [[ -z ${SIFT_srch} ]]; then

            if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

                echo " You have selected ${algo_f}, so we perform SIFT2 and use the weights during filtering " | tee -a ${prep_log2}

                task_in="tcksift2 -force -nthreads ${ncpu} ${WB_tck} ${subj_fod} ${TCKs_outd}/sub-${subj}${ses_str}_sift2_ws.txt"

                task_exec

                sift_str=" -tck_weights_in ${TCKs_outd}/sub-${subj}${ses_str}_sift2_ws.txt "

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

        KUL_dispatch_bundles

        echo "tracking source is ${tracking_source}"

    elif [[ ${T_app} -eq 1 ]] || [[ ${T_app} -eq 4 ]] || [[ ${T_app} -eq 5 ]]; then

        echo " You have asked for inidividual bundle tractography  " | tee -a ${prep_log2}

        KUL_dispatch_bundles

    fi

fi

# Assemble every bundle's QQ metrics into one bundle x metric summary and one
# spider plot per bundle. Runs once per subject, after every dispatched bundle's
# own QQ work (KUL_dispatch_bundles blocks on its own internal `wait` above) --
# needs every bundle's scores in hand before it can normalize each metric's axis.
if [[ "${Q_flag}" -eq 1 ]]; then

    echo " Assembling QQ metrics and generating spider plots per bundle " | tee -a ${prep_log2}

    task_in="KUL_FWT_bundle_spider_plot.py ${TCKs_outd} ${subj} ${ses_str}"
    task_exec

fi

# Single-page contact sheet of every bundle's screenshots, with the per-bundle
# spider pages linked from it when -Q also ran. Gated on S_flag because it has
# nothing to show without the screenshot step; it degrades to a warning rather
# than failing, like the other add-on outputs here.
if [[ "${S_flag}" -eq 1 ]]; then

    echo " Assembling the single-page bundle screenshot report " | tee -a ${prep_log2}

    if command -v KUL_FWT_bundle_report.py >/dev/null 2>&1; then
        task_in="KUL_FWT_bundle_report.py ${TCKs_outd} ${subj} ${ses_str}"
        task_exec
    else
        echo "WARNING: KUL_FWT_bundle_report.py not found, skipping the screenshot report" | tee -a ${prep_log2}
    fi

fi
