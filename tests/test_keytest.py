"""KEYTEST.COM loaded from disk and run on the real kernel/Z80 emulator."""
import hashlib
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from test_emulator import ROOT, EMULATOR, compile_harness, read_cpm_file


class Keytest(unittest.TestCase):
    def test_raw_keyboard_diagnostic(self):
        build = ROOT / 'build'
        binary = (build / 'KEYTEST.COM').read_bytes()
        self.assertEqual(read_cpm_file(build / 'p2000m-sd-template.img', 0, b'KEYTEST COM'),
                         binary + b'\x1a' * (-len(binary) % 128))
        checksums = (build / 'SHA256SUMS').read_text()
        self.assertIn(hashlib.sha256(binary).hexdigest() + '  KEYTEST.COM', checksums)
        compile_harness(EMULATOR, 'keytest')
        with tempfile.TemporaryDirectory(prefix='p2000m-keytest-') as tmp:
            card = Path(tmp) / 'card.img'
            shutil.copyfile(build / 'p2000m-sd-template.img', card)
            def digest():
                with card.open('rb') as stream:
                    return hashlib.file_digest(stream, 'sha256').digest()
            before = digest()
            run = subprocess.run([str(build / 'keytest-test'), str(EMULATOR), str(build), str(card)],
                                 capture_output=True, text=True, timeout=120)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertEqual(digest(), before, 'Diagnostic changed the SD image')
            print(run.stdout.strip())
