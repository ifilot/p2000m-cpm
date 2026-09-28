#!/usr/bin/env python3
"""Assemble the static WebAssembly browser emulator for GitHub Pages."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'
EMULATOR = ROOT / 'tests/emulator'
WEB = ROOT / 'web'
WEB_FILES = ('index.html', 'app.js', 'keyboard.js', 'style.css')
EMULATOR_NAME = 'p2000m-web'
EMULATOR_SUFFIXES = ('.js', '.wasm')
VERSION_MARKER = '__VERSION__'
BUILD_MARKER = '__BUILD__'
# Published name, source path and exact size of every machine asset.
ASSETS = (
    ('p2000.rom', EMULATOR / 'assets/roms/p2000.rom', 4096),
    ('cartridge.bin', BUILD / 'cartridge.bin', 16 * 1024),
    ('charrom-upper.bin', ROOT / 'assets/charrom/p2000m_charrom_upper.bin', 256 * 8),
    ('charrom-lower.bin', ROOT / 'assets/charrom/p2000m_charrom_lower.bin', 256 * 4),
    ('p2000m-sd-template.img.gz', BUILD / 'p2000m-sd-template.img.gz', None),
)
CORE_SOURCES = ('src/core/p2000_machine.cpp', 'src/core/p2000_fdc.cpp',
                'src/core/p2000_sd.cpp')
LINK_FLAGS = (
    '-sMODULARIZE=1',
    '-sEXPORT_NAME=createP2000M',
    '-sALLOW_MEMORY_GROWTH=1',
    '-sENVIRONMENT=web,worker,node',
    '-sFILESYSTEM=1',
    "-sEXPORTED_RUNTIME_METHODS=['FS','HEAPU8','UTF8ToString']",
    '--no-entry',
)


def require_file(path, description, size=None):
    if not path.is_file():
        raise ValueError(f'Missing {description}: {path}')
    if size is not None and path.stat().st_size != size:
        raise ValueError(f'{description} must be exactly {size} bytes: {path}')
    return path


def compile_emulator(output, emcc='emcc', emxx='em++', emulator=EMULATOR):
    """Compile the bundled core and web entry point; output has no suffix."""
    output.parent.mkdir(parents=True, exist_ok=True)
    cpu = emulator / 'src/vendor/superzazu_z80'
    z80_object = output.parent / 'z80-web.o'
    subprocess.run([emcc, '-O3', '-c', str(cpu / 'z80.c'), '-o', str(z80_object)],
                   check=True)
    # Bundled-software helpers are unused; their search directories are inert.
    subprocess.run([emxx, '-O3', '-std=c++17',
                    '-I' + str(emulator / 'src/core'), '-I' + str(cpu),
                    '-DP2000M_SOURCE_ROM_DIR="/"', '-DP2000M_SOURCE_SOFTWARE_DIR="/"',
                    str(WEB / 'wasm/p2000m_web.cpp'),
                    *(str(emulator / source) for source in CORE_SOURCES),
                    str(z80_object), *LINK_FLAGS,
                    '-o', str(output.with_suffix('.js'))], check=True)
    return output


def build_site(destination, emulator, version, root=ROOT, assets=ASSETS):
    """Atomically assemble the web page, machine assets and WebAssembly."""
    destination = Path(destination).resolve()
    emulator = Path(emulator).resolve()
    source = root / 'web'
    pages = [require_file(source / name, f'web file {name}') for name in WEB_FILES]
    files = [(require_file(path, name, size), name) for name, path, size in assets]
    files.extend((require_file(emulator.with_suffix(suffix),
                               f'WebAssembly emulator {suffix}'),
                  EMULATOR_NAME + suffix) for suffix in EMULATOR_SUFFIXES)
    index = pages[0].read_text(encoding='utf-8')
    for marker in (VERSION_MARKER, BUILD_MARKER):
        if marker not in index:
            raise ValueError(f'web/index.html lacks the {marker} marker')
    # Content hash of everything the page loads; it versions each asset URL.
    digest = hashlib.sha256()
    for path in [*pages[1:], *(path for path, _name in files)]:
        digest.update(path.name.encode() + b'\0' + path.read_bytes())
    build = digest.hexdigest()[:12]

    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f'.{destination.name}-',
                                     dir=destination.parent) as temporary:
        work = Path(temporary)
        stage = work / destination.name
        stage.mkdir()
        for page in pages[1:]:
            shutil.copyfile(page, stage / page.name)
        (stage / 'index.html').write_text(
            index.replace(VERSION_MARKER, version).replace(BUILD_MARKER, build),
            encoding='utf-8')
        for path, name in files:
            shutil.copyfile(path, stage / name)
        (stage / '.nojekyll').write_text('', encoding='ascii')

        backup = work / 'previous'
        if destination.exists():
            if not destination.is_dir() or destination.is_symlink():
                raise ValueError(f'Site output is not a normal directory: {destination}')
            destination.rename(backup)
        try:
            stage.rename(destination)
        except OSError:
            if backup.exists():
                backup.rename(destination)
            raise
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=BUILD / 'site')
    parser.add_argument('--emcc', default='emcc', help='Emscripten C compiler')
    parser.add_argument('--emxx', default='em++', help='Emscripten C++ compiler')
    parser.add_argument('--emulator', type=Path,
                        help='Prebuilt emulator path without .js/.wasm; skips emcc')
    args = parser.parse_args()
    version = (ROOT / 'VERSION').read_text(encoding='ascii').strip()
    try:
        emulator = args.emulator or compile_emulator(
            BUILD / 'web' / EMULATOR_NAME, args.emcc, args.emxx)
        print(f'Built {build_site(args.output, emulator, version)}')
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
