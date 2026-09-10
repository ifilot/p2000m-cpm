#!/usr/bin/env python3
"""Independent real-Z80 program cases. Compiles the harness against the supplied emulator."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import shutil
import unittest
from build import CORE_FILES
from sd_image import create_image, install_kernel
from test_emulator import ROOT, fat_digest, read_cpm_file, compile_harness

BUILD = ROOT / 'build'
EMULATOR = ROOT.parent / 'p2000m-emulator'
CODE = bytes.fromhex('11 0b 01 0e 09 cd 05 00 c3 00 00') + b'ASM/LOAD OK\r\n$'
SOURCE = b" ORG 100H\r\n LXI D,MSG\r\n MVI C,9\r\n CALL 5\r\n JMP 0\r\nMSG: DB 'ASM/LOAD OK',13,10,'$'\r\n END\r\n"


def intel_hex(data):
    record = bytes([len(data), 1, 0, 0]) + data
    return b':' + (record + bytes([-sum(record) & 255])).hex().upper().encode() + b'\r\n:00000001FF\r\n'


def decode_hex(data):
    result = {}
    for line in data.rstrip(b'\x1a').splitlines():
        if not line.startswith(b':'):
            continue
        record = bytes.fromhex(line[1:].decode())
        if sum(record) & 255:
            raise AssertionError('Bad Intel HEX checksum')
        if record[3] == 0:
            address = int.from_bytes(record[1:3], 'big')
            result.update((address + i, c) for i, c in enumerate(record[4:4+record[0]]))
    return bytes(result[i] for i in range(0x100, 0x100 + len(CODE)))


class BundledPrograms(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compile_harness(EMULATOR, "cpm")

    def run_program(self, name):
        with tempfile.TemporaryDirectory(prefix='p2000m-program-') as tmp:
            tmp = Path(tmp)
            files = [*CORE_FILES, *(BUILD / (n + '.COM') for n in ('HELLO', 'COPY', 'CPMTEST', 'RAMTEST', 'SYNC'))]
            # More than one 32 KiB directory extent; binary data includes Ctrl-Z.
            payload = bytes(range(256)) * 145
            fixtures = {'PAYLOAD.BIN': payload, 'HEXTEST.BIN': bytes(range(128)),
                        'TEST.ASM': SOURCE}
            if name == 'LOAD':
                fixtures['TEST.HEX'] = intel_hex(CODE)
            for filename, data in fixtures.items():
                path = tmp / filename
                path.write_bytes(data)
                files.append(path)
            card = tmp / 'card.img'
            existing = tmp / "RESULT.BIN"
            existing.write_bytes(b"PRESERVE ME" + bytes(117))
            create_image(card, files, [existing] if name == "COPYEXISTS" else [])
            if name.startswith('ZORK'):
                shutil.copyfile(BUILD / 'p2000m-sd-template.img', card)
            install_kernel(card, (BUILD / 'kernel.bin').read_bytes())
            before = fat_digest(card)
            run = subprocess.run([str(BUILD / 'cpm-test'), str(EMULATOR), str(BUILD), str(card), name],
                                 capture_output=True, text=True, timeout=180)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertEqual(fat_digest(card), before, 'FAT32 changed')
            if name in ('PIP', 'COPY'):
                self.assertEqual(read_cpm_file(card, 1, b'RESULT  BIN'), payload)
            elif name == 'COPYEXISTS':
                self.assertEqual(read_cpm_file(card, 1, b'RESULT  BIN'), existing.read_bytes())
            elif name == 'ASM':
                self.assertEqual(decode_hex(read_cpm_file(card, 0, b'TEST    HEX')), CODE)
            elif name == 'LOAD':
                self.assertEqual(read_cpm_file(card, 0, b'TEST    COM'), CODE + b'\x00' * (-len(CODE) % 128))
            elif name == 'ED':
                text = read_cpm_file(card, 0, b'NOTES   TXT')
                self.assertEqual(text.rstrip(b'\x1a'), b'EDITED ON SD\r\n')


for program in ('ABI', 'HELLO', 'COPY', 'COPYEXISTS', 'CPMTEST', 'CPMABORT', 'RAMTEST', 'RAMEXISTS', 'SYNC', 'DIR', 'PIP', 'ASM', 'LOAD', 'DDT', 'DUMP', 'ED', 'STAT', 'ZORK1', 'ZORK2', 'ZORK3'):
    setattr(BundledPrograms, 'test_' + program.lower(), lambda self, name=program: self.run_program(name))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path, default=EMULATOR)
    args, remaining = parser.parse_known_args()
    EMULATOR = args.emulator.resolve()
    unittest.main(argv=[__file__, *remaining], verbosity=2)
