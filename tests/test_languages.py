"""Execute the bundled language tools on the real Z80 emulator core."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import test_programs


class Languages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        test_programs.compile_harness(test_programs.EMULATOR, 'cpm')

    run_program = test_programs.BundledPrograms.run_program

    def test_mbasic(self):
        self.run_program('MBASIC')

    def test_bdsc(self):
        self.run_program('BDSC')

    def test_mscobol(self):
        self.run_program('MSCOBOL')
