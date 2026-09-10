# Version 0.2.0 memory budget

The TPA is **0100–C3FF: 49,920 bytes (48.75 KiB)**. Version 0.1.0 provided
38,656 bytes (37.75 KiB), so this release gains **11 KiB, or 29.1%**.
Page-zero CALL 5 points directly to BDOS at C400. The CCP enforces that same
boundary when loading COM files and executing SAVE. Build metadata and the
boot display derive their numbers from `src/memory.inc`.

## How the space was recovered

- Pack BDOS, CCP and BIOS consecutively instead of reserving oversized regions.
- Keep cold-only startup at A000; applications reclaim it after cold boot.
  No warm-boot path depends on those bytes.
- Move the 1,981-byte filesystem engine into always-mapped ROM at E800–EFBC.
  No banking or copying is needed. Mutable state, FCBs, DMA and caches stay in RAM.
- Move ROM/BDOS scratch out of the old 9E00/9F00 application region.
- Compact the stacks. CCP and initial transient stack share space because they
  do not execute concurrently; BDOS has an independent stack.
- Load only A000–D7FF (14 KiB). Initialize runtime buffers separately, preserving
  the ROM state at DBC0–DBFF. Loading over that state would corrupt active SD I/O.

## Runtime map

| Address range | Use |
| --- | --- |
| 0000–00FF | CP/M page zero |
| 0100–C3FF | 48.75 KiB application TPA |
| C400–D5E2 | Packed BDOS, CCP, BIOS, console, cache code and tables |
| D5E3–D5FF | 29 bytes of code-growth margin; overflow fails assembly |
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
| E000–E7FF | ROM loader, SD driver and display routines |
| E800–EFBC | ROM filesystem engine |
| EFBD–EFFF | 67 spare bytes in filesystem ROM region |
| F000–FFFF | Video; not application RAM |

Other workspace gaps are reserved. The co-board still exposes 56 KiB of
CPU-addressable RAM. The 128 KiB SRAM disk is accessed through I/O ports, not
additional linear TPA. A 54 KiB TPA would require a more extensive resident
system reduction or a banking/overlay design.

## Link and compatibility checks

`tools/link_core.py` first measures filesystem labels at E800 using fixed-size
absolute RAM references, links the compact kernel, then builds ROM against
the resulting RAM addresses. Every filesystem label and its embedded bytes
are checked against the linked module. Region overflow fails assembly.
A 16-byte link fingerprint is embedded in both artifacts; the kernel checks it
before calling ROM services. This guards cross-reference compatibility, not
authenticity. ROM and kernel must be upgraded as a matched build.

The header is `P2MSYS02`; the payload signature is `P2MCPM02`. Older ROMs reject
the new payload rather than loading it with the old memory map. Disk geometry
and drive assignments are unchanged from 0.1.0.

Tests execute a full 49,920-byte COM, use its highest 128 bytes for real SD I/O,
check sentinels throughout reclaimed memory, flush/reopen/delete, and return
through warm boot. Oversized COM files are rejected. Stack canaries cover
filesystem, cache recovery, utility and Zork tests. Historical raw kernel
swapping for cache benchmarking is no longer safe across ROM ABI versions;
the normal cache traffic regression remains supported.
