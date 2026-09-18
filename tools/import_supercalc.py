#!/usr/bin/env python3
"""Re-extract the pinned Burcon SuperCalc disk and apply its installer-made profile.

Download the source image named in assets/supercalc/README.md, then run:
  python3 tools/import_supercalc.py /path/to/supercalc2.dsk --output /tmp/sc-check
The normal build uses bundled assets and never downloads software.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA256 = 'b08ab3f8db3ee389061250fa1d781ed5b4d4824b3bfa5ff0345bbb423d396b52'


def extract(image):
    if hashlib.sha256(image).hexdigest() != SOURCE_SHA256:
        raise ValueError('Unexpected source disk image')
    records = []
    # Burcon uses both BDOS translation and a second Altair skew on tracks >=6.
    skew = [(i % 4) * 8 + ((i % 16) // 4) * 2 + i // 16 for i in range(32)]
    for track in range(2, 77):
        for logical in skew:
            physical = logical if track < 6 else logical * 17 % 32
            start = (track * 32 + physical) * 137
            sector = image[start:start + 137]
            payload = sector[3:131] if track < 6 else sector[7:135]
            actual = sum(payload) & 255 if track < 6 else (sum(sector[2:135]) - sector[4]) & 255
            expected = sector[132] if track < 6 else sector[4]
            if actual != expected:
                raise ValueError(f'Sector checksum failed: {track}/{physical}')
            records.append(payload)
    raw = b''.join(records)
    files = {}
    for offset in range(0, 4096, 32):
        entry = raw[offset:offset + 32]
        if entry[0] != 0:
            continue
        name = entry[1:9].decode().strip() + '.' + entry[9:12].decode().strip()
        data = b''.join(raw[n * 2048:(n + 1) * 2048] for n in entry[16:] if n)[:entry[15] * 128]
        files.setdefault(name, []).append((entry[12], data))
    return {name: b''.join(data for _, data in sorted(parts)) for name, parts in files.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assets = ROOT / 'assets/supercalc'
    files = extract(args.image.read_bytes())
    profile = json.loads((assets / 'terminal-profile.json').read_text())
    original = files['SC2.COM']
    if hashlib.sha256(original).hexdigest() != profile['original_sha256']:
        raise ValueError('Original SC2.COM differs')
    data = bytearray(original)
    patch = bytes.fromhex(profile['bytes'])
    offset = profile['offset']
    data[offset:offset + len(patch)] = patch
    files['SC2.COM'] = bytes(data)
    # Verify everything before writing; do not import the Altair system utilities.
    expected = [line.split() for line in (assets / 'SHA256SUMS').read_text().splitlines()]
    for digest, name in expected:
        if hashlib.sha256(files[name]).hexdigest() != digest:
            raise ValueError(f'Extracted file differs: {name}')
    args.output.mkdir(parents=True, exist_ok=True)
    for _, name in expected:
        (args.output / name).write_bytes(files[name])
    print(f'Verified and extracted {len(expected)} files to {args.output}')


if __name__ == '__main__':
    main()
