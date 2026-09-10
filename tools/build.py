#!/usr/bin/env python3
"""Build the original assembly cartridge and SD-loaded kernel."""
from pathlib import Path
import subprocess
from sd_image import create_image, install_kernel

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
CORE_NAMES = ('asm', 'ddt', 'dump', 'ed', 'load', 'pip', 'stat')
CORE_FILES = [ROOT / 'assets/cpm_core' / (name + '.com') for name in CORE_NAMES]


def main():
    BUILD.mkdir(exist_ok=True)
    for name in ('cartridge', 'kernel'):
        subprocess.run(['z80asm', '-I', str(ROOT / 'src'), '-o', str(BUILD / f'{name}.bin'),
                        str(ROOT / 'src' / f'{name}.asm')], check=True)
    cartridge = bytearray((BUILD / 'cartridge.bin').read_bytes())
    if len(cartridge) > 8192:
        raise ValueError('Cartridge exceeds 8 KiB')
    cartridge.extend(b'\xff' * (8192 - len(cartridge)))
    cartridge[1:3] = (8192 - 5).to_bytes(2, 'little')
    cartridge[3:5] = (-sum(cartridge[5:]) & 0xffff).to_bytes(2, 'little')
    (BUILD / 'cartridge.bin').write_bytes(cartridge)
    kernel = (BUILD / 'kernel.bin').read_bytes()
    if len(kernel) != 16384:
        raise ValueError('Kernel must be exactly 16 KiB')
    for program in ('hello', 'cpmtest', 'copy'):
        subprocess.run(['z80asm', '-o', str(BUILD / (program.upper() + '.COM')),
                        str(ROOT / 'programs' / (program + '.asm'))], check=True)
    # Rebuildable output only; don't overwrite the user's persistent SD image.
    image = BUILD / 'p2000m-sd-template.img'
    image.unlink(missing_ok=True)
    create_image(image, [BUILD / "HELLO.COM", BUILD / "CPMTEST.COM", BUILD / "COPY.COM"] + CORE_FILES)
    install_kernel(image, kernel)
    print(f'Built {image} and {BUILD / "cartridge.bin"}')


if __name__ == '__main__':
    main()
