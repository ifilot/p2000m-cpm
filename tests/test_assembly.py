"""Freeze the pre-documentation machine code, including addresses and padding."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE = json.loads((ROOT / 'tests/fixtures/assembly_baseline.json').read_text())


class AssemblyConservation(unittest.TestCase):
    def test_original_machine_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            for source, expected in BASELINE['artifacts'].items():
                with self.subTest(source=source):
                    output = Path(tmp) / 'assembled.bin'
                    subprocess.run(['z80asm', '-I', str(ROOT / 'src'), '-o',
                                    str(output), str(ROOT / source)], check=True,
                                   capture_output=True)
                    data = output.read_bytes()
                    self.assertEqual(len(data), expected['bytes'])
                    self.assertEqual(hashlib.sha256(data).hexdigest(), expected['sha256'])
