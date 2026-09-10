#!/usr/bin/env python3
"""Compile against the supplied emulator core without modifying its checkout."""
import argparse
from pathlib import Path
import subprocess
import tempfile
import hashlib
import struct
from sd_image import create_image, install_kernel
from build import CORE_FILES

ROOT = Path(__file__).resolve().parents[1]


def fat_digest(card):
    digest = hashlib.sha256()
    with card.open('rb') as stream:
        stream.seek(1024 * 1024)
        for _ in range(64):
            block = stream.read(1024 * 1024)
            if len(block) != 1024 * 1024:
                raise AssertionError('FAT32 partition is truncated')
            digest.update(block)
    return digest.digest()


def read_cpm_file(card, drive, name):
    # Independent directory decoder for persistent output validation.
    base = (133120 + drive * 16384) * 512
    chunks = []
    with card.open('rb') as stream:
        stream.seek(base)
        directory = stream.read(16384)
        for pos in range(0, len(directory), 32):
            entry = directory[pos:pos + 32]
            if entry[0] != 0 or bytes(c & 127 for c in entry[1:12]) != name:
                continue
            extent = (entry[12] & 31) + (entry[14] & 63) * 32
            size = ((extent & 1) * 128 + entry[15]) * 128
            data = bytearray()
            for block in struct.unpack_from('<8H', entry, 16):
                if block:
                    stream.seek(base + block * 4096)
                    data.extend(stream.read(4096))
            chunks.append(((extent & ~1) * 16384, bytes(data[:size])))
    if not chunks:
        raise AssertionError(f'Missing persistent file {name!r}')
    output = bytearray()
    for offset, data in sorted(chunks):
        if offset != len(output):
            raise AssertionError('Unexpected sparse output file')
        output.extend(data)
    return bytes(output)


def compile_harness(emulator, name):
    """Build a headless test against the real core; never alter its checkout."""
    core = emulator / 'src/core'
    cpu = emulator / 'src/vendor/superzazu_z80'
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    subprocess.run(['gcc', '-O2', '-c', str(cpu / 'z80.c'), '-o', str(build / 'z80.o')], check=True)
    subprocess.run(['g++', '-O2', '-std=c++17', '-I' + str(core), '-I' + str(cpu), '-I' + str(build / 'generated'),
                    '-DP2000M_SOURCE_ROM_DIR="' + str(emulator / 'assets/roms') + '"',
                    '-DP2000M_SOURCE_SOFTWARE_DIR="' + str(emulator / 'assets/software') + '"',
                    str(ROOT / 'tests' / (name + '.cpp')), str(core / 'p2000_machine.cpp'),
                    str(core / 'p2000_fdc.cpp'), str(core / 'p2000_sd.cpp'),
                    str(build / 'z80.o'), '-o', str(build / (name + '-test'))], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--emulator', type=Path,
                        default=ROOT.parent / 'p2000m-emulator')
    args = parser.parse_args()
    build = ROOT / 'build'
    build.mkdir(exist_ok=True)
    # Verify the deliverable itself contains each requested utility byte-exact.
    for source in CORE_FILES:
        disk_name = (source.stem.upper().ljust(8) + 'COM').encode('ascii')
        actual = read_cpm_file(build / 'p2000m-sd-template.img', 0, disk_name)
        expected = source.read_bytes()
        if actual != expected + b'\x1a' * (-len(expected) % 128):
            raise AssertionError(f'Bundled utility mismatch: {source.name}')
    print('PASS: all seven standard utilities are present byte-exact in the built SD image', flush=True)
    for name in ('cache', 'boot', 'cpm'):
        compile_harness(args.emulator, name)
        with tempfile.TemporaryDirectory(prefix='p2000m-cpm-') as tmp:
            card = Path(tmp) / 'writable.img'
            files = [build / 'HELLO.COM', build / 'CPMTEST.COM', build / 'COPY.COM'] if name == 'cpm' else []
            if name == 'cpm':
                files += CORE_FILES
                hex_test = Path(tmp) / 'HEXTEST.BIN'
                hex_test.write_bytes(bytes(range(128)))
                files.append(hex_test)
                source = Path(tmp) / 'TEST.ASM'
                source.write_bytes(b" ORG 100H\r\n LXI D,MSG\r\n MVI C,9\r\n CALL 5\r\n JMP 0\r\nMSG: DB 'ASM/LOAD OK',13,10,'$'\r\n END\r\n")
                files.append(source)
                limit = Path(tmp) / 'TPALIMIT.COM'
                subprocess.run(['z80asm', '-I', str(ROOT / 'src'), '-o', str(limit), str(ROOT / 'tests/tpalimit.asm')], check=True)
                files.append(limit)
                oversized = Path(tmp) / 'TOOBIG.COM'
                oversized.write_bytes(limit.read_bytes() + bytes(128))
                files.append(oversized)
            create_image(card, files)
            install_kernel(card, (build / 'kernel.bin').read_bytes())
            original_fat = fat_digest(card)
            command = [str(build / (name + '-test')), str(args.emulator), str(build), str(card)]
            subprocess.run(command, check=True)
            if fat_digest(card) != original_fat:
                raise AssertionError('CP/M operations modified the FAT32 partition')
            if name == 'cpm':
                hello = (build / 'HELLO.COM').read_bytes()
                for filename in (b'NEW     COM', b'SAVED   COM'):
                    if not read_cpm_file(card, 1, filename).startswith(hello):
                        raise AssertionError('PIP/REN/SAVE output differs from HELLO.COM')
                expected = bytes.fromhex('11 0b 01 0e 09 cd 05 00 c3 00 00') + b'ASM/LOAD OK\r\n$'
                if not read_cpm_file(card, 0, b'TEST    COM').startswith(expected):
                    raise AssertionError('ASM/LOAD machine code differs from expected output')
                if not read_cpm_file(card, 0, b'NOTES   TXT').startswith(b'EDITED ON SD\r\n'):
                    raise AssertionError('ED did not save the edited text')
            print('PASS: FAT32 partition unchanged; persistent application output checked', flush=True)




if __name__ == '__main__':
    main()
