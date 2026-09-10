"""Generate assembly-only dashboard assets and per-artifact build identity."""
from datetime import datetime, timezone
import os
from pathlib import Path

from preview_boot import design, DRIVE_LABELS
from memory_layout import LAYOUT, TPA_TEXT, KERNEL_RANGE


def db(label, data):
    return label + ':\n' + ''.join('    db ' + ','.join(str(x) for x in data[i:i+32]) + '\n'
                                  for i in range(0, len(data), 32))


def generate(root):
    version = (root / 'VERSION').read_text().strip()
    if not version or any(c not in '0123456789.-abcdefghijklmnopqrstuvwxyz' for c in version):
        raise ValueError('Invalid VERSION')
    epoch = int(os.environ['SOURCE_DATE_EPOCH']) if 'SOURCE_DATE_EPOCH' in os.environ else None
    instant = datetime.fromtimestamp(epoch, timezone.utc) if epoch is not None else datetime.now(timezone.utc)
    timestamp = instant.strftime('%Y-%m-%d %H:%M UTC')
    metadata = {name: f'  {name:<7} v{version:<9} Built {timestamp}' for name in ('ROM', 'Kernel')}
    screen = design('grid3')
    screen.put(1, metadata['ROM'].ljust(78))
    screen.put(2, '  Kernel  version/build pending verification'.ljust(78))
    screen.put(3, '  TPA     pending kernel verification'.ljust(78))
    screen.item(6, 'Co-board', 'RAM switch 9000 / F000', 'SWITCHING')
    screen.item(7, 'Kernel', f'{KERNEL_RANGE}  /  SD sectors 16-{15 + LAYOUT["kernel_sectors"]}', 'WAIT')
    screen.item(9, 'Manufacturer', 'MID --  /  OEM --', 'PENDING')
    screen.item(10, 'Identity', 'Product -----  /  Serial --------', '')
    screen.item(11, 'Startup', 'SPI mode  /  attempt 1/8', 'STARTING')
    for row in range(13, 17):
        for col in (18, 44, 70):
            screen.put(row, '    --', col=col)
    for row in range(18, 24):
        screen.put(row, ' ' * 80, col=0)
    screen.put(18, '  Preparing co-board RAM switch ...')
    out = root / 'build/generated'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'boot_screen.inc').write_text(db('stock_screen', screen.chars) +
        db('stock_banner', screen.lines[0].encode('ascii') + b'\0'))
    ready = design('grid3')
    kernel = db('kernel_build_text', metadata['Kernel'].ljust(78).encode('ascii') + b'\0')
    kernel += db('kernel_tpa_text', TPA_TEXT.ljust(78).encode('ascii') + b'\0')
    for index, row in enumerate(range(13, 17)):
        kernel += db(f'drive_row_{index}', ready.lines[row][1:79].encode('ascii') + b'\0')
    kernel += db('implementation_text', f'P2000M SD System {version}\r\n'.encode('ascii') + b'\0')
    (out / 'kernel_screen.inc').write_text(kernel)
    return {'version': version, 'built_utc': instant.strftime('%Y-%m-%dT%H:%M:%SZ'),
            'display_timestamp': timestamp, 'drives': list(DRIVE_LABELS), 'memory': LAYOUT}
