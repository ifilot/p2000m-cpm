# P2000M SD CP/M

An original Z80 assembly implementation of the CP/M 2.2 interface for a
P2000M with its **CP/M co-board installed**, an 8 KiB boot cartridge in port 1,
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

| Partition / drive | Size | Purpose |
| --- | ---: | --- |
| First partition: FAT32 | 64 MiB | Host-accessible storage, label `P2000M DATA` |
| Second partition: `A:` | 8 MiB | CP/M filesystem; original programs installed here |
| Third partition: `B:` | 8 MiB | CP/M filesystem; initially empty |
| Cartridge SRAM: `C:` | 128 KiB | Volatile CP/M RAM drive; 126 KiB usable after its directory |

The raw image is **81 MiB**, including a 1 MiB alignment gap containing the
partition table, system header, and kernel. The FAT32 partition is formatted
and ready for host use. **Accessing FAT32 files from CP/M is a future extension**;
CP/M currently exposes only A:, B:, and C:.

## Build and test

Requirements: Python 3.11+, `z80asm` (Debian syntax), and GCC/G++ for emulator tests.
The default emulator path is `../p2000m-emulator`.

```sh
python3 tools/build.py
python3 tools/package.py  # optional: compressed image and SHA256SUMS
python3 -m unittest discover -s tests -v
python3 tools/test_emulator.py
python3 tools/test_programs.py  # isolated utility and register-contract cases
# Or specify another checkout:
python3 tools/test_emulator.py --emulator /path/to/p2000m-emulator
```

Build outputs:

- `build/cartridge.bin`: signed, padded 8 KiB port-1 ROM.
- `build/kernel.bin`: 16 KiB system image, also installed in the SD image.
- `build/p2000m-sd-template.img.gz`: compressed image, produced by `package.py`.
- `build/SHA256SUMS`: checksums for ROM, kernel, raw image and compressed image.
- `build/p2000m-sd-template.img`: complete bootable SD image.
- `build/HELLO.COM`, `build/COPY.COM`, `build/CPMTEST.COM`: original transient programs.

Decompress the `.img.gz` before attaching it to the emulator.

The build regenerates the **template image**. Use a separate copy for persistent
work, so rebuilding does not erase your files. The test runner creates temporary
images and compiles the emulator core without modifying its checkout.

## Boot

In the emulator, install the CP/M co-board, load `cartridge.bin` in cartridge
slot 1, install the SD cartridge in slot 2, and attach a writable copy of the
SD template image. Leave the floppy drives empty and reset. The machine should
show the system banner and `A>` prompt without requiring a floppy boot step.

For physical hardware, program the port-1 ROM and write the **whole raw image**
to an SDHC card of at least 4 GB. Copying the `.img` file into an existing FAT
filesystem is not equivalent. The implementation has been tested against the
supplied emulator, not on a physical P2000M. Its SPI driver targets the
emulator's PCB v6+ byte-wide cartridge interface and SDHC block addressing.

## Use

```text
A>DIR
A>HELLO
A>DUMP HELLO.COM
A>STAT
A>COPY A:HELLO.COM B:HELLO.COM
A>B:HELLO
A>COPY A:HELLO.COM C:HELLO.COM
A>C:HELLO
A>REN B:GREETING.COM=B:HELLO.COM
A>ERA B:GREETING.COM
A>CPMTEST
```

`CPMTEST` creates, verifies, and deletes `CPMTEST.DAT` in user area 0 on A:, B:,
and C:. It replaces an existing file with that name. It runs substantial disk
I/O; wait for `CPMTEST PASS` before resetting.

Built-in commands are `DIR [pattern]`, `TYPE file`, `ERA pattern`,
`REN new=old`, `USER 0` through `USER 15`, `SAVE pages file` (256-byte pages),
and `A:`, `B:`, or `C:` to change drive. Names follow CP/M's 8.3 convention.
`COPY source destination` is a supplied program; it refuses to overwrite an
existing destination. `SAVE` likewise refuses an existing filename.

Return completes a command. Backspace edits the line. Letters are uppercase
by default; Shift produces lowercase letters and shifted punctuation.
**Escape followed by a letter sends its control code** (for example Escape, C
for Ctrl-C; Escape, Z for Ctrl-Z). Escape twice sends a literal Escape. This
provides control characters through the emulator's existing keyboard mapping.

A program's `RET` or `JMP 0` returns to the command processor through warm boot,
which preserves C:. Machine reset/cold boot reformats C:. Save RAM-drive files
to A: or B: before resetting or powering off.

## Add your own programs when creating an image

The host image builder can populate either CP/M partition with 8.3-named files:

```sh
python3 tools/sd_image.py build/my-card.img --kernel build/kernel.bin \
    --a build/HELLO.COM build/COPY.COM MYPROG.COM --b README.TXT
```

It refuses to overwrite an existing output. Omitting `--kernel` creates a
data-only image that cannot boot. Files are stored in CP/M user area 0, rounded
to 128-byte records; the final record uses CP/M text padding (`1Ah`).

See [design notes](docs/design.md) for the BIOS ABI, memory map, disk geometry,
implementation boundaries, and test coverage.

For a guided reading order, register conventions and the regression-test strategy,
see the [Z80 source guide](docs/source-guide.md).
