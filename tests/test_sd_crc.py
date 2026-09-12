"""Inject SD wire faults while running the actual Z80 CRC and cache routines."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from sd_image import create_image, install_kernel
from test_emulator import ROOT, EMULATOR, compile_harness, fat_digest


class SDCRC(unittest.TestCase):
    def test_wire_integrity(self):
        build = ROOT / 'build'
        emulator = EMULATOR
        compile_harness(emulator, 'sd_crc')
        with tempfile.TemporaryDirectory(prefix='p2000m-crc-') as tmp:
            card = Path(tmp) / 'card.img'
            create_image(card)
            install_kernel(card, (build / 'kernel.bin').read_bytes())
            before = fat_digest(card)
            result = subprocess.run([str(build / 'sd_crc-test'), str(emulator), str(build), str(card)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(fat_digest(card), before, 'CRC tests modified FAT32')
