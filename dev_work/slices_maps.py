#!/usr/bin/env python3

import numpy as np
import nibabel as nib
from concurrent.futures import ProcessPoolExecutor
import argparse
import os

def create_image(input_path, output_path):
    # Load the input image
    img = nib.load(input_path)

    # Get the shape of the image
    x, y, z = img.shape

    # Create an executor for parallel processing
    with ProcessPoolExecutor() as executor:
        # Create sagittal, coronal, and axial images
        for axis, name in zip([0, 1, 2], ['sagittal', 'coronal', 'axial']):
            # Create an empty 3D array with the same shape as the input image
            new_data = np.zeros((x, y, z))

            # Set the voxel values to the slice index
            slices = np.arange(img.shape[axis])
            indices = [np.s_[:]] * 3
            for s in slices:
                indices[axis] = s
                new_data[tuple(indices)] = s+1

            # Create a new Nifti image with the same header as the input image
            new_img = nib.Nifti1Image(new_data, img.affine, img.header)

            # Save the new image
            nib.save(new_img, os.path.join(output_path, f'{name}.nii.gz'))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Create sagittal, coronal, and axial images from a 3D NIfTI image.')
    parser.add_argument('-i', '--input', required=True, help='Path to the input NIfTI image.')
    parser.add_argument('-o', '--output', required=True, help='Path to the output directory.')

    args = parser.parse_args()
    create_image(args.input, args.output)
