"""Two-pass RAM/ROM link with checked, fixed-size absolute cross-references."""
from pathlib import Path
import re
import subprocess
import hashlib
import json

from memory_layout import LAYOUT

KERNEL_API = ('return_zero', 'return_ff', 'return_a', 'selected', 'dph_a',
              'track', 'record', 'dma', 'writing', 'cursor', 'column',
              'warm_boot', 'bdos_input', 'bdos_output', 'bdos_reader',
              'bdos_direct', 'bdos_iobyte', 'bdos_setio', 'bdos_string', 'bdos_line',
              'bdos_status', 'bdos_version', 'bdos_reset', 'bdos_select', 'bdos_login',
              'bdos_current', 'bdos_dma', 'bdos_alloc', 'bdos_protect', 'bdos_ro',
              'bdos_dpb', 'bdos_user', 'bdos_reset_drives')


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
    # Probe the complete cartridge: all cross-module references are absolute.
    exports(generated / 'kernel_exports.inc', KERNEL_API, dict.fromkeys(KERNEL_API, 0))
    probe = assemble(root / 'src/cartridge.asm', generated / 'rom_probe.bin', root, generated)
    names = []
    for source in ('filesystem.asm', 'cache.asm', 'console.asm', 'keyboard.asm', 'keyboard_repeat.asm', 'rom_tables.asm', 'disk_io.asm'):
        names += re.findall(r'^(\w+):', (root / 'src' / source).read_text(), re.M)
    names += ['rom_restart']
    exports(generated / 'rom_exports.inc', names, probe)
    kernel = assemble(root / 'src/kernel.asm', output / 'kernel.bin', root, generated)
    assert kernel['bdos_entry'] == LAYOUT['tpa_limit']
    assert kernel['cold_code_end'] <= LAYOUT['resident_base']
    assert kernel['resident_code_end'] <= LAYOUT['resident_code_limit']
    exports(generated / 'kernel_exports.inc', KERNEL_API, kernel)
    contract = {'ram': {key: kernel[key] for key in KERNEL_API},
                'rom': {key: probe[key] for key in names}, 'memory': LAYOUT}
    fingerprint = hashlib.sha256(json.dumps(contract, sort_keys=True).encode()).digest()[:16]
    (generated / 'link_id.inc').write_text('    db ' + ','.join(str(x) for x in fingerprint) + '\n')
    (generated / 'link-id.txt').write_text(fingerprint.hex() + '\n')
    final_kernel = assemble(root / 'src/kernel.asm', output / 'kernel.bin', root, generated)
    assert all(final_kernel[key] == kernel[key] for key in kernel), 'Fingerprint changed RAM layout'
    rom = assemble(root / 'src/cartridge.asm', output / 'cartridge.bin', root, generated)
    assert all(rom[name] == probe[name] for name in names), 'ROM link changed layout'
    assert rom['rom_runtime_end'] <= LAYOUT['rom_filesystem_base']
    assert rom['rom_filesystem_end'] <= LAYOUT['rom_end']
    assert rom['rom_keyboard_tail_end'] <= LAYOUT['rom_end']
    assert rom['keyboard_vector'] == 0xe7fe
    assert rom['boot_loader_end'] <= 0x8000, 'Loader exceeds stock D000-DFFF copy window'
    cartridge = (output / 'cartridge.bin').read_bytes()
    assert len(cartridge) == 0x2000 + rom['boot_loader_end'] - LAYOUT['boot_loader_base']
    assert cartridge[0x101a:0x102a] == fingerprint
    kernel_bytes = (output / 'kernel.bin').read_bytes()
    kernel_tag = kernel['ui_signature'] - LAYOUT['kernel_load'] + 8
    assert kernel_bytes[kernel_tag:kernel_tag + 16] == fingerprint
    return {**LAYOUT, **{key: kernel[key] for key in ('bios', 'bdos_entry', 'resident_code_end', 'cold_code_end')},
            **{key: rom[key] for key in ('rom_driver_end', 'rom_runtime_end', 'rom_filesystem_end', 'rom_keyboard_tail_end', 'boot_loader_end',
                                        'header_check', 'kernel_checksum', 'boot_sd_retry',
                                        'keyboard_interrupt', 'keyboard_vector', 'key_head', 'key_tail',
                                        'key_overflow', 'key_repeat_count')}}
