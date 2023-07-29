#!/usr/bin/env python3

import pandas as pd
import matplotlib.pyplot as plt
import argparse
import os
from pdf2image import convert_from_path

def plot_mean_values(input_file, output_file, image_pdf):

    os.system('export QT_DEBUG_PLUGINS=1')
    # Load the data from the text file
    data = pd.read_csv(input_file, sep=",")

    # Strip whitespaces from column names
    data.columns = data.columns.str.strip()

    # Handle missing values by dropping the rows that contain them
    # data = data.dropna()
    # Strip whitespaces from data
    data = data.apply(lambda x: x.str.strip() if x.dtype == "object" else x)

    # Strip whitespaces from column names
    data.columns = data.columns.str.strip()

    # strip white spaces from data
    data = data.apply(lambda x: x.str.strip() if x.dtype == "object" else x)

    # Handle missing values by replacing empty strings with NaN and dropping rows that contain them
    data.replace("", pd.NA, inplace=True)
    # data.dropna(inplace=True)

    # get names
    base_name = os.path.basename(input_file)
    bundle = base_name.split('scores_')[1].split('.')[0]
    metric = 'Mean_' + base_name.split('_')[1]

    # # Split the 'Segments, Mean_FDC' column into two separate columns
    # data[['Segments', metric]] = data[data.columns[0]].str.split(',', expand=True)

    # Convert the 'Segments' and 'Mean_metric' columns to numeric
    data['Segments'] = pd.to_numeric(data['Segments'])
    data[metric] = pd.to_numeric(data[metric])

    # # Drop the original first column
    # data = data.drop(columns=data.columns[0])

    # Convert PDF to PNG
    images = convert_from_path(image_pdf)

    # Create a figure and two subplots (axes): one for the plot and one for the image
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 10))

    # Create line plot in the first subplot
    ax1.plot(data['Segments'], data[metric])

    # Set title and labels for axes
    plot_title = f"{metric} Values by Segment for {bundle}"
    ax1.set_title(plot_title)
    ax1.set_xlabel("Segments")
    ax1.set_ylabel(f"{metric} Value")

    # Add image to the second subplot
    ax2.imshow(images[0])
    ax2.axis('off')  # Hide axes for the image subplot

    # Save the plot to a PDF file
    plt.savefig(output_file)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Plot values from text file.')
    parser.add_argument('input_file', type=str, help='Input text file.')
    parser.add_argument('output_file', type=str, help='Output PDF file.')
    parser.add_argument('image_pdf', type=str, help='PDF file for image to insert.')
    args = parser.parse_args()

    plot_mean_values(args.input_file, args.output_file, args.image_pdf)
