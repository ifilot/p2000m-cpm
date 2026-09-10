#!/usr/bin/env python3
"""Create an upgraded copy of a 0.1/0.2 SD image, preserving its files/partitions."""
import argparse
from pathlib import Path
import shutil
import struct

from memory_layout import LAYOUT
from sd_image import FAT_START, FAT_SECTORS, STARTS, SD_DRIVES, VOLUME_SIZE, SECTOR, IMAGE_SIZE, install_kernel


def upgrade(source, destination, kernel_path):
    if not source.is_file():
        raise ValueError('Source must be a regular image file, not a physical device')
    kernel = kernel_path.read_bytes()
    if len(kernel) != LAYOUT['kernel_bytes'] or kernel[3:11] != b'P2MCPM02':
        raise ValueError('Expected a version 0.2 kernel')
    with source.open('rb') as old:
        mbr = old.read(512)
        if (len(mbr) != 512 or mbr[510:] != b'\x55\xaa' or
                mbr[450] != 12 or mbr[466] != 82 or
                struct.unpack_from('<II', mbr, 454) != (FAT_START, FAT_SECTORS) or
                struct.unpack_from('<II', mbr, 470) != (STARTS[0], SD_DRIVES * VOLUME_SIZE // SECTOR) or
                mbr[478:510] != bytes(32) or source.stat().st_size < IMAGE_SIZE):
            raise ValueError('Source does not have the supported eleven-volume SD layout')
        old.seek(0)
        # Exclusive creation: never replace the source or an existing destination.
        with destination.open('xb') as new:
            shutil.copyfileobj(old, new, 1024 * 1024)
    install_kernel(destination, kernel)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--kernel', type=Path, default=Path(__file__).resolve().parents[1] / 'build/kernel.bin')
    args = parser.parse_args()
    try:
        upgrade(args.source, args.destination, args.kernel)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
    print(f'Created {args.destination}; source unchanged. Also install the matching 0.2 ROM.')


if __name__ == '__main__':
    main()
