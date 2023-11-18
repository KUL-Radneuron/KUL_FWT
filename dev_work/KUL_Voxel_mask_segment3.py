#!/usr/bin/env python3
# need to make sure that segment sizes are comparable!
# need condition not to go below a certain voxel count maybe?

import numpy as np
import os
import argparse
import nibabel as nib
from sklearn.decomposition import PCA


def divide_mask(input_path, output_path, num_segments):
    # Load the binary mask.
    img = nib.load(input_path)
    mask = img.get_fdata()

    # Generate the coordinates of the tract voxels.
    x, y, z = np.where(mask == 1)

    # Stack the coordinates together.
    coords = np.vstack([x, y, z])

    # Use PCA to find the major axis of the tract.
    pca = PCA(n_components=1)
    pca.fit(coords.T)

    # Calculate the direction of the tract.
    direction = pca.components_[0]

    # Create a unit vector for the direction.
    direction /= np.linalg.norm(direction)

    # Check which axis of the image the principal component aligns with.
    axis = np.argmax(np.abs(direction))

    # Define the direction vector based on the axis.
    if axis == 0:  # x-axis
        direction = np.array([1, 0, 0])
    elif axis == 1:  # y-axis
        direction = np.array([0, 1, 0])
    elif axis == 2:  # z-axis
        direction = np.array([0, 0, 1])

    # Calculate the centroid of the tract.
    centroid = np.mean(coords, axis=1)

    # Calculate the projections of the tract voxels onto the major axis.
    projections = np.dot((coords.T - centroid), direction)

    # Calculate the min and max projections to determine the length of the tract.
    min_proj, max_proj = np.min(projections), np.max(projections)

    # Scale the projections to range from 1 to num_segments.
    scaled_projections = 1 + (num_segments - 1) * (projections - min_proj) / (max_proj - min_proj)

    # If the principal component's direction is negative, reverse the order.
    if pca.components_[0][axis] < 0:
        scaled_projections = num_segments - scaled_projections + 1

    # Round the scaled segment indices to the nearest integer.
    segments = np.round(scaled_projections).astype(int)

    # Create a new mask with segment values and set background to 0.
    segments_mask = np.zeros_like(mask)
    segments_mask[x, y, z] = segments

    # Save the segments to a NIfTI file.
    new_img = nib.Nifti1Image(segments_mask, img.affine)
    nib.save(new_img, output_path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Divide a tractogram binary mask into 100 equal segments.')
    parser.add_argument('-i', '--input_path', type=str, help='Path to the input binary mask file.')
    parser.add_argument('-o', '--output_dir', type=str, help='Directory for the output file.', default='.')
    parser.add_argument('-n', '--num_segments', type=int, help='Desired number of segments to generate, default is 100.', default='100')

    args = parser.parse_args()
    
    output_path = os.path.join(args.output_dir, 'segments.nii.gz')

    # Call the function with your specific paths
    divide_mask(args.input_path, output_path, args.num_segments)