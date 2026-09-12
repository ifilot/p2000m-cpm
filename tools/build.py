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
from memory_layout import LAYOUT
from link_core import link_core

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
CARTRIDGE_SIZE = 16 * 1024
CORE_NAMES = ('ASM', 'DDT', 'DUMP', 'ED', 'LOAD', 'PIP', 'STAT')
CORE_FILES = [ROOT / 'assets/cpm_core' / (name + '.COM') for name in CORE_NAMES]
BASIC_FILES = [ROOT / 'assets/mbasic/MBASIC.COM', ROOT / 'programs/basdemo/BASDEMO.BAS']
BDS_FILES = sorted(p for p in (ROOT / 'assets/bdsc').iterdir() if p.suffix.upper() in
                   ('.COM', '.CRL', '.CCC', '.H', '.LBR', '.DOC')) + [ROOT / 'programs/cdemo/CDEMO.C']
LANGUAGE_FILES = {1: BDS_FILES, 4: BASIC_FILES}
SERIAL_NAMES = ('SERPINS', 'SERTX', 'SERRX')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--zork-dir', type=Path, default=ROOT / 'assets/zork',
                        help='Zork COM/DAT directory (default: bundled assets/zork)')
    args = parser.parse_args()
    zork = [args.zork_dir / f'ZORK{i}.{ext}' for i in (1, 2, 3) for ext in ('COM', 'DAT')]
    for path in zork:
        if not path.is_file():
            parser.error(f'Missing Zork file: {path}; specify --zork-dir')
    BUILD.mkdir(exist_ok=True)
    metadata = generate(ROOT)
    exported = link_core(ROOT, BUILD)
    metadata['memory'] = exported
    metadata['link_id'] = (BUILD / 'generated/link-id.txt').read_text().strip()
    (BUILD / 'generated/memory_layout.h').write_text('#pragma once\nnamespace p2m_layout {\n' +
        ''.join(f'constexpr unsigned {key} = 0x{value:04x};\n' for key, value in exported.items()) + '}\n')
    cartridge = bytearray((BUILD / 'cartridge.bin').read_bytes())
    if len(cartridge) > CARTRIDGE_SIZE:
        raise ValueError('Cartridge exceeds 16 KiB')
    cartridge.extend(b'\x00' * (CARTRIDGE_SIZE - len(cartridge)))
    # The monitor checks the bytes following the five-byte header.
    cartridge[1:3] = (CARTRIDGE_SIZE - 5).to_bytes(2, 'little')
    cartridge[3:5] = (-sum(cartridge[5:]) & 0xffff).to_bytes(2, 'little')
    (BUILD / 'cartridge.bin').write_bytes(cartridge)
    kernel = (BUILD / 'kernel.bin').read_bytes()
    if len(kernel) != LAYOUT['kernel_bytes']:
        raise ValueError('Kernel length differs from memory.inc')
    for program in ('hello', 'cpmtest', 'copy', 'ramtest', 'sync', *(name.lower() for name in SERIAL_NAMES)):
        subprocess.run(['z80asm', '-I', str(ROOT / 'programs/common'), '-o', str(BUILD / (program.upper() + '.COM')),
                        str(ROOT / 'programs' / program / (program + '.asm'))], check=True)
    # Rebuildable output only; don't overwrite the user's persistent SD image.
    image = BUILD / 'p2000m-sd-template.img'
    image.unlink(missing_ok=True)
    create_image(image, [BUILD / "HELLO.COM", BUILD / "CPMTEST.COM", BUILD / "COPY.COM", BUILD / "RAMTEST.COM", BUILD / "SYNC.COM"] + CORE_FILES,
                 files_by_drive={2: zork, **LANGUAGE_FILES,
                                 1: BDS_FILES + [BUILD / (name + '.COM') for name in SERIAL_NAMES]})
    install_kernel(image, kernel)
    # Deterministic gzip envelope; SOURCE_DATE_EPOCH fixes embedded timestamps.
    with image.open('rb') as source, (BUILD / 'p2000m-sd-template.img.gz').open('wb') as target:
        with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as archive:
            while chunk := source.read(1024 * 1024):
                archive.write(chunk)
    metadata['zork_sources'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in zork}
    metadata['language_sources'] = {chr(65 + drive):
        {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
        for drive, files in LANGUAGE_FILES.items()}
    (BUILD / 'build-info.json').write_text(json.dumps(metadata, indent=2) + '\n')
    outputs = ['cartridge.bin', 'kernel.bin', 'p2000m-sd-template.img', 'p2000m-sd-template.img.gz', 'build-info.json',
               'HELLO.COM', 'COPY.COM', 'CPMTEST.COM', 'RAMTEST.COM', 'SYNC.COM',
               *(name + '.COM' for name in SERIAL_NAMES)]
    checksums = []
    for name in outputs:
        with (BUILD / name).open('rb') as artifact:
            checksums.append(hashlib.file_digest(artifact, 'sha256').hexdigest() + '  ' + name + '\n')
    (BUILD / 'SHA256SUMS').write_text(''.join(checksums))
    print(f'Built {image} and {BUILD / "cartridge.bin"}')


if __name__ == '__main__':
    main()
