# Version 0.3.0 memory budget

The TPA is **0100–CCFF: 52,224 bytes (51 KiB)**. This gains **2.25 KiB**
over 0.2.0 (48.75 KiB) and **13.25 KiB** over 0.1.0 (37.75 KiB).
CALL 5 points directly to BDOS at CD00. The CCP loader, SAVE, metadata and
boot display derive the boundary from `src/memory.inc`.

## Disposable boot code and permanent ROM

Before switching the co-board, the cartridge copies its 1,390-byte loader
from stock ROM 3000–356D into stock RAM D000–D56D. The hardware maps that RAM
to 7000–756D after the switch. E000 jumps to 7000; the loader validates and
reads the SD kernel into A000–D7FF. It remains intact throughout SD retries.

The SD kernel's cold initialization, SRAM formatting and dashboard strings
occupy A000–A4FB. After cold boot, both temporary regions belong to applications.
Normal disk I/O, console input/output, warm boot and recovery never execute them.

Permanent ROM now holds the SD protocol driver, BIOS disk operations, both
sector-cache routines, keyboard/console code, read-only BDOS/DPB tables and
the filesystem engine. All writable state stays in RAM, including the DPH
scratch words, keyboard state, FCBs, allocation maps and cache buffers.

The public BIOS BOOT entry first flushes dirty caches, then runs a ROM routine
that restores stock mapping and jumps to the monitor. The monitor reloads the
cartridge bootstrap, so cold restart works even after a maximum-size COM has
overwritten all temporary code. A flush failure instead enters the existing
warm-boot recovery prompt with dirty data retained. WBOOT never reformats L:.

## Runtime map

| Address range | Use |
| --- | --- |
| 0000–00FF | CP/M page zero |
| 0100–CCFF | 51 KiB application TPA |
| CD00–D5CE | Resident BDOS, CCP, BIOS vectors/warm restart and writable tables |
| D5CF–D5FF | 49 bytes of code-growth margin |
| D600–D6FF | 256-byte private BDOS stack |
| D700–D7FF | 256-byte CCP / initial transient stack |
| D800–D9FF | 512-byte data-sector cache |
| DA00–DA7F | Directory-record buffer |
| DA80–DB7F | Shared SD allocation bitmap |
| DB80–DBBF | BDOS/filesystem workspace |
| DBC0–DBFF | ROM SD state, boot diagnostics and CID |
| DC00–DC7F | Reserved runtime space |
| DC80–DC8F | RAM-drive allocation bitmap |
| DC90–DCAD | Sector-cache descriptors, state and counters |
| DD00–DD7F | Internal 128-byte DMA buffer |
| DD80–DD9F | Directory-entry staging |
| DDA0–DDC3 | Search FCB |
| DE00–DFFF | 512-byte directory-sector cache |
| E000–E26D | ROM SD/display/restart core |
| E26E–E75B | ROM console, cache, disk operations and read-only tables |
| E75C–E7FF | 164 spare ROM bytes |
| E800–EFBC | 1,981-byte ROM filesystem engine |
| EFBD–EFFF | 67 spare ROM bytes |
| F000–FFFF | Video; not application RAM |

Other workspace gaps remain reserved. The co-board exposes 56 KiB of linear
RAM; the 128 KiB cartridge SRAM disk is accessed through I/O ports and cannot
extend the linear TPA. ROM has 231 spare bytes in two gaps.

## Link, compatibility and tests

`tools/link_core.py` probes the full cartridge with fixed-size absolute
RAM references, exports ROM entry points, links the kernel, then links ROM
against the resulting RAM addresses. It checks exported addresses, region
bounds, loader-copy bounds and a shared 16-byte link fingerprint.
The fingerprint guards cross-reference compatibility, not authenticity.
The mismatch error path uses only disposable RAM code and direct video writes,
so it does not invoke incompatible ROM services.

The header is `P2MSYS03`; the kernel signature is `P2MCPM03`.
**Upgrade ROM and kernel as a matched pair.** SD geometry and files are unchanged;
`tools/update_kernel.py` creates an upgraded copy without overwriting its source.

Tests cover the byte-exact loader copy, delayed card insertion, header/checksum
retry, absent-card exhaustion, mismatched ROM/kernel rejection, cold restart
after TPA overwrite, and warm-boot SRAM preservation. A full 52,224-byte COM
does real SD I/O using the highest 128 bytes and checks sentinels from 7000
through CCFF, covering both disposable regions. Oversized COMs are rejected.
Stack guards, cache ordering/failure retention and all utility/Zork cases
exercise the new ROM-resident paths.
