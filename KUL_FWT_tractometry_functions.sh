#!/bin/bash
# KUL_FWT_tractometry_functions.sh
#
# Shared, SOURCED (not executed) tractometry logic for KUL_FWT_make_TCKs.sh and
# KUL_FWT_make_TCKs_4Temp.sh. Unifies all per-bundle metric profiling around
# dipy.stats.analysis.afq_profile (KUL_FWT_buan_profile.py) instead of the
# previous design of a separate MRtrix fixel-based 50-segment sampler for
# FA/ADC/AD/RD/TDI/Length/Curve plus an additive BUAN pass alongside it.
#
# Being sourced (not a subprocess), KUL_FWT_run_tractometry runs in the
# caller's own shell/variable scope. Caller must set, before calling it:
#   TCK_out, TCK_2_make, T, algo_f, subj, ses_str, prep_d, ncpu, prep_log2
#   tck_rs1_innat              - resampled bundle .tck (native space)
#   tck_filt5_centroid1        - bundle centroid .tck (scil_bundle_compute_centroid)
#   tractometry_reference_nii  - .nii.gz reference for the .tck (e.g. subj_FA or temp_fod1)
#   buan_metrics[] / buan_scalars[] - plain scalar metric names + their .nii.gz sources
#     (e.g. FA/ADC/AD/RD/TDI/Length/Curve, or just TDI/Length/Curve)
#
# For iFOD1/iFOD2/SD_Stream, also profiles the fixel-only metrics (FD/Disp/Peaks/
# FC/logFC/FDC): this bundle's own fixels are isolated from the whole-brain
# prep_d/fixel_metrics via tck2fixel, masked to the bundle, then collapsed to a
# plain per-voxel scalar via `fixel2voxel ... mean` (most voxels along a single
# bundle have exactly one relevant fixel) so they can be profiled identically to
# every other metric. No population-level fixel smoothing (fixelconnectivity/
# fixelfilter) is applied — that machinery gets its statistical meaning from
# connectivity-based enhancement across subjects (fixelcfestats), which doesn't
# apply within a single subject's own bundle; afq_profile's own cross-streamline
# averaging at each node is the noise reduction here.

function KUL_FWT_run_tractometry {

    local metrics=("${buan_metrics[@]}")
    local scalars=("${buan_scalars[@]}")

    if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

        # isolate this bundle's own fixels out of the whole-brain fixel_metrics dir
        task_in="tck2fixel ${tck_rs1_innat} ${prep_d}/fixel_metrics ${TCK_out}/QQ/tmp/${TCK_2_make}_native_fixels ${TCK_2_make}_native_fixels.mif -nthreads $ncpu -force"
        task_exec

        # whole-bundle mask straight from the TDI footprint (no scil_bundle_label_map needed)
        task_in="mrcalc ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi.nii.gz 0 -gt -nan ${TCK_out}/QQ/tmp/${TCK_2_make}_bundle_mask_nan.nii.gz -force"
        task_exec

        task_in="voxel2fixel -force ${TCK_out}/QQ/tmp/${TCK_2_make}_bundle_mask_nan.nii.gz ${TCK_out}/QQ/tmp/${TCK_2_make}_native_fixels ${TCK_out}/QQ/tmp/${TCK_2_make}_fixelized_bundle_mask ${TCK_2_make}_bundle_mask_nan.mif"
        task_exec

        local fixel_names=("${subj_ffd}" "${subj_fdisp}" "${subj_fpk}" "${subj_ffc}" "${subj_flogfc}" "${subj_ffdc}")
        local fixel_labels=("FD" "Disp" "Peaks" "FC" "logFC" "FDC")

        for i in "${!fixel_names[@]}"; do
            local masked="${TCK_out}/QQ/tmp/${TCK_2_make}_${fixel_labels[$i]}_masked.mif"
            local voxelized="${TCK_out}/QQ/tmp/${TCK_2_make}_${fixel_labels[$i]}_voxel.nii.gz"

            task_in="mrcalc ${prep_d}/fixel_metrics/${fixel_names[$i]} ${TCK_out}/QQ/tmp/${TCK_2_make}_fixelized_bundle_mask/${TCK_2_make}_bundle_mask_nan.mif -mult ${masked} -force"
            task_exec

            task_in="fixel2voxel ${masked} mean ${voxelized} -force"
            task_exec

            metrics+=("${fixel_labels[$i]}")
            scalars+=("${voxelized}")
        done

    fi

    for met in "${!metrics[@]}"; do
        local out_txt="${TCK_out}/QQ/sub-${subj}${ses_str}_${metrics[$met]}_scores_${TCK_2_make}.txt"
        local out_pdf="${TCK_out}/QQ/sub-${subj}${ses_str}_${metrics[$met]}_scores_${TCK_2_make}_plot.pdf"
        local plot_title="sub-${subj}${ses_str}_${TCK_2_make}_${metrics[$met]}"
        task_in="KUL_FWT_buan_profile.py ${tck_rs1_innat} ${tractometry_reference_nii} ${scalars[$met]} \
            ${metrics[$met]} ${out_txt} --n-points 50 --orient-by-tck ${tck_filt5_centroid1} \
            --plot-pdf ${out_pdf} --plot-title ${plot_title}"
        task_exec &
    done

}
