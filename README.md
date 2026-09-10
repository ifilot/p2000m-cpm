# P2000M SD CP/M — 0.3.0

An original Z80 assembly implementation of the CP/M 2.2 interface for a
P2000M with its **CP/M co-board installed**, a 16 KiB boot cartridge in port 1,
and the SD/SRAM cartridge in port 2. The cartridge activates the co-board
memory map itself. All disk operations use the SD cartridge; no floppy drive,
floppy media, or MultiWare RAM-disk hardware is used.

The system includes a BIOS, BDOS, command processor, SD image builder, and
original `HELLO.COM`, `COPY.COM`, and `CPMTEST.COM` programs. It is an independent
CP/M-compatible implementation, not a copy of Digital Research's operating
system. Drive A: also includes the standard **PIP, ASM, LOAD, DDT, DUMP, ED,
and STAT** utilities. Their binaries are preserved unchanged; see
[utility provenance and checksums](assets/cpm_core/README.md).

## Drives and image layout

The 153 MiB image contains a 64 MiB FAT32 partition and one 88 MiB CP/M
container split into eleven equal 8 MiB volumes. The 1 MiB alignment gap
contains the MBR, system header and kernel. FAT32 is host-accessible;
**FAT32 file access from CP/M is not implemented**.

| Drive | Label | Medium / capacity |
| --- | --- | --- |
| A: | SYSTEM | SD / 8 MiB; system utilities and test programs |
| B: | TOOLS | SD / 8 MiB; extra applications |
| C: | ZORK | SD / 8 MiB; Zork I, II and III with their data files |
| D: | GAMES | SD / 8 MiB |
| E: | BASIC | SD / 8 MiB |
| F: | ASM | SD / 8 MiB |
| G: | SOURCE | SD / 8 MiB |
| H: | DOCS | SD / 8 MiB |
| I: | DATA | SD / 8 MiB |
| J: | EXTRA 1 | SD / 8 MiB |
| K: | EXTRA 2 | SD / 8 MiB |
| L: | SCRATCH | SRAM / 128 KiB; 126 KiB usable |

Labels suggest uses, not restrictions. Apart from A: and C:, SD drives start
empty. The version 0.3.0 BIOS deliberately rejects the old two-partition
CP/M layout before permitting writes.

**Upgrade requires both the new port-1 ROM and an updated SD kernel.** Back up files
from your existing card first; writing the full template replaces its partition
table and contents. The build never writes to a physical card or your separately
named working image. Keep the old ROM/image pair together if you want to return
to the earlier version. A header/ABI guard rejects older artifacts; a link fingerprint guards ROM/kernel cross-references.

## Updating an existing 0.1.0 or 0.2.0 image

The eleven SD volumes and their files are unchanged by 0.3.0. To retain your
files, first back up/read your existing card into an image, then create an
upgraded copy:

```sh
python3 tools/update_kernel.py existing-card.img upgraded-card.img
```

The tool validates the layout, refuses to overwrite an existing destination,
and changes only the kernel/header in the copy. It does not access physical
cards. Install the matching 0.3.0 cartridge ROM as well. Writing the freshly
built template instead would replace existing files with the bundled defaults.

## Build and test

Requirements: Python 3.11+, `z80asm` (Debian syntax), and GCC/G++ for emulator tests.
The default emulator path is `../p2000m-emulator`. Zork binaries are read from
`/mnt/d/PROGRAMMING/p2000c/p2000c-cpm-transfer/programs/games/zork`; use
`python3 tools/build.py --zork-dir /path/to/zork` elsewhere. They are copied
byte-for-byte into the generated image, not added to the source repository.

```sh
python3 tools/build.py
python3 tools/package.py  # optional: regenerate packaging/checksums only
python3 -m unittest discover -s tests -v
python3 tools/test_emulator.py
python3 tools/test_programs.py  # isolated utility and register-contract cases
# Or specify another checkout:
python3 tools/test_emulator.py --emulator /path/to/p2000m-emulator
```

Build outputs:

- `build/cartridge.bin`: signed 16 KiB port-1 ROM, with unused space padded with `0x00`.
- `build/kernel.bin`: 14 KiB load image (runtime buffers are initialized separately), also installed in the SD image.
- `build/p2000m-sd-template.img.gz`: compressed image, produced automatically by the build.
- `build/SHA256SUMS`: checksums for the ROM, kernel, images, build manifest and original COM utilities.
- `build/build-info.json`: version, UTC build time, drive labels and Zork source hashes.
- `build/p2000m-sd-template.img`: complete bootable SD image.
- `build/HELLO.COM`, `build/COPY.COM`, `build/CPMTEST.COM`, `build/RAMTEST.COM`, `build/SYNC.COM`: original transient programs.

Decompress the `.img.gz` before attaching it to the emulator.

The build regenerates the **template image**. Use a separate copy for persistent
work, so rebuilding does not erase your files. The test runner creates temporary
images and compiles the emulator core without modifying its checkout.

## Boot

In the emulator, install the CP/M co-board, load `cartridge.bin` in cartridge
slot 1, install the SD cartridge in slot 2, and attach a writable copy of the
SD template image. Leave the floppy drives empty and reset. The machine should
show the 80×24 boot dashboard and `A>` on line 21. It includes separate
ROM/kernel versions and UTC build timestamps, a 51 KiB (52,224-byte) TPA
at 0100–CCFF, hardware/card status, and twelve named drives in three columns.
Activity updates in place on line 19; errors retain command/response details
on line 20, and no stale diagnostics appear below a working prompt.
Reverse-video headings scroll with the text and are cleared for application
output. Full-screen clear also resets attributes.

Version comes from `VERSION`; applications still receive CP/M version 2.2.
The 51 KiB TPA is the current software limit, not the co-board's total
56 KiB RAM capacity. See the [memory budget and ROM-resident filesystem](docs/memory-budget.md).
`SOURCE_DATE_EPOCH` can fix build timestamps for reproducible artifacts.
The timestamp describes the compiled ROM/kernel, not card formatting time.

The cartridge header disables the monitor's floppy-DOS boot request. The
first cartridge message is printed before clearing the rest of the screen;
monitor startup/RAM checks before cartridge entry still take place. The ROM
also disables the monitor's CTC channels because our console polls the keyboard.

SD initialization makes up to eight attempts, restarting the SD initialization
sequence (including CMD0 reset) after a roughly 500 ms pause between failures.
This resets the card protocol, not the P2000 or co-board. The attempt number
is displayed; exhaustion produces a bounded error. The command layer waits
for card readiness (except for CMD0), allows up to 256 response bytes, and
spaces idle ACMD41 polls by at least 1 ms. Failed sector reads, including the
header, kernel and BIOS partition-table reads, get three attempts with SD
reinitialization between attempts. Invalid headers/signatures/checksums allow
up to three complete load/validation passes. Writes are not automatically
replayed. Recovery updates the status field; exhausted boot errors show the last command and response byte.
After initialization the
ROM reads CMD10 and shows numeric MID, OEM, product and serial fields; the full
16-byte CID remains at DBE0–DBEF during boot.
If CID cannot be read, it says so and continues booting; no manufacturer name
is guessed from the numeric ID.

For physical hardware, program the port-1 ROM and write the **whole raw image**
to an SDHC card of at least 4 GB. Copying the `.img` file into an existing FAT
filesystem is not equivalent. The preceding 16 KiB build was reported to boot
on a physical P2000M; version 0.3.0 has been tested in the
supplied emulator and awaits a hardware trial. Its SPI driver targets the
emulator's PCB v6+ byte-wide cartridge interface and SDHC block addressing.

## Use

```text
A>DIR
A>HELLO
A>DUMP HELLO.COM
A>STAT
A>COPY A:HELLO.COM B:HELLO.COM
A>B:HELLO
A>COPY A:HELLO.COM L:HELLO.COM
A>L:HELLO
A>REN B:GREETING.COM=B:HELLO.COM
A>ERA B:GREETING.COM
A>CPMTEST
```

`CPMTEST` creates, verifies, and deletes `CPMTEST.DAT` on **A: only**, in the
current user area. It replaces an existing file with that name. It writes and
reads/verifies 600 records (75 KiB), closes/reopens the file, checks EOF and
size, verifies a random read at record 513, then deletes the file and confirms
it cannot be reopened. There is no random-write phase.

Each phase is named. Write/read progress updates every 30 completed records
(5%), with an in-place bar and `000/600` count. Failures report the operation,
drive, zero-based record index and failure value; data mismatches also report
byte offset and expected/actual values in hexadecimal.

Press **Escape, then C** (Ctrl-C) to abort between completed records. The test
closes and retains its partial `CPMTEST.DAT` and returns to the command prompt;
it does not interrupt an active SD write. Otherwise wait for `CPMTEST PASS`.
SD record I/O now uses separate 512-byte data and directory caches. This
combines adjacent record writes and avoids repeated sector reads. Allocation
still scans directories and zero-fills blocks, so runtime depends on the card
and directory contents. A measured 32-record write/read workload dropped from
64 sector reads + 32 writes to 16 reads + 8 writes (75% fewer SD transfers).

SD writes are buffered until close, cache eviction, a drive change, disk reset,
or return to the command prompt. **Wait for the prompt before resetting or
switching off.** `SYNC` explicitly commits pending writes through BDOS disk
reset and selects A: as the default drive. From another drive, use `A:SYNC`.
It is a useful explicit save point; ordinary return to the prompt also flushes.

Data is committed before dependent directory metadata. A failed flush keeps
the dirty bytes and reports an error. If warm boot cannot flush, it displays
instructions and waits for **R** to retry; restore the **original card** and
do not reset. Live card swapping is not supported. A physical reset/power
failure during an open file can lose pending changes; this is not a journaled
filesystem and individual SD writes are not guaranteed power-loss atomic.

`RAMTEST` runs the same 600-record (75 KiB) file checks **only on L:**, including
both SRAM banks, with progress and Escape-then-C cancellation. It uses
`L:RAMTEST.DAT`, refuses an existing file with that name, and leaves other files
alone. It needs at least 75 KiB free. Success removes the test file; an abort or
failure may leave it for inspection. This is a filesystem-level RAM-disk test,
not an exhaustive test of every SRAM cell or the directory storage.

`STAT.COM` is already bundled on A:. Useful commands are:

```text
STAT                 (free space for logged-in drives)
STAT A:DSK:          (A: capacity and filesystem geometry)
STAT B:DSK:          (B: capacity and filesystem geometry)
STAT L:DSK:          (RAM-disk capacity and filesystem geometry)
STAT A:*.*           (file sizes and allocation)
STAT A:HELLO.COM     (one file)
```

Type only the command, without the parenthesized explanation. From any other drive,
invoke `A:STAT` to load the utility from A:. A:–K: each have 8192 KiB of total
partition space; directory storage and files reduce the reported free space.
`DIR` displays four filenames per row and accepts drive prefixes/wildcards.

Built-in commands are `DIR [pattern]`, `TYPE file`, `ERA pattern`,
`REN new=old`, `USER 0` through `USER 15`, `SAVE pages file` (256-byte pages),
and `A:` through `L:` to change drive. Names follow CP/M's 8.3 convention.
`COPY source destination` is a supplied program; it refuses to overwrite an
existing destination. `SAVE` likewise refuses an existing filename.

Return completes a command. Backspace edits the line. Letters are lowercase
by default; either Shift key produces uppercase letters and shifted punctuation.
Commands and filenames remain case-insensitive.
**Escape followed by a letter sends its control code** (for example Escape, C
for Ctrl-C; Escape, Z for Ctrl-Z). Escape twice sends a literal Escape. This
provides control characters through the emulator's existing keyboard mapping.
The console translates ASCII `#` to P2000 video code `5Fh`; video code `23h`
is the sterling glyph, so writing ASCII bytes directly would display `£`.

A program's `RET` or `JMP 0` returns to the command processor through warm boot,
which preserves L:. Machine reset/cold boot reformats L:. Save RAM-drive files
to any SD drive before resetting or powering off.

## Add your own programs when creating an image

The host image builder can populate any SD volume with 8.3-named files:

```sh
python3 tools/sd_image.py build/my-card.img --kernel build/kernel.bin \
    --a build/HELLO.COM build/COPY.COM MYPROG.COM --b README.TXT \
    --drive G SOURCE.ASM --drive H MANUAL.TXT
```

It refuses to overwrite an existing output. Omitting `--kernel` creates a
data-only image that cannot boot. Files are stored in CP/M user area 0, rounded
to 128-byte records; the final record uses CP/M text padding (`1Ah`).

See [design notes](docs/design.md) for the BIOS ABI, memory map, disk geometry,
implementation boundaries, and test coverage.

For a guided reading order, register conventions and the regression-test strategy,
see the [Z80 source guide](docs/source-guide.md).

## Zork

Switch to its data drive before starting a game:

```text
A>C:
C>ZORK1
```

Use `ZORK2` or `ZORK3` for the other games. The emulator regression verifies
startup and `LOOK` in all three; it is not a complete game playthrough.
