# Version 0.1.0 memory budget

The TPA is 0100–97FF inclusive: 0x9800 - 0x0100 = 38,656 bytes = 37.75 KiB.
This is enforced, not just displayed: page-zero CALL 5 points to a trampoline
at 9800, and the CCP loader refuses COM data beyond that boundary. The
TPALIMIT regression loads all 38,656 bytes and checks the highest bytes survive.

The co-board's current fixed hardware decode gives CPU-addressable RAM at
0000–DFFF (56 KiB), cartridge ROM at E000–EFFF, and video at F000–FFFF.
Thus 56 KiB is the total RAM map, not the application capacity.

| Address range | Reserved use | Size |
| --- | --- | ---: |
| 0000–00FF | CP/M page zero | 256 bytes |
| 0100–97FF | TPA | 37.75 KiB |
| 9800–9FFF | BDOS trampoline, stacks, ROM/BDOS scratch | 2 KiB |
| A000–A7FF | Entry and resident command processor | 2 KiB |
| A800–BFFF | BDOS and filesystem | 6 KiB |
| C000–D7FF | BIOS, console and tables | 6 KiB |
| D800–DFFF | Sector/directory buffers and allocation workspace | 2 KiB |
| E000–EFFF | Resident ROM driver | 4 KiB (not RAM) |
| F000–FFFF | Video | 4 KiB (not TPA) |

The fixed module boundaries are conservative and waste space. A 0.1.0 layout
audit found approximately 7.4 KiB of padding between the end of the CCP and
A800, the end of the filesystem and C000, and the end of BIOS data and D800.
Those holes are not available as contiguous TPA in the current layout.

Repacking the resident modules, stacks and buffers could reclaim substantial
space, but requires relocating code, auditing absolute addresses, and repeating
ABI/TPA/cache/real-hardware tests. A 54 KiB TPA would leave only 1.75 KiB of the
56 KiB RAM map for all resident OS code, stacks and buffers after page zero.
That cannot be achieved by changing the loader limit or banner alone. Further
gains would require a much smaller resident system and/or an explicitly designed
overlay/banking strategy. This release does not implement that redesign.

Source evidence: `src/kernel.asm`, `src/bios.asm`, `src/ccp.asm`,
`tests/tpalimit.asm`, and the sibling co-board's
`cupl/p2000m-cpm-coboard.pld` (`CPM_RAM1/2/3`, `CPM_CART1`, `CPM_VIDEO`).
