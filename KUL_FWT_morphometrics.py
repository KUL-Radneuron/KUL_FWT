#!/usr/bin/env python3

# This is an automated command line tool to calculate morphological features of tractograms
# This is based on: https://doi.org/10.1016/j.neuroimage.2020.117329
# Robert Pretorius @ robert.w.pretorius@gmail.com
# Ahmed Radwan @ ahmed.radwan@kuleuven.be, radwanphd@gmail.com

import numpy as np
from numpy.linalg import norm
from skimage.measure import marching_cubes, mesh_surface_area
from dipy.tracking.utils import density_map
import nibabel as nib
import nibabel.streamlines as nibs
import argparse
import csv

def streamline2volume(tract, reference_vol):
    """Generates bundle volume from streamline file
    Args:
        tract (.tck): tck tract file for one side as found in init args
    Returns:
        output_vol(numpy array): array with binarized tract volume
    """

    # load reference nii and get the correct reference dimensions out of it
    reference = reference_vol
    ref_affine = reference.affine
    ref_dim = reference.header["dim"][1:4]

    # load individual streamlines from the tract file
    streamlines = tract.tractogram.streamlines

    # transform streamlines to volume with dipy module
    tract_vol = density_map(
        streamlines, affine=ref_affine, vol_dims=ref_dim)

    output_vol = np.where(tract_vol > 0.5, 1, 0)  # binarize the volume

    return output_vol

def stream_length(stream):
    """Calculates length of individual stream.
    calculates lenght of a stream as part of calculating tract length in:
    https://doi.org/10.1016/j.neuroimage.2020.117329 - table 1
    This function is needed to succesfully run some of the following
    functions that depend on individual stream lenghts.
    Args:
        stream (numpy array): individual stream as is found in the .tck
            files if you iterate over tract.streamlines.
    Returns:
        stream_sum(float): The length of the stream
    """

    stream_sum = 0
    for tt in range(stream.shape[0]-1):
        stream_sum += norm(stream[tt]-stream[tt+1])
    return stream_sum

def tract_length(tract):
    """Calculates average length of the tract
    calculates lenght of a tract as part of calculating tract length in:
    https://doi.org/10.1016/j.neuroimage.2020.117329 - table 1
    This basically takes the average length of individual stream lenghts
    within a tract
    Args:
        tract (.tck): see above
    Returns:
        tract_length(float): average length of the tract
    """

    tract_streams = tract.streamlines
    stream_sums = []
    for stream in tract_streams:
        stream_sums.append(stream_length(stream))

    output = np.mean(stream_sums)
    return output

def tract_span(tract):
    """Calculates the span of the tract
    calculates span of a tract as part of calculating metric described in:
    https://doi.org/10.1016/j.neuroimage.2020.117329 - table 1
    This basically takes the mean of the distances between the starting
    points and ending points of the individual streams.
    Args:
        tract (.tck): see above
    Returns:
        tract_span(flaot): span of the tract
    """
    tract_streams = tract.streamlines
    span_sums = []
    for stream in tract_streams:
        span_sums.append(norm(stream[0] - stream[-1]))
    tract_span = np.mean(span_sums)

    return tract_span

def tract_diameter(tract, tract_vol):
    """Calculates diameter of tract
    calculates span of a tract as part of calculating metric described in:
    https://doi.org/10.1016/j.neuroimage.2020.117329 - table 1
    Basically simplifies the tract as a cilinder and calculates a diameter
    based on the tract lenght and tract volume.
    Args:
        tract (.tck): see above
        tract_vol (numpy_array): see above
    Returns:
        tract_diameter(float): the diameter of the tract
    """
    length_metric = tract_length(tract)
    N_voxels = np.sum(tract_vol)
    volume = N_voxels
    diameter = 2*np.sqrt(volume / (np.pi*length_metric))
    return diameter

def tract_surface_area(tract_vol):
    """Calculates surface area of the tract
    Where the reference publication
    (https://doi.org/10.1016/j.neuroimage.2020.117329)
    uses voxel spacing to calculate the suface volume of the tract
    we use a marching cubes algorithm to approximage a surface mesh of the
    bundle and then calculate the  area of that surface mesh.
    Args:
        tract_vol (numpy_array): see above
    Returns:
        surface_area(float): surface area of tract
    """

    verts, faces, _, _ = marching_cubes(tract_vol)
    surface_area = mesh_surface_area(verts, faces)
    return surface_area

def calculate_metrics(tract, tract_vol):
    """Calculates all the metrics for a bundle and stores them in a dictionary
    Args:
        tract (.tck): tract file of one side of the bundle of interest
        tract_vol (numpy array): 3d array of binarized tract volume (see
            streamline2volume function)
    Returns:
        metrics_dict(dict):
    """

    # Calculate all the metrics and assign to variables
    length_metric = tract_length(tract)
    span_metric = tract_span(tract)
    curl_metric = length_metric / span_metric
    diameter_metric = tract_diameter(tract, tract_vol)
    elongation_metric = length_metric / diameter_metric
    volume_metric = np.sum(tract_vol)
    surface_area_metric = tract_surface_area(tract_vol)
    irregularity_metric = surface_area_metric / \
        (np.pi*diameter_metric*length_metric)

    # Construct final dictionary to output
    metrics_dict = {'tract_length': float(length_metric),
                    'tract_span': float(span_metric),
                    'tract_curl': float(curl_metric),
                    'tract_diameter': float(diameter_metric),
                    'tract_elongation': float(elongation_metric),
                    'tract_volume': float(volume_metric),
                    'tract_surface_area': float(surface_area_metric),
                    'tract_irregularity': float(irregularity_metric),
                    }

    return metrics_dict


# if both tracts are given we calculate ratios betwen them
def calculate_ratios(metrics_L, metrics_R):
    """Calculates all the L/R ratios for metrics of a pair of lateralized bundles and stores them in a dictionary
    Args:
        tract (.tck): tract file of one side of the bundle of interest
        tract_vol (numpy array): 3d array of binarized tract volume (see
            streamline2volume function)
    Returns:
        metrics_dict(dict):
    """
    ratios = {}
    for key in metrics_L.keys():
        if key in metrics_R:
            ratios[key + "_ratio"] = metrics_L[key] / metrics_R[key]
    return ratios

def dict_append_suffix(d: dict, suffix: str):
    """Adds a suffix to all dictionary keys
    This is a helper function to make sure the dictionary keys are named
    correctly before they are integrated into a dataframe.
    Args:
        d (dict): dictionary where you want to add suffix
        suffix (str): suffix you want to add
    Returns:
        (dict): dictionary with update suffixes
    """

    old_keys = list(d.keys())

    for ii in range(len(old_keys)):
        old_key = old_keys[ii]
        new_key = old_key+suffix

        d[new_key] = d[old_key]
        d.pop(old_key)
    return d

# updated to handle L and R, L or R, and no input 
if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Automated tool to calculate morphological features of left and/or right brain tractograms. The script can process either or both tracts and provide metrics such as span mm, length mm, volume mm³, diameter mm, and surface area mm². Optionally, it calculates ratios of these metrics between left and right tracts if both are provided.",
        epilog="Output Format: The script outputs a CSV file containing the calculated metrics. The CSV file has columns for metric names, values for the left tract, right tract, and their ratios. Metrics are in units based on the input data's spatial resolution (typically in mm, mm², or mm³)."
    )
    parser.add_argument("reference_nii", help="Path to the reference NIFTI file")
    parser.add_argument("--left_tract", help="Path to the left tract TCK file", default=None)
    parser.add_argument("--right_tract", help="Path to the right tract TCK file", default=None)
    parser.add_argument("--output", help="Name of the output CSV file", default="tract_metrics_output.csv")

    try:
        args = parser.parse_args()

        # Check if at least one tractogram is provided
        if not args.left_tract and not args.right_tract:
            print("Error: At least one tractogram input (left or right) is required.")
            parser.print_help()
            exit(1)

        reference_nii = nib.load(args.reference_nii)
        metrics_L = metrics_R = ratio_metrics = None

        # Process left tract
        if args.left_tract:
            left_tck = nibs.load(args.left_tract)
            vol_L = streamline2volume(left_tck, reference_nii)
            metrics_L = calculate_metrics(left_tck, vol_L)
            print("Left Tract Metrics:", metrics_L)

        # Process right tract
        if args.right_tract:
            right_tck = nibs.load(args.right_tract)
            vol_R = streamline2volume(right_tck, reference_nii)
            metrics_R = calculate_metrics(right_tck, vol_R)
            print("Right Tract Metrics:", metrics_R)

        # Calculate and print ratios if both tracts are provided
        if metrics_L and metrics_R:
            ratio_metrics = calculate_ratios(metrics_L, metrics_R)
            print("Ratios Between Left and Right Tracts:", ratio_metrics)

        # Write output to CSV
        with open(args.output, 'w', newline='') as csvfile:
            fieldnames = ['Metric', 'Left Tract', 'Right Tract', 'Ratio (L/R)']
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

            writer.writeheader()

            # All possible metrics that could be in the dictionaries
            all_metrics = set(metrics_L.keys()) | set(metrics_R.keys()) if metrics_L and metrics_R else metrics_L.keys() if metrics_L else metrics_R.keys()

            for metric in all_metrics:
                left_value = metrics_L.get(metric, 'N/A') if metrics_L else 'N/A'
                right_value = metrics_R.get(metric, 'N/A') if metrics_R else 'N/A'
                ratio_value = ratio_metrics.get(metric + "_ratio", 'N/A') if ratio_metrics else 'N/A'

                writer.writerow({
                    'Metric': metric,
                    'Left Tract': left_value,
                    'Right Tract': right_value,
                    'Ratio (L/R)': ratio_value
                })

    except argparse.ArgumentError as e:
        print("Error:", str(e))
        parser.print_help()
    parser = argparse.ArgumentParser(
        description="Automated tool to calculate morphological features of left and/or right brain tractograms. The script can process either or both tracts and provide metrics such as span mm, length mm, volume mm³, diameter mm, and surface area mm². Optionally, it calculates ratios of these metrics between left and right tracts if both are provided.",
        epilog="Output Format: The script outputs a CSV file containing the calculated metrics. The CSV file has columns for metric names, values for the left tract, right tract, and their ratios. Metrics are in units based on the input data's spatial resolution (typically in mm, mm², or mm³)."
    )
    parser.add_argument("reference_nii", help="Path to the reference NIFTI file")
    parser.add_argument("--left_tract", help="Path to the left tract TCK file", default=None)
    parser.add_argument("--right_tract", help="Path to the right tract TCK file", default=None)
    parser.add_argument("--output", help="Name of the output CSV file", default="tract_metrics_output.csv")

    try:
        args = parser.parse_args()

        # Check if at least one tractogram is provided
        if not args.left_tract and not args.right_tract:
            print("Error: At least one tractogram input (left or right) is required.")
            parser.print_help()
            exit(1)

        reference_nii = nib.load(args.reference_nii)
        metrics_L = metrics_R = None

        # Process left tract
        if args.left_tract:
            left_tck = nibs.load(args.left_tract)
            vol_L = streamline2volume(left_tck, reference_nii)
            metrics_L = calculate_metrics(left_tck, vol_L)
            print("Left Tract Metrics:", metrics_L)

        # Process right tract
        if args.right_tract:
            right_tck = nibs.load(args.right_tract)
            vol_R = streamline2volume(right_tck, reference_nii)
            metrics_R = calculate_metrics(right_tck, vol_R)
            print("Right Tract Metrics:", metrics_R)

        # Calculate and print ratios if both tracts are provided
        if metrics_L and metrics_R:
            ratio_metrics = calculate_ratios(metrics_L, metrics_R)
            print("Ratios Between Left and Right Tracts:", ratio_metrics)

    except argparse.ArgumentError as e:
        print("Error:", str(e))
        parser.print_help()