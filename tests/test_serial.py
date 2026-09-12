"""Cycle-level serial tests use the existing Z80 core and modeled pin waveforms."""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from test_emulator import EMULATOR, read_cpm_file


class SerialDiagnostics(unittest.TestCase):
    def test_uart_waveforms(self):
        cpu = EMULATOR / 'src/vendor/superzazu_z80'
        with tempfile.TemporaryDirectory(prefix='p2000m-serial-') as tmp:
            tmp = Path(tmp)
            binary = tmp / 'SERTX.COM'
            result = subprocess.run(['z80asm', '-L', '-I', str(ROOT / 'programs/common'), '-o', str(binary),
                                     str(ROOT / 'programs/sertx/sertx.asm')], check=True, capture_output=True, text=True)
            symbols = {name: int(value, 16) for name, value in
                       re.findall(r'^(\w+):\s+equ \$([0-9a-f]+)', result.stderr + result.stdout, re.M)}
            for name in ('serpins', 'serrx'):
                subprocess.run(['z80asm', '-I', str(ROOT / 'programs/common'), '-o', str(tmp / (name + '.COM')),
                                str(ROOT / 'programs' / name / (name + '.asm'))], check=True)
            subprocess.run(['gcc', '-O2', '-c', str(cpu / 'z80.c'), '-o', str(tmp / 'z80.o')], check=True)
            executable = tmp / 'serial-test'
            subprocess.run(['g++', '-O2', '-std=c++17', '-I' + str(cpu), str(ROOT / 'tests/serial.cpp'),
                            str(tmp / 'z80.o'), '-o', str(executable)], check=True)
            result = subprocess.run([str(executable), str(binary), *(str(symbols[name]) for name in
                ('serial_tx', 'serial_rx', 'serial_ready', 'serial_rx_idle', 'serial_force')),
                str(tmp / 'serpins.COM'), str(tmp / 'serrx.COM')],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_bundled_diagnostics(self):
        for name in ('SERPINS', 'SERTX', 'SERRX'):
            with self.subTest(program=name):
                binary = (ROOT / 'build' / (name + '.COM')).read_bytes()
                disk = read_cpm_file(ROOT / 'build/p2000m-sd-template.img', 1,
                                     (name.ljust(8) + 'COM').encode('ascii'))
                self.assertEqual(disk, binary + b'\x1a' * (-len(binary) % 128))
