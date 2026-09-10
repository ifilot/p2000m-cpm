# Architecture and verification

## Scope

Original Z80 source implements the boot ROM, CP/M-compatible BIOS/BDOS, command
processor and example programs. Host Python handles assembly orchestration and
raw image construction. The emulator is used only to execute actual Z80 code
against its hardware model; filesystem operations do not use host-service traps.

The co-board is required and assumed present, as confirmed by the user. FAT32
file access from within CP/M is deliberately left as the requested future
extension. Disk functions always address the SD cartridge or its SRAM.

## Boot and CPU memory

The cartridge header uses the P2000 monitor's length and additive checksum.
An 8 KiB ROM is mapped at stock addresses 1000–2FFF. Startup duplicates a small
switch routine at stock RAM 9000 and F000. The OUT (20h),80h at 9002 enables
co-board decoding. The next instruction at mapped 9004 comes from stock F004
and jumps to E000, the cartridge slice still visible after switching.

The resident loader initializes SDHC SPI mode using CMD0, CMD8, CMD55/ACMD41
and CMD58. It reads the system header at LBA 15 and loads 32 sectors from LBA 16
into A000–DFFF. It validates the header, kernel size, kernel signature and
16-bit additive checksum before executing A000. Missing/unresponsive cards,
invalid signatures, and checksum errors produce `SD BOOT ERROR` and halt.
Polling loops are bounded. The additive checksum detects accidental corruption;
it is not an authentication mechanism. SD data CRC is disabled in SPI mode.

| CPU addresses | Purpose |
| --- | --- |
| 0000–00FF | Standard CP/M page zero, FCBs, command tail/DMA |
| 0100–97FF | Transient program area, up to 38,656 bytes |
| 9800–9802 | BDOS entry trampoline, referenced by CALL 5 |
| 9803–9FFF | System stacks and working state |
| A000–A7FF | Kernel entry and command processor |
| A800–BFFF | BDOS and filesystem engine |
| C000–D7FF | BIOS, console, geometry and working state |
| D800–DFFF | Sector/directory buffers and allocation maps |
| E000–EFFF | Resident cartridge loader and SD block routines |
| F000–FFFF | Character and attribute video RAM |

Applications enter at 0100. Location 0000 jumps to BIOS warm boot; location
0005 jumps through 9800 to BDOS. BDOS uses a private stack and returns results
in HL and A/B. The command processor stays resident above the reported TPA
limit, so warm boot need not reload it or overwrite the RAM drive. Warm boot
restores the command processor's drive from page zero. Disk writes are
write-through, so successful writes require no deferred cache flush.

## SD image

The image is 81 MiB. Physical sectors are 512 bytes. All partition sizes and
starts are explicit MBR LBA fields; CHS fields are placeholders.

| Region | Start LBA | Sectors | Type / contents |
| --- | ---: | ---: | --- |
| MBR | 0 | 1 | Three primary partition entries |
| System header | 15 | 1 | `P2MSYS01`, little-endian size and checksum |
| Kernel | 16 | 32 | 16 KiB kernel; `P2MCPM01` signature at offset 3 |
| FAT32 | 2048 | 131072 | Type 0Ch, exactly 64 MiB |
| A: | 133120 | 16384 | Type 52h, exactly 8 MiB |
| B: | 149504 | 16384 | Type 52h, exactly 8 MiB |

Other sectors before the FAT32 partition are reserved and zero-filled. FAT32
has 512-byte clusters, 32 reserved sectors, two FATs, a root directory containing
its volume label, FSInfo, and backup boot/FSInfo sectors. Construction follows
the [Microsoft FAT specification](https://www.scs.stanford.edu/~zyedidia/docs/_other/fat.pdf).
The ROM boots the alignment-gap kernel independently of FAT32. The BIOS
validates both CP/M partition types, starts and lengths before allowing access;
repartitioning requires updating the BIOS and image builder together.

## CP/M geometry

| DPB field | A: and B: | C: |
| --- | ---: | ---: |
| SPT | 128 | 32 |
| BSH / BLM | 5 / 31 | 3 / 7 |
| EXM | 1 | 0 |
| DSM | 2047 | 127 |
| DRM | 511 | 63 |
| AL0 / AL1 | F0h / 00h | C0h / 00h |
| CKS / OFF | 0 / 0 | 0 / 0 |

Each SD volume has 4 KiB allocation blocks and 16-bit block numbers: eight
allocation pointers cover 32 KiB per physical directory entry. Four directory
blocks consume 16 KiB, leaving 8,372,224 data bytes per volume. C: uses 1 KiB
blocks, 8-bit allocation pointers, and a 2 KiB directory, leaving 126 KiB.
All drives support CP/M user areas 0–15 and the standard extent/record format.
Files have record-granular lengths; exact trailing byte counts are not stored.

The SD BIOS deblocks 128-byte records with a 512-byte read/modify/write buffer.
It preserves adjacent records and propagates read-only/I/O failures. The SRAM
BIOS explicitly sets low address port 48h, high address 49h and bank 4Bh for
data transfers through 4Dh. There is no auto-increment hardware assumption.
Both SRAM banks are formatted only on cold boot.

The CP/M BIOS jump table starts at C000 and provides all 17 CP/M 2.2 entries.
Resident ROM entry E003 reads one physical SD sector; E006 writes one; E009
initializes SDHC. The 32-bit little-endian LBA is at 9E00 and buffer pointer at
9E04. These routines return A=0 on success, A=1 on failure and clobber AF/BC/DE/HL.
No driver uses the floppy controller ports or MultiWare ports 95h–97h.

## BDOS and console

The BDOS dispatch covers the documented CP/M 2.2 calls through function 40:
console input/output, buffered lines, drive/DMA/user management, directory
search, open/create/close/delete/rename, attributes and protection, allocation
and DPB queries, sequential/random records, size and random-position conversion.
Functions 38–39 return zero. Reader input returns EOF; unconnected list/punch
output is discarded. The API is based on the
[Digital Research system-interface documentation](https://www.cpm.z80.de/manuals/archive/cpm22htm/ch5.htm).

Metadata and data writes are synchronous. Close confirms the file exists;
normal writes have already persisted extent lengths and allocation pointers.
Allocation maps are reconstructed from the directory when allocating or
querying free space. Newly allocated blocks are zeroed, including function 40
writes. No journal or power-loss atomicity is claimed.

The console directly scans the keyboard matrix and writes video RAM. It
supports scrolling, CR/LF, tabs, backspace and form feed. Escape prefixes provide
control characters without changing the emulator's key mapping. Full terminal
escape-sequence emulation, interrupt-driven input and typematic repeat are not
implemented. Interactive programs should use the simple CP/M console interface.

## Verification

`python3 -m unittest discover -s tests -v` checks MBR placement, FAT32 geometry,
FAT/FSInfo/root structures, backup records, filename rejection and CP/M imports
across logical/physical extent boundaries.

`python3 tools/test_emulator.py` compiles the existing emulator core and executes
these independent integration harnesses:

- ROM-driven co-board switching and byte-exact 16 KiB loading before execution.
- Missing-card and corrupt-kernel boot errors.
- BIOS reads/writes at SD sector/track/end-of-partition boundaries, followed by
  an independent comparison of every record in both persisted CP/M volumes.
- Read-only card rejection, invalid drive/track rejection, both SRAM bank
  boundaries, and RAM-drive preservation through warm boot.
- Keyboard-driven CCP execution of original transient programs.
- `CPMTEST.COM`: 600 records per drive, close/reopen, extent transitions,
  sequential/random reads, file size and deletion across A:, B:, C:.
- Unmodified PIP, STAT, ASM, LOAD, DUMP, DDT and ED from the bundled collection. ASM
  and LOAD build a test program that executes; ED edits and saves a text file.
- Exact TPA-size COM execution, oversized-COM rejection, original COPY, REN and SAVE.
- Sparse 8 MiB logical-file length, random/sequential overflow, zero filling,
  attributes, user-area isolation, directory exhaustion/reclamation and drive
  write protection through actual CALL 5 instructions.
- A hash of the entire FAT32 partition before/after tests, and independent
  host decoding of files produced by the CP/M applications.

The seven standard utility binaries are bundled in `assets/cpm_core` and
installed in drive A: of the deliverable. Tests verify each installed binary
byte-for-byte, run the utilities, and compare DUMP's first and last output rows
against a known 128-byte input file. Source provenance and hashes are recorded
in [the collection README](../assets/cpm_core/README.md).
Monitor ROM and emulator CPU/device code remain in the referenced checkout.
Physical cartridge timing and real hardware have not been tested; emulator
success is not a substitute for a hardware trial.
