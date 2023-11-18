#!/usr/bin/env python3

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
    coords = np.vstack([x, y, z])

    # Calculate the centroid of the tract.
    centroid = np.mean(coords, axis=1)

    # Set the direction based on user choice or PCA
    if args.axis == 'x':
        direction = np.array([1, 0, 0])
    elif args.axis == 'y':
        direction = np.array([0, 1, 0])
    elif args.axis == 'z':
        direction = np.array([0, 0, 1])
    else:
        # Use PCA to determine the major axis of the tract.
        pca = PCA(n_components=1)
        pca.fit(coords.T)
        direction = pca.components_[0]
        direction /= np.linalg.norm(direction)

    # Calculate the projections of the tract voxels onto the major axis.
    projections = np.dot((coords.T - centroid), direction)
    min_proj, max_proj = np.min(projections), np.max(projections)
    scaled_projections = 1 + (num_segments - 1) * (projections - min_proj) / (max_proj - min_proj)

    if args.axis == 'pca' and pca.components_[0][np.argmax(np.abs(direction))] < 0:
        scaled_projections = num_segments - scaled_projections + 1

    # Round the scaled segment indices to the nearest integer.
    segments = np.round(scaled_projections).astype(int)
    segments_mask = np.zeros_like(mask)
    segments_mask[x, y, z] = segments

    # Save the segments to a NIfTI file.
    new_img = nib.Nifti1Image(segments_mask, img.affine)
    nib.save(new_img, output_path)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Divide a tractogram binary mask into segments.')
    parser.add_argument('-i', '--input_path', type=str, help='Path to the input binary mask file.')
    parser.add_argument('-o', '--output_dir', type=str, help='Directory for the output file.', default='.')
    parser.add_argument('-n', '--num_segments', type=int, help='Desired number of segments to generate.', default=100)
    parser.add_argument('--axis', default='pca', choices=['x', 'y', 'z', 'pca'],
                        help='Axis for segmentation (x, y, z, or pca). Default is pca.')

    args = parser.parse_args()
    output_path = os.path.join(args.output_dir, 'segments.nii.gz')
    divide_mask(args.input_path, output_path, args.num_segments)