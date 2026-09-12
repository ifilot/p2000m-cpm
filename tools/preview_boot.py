#!/usr/bin/env python3
"""Render proposed boot screens, not firmware captures, with the P2000M ROM font.

Requires Pillow and the sibling emulator's character ROMs. No firmware or SD
image is changed. Text and attribute dumps accompany each PNG for inspection.
"""
import argparse
from pathlib import Path
from memory_layout import TPA_TEXT, KERNEL_RANGE, LAYOUT

ROOT = Path(__file__).resolve().parents[1]
COLS, ROWS = 80, 24
GREEN, BLACK = (0, 255, 65), (0, 0, 0)
DRIVE_LABELS = ('SYSTEM', 'TOOLS', 'ZORK', 'GAMES', 'BASIC', 'ASM',
                'SOURCE', 'DOCS', 'DATA', 'EXTRA 1', 'EXTRA 2', 'SCRATCH')


class Screen:
    def __init__(self):
        self.chars = bytearray(b' ' * (COLS * ROWS))
        self.attrs = bytearray(COLS * ROWS)
        self.lines = [' ' * COLS for _ in range(ROWS)]

    def put(self, row, text, col=1, inverse=False):
        assert 0 <= row < ROWS and 0 <= col <= COLS
        assert len(text) <= COLS - col, (row, len(text), text)
        for i, char in enumerate(text):
            assert 32 <= ord(char) < 127 and char != '_'
            # The native 0x23 glyph is a pound sign; 0x5f is the hash.
            self.chars[row * COLS + col + i] = 0x5f if char == '#' else ord(char)
            self.attrs[row * COLS + col + i] = 8 if inverse else 0
        self.lines[row] = self.lines[row][:col] + text + self.lines[row][col + len(text):]

    def bar(self, row, title):
        self.put(row, ('  ' + title).ljust(78), inverse=True)

    def item(self, row, name, detail, status):
        assert len(name) <= 13 and len(detail) <= 47 and len(status) <= 12
        self.put(row, f'| {name:<13} {detail:<47} {status:>12} |')

    def border(self, row):
        self.put(row, '+' + '-' * 76 + '+')


def design(state):
    s = Screen()
    ready, failed = state in ('ready', 'expanded', 'grid3', 'grid2'), state == 'failed'
    # Illustrative shared release metadata, not dates read from a real build.
    s.bar(0, 'P2000M SD SYSTEM')
    s.put(0, 'CP/M 2.2 compatible', col=58, inverse=True)
    s.put(1, '  System  v0.4.0     Built 2026-09-10 14:32 UTC')
    s.put(2, '  Cartridge + kernel  /  matched system release' if ready else
          '  Cartridge + kernel  /  kernel not loaded' if failed else
          '  Cartridge + kernel  /  pending verification')
    s.put(3, TPA_TEXT if ready else
          '  TPA     pending kernel verification')
    s.border(4)
    s.item(5, 'Cartridge', '16 KiB ROM   1000-4FFF', 'OK')
    s.item(6, 'Co-board', 'RAM enabled  /  RAM loader 7000', 'OK')
    s.item(7, 'Kernel', f'{KERNEL_RANGE}  /  signature + checksum' if ready else
           f'{KERNEL_RANGE}  /  SD sectors 16-{15 + LAYOUT["kernel_sectors"]}', 'OK' if ready else
           ('NOT LOADED' if failed else 'LOADING'))
    s.bar(8, 'SD CARD')
    # The loader reads CID after establishing SPI mode.
    s.item(9, 'Manufacturer', 'MID 03  /  OEM SD' if ready else
           'Not available' if failed else 'Identification pending',
           'READY' if ready else 'FAILED' if failed else 'PENDING')
    s.item(10, 'Identity', 'Product AKGCE  /  Serial DAA835A4' if ready else '--', '')
    s.item(11, 'Startup', 'SPI mode', 'FAILED' if failed else 'OK' if ready else 'STARTING')
    s.bar(12, '')
    for col, label in ((3, 'DRIVE'), (17, 'BACKING STORE'), (49, 'CAPACITY'), (71, 'STATUS')):
        s.put(12, label, col=col, inverse=True)
    s.item(13, 'A:', 'SD card / partition A             8 MiB' if ready else
           'SD card / partition A                --', 'READY' if ready else 'PENDING')
    s.item(14, 'B:', 'SD card / partition B             8 MiB' if ready else
           'SD card / partition B                --', 'READY' if ready else 'PENDING')
    s.item(15, 'C:', 'RAM / 126 KiB usable            128 KiB', 'READY' if ready else 'PENDING')
    bottom = 16
    if state == 'expanded':
        # Future configurable-volume concept only; not supported by firmware yet.
        for row, drive, detail in (
            (16, 'D:', 'SD card / ZORK                    1 MiB'),
            (17, 'E:', 'SD card / GAMES                   2 MiB'),
            (18, 'F:', 'SD card / DEVELOPMENT             4 MiB'),
        ):
            s.item(row, drive, detail, 'READY')
        bottom = 19
    if state in ('grid3', 'grid2'):
        # Proposed 12-drive layout: SD A:..K:, with RAM moved to L:.
        # Overwrite the legacy drive section; no firmware storage change here.
        columns = 3 if state == 'grid3' else 2
        widths = (25, 25, 24) if columns == 3 else (37, 38)
        s.bar(12, 'DRIVES A-L  /  11 SD VOLUMES + 1 RAM DISK')
        for row in range(12 // columns):
            cells = []
            for column, width in enumerate(widths):
                index = row * columns + column
                letter = chr(ord('A') + index)
                media, size = ('RAM', '128KiB') if letter == 'L' else ('SD', '8 MiB')
                cell = f' {letter}: {DRIVE_LABELS[index]:<7} {"(" + media + ")":<5} {size:>6}'
                assert len(cell) <= width, (letter, cell, width)
                cells.append(cell.ljust(width))
            s.put(13 + row, '|' + '|'.join(cells) + '|')
        bottom = 13 + 12 // columns
    s.border(bottom)
    if ready:
        s.put(bottom + 1, '  BOOT COMPLETE  /  CP/M entry points installed')
        s.put(bottom + 3, 'A>')
    elif failed:
        s.bar(bottom + 1, 'BOOT STOPPED  /  SD initialization failed')
        s.put(bottom + 2, '  Last command: CMD0 (00)   Response: 3F   Attempts: 8/8')
        s.put(bottom + 4, '  Check the card and cartridge connections, then reset the machine.')
    else:
        s.put(bottom + 1, f'  LOADING KERNEL   (########--------)  {LAYOUT["kernel_sectors"] // 2}/{LAYOUT["kernel_sectors"]} sectors')
        s.put(bottom + 2, '  Next: checksum, card identification, partitions, RAM disk')
    return s


def render(screen, font):
    from PIL import Image
    frame = Image.new('RGB', (COLS * 8, ROWS * 12), BLACK)
    pixels = frame.load()
    for index, code in enumerate(screen.chars):
        inverse = bool(screen.attrs[index] & 8)
        foreground, background = (BLACK, GREEN) if inverse else (GREEN, BLACK)
        x, y = (index % COLS) * 8, (index // COLS) * 12
        for scanline in range(12):
            bits = font[scanline * 256 + code]
            for column in range(8):
                pixels[x + column, y + scanline] = foreground if bits & (128 >> column) else background
    return frame


def main():
    from PIL import Image
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--charrom-dir', type=Path, default=
                        ROOT.parent / 'p2000m-emulator/assets/charrom')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/boot-previews')
    args = parser.parse_args()
    font = (args.charrom_dir / 'p2000m_charrom_upper.bin').read_bytes()
    font += (args.charrom_dir / 'p2000m_charrom_lower.bin').read_bytes()
    assert len(font) == 256 * 12
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ('loading', 'ready', 'failed', 'expanded', 'grid3', 'grid2'):
        screen = design(name)
        frame = render(screen, font)
        frame.save(args.output / f'{name}-native.png')
        frame.resize((1280, 576), Image.Resampling.NEAREST).save(args.output / f'{name}.png')
        (args.output / f'{name}.txt').write_text('\n'.join(screen.lines) + '\n')
        (args.output / f'{name}.chars.bin').write_bytes(screen.chars)
        (args.output / f'{name}.attrs.bin').write_bytes(screen.attrs)
        print(f'{name}: 80x24 cells, 640x288 native pixels; {args.output / (name + ".png")}')


if __name__ == '__main__':
    main()
