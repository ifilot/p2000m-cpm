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
Its flag byte is 5Ch, clearing the floppy-DOS request bit previously set in
5Eh. Monitor ROM 0313h tests that bit before calling its floppy loader at
0E90h. We retain normal monitor validation and print immediately after entry;
we do not use the 58h shortcut that bypasses normal monitor initialization.
CTC channels 0–3 are disabled with control 03h at cartridge entry. Kernel warm
entry installs our own IM2 configuration and enables channel 3 for 50 Hz keyboard
scanning; the monitor's interrupt handlers are never used after remapping.
A 16 KiB ROM is mapped at stock addresses 1000–4FFF. Unused space is padded
with 00h; the header length is 3FFBh and the checksum covers offsets 5–3FFFh.
The runtime ROM remains at file offset 1000h (stock 2000h, mapped E000h).
The boot-only loader is stored at file offset 2000h (stock 3000h). Before the
switch it is copied to stock D000h, which becomes co-board RAM 7000h.
The E000 entry jumps to that disposable loader. It is never needed by warm boot.
Startup duplicates a small
switch routine at stock RAM 9000 and F000. The OUT (20h),80h at 9002 enables
co-board decoding. The next instruction at mapped 9004 comes from stock F004
and jumps to E000, the cartridge slice still visible after switching.

The stock ROM prints to video at 5000h before the switch. The temporary RAM loader
continues writing to video at F000h without clearing those lines, showing SD initialization,
header validation, completed kernel sectors, verification and kernel entry.
Its status cursor uses scratch DBD0h–DBD1h. ROM errors replace the activity row
(18, zero-based), with command/response details on row 19. The dashboard has
metadata on rows 1–2, TPA capacity on row 3, card identity on rows 9–10,
the drive grid on rows 13–16 and the prompt on row 20. E00C prints a string
at a fixed position; E00F replaces the activity row. These are boot-only services
implemented in the disposable RAM loader. The kernel checks the UI
ABI signature at E012 before calling these new services. Inverse attributes
scroll with text and are reset for application output. The E000/E003/E006/E009 jump
vectors and kernel placement remain fixed.

Initialization retries the complete CMD0/CMD8/CMD59/CMD55/ACMD41/CMD58 sequence up to eight
times, with approximately 500 ms at 2.5 MHz between attempts. Command readiness
polling is bounded at 65535 bytes (skipped for CMD0 recovery); response polling
is bounded at 256 bytes. The 1000 ACMD41 attempts have at least 1 ms spacing.
The attempt counter is at DBD2h, the boot-display flag at DBD3h, the three-pass
content-validation budget at DBD4h, and last-command/response bytes at
DBD5h–DBD6h; CID bytes occupy DBE0h–DBEFh during boot. CMD10 reads a 16-byte
CID data block and validates its trailing CRC16; byte zero is the MID,
as defined by the [SD Association physical-layer specification](https://www.sdcard.org/cms/wp-content/themes/sdcard-org/dl.php?f=Part1_Physical_Layer_Simplified_Specification_Ver6.00.pdf).
MID, OEM, product and serial are shown for debugging; the full CID remains in
scratch. An unavailable or CRC-invalid CID is nonfatal and its identity fields
are not displayed. Retries do not reset the co-board or CPU and
do not reformat the card. The E003h read entry retries three times, reinitializing
between failed reads while retaining the requested LBA and destination. This
covers header/kernel/MBR and runtime reads. Boot header, signature or checksum
failures restart the load for at most three passes. Recovery output is enabled
until BIOS disk initialization completes, then disabled for applications.
The write entry remains synchronous and is never automatically replayed.

The SD driver initializes SDHC SPI mode using CMD0, CMD8, CMD59, CMD55/ACMD41,
and CMD58. It reads the system header at LBA 15 and loads 28 sectors from LBA 16
into A000–D7FF. It validates the header, kernel size, kernel signature and
16-bit additive checksum before executing A000. Missing/unresponsive cards,
invalid signatures, and checksum errors produce `SD BOOT ERROR` and halt.
Polling loops are bounded. The additive checksum detects accidental corruption;
it is not an authentication mechanism.

The SD driver generates CRC7 (polynomial 09h, zero initial value, MSB first)
over every command's five bytes, then appends the end bit. CMD59 with argument
1 is mandatory before ACMD41 on every initialization, including recovery after CMD0;
the expected CMD59 response is 01h (still idle). There
is no fallback to unchecked communication. All 512-byte sector transfers and
the 16-byte CID block use CRC16 (polynomial 1021h, zero initial value, no final
XOR, high byte first on the wire). CRC16 is folded one byte at a time without
a lookup table or additional RAM state.

A read CRC mismatch returns failure before the cache can mark the sector
valid. Both CRC bytes are consumed, and the existing three-attempt read path
reinitializes the card between attempts. The diagnostic response byte is 08h
for a locally detected read CRC mismatch. Writes send a calculated CRC16 and
still require an accepted data-response token and completion of busy polling.
The actual write-response token is retained for diagnosis (0Bh means CRC
rejection). Failed writes are not automatically replayed; dirty cache data and
dependent metadata remain available for explicit retry. CRC does not provide
authentication, persistent file checksums, or write-readback verification.

The exact runtime map is documented in [memory-budget.md](memory-budget.md)
and defined by `src/memory.inc`. The TPA is 0100–C8FF (50 KiB).
The packed RAM system starts at C900; the filesystem engine occupies always-
mapped ROM E800–EFBC. Buffers and all ROM/BDOS scratch remain outside the TPA.
The 14 KiB load image stops at D800 so it never overwrites active ROM state.
Cold boot initializes runtime buffers separately, preserving the ROM scratch.
Both the 7000 loader and A000 cold bootstrap can subsequently be overwritten
by applications. BIOS BOOT flushes and returns through the stock monitor to
recreate them; WBOOT stays resident and preserves the RAM drive.

Applications enter at 0100. Location 0000 jumps to BIOS warm boot; location
0005 jumps directly to the BDOS entry at C900. BDOS uses a private stack and returns results
in HL and A/B. The command processor stays resident above the reported TPA
limit, so warm boot need not reload it or overwrite the RAM drive. Warm boot
restores the command processor's drive from page zero. SD writes are buffered;
warm boot flushes data and metadata before restarting the prompt. Failed
flushes retain dirty buffers and wait for an explicit R retry.

## SD image

The image is 153 MiB. Physical sectors are 512 bytes. All partition sizes and
starts are explicit MBR LBA fields; CHS fields are placeholders.

| Region | Start LBA | Sectors | Type / contents |
| --- | ---: | ---: | --- |
| MBR | 0 | 1 | Two primary partition entries |
| System header | 15 | 1 | `P2MSYS03`, little-endian size and checksum |
| Kernel | 16 | 28 | 14 KiB load image; `P2MCPM03` signature at offset 3 |
| FAT32 | 2048 | 131072 | Type 0Ch, exactly 64 MiB |
| CP/M container A:–K: | 133120 | 180224 | Type 52h, eleven fixed 8 MiB slices |

Other sectors before the FAT32 partition are reserved and zero-filled. FAT32
has 512-byte clusters, 32 reserved sectors, two FATs, a root directory containing
its volume label, FSInfo, and backup boot/FSInfo sectors. Construction follows
the [Microsoft FAT specification](https://www.scs.stanford.edu/~zyedidia/docs/_other/fat.pdf).
The ROM boots the alignment-gap kernel independently of FAT32. The BIOS
validates the FAT32 and CP/M container types, starts and lengths, and requires
unused MBR entries to be zero before allowing access. Slice `d` starts at
`133120 + d*16384` for `d=0..10`; L: is SRAM. The old layout is rejected;
repartitioning requires updating the BIOS and image builder together.

## CP/M geometry

| DPB field | A:–K: | L: |
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
blocks consume 16 KiB, leaving 8,372,224 data bytes per volume. L: uses 1 KiB
blocks, 8-bit allocation pointers, and a 2 KiB directory, leaving 126 KiB.
All drives support CP/M user areas 0–15 and the standard extent/record format.
Files have record-granular lengths; exact trailing byte counts are not stored.

The SD BIOS deblocks 128-byte records through two 512-byte sector caches.
It preserves adjacent records and reports read-only/I/O errors at eviction or
commit (an ordinary buffered WRITE may succeed before the medium rejects it).
The SRAM
BIOS explicitly sets low address port 48h, high address 49h and bank 4Bh for
data transfers through 4Dh. There is no auto-increment hardware assumption.
Both SRAM banks are formatted only on cold boot.

The cartridge's software-controlled READ/WRITE LEDs use port 44h: bit 0 is
READ, bit 1 is WRITE, and zero turns both off. SD commands light READ except
CMD24, which lights WRITE through the data/CRC and busy wait. `sd_close` clears
both on every normal/error exit, including retries. Physical SRAM record reads
and writes use the same LEDs; cold formatting lights WRITE. Cache hits and
writes staged only in CPU RAM do not light either LED. The cartridge's separate
SEL/ACT indicators remain hardware-controlled. The original rev6 schematic's
"$64" annotation is a typo: its decoder and original `src/ports.inc` specify 44h.

### Sector cache and durability

`src/cache.asm` keeps one data sector at D800h and one directory sector at
DE00h. The directory is exactly SD track zero (16 KiB) on all eleven SD
volumes. Each descriptor has valid/dirty flags, the complete 32-bit physical
LBA and a buffer pointer. DC90h/DC98h hold the descriptors; DCA0h–DCA5h hold
request/fault/hint state. DCA6h/DCA8h/DCAAh/DCACh are 16-bit counters for ROM
read calls, successful sector writes, cache hits and write attempts (wrapping).
The second buffer uses previously unused kernel RAM; TPA size is unchanged.

On a hit, only 128 bytes move between DMA and the sector buffer. On a miss,
dirty eviction must succeed before replacement. A data eviction writes only
data; a dirty directory eviction writes data first, then directory metadata.
A clean directory miss does not flush data. A failed fill never publishes a
valid tag, including in the filesystem's upper 128-byte directory buffer.

CLOSE, BDOS 13/37 disk resets, drive changes, and warm boot/prompt entry flush
both buffers. CREATE/DELETE/RENAME/attribute operations also commit before
returning, including partial changes on failure. BIOS WRITE hint 1 requests
an immediate ordered barrier; hints 0/2 allow buffering. Vector 17 at BIOS base + 51
is a project extension for explicit flush (A=0 success, 1 error; IX/IY preserved).
Standard vector order is unchanged; their absolute addresses have moved.

After a rejected flush, pending tags/bytes remain dirty and ordinary cached
I/O is blocked. An explicit flush retry reinitializes the original card and
retries the pending commits. A data failure prevents directory writeback; a
directory failure leaves already-committed data intact and retains metadata.
No rollback, sector atomicity or power-loss journal is claimed. Fixed mounted
media is assumed: never substitute another card while dirty state exists.
Clients bypassing the BIOS via raw ROM I/O must flush/invalidate appropriately;
raw writes behind the cache and live card changes are not coherent.

The cache test counts actual calls to E003h/E006h, checks ordering and neighbours,
injects read and write failures, retries CLOSE and warm boot, and checks
the fixed expected traffic counts. Historical raw kernel swaps are no longer
supported because the ROM/SD workspace ABI changed.
The measured 32-record sequential write/read case uses 16 reads + 8 writes,
versus 64 + 32 without caching. Alternating four data and four directory
record writes needs two reads and two ordered writes with the separate caches.

The CP/M BIOS jump table is linked in packed RAM and provides all 17 CP/M 2.2
entries. Discover its base as the warm-boot vector at 0001 minus three; do not
hard-code C000. The extended flush vector remains index 17 (base + 51).
Resident ROM entry E003 reads one physical SD sector; E006 writes one; E009
initializes SDHC. The 32-bit little-endian LBA is at DBC0 and buffer pointer at
DBC4. These routines return A=0 on success, A=1 on failure and clobber AF/BC/DE/HL.
No driver uses the floppy controller ports or MultiWare ports 95h–97h.

## BDOS and console

The BDOS dispatch covers the documented CP/M 2.2 calls through function 40:
console input/output, buffered lines, drive/DMA/user management, directory
search, open/create/close/delete/rename, attributes and protection, allocation
and DPB queries, sequential/random records, size and random-position conversion.
Functions 38–39 return zero. Reader input returns EOF; unconnected list/punch
output is discarded. The API is based on the
[Digital Research system-interface documentation](https://www.cpm.z80.de/manuals/archive/cpm22htm/ch5.htm).

Allocation pointers are checked against reserved directory blocks and the
selected medium's block count before address arithmetic. Physical filesystem
I/O errors and invalid nonzero allocation pointers print a BDOS hard error
and warm-boot; they cannot masquerade as ordinary EOF or file-not-found.
Direct BIOS calls retain their error-return contract. Dirty cache data is
retained if warm-boot flushing fails. This is detection, not directory repair.
Missing-extent writes check the existing file's on-disk read-only attribute,
even when the caller supplies a fresh FCB. OPEN selects by EX/S2, preserves CR,
and binds wildcard names to the matched file. Search with DR='?' returns raw
directory entries, including free slots and other users. SELECT logs in the
selected drive immediately.

Cooked BDOS console calls support Ctrl-S pause and Ctrl-Q resume; Ctrl-C while
paused warm-boots. Direct function 6 remains raw. Buffered input supports TAB,
Ctrl-E physical newline, Ctrl-R redraw, Ctrl-U/X line deletion, and BS/DEL
across expanded tabs and display rows. Ctrl-C warm-boots on an empty line and
is retained as a character mid-line. Other control bytes echo in caret form.
These paths are covered by `tests/bdos_conformance.cpp` on SD and SRAM media.

The built-in software-timed RS232 port is documented and exercised by three
standalone programs; see [serial hardware testing](serial-testing.md).
It is not yet connected to BIOS peripheral device routing.

Normal writes stage data, extent lengths and allocation pointers in the cache.
Close commits pending data before metadata and confirms the file exists;
it returns an error if the commit fails.
All SD DPHs share a 256-byte allocation scratch bitmap, rebuilt from the
selected directory before every allocation or BDOS 27 query. L: has a separate
16-byte bitmap. This avoids eleven resident bitmaps and leaves TPA unchanged.
Login and protection masks are 16-bit words at DBB6h and DBB4h. BDOS 24/29
return both bytes; BDOS 37 selectively resets both bytes.
Newly allocated blocks are zeroed, including function 40
writes. No journal or power-loss atomicity is claimed.

The console writes video RAM and supports scrolling, CR/LF, tabs, backspace and
form feed. Keyboard scanning runs from the CTC channel-3 interrupt at 50 Hz,
with per-key two-sample debounce and a 63-byte FIFO. Shift and Escape-prefix
translation happen when events enter the queue. Repeat starts after 50 ticks
and then repeats every two ticks. Full terminal escape-sequence emulation is
not implemented; programs should use the simple CP/M console interface.

The IM2 vector is a ROM word at E7FE (I=E7, CTC base F8, channel-3 vector FE).
The ISR saves main registers and IX on its own 128-byte stack, leaving IY and
alternate registers untouched. It never calls BDOS or accesses SD state. FIFO
head is published after storing a byte; the consumer releases a slot only
after reading it. Overflow retains old input and sets a sticky diagnostic flag.
DI console callers run two synchronous scans without changing their interrupt
state; repeat is never advanced by application polling. BIOS warm boot restores
IM2/CTC ownership, while cold restart disables the keyboard CTC and restores
IM0/I=0 before entering the monitor.

## Verification

`python3 -m unittest discover -s tests -v` checks MBR placement, FAT32 geometry,
FAT/FSInfo/root structures, backup records, filename rejection and CP/M imports
across logical/physical extent boundaries.

`python3 tools/test_emulator.py` compiles the existing emulator core and executes
these independent integration harnesses:

- ROM-driven co-board switching and byte-exact 14 KiB loading before execution.
- Missing-card and corrupt-kernel boot errors.
- BIOS reads/writes at SD sector/track/end-of-partition boundaries, followed by
  an independent comparison of every record in all eleven persisted CP/M volumes.
- Read-only card rejection, invalid drive/track rejection, both SRAM bank
  boundaries, and RAM-drive preservation through warm boot.
- Keyboard-driven CCP execution of original transient programs.
- `CPMTEST.COM`: 600 records on A: only, close/reopen, extent transitions,
  sequential/random reads, file size and deletion. RAMTEST separately exercises L:.
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
Monitor ROM and emulator CPU/device code are bundled in `tests/emulator`;
see its [provenance and update guide](../tests/emulator/README.md).
The preceding 16 KiB cartridge build was reported to boot on real hardware.
The 0.3.0 ROM/RAM relocation and diagnostics are emulator-tested and await a hardware
trial; physical SD timings and full hardware storage tests remain unverified.
