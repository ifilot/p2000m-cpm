"""Bank switching and the real BANKTEST.COM on good and faulty hardware models."""
from pathlib import Path
import subprocess
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from test_emulator import ROOT, EMULATOR, compile_harness


class Banking(unittest.TestCase):
    def test_cpld_and_cpu_output_bus(self):
        compile_harness(EMULATOR, 'cpm_banking')
        subprocess.run([str(ROOT / 'build/cpm_banking-test')], check=True, timeout=30)

    def test_hardware_diagnostic(self):
        compile_harness(EMULATOR, 'banktest')
        subprocess.run([str(ROOT / 'build/banktest-test'), str(ROOT / 'build/BANKTEST.COM')],
                       check=True, timeout=30)
