"""Read the assembly memory contract; no independent host-side address constants."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def load_layout():
    text = (ROOT / 'src/memory.inc').read_text()
    values = {name: int(value, 0) for name, value in
              re.findall(r'^(\w+): equ (0x[0-9a-f]+|[0-9]+)\s*$', text, re.M)}
    assert values['kernel_bytes'] == values['kernel_end'] - values['kernel_load']
    assert values['kernel_bytes'] == values['kernel_sectors'] * 512
    assert values['tpa_limit'] == values['resident_base']
    assert values['kernel_end'] <= values['bdos_workspace'] < values['rom_workspace']
    return values


LAYOUT = load_layout()
TPA_BYTES = LAYOUT['tpa_limit'] - 0x100
TPA_TEXT = f"  TPA     {TPA_BYTES / 1024:.2f} KiB ({TPA_BYTES} bytes)  /  0100-{LAYOUT['tpa_limit'] - 1:04X}"
KERNEL_RANGE = f"{LAYOUT['kernel_load']:04X}-{LAYOUT['kernel_end'] - 1:04X}"
