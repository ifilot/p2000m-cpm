#!/usr/bin/env python3
"""Build the P2000M FAT32/CP/M SD layout, optionally installing its kernel."""
import argparse
from pathlib import Path
import struct
from memory_layout import LAYOUT

SECTOR = 512
VOLUME_SIZE = 8 * 1024 * 1024
FAT_START = 2048
FAT_SECTORS = 64 * 1024 * 1024 // SECTOR
FAT_CLUSTER_SECTORS = 1
SD_DRIVES = 11
LABELS = ('SYSTEM', 'TOOLS', 'ZORK', 'CALC', 'BASIC', 'COBOL',
          'SOURCE', 'DOCS', 'DATA', 'GAMES', 'EXTRA 2')
STARTS = tuple(FAT_START + FAT_SECTORS + i * (VOLUME_SIZE // SECTOR)
               for i in range(SD_DRIVES))
IMAGE_SIZE = (STARTS[-1] + VOLUME_SIZE // SECTOR) * SECTOR
BLOCK = 4096
DIRECTORY_ENTRIES = 512
DIRECTORY_BLOCKS = 4
EXTENT_SIZE = 32768


def fat_geometry():
    # 512-byte clusters keep this 64 MiB volume above the FAT32 cluster minimum.
    # 32 reserved sectors, two FATs.
    fat_size = 1
    while True:
        clusters = (FAT_SECTORS - 32 - 2 * fat_size) // FAT_CLUSTER_SECTORS
        needed = ((clusters + 2) * 4 + SECTOR - 1) // SECTOR
        if fat_size >= needed:
            return fat_size, clusters
        fat_size = needed


def write_fat32(out):
    fat_size, clusters = fat_geometry()
    boot = bytearray(SECTOR)
    boot[:11] = b'\xeb\x58\x90P2000MSD'
    struct.pack_into('<HBHBHHBHHHII', boot, 11,
                     SECTOR, FAT_CLUSTER_SECTORS, 32, 2, 0, 0, 0xf8, 0, 63, 255,
                     FAT_START, FAT_SECTORS)
    struct.pack_into('<IHHIHH', boot, 36, fat_size, 0, 0, 2, 1, 6)
    boot[64] = 0x80
    boot[66] = 0x29
    struct.pack_into('<I', boot, 67, 0x50324d01)
    boot[71:82] = b'P2000M DATA'
    boot[82:90] = b'FAT32   '
    boot[90:94] = b'\xfa\xf4\xeb\xfd'  # Halt if a PC tries to execute the VBR.
    boot[510:512] = b'\x55\xaa'
    info = bytearray(SECTOR)
    struct.pack_into('<I', info, 0, 0x41615252)
    struct.pack_into('<III', info, 484, 0x61417272, clusters - 1, 3)
    struct.pack_into('<I', info, 508, 0xaa550000)
    for sector, data in ((0, boot), (1, info), (6, boot), (7, info)):
        out.seek((FAT_START + sector) * SECTOR)
        out.write(data)
    for copy in range(2):
        out.seek((FAT_START + 32 + copy * fat_size) * SECTOR)
        out.write(struct.pack('<III', 0x0ffffff8, 0xffffffff, 0x0fffffff))
    root = bytearray(32)
    root[:11] = boot[71:82]
    root[11] = 8  # Volume label, followed by the zero-filled directory terminator.
    out.seek((FAT_START + 32 + 2 * fat_size) * SECTOR)
    out.write(root)


def disk_name(path):
    name = Path(path).name.upper()
    parts = name.split('.')
    if len(parts) > 2 or not 1 <= len(parts[0]) <= 8:
        raise ValueError(f'Not a CP/M 8.3 filename: {name}')
    suffix = parts[1] if len(parts) == 2 else ''
    allowed = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'()-@^_`{}~"
    if len(suffix) > 3 or any(c not in allowed for c in parts[0] + suffix):
        raise ValueError(f'Not a CP/M 8.3 filename: {name}')
    return (parts[0].ljust(8) + suffix.ljust(3)).encode('ascii')


def make_volume(paths=()):
    volume = bytearray(b'\xe5' * VOLUME_SIZE)
    next_block, entry_index = DIRECTORY_BLOCKS, 0
    seen = set()
    for path in paths:
        name = disk_name(path)
        if name in seen:
            raise ValueError(f'Duplicate CP/M filename: {path}')
        seen.add(name)
        data = Path(path).read_bytes()
        for offset in range(0, max(1, len(data)), EXTENT_SIZE):
            chunk = data[offset:offset + EXTENT_SIZE]
            blocks = (len(chunk) + BLOCK - 1) // BLOCK
            if entry_index >= DIRECTORY_ENTRIES or next_block + blocks > VOLUME_SIZE // BLOCK:
                raise ValueError('CP/M volume is full')
            entry = bytearray(32)
            entry[1:12] = name  # user 0
            records = (len(chunk) + 127) // 128
            extent = offset // 16384 + (1 if records > 128 else 0)
            entry[12] = extent & 31
            entry[14] = extent >> 5
            entry[15] = records - (128 if records > 128 else 0)
            for i in range(blocks):
                struct.pack_into('<H', entry, 16 + 2 * i, next_block + i)
            begin = next_block * BLOCK
            volume[begin:begin + blocks * BLOCK] = b'\x1a' * (blocks * BLOCK)
            volume[begin:begin + len(chunk)] = chunk
            volume[entry_index * 32:(entry_index + 1) * 32] = entry
            next_block += blocks
            entry_index += 1
    return volume


def create_image(path, files_a=(), files_b=(), *, files_by_drive=None):
    # Validate and construct before opening the destination; never overwrite.
    files = {0: files_a, 1: files_b}
    if files_by_drive:
        if any(not isinstance(d, int) or not 0 <= d < SD_DRIVES for d in files_by_drive):
            raise ValueError('SD drive index must be 0..10 (A:..K:)')
        files.update(files_by_drive)
    volumes = [make_volume(files.get(d, ())) for d in range(SD_DRIVES)]
    mbr = bytearray(SECTOR)
    partitions = ((0x0c, FAT_START, FAT_SECTORS),
                  (0x52, STARTS[0], SD_DRIVES * VOLUME_SIZE // SECTOR))
    for i, (kind, start, size) in enumerate(partitions):
        struct.pack_into('<B3sB3sII', mbr, 446 + 16 * i,
                         0, b'\xfe\xff\xff', kind, b'\xfe\xff\xff', start, size)
    mbr[510:512] = b'\x55\xaa'
    with Path(path).open('xb') as out:
        out.truncate(IMAGE_SIZE)
        out.write(mbr)
        write_fat32(out)
        for start, volume in zip(STARTS, volumes):
            out.seek(start * SECTOR)
            out.write(volume)


def install_kernel(path, kernel):
    """Install the fixed-size kernel and integrity header in the alignment gap."""
    if len(kernel) != LAYOUT['kernel_bytes'] or kernel[3:11] != b'P2MCPM03':
        raise ValueError('Expected a signed 0.3 kernel (14 KiB)')
    header = bytearray(SECTOR)
    header[:8] = b'P2MSYS03'
    struct.pack_into('<HH', header, 8, len(kernel), sum(kernel) & 0xffff)
    with Path(path).open('r+b') as out:
        out.seek(15 * SECTOR)
        out.write(header)
        out.write(kernel)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--kernel', type=Path, help='Install a built 0.3 kernel')
    parser.add_argument('--a', nargs='*', default=[], metavar='FILE')
    parser.add_argument('--b', nargs='*', default=[], metavar='FILE')
    parser.add_argument('--drive', action='append', nargs='+', default=[], metavar='LETTER_OR_FILE',
                        help='Populate an SD drive: --drive C FILE... (A through K; repeatable)')
    args = parser.parse_args()
    try:
        kernel = args.kernel.read_bytes() if args.kernel else None
        if kernel is not None and (len(kernel) != LAYOUT['kernel_bytes'] or kernel[3:11] != b'P2MCPM03'):
            raise ValueError('Invalid kernel')
        files_by_drive = {}
        for group in args.drive:
            letter = group[0].upper().rstrip(':')
            if len(letter) != 1 or not 'A' <= letter <= 'K':
                raise ValueError('--drive expects A through K followed by files')
            files_by_drive.setdefault(ord(letter) - ord('A'), []).extend(group[1:])
        create_image(args.output, args.a, args.b, files_by_drive=files_by_drive)
        if kernel is not None:
            install_kernel(args.output, kernel)
    except (ValueError, OSError) as error:
        parser.exit(1, f'{error}\n')
    status = 'kernel installed' if args.kernel else 'data-only image'
    print(f'Created {args.output}: 64 MiB FAT32, eleven 8 MiB CP/M volumes A:..K:; {status}.')


if __name__ == '__main__':
    main()
