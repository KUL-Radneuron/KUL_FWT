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
#   buan_metrics[] / buan_scalars[] - plain scalar metric names + their .nii.gz sources,
#     built by the caller via repeated KUL_FWT_add_metric_if_present calls against its
#     full candidate set (FA/ADC/AD/RD/TDI/Length/Curve/LoRE-SD contrasts/...). Whichever
#     of those actually exist on disk for this subject is whatever gets profiled -- QQ
#     was never meant to require every possible metric, just to use what it's given.
#
# For iFOD1/iFOD2/SD_Stream, also profiles the fixel-only metrics (FD/Disp/Peaks), but
# only if prep_d/fixel_metrics actually has them -- e.g. a -Q-less prior run, or a
# deliberately trimmed fixel-generation block, means it won't, and that's not fatal to
# the rest of tractometry, just to those 3 metrics. When present: this bundle's own
# fixels are isolated from the whole-brain prep_d/fixel_metrics via tck2fixel, masked to
# the bundle, then collapsed to a plain per-voxel scalar via `fixel2voxel ... mean` (most
# voxels along a single bundle have exactly one relevant fixel) so they can be profiled
# identically to every other metric. FC/logFC/FDC are deliberately excluded: they come
# from warp2metric -fc, which quantifies a fixel's cross-sectional area change relative
# to a *population* template (Raffelt et al. FBA) -- meaningless without a cohort to
# compare against, which a single clinical subject doesn't have. No population-level
# fixel smoothing (fixelconnectivity/fixelfilter) is applied either -- that machinery
# gets its statistical meaning from connectivity-based enhancement across subjects
# (fixelcfestats), which doesn't apply within a single subject's own bundle; afq_profile's
# own cross-streamline averaging at each node is the noise reduction here.

# Appends (name, scalar_path) to the caller's buan_metrics/buan_scalars arrays only if
# scalar_path exists, logging a skip note otherwise. Lets a caller declare its whole
# candidate metric set unconditionally without every call site needing its own
# existence check, and keeps tractometry from ever depending on any single metric.
function KUL_FWT_add_metric_if_present {
    local name="$1"
    local scalar_path="$2"

    if [[ -f "${scalar_path}" ]]; then
        buan_metrics+=("${name}")
        buan_scalars+=("${scalar_path}")
    else
        echo " metric ${name} not found (${scalar_path}), skipping" | tee -a ${prep_log2}
    fi
}

function KUL_FWT_run_tractometry {

    local metrics=("${buan_metrics[@]}")
    local scalars=("${buan_scalars[@]}")

    if [[ ${algo_f} == "iFOD2" ]] || [[ ${algo_f} == "iFOD1" ]] || [[ ${algo_f} == "SD_Stream" ]]; then

        local fixel_names=("${subj_ffd}" "${subj_fdisp}" "${subj_fpk}")
        local fixel_labels=("FD" "Disp" "Peaks")
        local fixels_available=1
        local fn

        for fn in "${fixel_names[@]}"; do
            [[ -f "${prep_d}/fixel_metrics/${fn}" ]] || fixels_available=0
        done

        if [[ "${fixels_available}" -eq 1 ]]; then

            # isolate this bundle's own fixels out of the whole-brain fixel_metrics dir
            task_in="tck2fixel ${tck_rs1_innat} ${prep_d}/fixel_metrics ${TCK_out}/QQ/tmp/${TCK_2_make}_native_fixels ${TCK_2_make}_native_fixels.mif -nthreads $ncpu -force"
            task_exec

            # whole-bundle mask straight from the TDI footprint (no scil_bundle_label_map
            # needed). Plain 0/1 (not -nan-filled): voxel2fixel broadcasts this to every
            # fixel in a voxel, then mrcalc multiplies it into the whole-brain fixel data,
            # and afq_profile samples the resulting voxelized map with trilinear
            # interpolation -- any NaN neighbouring a real value poisons the interpolated
            # result, and a thin tube-shaped bundle mask puts nearly every along-tract
            # sample point next to the mask boundary. Verified directly: trilinear
            # sampling of the old -nan-filled map was ~29% NaN at the raw per-point level
            # (0% for nearest-neighbour at the same points), enough to poison every one of
            # afq_profile's weighted segment averages and return 100% NaN profiles despite
            # the underlying masked fixel data being fine. 0-fill instead just tapers
            # smoothly to background at the boundary, same as any other masked metric here.
            task_in="mrthreshold ${TCK_out}/QQ/${TCK_2_make}_fin_${T}_${algo_f}_tdi.nii.gz -abs 0.0 -comparison gt ${TCK_out}/QQ/tmp/${TCK_2_make}_bundle_mask.nii.gz -force"
            task_exec

            task_in="voxel2fixel -force ${TCK_out}/QQ/tmp/${TCK_2_make}_bundle_mask.nii.gz ${TCK_out}/QQ/tmp/${TCK_2_make}_native_fixels ${TCK_out}/QQ/tmp/${TCK_2_make}_fixelized_bundle_mask ${TCK_2_make}_bundle_mask.mif"
            task_exec

            for i in "${!fixel_names[@]}"; do
                local masked="${TCK_out}/QQ/tmp/${TCK_2_make}_fixelized_bundle_mask/${TCK_2_make}_${fixel_labels[$i]}_masked.mif"
                local voxelized="${TCK_out}/QQ/tmp/${TCK_2_make}_${fixel_labels[$i]}_voxel.nii.gz"

                task_in="mrcalc ${prep_d}/fixel_metrics/${fixel_names[$i]} ${TCK_out}/QQ/tmp/${TCK_2_make}_fixelized_bundle_mask/${TCK_2_make}_bundle_mask.mif -mult ${masked} -force"
                task_exec

                task_in="fixel2voxel ${masked} mean ${voxelized} -force"
                task_exec

                metrics+=("${fixel_labels[$i]}")
                scalars+=("${voxelized}")
            done

        else
            echo " fixel metrics not found in ${prep_d}/fixel_metrics -- skipping FD/Disp/Peaks for ${TCK_2_make}" | tee -a ${prep_log2}
        fi

    fi

    for met in "${!metrics[@]}"; do
        local out_txt="${TCK_out}/QQ/sub-${subj}${ses_str}_${metrics[$met]}_scores_${TCK_2_make}.txt"
        local out_pdf="${TCK_out}/QQ/sub-${subj}${ses_str}_${metrics[$met]}_scores_${TCK_2_make}_plot.pdf"
        local plot_title="sub-${subj}${ses_str}_${TCK_2_make}_${metrics[$met]}"
        task_in="KUL_FWT_buan_profile.py ${tck_rs1_innat} ${tractometry_reference_nii} ${scalars[$met]} \
            ${metrics[$met]} ${out_txt} --n-points 20 --orient-by-tck ${tck_filt5_centroid1} \
            --plot-pdf ${out_pdf} --plot-title ${plot_title}"
        task_exec &
    done

    # Wait for every backgrounded per-metric profiling job above before returning, so the
    # caller's QQ_done.done marker (touched only if this function returns success) can never
    # be written while a profiling job is still running or was silently lost.
    local qq_fail=0
    local _j
    for _j in $(jobs -p); do
        wait "$_j" || qq_fail=1
    done
    if [ "$qq_fail" -ne 0 ]; then
        echo "ERROR: one or more tractometry profiling jobs failed for ${TCK_2_make} (see per-metric task_exec output above)" | tee -a ${prep_log2}
        return 1
    fi

}
