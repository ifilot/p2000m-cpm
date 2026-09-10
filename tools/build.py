#!/usr/bin/env python3
"""Build the original assembly cartridge and SD-loaded kernel."""
from pathlib import Path
import subprocess
import argparse
import gzip
import hashlib
import json
from sd_image import create_image, install_kernel
from build_metadata import generate

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
CARTRIDGE_SIZE = 16 * 1024
CORE_NAMES = ('asm', 'ddt', 'dump', 'ed', 'load', 'pip', 'stat')
CORE_FILES = [ROOT / 'assets/cpm_core' / (name + '.com') for name in CORE_NAMES]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zork-dir', type=Path, default=Path('/mnt/d/PROGRAMMING/p2000c/p2000c-cpm-transfer/programs/games/zork'))
    args = parser.parse_args()
    zork = [args.zork_dir / f'ZORK{i}.{ext}' for i in (1, 2, 3) for ext in ('COM', 'DAT')]
    for path in zork:
        if not path.is_file():
            parser.error(f'Missing Zork file: {path}; specify --zork-dir')
    BUILD.mkdir(exist_ok=True)
    metadata = generate(ROOT)
    for name in ('cartridge', 'kernel'):
        subprocess.run(['z80asm', '-I', str(ROOT / 'src'), '-I', str(BUILD / 'generated'), '-o', str(BUILD / f'{name}.bin'),
                        str(ROOT / 'src' / f'{name}.asm')], check=True)
    cartridge = bytearray((BUILD / 'cartridge.bin').read_bytes())
    if len(cartridge) > CARTRIDGE_SIZE:
        raise ValueError('Cartridge exceeds 16 KiB')
    cartridge.extend(b'\x00' * (CARTRIDGE_SIZE - len(cartridge)))
    # The monitor checks the bytes following the five-byte header.
    cartridge[1:3] = (CARTRIDGE_SIZE - 5).to_bytes(2, 'little')
    cartridge[3:5] = (-sum(cartridge[5:]) & 0xffff).to_bytes(2, 'little')
    (BUILD / 'cartridge.bin').write_bytes(cartridge)
    kernel = (BUILD / 'kernel.bin').read_bytes()
    if len(kernel) != 16384:
        raise ValueError('Kernel must be exactly 16 KiB')
    for program in ('hello', 'cpmtest', 'copy', 'ramtest', 'sync'):
        subprocess.run(['z80asm', '-I', str(ROOT / 'programs'), '-o', str(BUILD / (program.upper() + '.COM')),
                        str(ROOT / 'programs' / (program + '.asm'))], check=True)
    # Rebuildable output only; don't overwrite the user's persistent SD image.
    image = BUILD / 'p2000m-sd-template.img'
    image.unlink(missing_ok=True)
    create_image(image, [BUILD / "HELLO.COM", BUILD / "CPMTEST.COM", BUILD / "COPY.COM", BUILD / "RAMTEST.COM", BUILD / "SYNC.COM"] + CORE_FILES,
                 files_by_drive={2: zork})
    install_kernel(image, kernel)
    # Deterministic gzip envelope; SOURCE_DATE_EPOCH fixes embedded timestamps.
    with image.open('rb') as source, (BUILD / 'p2000m-sd-template.img.gz').open('wb') as target:
        with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as archive:
            while chunk := source.read(1024 * 1024):
                archive.write(chunk)
    metadata['zork_sources'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in zork}
    (BUILD / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
    outputs = ['cartridge.bin', 'kernel.bin', 'p2000m-sd-template.img', 'p2000m-sd-template.img.gz', 'build-info.json',
               'HELLO.COM', 'COPY.COM', 'CPMTEST.COM', 'RAMTEST.COM', 'SYNC.COM']
    checksums = []
    for name in outputs:
        with (BUILD / name).open('rb') as artifact:
            checksums.append(hashlib.file_digest(artifact, 'sha256').hexdigest() + '  ' + name + '\n')
    (BUILD / 'SHA256SUMS').write_text(''.join(checksums))
    print(f'Built {image} and {BUILD / "cartridge.bin"}')


if __name__ == '__main__':
    main()
