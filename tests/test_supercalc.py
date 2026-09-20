"""Pin the historical assets and exercise the configured spreadsheet on real CP/M."""
import hashlib
import shutil
import subprocess
import tempfile
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import test_programs


class SuperCalc(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        test_programs.compile_harness(test_programs.EMULATOR, "cpm")

    def test_asset_integrity(self):
        assets = ROOT / 'assets/supercalc'
        for line in (assets / 'SHA256SUMS').read_text().splitlines():
            digest, name = line.split()
            with self.subTest(file=name):
                self.assertEqual(hashlib.sha256((assets / name).read_bytes()).hexdigest(), digest)

    def test_spreadsheet(self):
        test_programs.BundledPrograms.run_program(self, 'SUPERCALC')

    def scenarios(self, *names, saved=()):
        with tempfile.TemporaryDirectory(prefix='supercalc-') as tmp:
            card = Path(tmp) / 'card.img'
            shutil.copyfile(test_programs.BUILD / 'p2000m-sd-template.img', card)
            before = test_programs.fat_digest(card)
            for name in names:
                run = subprocess.run([str(test_programs.BUILD / 'cpm-test'),
                                      str(test_programs.EMULATOR), str(test_programs.BUILD),
                                      str(card), name], capture_output=True, text=True, timeout=180)
                self.assertEqual(run.returncode, 0, name + "\n" + run.stdout + run.stderr)
                self.assertEqual(test_programs.fat_digest(card), before, 'FAT32 changed')
            for name in saved:
                data = test_programs.read_cpm_file(card, 3, name.ljust(8).encode() + b'CAL')
                self.assertTrue(data.startswith(b'SuperCalc ver.  1.00'), name)
                self.assertGreater(len(data), 512, name)
            # Overlays, installed executable and original sample files stay intact.
            for source in test_programs.SUPERCALC_FILES:
                name = (source.stem.ljust(8) + source.suffix[1:].ljust(3)).encode()
                data = source.read_bytes()
                self.assertEqual(test_programs.read_cpm_file(card, 3, name),
                                 data + b'\x1a' * (-len(data) % 128), source.name)

    def test_physical_zero_minus_and_underscore(self):
        self.scenarios('SCKEYS')

    def test_arithmetic_and_dependency_chains(self):
        self.scenarios('SCCALC')

    def test_navigation_and_scrolling(self):
        self.scenarios('SCNAV')

    def test_save_as_overwrite_and_cold_reload(self):
        self.scenarios('SCFILES', 'SCFILELOAD', saved=('ORIGINAL', 'CHANGED'))

    def test_sample_round_trip_and_recalculation(self):
        self.scenarios('SCSAMPLE', 'SCSAMPLOAD', saved=('SAMPCOPY',))

    def test_missing_file_recovery(self):
        self.scenarios('SCMISSING')
