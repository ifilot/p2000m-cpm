#!/usr/bin/env python3
"""Capture real emulator screen memory and render README screenshots (Pillow)."""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

from test_emulator import ROOT, EMULATOR, compile_harness


def main():
    from PIL import Image
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'docs/screenshots')
    args = parser.parse_args()
    build = ROOT / 'build'
    compile_harness(EMULATOR, 'screenshots')
    with tempfile.TemporaryDirectory(prefix='p2000m-screenshots-') as temporary:
        card = Path(temporary) / 'card.img'
        shutil.copyfile(build / 'p2000m-sd-template.img', card)
        subprocess.run([str(build / 'screenshots-test'), str(EMULATOR), str(build), str(card)], check=True)

    fonts = ROOT / 'assets/charrom'
    font = (fonts / 'p2000m_charrom_upper.bin').read_bytes()
    font += (fonts / 'p2000m_charrom_lower.bin').read_bytes()
    if len(font) != 256 * 12:
        raise ValueError('Unexpected character ROM size')
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ('boot', 'session', 'banktest', 'supercalc'):
        chars = (build / f'screenshot-{name}-characters.bin').read_bytes()
        attrs = (build / f'screenshot-{name}-attributes.bin').read_bytes()
        if len(chars) != 1920 or len(attrs) != 1920:
            raise ValueError('Unexpected screen dump size')
        frame = Image.new('RGB', (640, 288), 'black')
        pixels = frame.load()
        for index, (raw, attr) in enumerate(zip(chars, attrs)):
            code = (raw & 127) | ((attr & 1) << 7)
            foreground, background = (0, 255, 65), (0, 0, 0)
            if attr & 8:
                foreground, background = background, foreground
            for row in range(12):
                # Capture the visible blink phase, with hardware underline.
                bits = 255 if attr & 2 and row == 10 else font[row * 256 + code]
                for column in range(8):
                    pixels[(index % 80) * 8 + column, (index // 80) * 12 + row] = (
                        foreground if bits & (128 >> column) else background)
        path = args.output / f'{name}.png'
        frame.resize((1280, 576), Image.Resampling.NEAREST).save(path)
        print(path)


if __name__ == '__main__':
    main()
