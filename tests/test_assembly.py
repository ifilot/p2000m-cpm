"""Freeze machine code, addresses and padding against the documented baseline."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from build_metadata import generate

ROOT = Path(__file__).resolve().parents[1]
BASELINE = json.loads((ROOT / 'tests/fixtures/assembly_baseline.json').read_text())


class AssemblyConservation(unittest.TestCase):
    def test_original_machine_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture_root = Path(tmp)
            (fixture_root / 'VERSION').write_text((ROOT / 'VERSION').read_text())
            with patch.dict('os.environ', {'SOURCE_DATE_EPOCH': '0'}):
                generate(fixture_root)
            for source, expected in BASELINE['artifacts'].items():
                with self.subTest(source=source):
                    output = Path(tmp) / 'assembled.bin'
                    subprocess.run(['z80asm', '-I', str(ROOT / 'src'), '-I', str(ROOT / 'programs'),
                                    '-I', str(fixture_root / 'build/generated'), '-o',
                                    str(output), str(ROOT / source)], check=True,
                                   capture_output=True)
                    data = output.read_bytes()
                    self.assertEqual(len(data), expected['bytes'])
                    self.assertEqual(hashlib.sha256(data).hexdigest(), expected['sha256'])
