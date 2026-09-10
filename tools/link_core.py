"""Two-pass RAM/ROM link with checked, fixed-size absolute cross-references."""
from pathlib import Path
import re
import subprocess
import hashlib
import json

from memory_layout import LAYOUT

KERNEL_API = ('return_zero', 'return_ff', 'return_a', 'disk_error', 'disk_select',
              'disk_sector', 'disk_track', 'disk_dma', 'disk_read', 'disk_write',
              'cache_flush', 'cache_invalidate')


def assemble(source, output, root, generated):
    result = subprocess.run(['z80asm', '-L', '-I', str(root / 'src'), '-I', str(generated),
                             '-o', str(output), str(source)], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(result.stderr + result.stdout)
    return {key: int(value, 16) for key, value in
            re.findall(r'^(\w+):\s+equ \$([0-9a-f]+)', result.stderr + result.stdout, re.M)}


def exports(path, names, symbols):
    path.write_text('; Generated link contract; do not edit.\n' +
                    ''.join(f'{name}: equ 0x{symbols[name]:04x}\n' for name in names))


def link_core(root, output):
    generated = output / 'generated'
    (generated / 'link_id.inc').write_text('    db ' + ','.join(['0'] * 16) + '\n')
    # Absolute CALL/JP addresses cannot affect instruction lengths. Relative
    # jumps must stay within the filesystem module (the real link verifies it).
    exports(generated / 'kernel_exports.inc', KERNEL_API, dict.fromkeys(KERNEL_API, 0))
    probe = generated / 'filesystem_probe.asm'
    probe.write_text("include 'platform.inc'\ninclude 'bdos_workspace.inc'\n"
                     "include 'kernel_exports.inc'\norg rom_filesystem_base\ninclude 'filesystem.asm'\n")
    fs_symbols = assemble(probe, generated / 'filesystem_probe.bin', root, generated)
    fs_names = re.findall(r'^(\w+):', (root / 'src/filesystem.asm').read_text(), re.M)
    exports(generated / 'filesystem_exports.inc', fs_names, fs_symbols)
    kernel = assemble(root / 'src/kernel.asm', output / 'kernel.bin', root, generated)
    assert kernel['bdos_entry'] == LAYOUT['tpa_limit']
    assert kernel['resident_code_end'] <= LAYOUT['resident_code_limit']
    exports(generated / 'kernel_exports.inc', KERNEL_API, kernel)
    contract = {'ram': {key: kernel[key] for key in KERNEL_API},
                'rom': {key: fs_symbols[key] for key in fs_names}, 'memory': LAYOUT}
    fingerprint = hashlib.sha256(json.dumps(contract, sort_keys=True).encode()).digest()[:16]
    (generated / 'link_id.inc').write_text('    db ' + ','.join(str(x) for x in fingerprint) + '\n')
    (generated / 'link-id.txt').write_text(fingerprint.hex() + '\n')
    final_kernel = assemble(root / 'src/kernel.asm', output / 'kernel.bin', root, generated)
    assert all(final_kernel[key] == kernel[key] for key in kernel), 'Fingerprint changed RAM layout'
    rom = assemble(root / 'src/cartridge.asm', output / 'cartridge.bin', root, generated)
    assert all(rom[name] == fs_symbols[name] for name in fs_names), 'ROM filesystem link changed layout'
    assert rom['rom_driver_end'] <= LAYOUT['rom_filesystem_base']
    assert rom['rom_filesystem_end'] <= LAYOUT['rom_end']
    # Compare a second actual-filesystem build against the bytes embedded in ROM.
    assemble(probe, generated / 'filesystem_linked.bin', root, generated)
    fs_bytes = (generated / 'filesystem_linked.bin').read_bytes()
    cartridge = (output / 'cartridge.bin').read_bytes()
    offset = 0x1000 + LAYOUT['rom_filesystem_base'] - 0xe000
    assert cartridge[offset:offset + len(fs_bytes)] == fs_bytes
    assert cartridge[0x101a:0x102a] == fingerprint
    kernel_bytes = (output / 'kernel.bin').read_bytes()
    kernel_tag = kernel['ui_signature'] - LAYOUT['kernel_load'] + 8
    assert kernel_bytes[kernel_tag:kernel_tag + 16] == fingerprint
    return {**LAYOUT, **{key: kernel[key] for key in ('bios', 'bdos_entry', 'resident_code_end')},
            'rom_driver_end': rom['rom_driver_end'], 'rom_filesystem_end': rom['rom_filesystem_end']}
