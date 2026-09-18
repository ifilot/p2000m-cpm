# Version 0.4.1 memory budget

The TPA is **0100–C8FF: 51,200 bytes (50 KiB)**. The VT52-style terminal
parser reserves another **512 bytes** relative to the preceding 50.5 KiB
layout. It stays resident without requiring bank-capable hardware.
CALL 5 points directly to BDOS at C900. The CCP loader, SAVE, metadata and
boot display derive the boundary from `src/memory.inc`.

## Disposable boot code and permanent ROM

Before switching the co-board, the cartridge copies its 1,420-byte loader
from stock ROM 3000–358B into stock RAM D000–D58B. The hardware maps that RAM
to 7000–758B after the switch. E000 jumps to 7000; the loader validates and
reads the SD kernel into A000–D7FF. It remains intact throughout SD retries.

The SD kernel's cold initialization, SRAM formatting and dashboard strings
occupy A000–A4F3. After cold boot, both temporary regions belong to applications.
Normal disk I/O, console input/output, warm boot and recovery never execute them.

Permanent ROM now holds the SD protocol driver, BIOS disk operations, both
sector-cache routines, keyboard/console code, read-only BDOS/DPB tables and
the filesystem engine. All writable state stays in RAM, including the DPH
scratch words, keyboard state, FCBs, allocation maps and cache buffers.
Boot-only display routines have moved into the disposable loader to make room
for SD CRC7/CRC16. The runtime recovery stub checks the boot-active flag before
calling them. CRC itself needs no extra resident RAM. CRC7 and the wire CRC16 check now
share the ROM tail with CRC16 to make room for physical I/O activity LEDs. The later BDOS audit
fixes move FCB positioning, synchronization and block validation into resident
`src/fcb.asm`, freeing ROM for filesystem checks. The dispatch and DPB tables
remain in ROM. Terminal escape parsing and erasure live in resident RAM;
printable output, scrolling and the register-preserving console wrapper remain
in ROM. The parser and warm-boot reset exceed the previous 16-byte margin plus
a single 256-byte page, requiring two pages.

The public BIOS BOOT entry first flushes dirty caches, then runs a ROM routine
that restores stock mapping and jumps to the monitor. The monitor reloads the
cartridge bootstrap, so cold restart works even after a maximum-size COM has
overwritten all temporary code. A flush failure instead enters the existing
warm-boot recovery prompt with dirty data retained. WBOOT never reformats L:.

## Runtime map

| Address range | Use |
| --- | --- |
| 0000–00FF | CP/M page zero |
| 0100–C8FF | 50 KiB application TPA |
| C900–D509 | Resident BDOS, FCB helpers, CCP, BIOS vectors/CTC setup/warm restart, terminal parser and writable tables |
| D50A–D5FF | 246 bytes of code-growth margin |
| D600–D6FF | 256-byte private BDOS stack |
| D700–D7FF | 256-byte CCP / initial transient stack |
| D800–D9FF | 512-byte data-sector cache |
| DA00–DA7F | Directory-record buffer |
| DA80–DB7F | Shared SD allocation bitmap |
| DB80–DBBF | BDOS/filesystem workspace |
| DBC0–DBFF | ROM SD state, boot diagnostics and CID |
| DC00–DC7F | 128-byte private keyboard interrupt stack |
| DC80–DC8F | RAM-drive allocation bitmap |
| DC90–DCAD | Sector-cache descriptors, state and counters |
| DCC0–DCFF | Keyboard FIFO (64 slots, 63 usable) |
| DD00–DD7F | Internal 128-byte DMA buffer |
| DD80–DD9F | Directory-entry staging |
| DDA0–DDC3 | Search FCB |
| DDC4–DDE0 | Keyboard matrix history, queue/repeat/control state and saved IRQ SP |
| DE00–DFFF | 512-byte directory-sector cache |
| E000–E271 | ROM SD/restart core |
| E272–E7E1 | ROM keyboard/console, cache, disk operations and read-only tables |
| E7E2–E7FD | 28 spare ROM bytes |
| E7FE–E7FF | IM2 keyboard vector |
| E800–EF6A | 1,899-byte ROM filesystem engine |
| EF6B–EF82 | ROM keyboard-repeat routine |
| EF83–EFA6 | Table-free ROM CRC16 byte update |
| EFA7–EFBD | CRC7 byte update and wire CRC16 check |
| EFBE–EFFF | 66 spare ROM bytes |
| F000–FFFF | Video; not application RAM |

Other workspace gaps remain reserved. The co-board exposes 56 KiB of linear
RAM. The modern-revised board additionally offers seven optional 16 KiB banks
at 4000–7FFF; these are not yet used by this kernel. See the
[bank-switching assessment](bank-switching.md) for the interface and proposed use.
The 128 KiB cartridge SRAM disk is accessed through I/O ports and cannot
extend the linear TPA. ROM has 94 spare bytes in two gaps. The interrupt-driven
keyboard uses previously reserved workspace. Standalone serial diagnostics
consume TPA only while running and do not change this resident budget.

## Link, compatibility and tests

`tools/link_core.py` probes the full cartridge with fixed-size absolute
RAM references, exports ROM entry points, links the kernel, then links ROM
against the resulting RAM addresses. It checks exported addresses, region
bounds, loader-copy bounds and a shared 16-byte link fingerprint.
The fingerprint guards the shared release version and cross-reference compatibility,
not authenticity.
The mismatch error path uses only disposable RAM code and direct video writes,
so it does not invoke incompatible ROM services.

The header is `P2MSYS03`; the kernel signature is `P2MCPM03`.
**Upgrade ROM and kernel as a matched pair.** SD geometry and files are unchanged;
`tools/update_kernel.py` creates an upgraded copy without overwriting its source.

Tests cover the byte-exact loader copy, delayed card insertion, header/checksum
retry, absent-card exhaustion, mismatched ROM/kernel rejection, cold restart
after TPA overwrite, and warm-boot SRAM preservation. A full 51,200-byte COM
does real SD I/O using the highest 128 bytes and checks sentinels from 7000
through C8FF, covering both disposable regions. Oversized COMs are rejected.
Stack guards, cache ordering/failure retention and all utility/Zork cases
exercise the new ROM-resident paths.
CRC tests check fixed CRC7/CRC16 vectors and introduce faults at the SPI bridge
in command, data and CRC bytes. They verify boot recovery, CID rejection,
bounded retries, mandatory CRC enablement and retention of failed cached writes.
Runtime CRC/reinitialization tests overwrite both disposable RAM regions first.
