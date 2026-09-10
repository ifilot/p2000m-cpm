#!/usr/bin/env python3
"""Compress the built SD image and write checksums for the deliverables."""
from pathlib import Path
import gzip
import hashlib
import shutil

BUILD = Path(__file__).resolve().parents[1] / 'build'


def main():
    image = BUILD / 'p2000m-sd-template.img'
    packed = image.with_suffix('.img.gz')
    with image.open('rb') as source, packed.open('wb') as target:
        with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed, 1024 * 1024)
    lines = []
    for path in (BUILD / 'cartridge.bin', BUILD / 'kernel.bin', image, packed):
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        lines.append(f'{digest}  {path.name}\n')
    (BUILD / 'SHA256SUMS').write_text(''.join(lines))
    print(f'Wrote {packed} ({packed.stat().st_size:,} bytes) and SHA256SUMS')


if __name__ == '__main__':
    main()
