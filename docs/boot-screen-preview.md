# Boot screen proposal

The PNGs from `preview_boot.py` are design mockups, **not firmware captures**.
The chosen twelve-drive design is now implemented in version 0.2.0; the
`boot-characters.bin`/`boot-attributes.bin` dumps from the boot regression
contain an actual emulator capture. Historical mockups retain sample versions.

Run `python3 tools/preview_boot.py` to generate six previews in
`build/boot-previews/`: loading, ready after recovery, failed initialization,
and a future six-drive layout (`expanded`), plus twelve-drive three-column
(`grid3`) and two-column (`grid2`) alternatives.
The renderer requires Pillow and defaults to the sibling emulator's character
ROMs; `--charrom-dir` can override that location.

## Rendering accuracy

Each screen contains exactly 80 by 24 cells, using the real 8 by 12 P2000M
glyphs, black background, green foreground, and attribute bit 3 for inverse
video, matching `p2000m-emulator/src/display_widget.cpp`. PNGs are provided at
native 640 by 288 resolution and a nearest-neighbor 2x enlargement. This does
not simulate physical monitor scaling, overscan, phosphor bloom, or camera
perspective. ASCII borders deliberately use supported native characters rather
than assuming that the machine has IBM PC box-drawing characters. Hashes use
native code 0x5f, not the pound-sign glyph at 0x23.

Each PNG also has a 24-line text layout and separate 1,920-byte character and
attribute dumps. Bounds are checked during rendering.

## Layout and behavior proposed for implementation

The revised layout separates CP/M compatibility from independently versioned
ROM and kernel artifacts. Both show their own build timestamp in UTC. Versions
`v0.3.1` / `v0.4.0` and both dates are illustrative, not actual build metadata.
Kernel metadata remains pending until the kernel has been loaded and verified.
The title describes compatibility; it does not change BDOS's version response.

### 24-line budget (one-based screen lines)

| Lines | Content |
| --- | --- |
| 1 | System title and CP/M 2.2 compatibility |
| 2-3 | ROM and kernel versions, with individual build dates/times |
| 4 | TPA size and address range |
| 5-8 | Table border and cartridge/co-board/kernel status |
| 9-12 | SD heading, manufacturer, identity and retry status |
| 13 | Drive table heading |
| 14-16 | Current A/B/C drives |
| 17-19 | Optional future D/E/F drives |
| 20 | Bottom border (six-drive case) |
| 21-22 | Boot result and blank separator |
| 23 | Command prompt |
| 24 | Spare line |

With only A/B/C, the bottom border moves to line 17 and the prompt to line 20,
leaving four spare lines. The six-drive preview illustrates ZORK, GAMES and
DEVELOPMENT volumes with example sizes; it does not implement them. Beyond six
drives, use a compact multi-column summary or a separate drive-list command
rather than overflowing the 24-line boot screen. No permanent footer is drawn
below the prompt.

### Revised recommendation: twelve drives in three columns

The `grid3` preview replaces the one-drive-per-line section with four rows of
three entries, ordered left to right, A through L. Each entry shows its drive
letter, a short purpose label, explicit `(SD)` or `(RAM)` backing, and capacity.
The prompt is on line 21, leaving lines
22-24 spare. The `grid2` comparison takes six drive rows and places the prompt
on line 23, leaving one spare line. Both retain identical metadata and boot
diagnostics above the drive section.

The screen displays raw manufacturer identification (`MID 03 / OEM SD`), not
a decoded brand name. Product and serial remain visible. There is no RAM
volatility warning; a blank line separates the boot result from the prompt.

The example assumes twelve drives total: eleven 8 MiB SD volumes (88 MiB in
total) and a 128 KiB RAM disk at L: (126 KiB usable), moved from C: in the proposed
layout. This is a proposed
configuration, now used by the 0.2.0 build. No partition or filesystem changes are made by rendering
these previews. The ready-only grids assume every listed drive has passed
validation; pending/error states would replace capacities with explicit status
where validation has not succeeded.

Suggested purpose labels (organizational guidance, not restrictions):

| Drive | Label | Intended contents |
| --- | --- | --- |
| A: | SYSTEM | CP/M system utilities and essential commands |
| B: | TOOLS | Additional utilities and applications |
| C: | ZORK | Zork interpreter, game data and saves |
| D: | GAMES | Other games and their saves |
| E: | BASIC | BASIC interpreters and programs |
| F: | ASM | Assemblers, linkers and debugging tools |
| G: | SOURCE | Development source files and projects |
| H: | DOCS | Documentation and text files |
| I: | DATA | Application data and working documents |
| J: | EXTRA 1 | Unassigned persistent storage |
| K: | EXTRA 2 | Unassigned persistent storage |
| L: | SCRATCH | Temporary RAM workspace; never the only copy of important files |

All SD volumes in this proposal remain 8 MiB. `128KiB` omits the space only
to fit the RAM entry into a 24-character grid cell. Moving RAM to L: during
eventual implementation also requires updating RAMTEST, drive-selection code,
tests and documentation; the mockup does not make those firmware changes.

- Show the title as soon as video output is safe, before drawing the full table.
- Reserve fixed rows across the ROM loader and kernel. Update fields in place;
  do not append a line for every action or retry.
- Group cartridge/co-board/kernel, SD identity, and drives into distinct areas.
- Use one activity line for the current operation and bounded progress counters.
- Show pending fields until their values have actually been read or validated.
  In particular, the current kernel reads CID after the ROM loads the kernel.
- Retain successful recovery as a compact attempt count and `RECOVERED` status.
  A first-attempt success would show `attempt 1/8` and `OK` instead.
- Show raw command/response bytes when boot stops, not below a working prompt.
- Place the command prompt below all boot output; no subsequent boot diagnostics
  should write below it. The dashboard is ordinary scrollable console history,
  not a permanent panel consuming the command screen.
- Do not introduce an artificial display delay for aesthetic purposes.

The ready state uses the card and partition information from the supplied
photo. CID transcription: `035344414B47434580DAA835A4010C81`. It decodes to
MID `03`, OEM `SD`, product `AKGCE`, revision `8.0`, and serial `DAA835A4`.
The loading state is an illustrative halfway point; the failure state is an
illustrative exhausted retry using the photographed CMD0/response `3F`, not a
claim that the photographed boot failed. The 8 MiB entries are partition sizes,
not total physical SD-card capacity or currently free file space.

The existing stale recovery message is caused by `boot_recovery` in
`src/cartridge.asm`, which writes directly to `0xf5f0` (screen row 19, zero-based)
without clearing that row after recovery. It is useful during troubleshooting
but does not represent a continuing failure once CP/M has started.

## Card identification

An SD CID contains 128 bits: 16 bytes or 32 hexadecimal digits. MID `0x03`
identifies SanDisk for SD cards; OEM `SD` is useful supporting information.
The product and serial fields help distinguish individual cards for debugging.
CID identity is reported by the card, not proof of authenticity, and the
five-character product name is not necessarily its retail model name.

Primary references: Linux's [SD manufacturer definitions](https://github.com/torvalds/linux/blob/master/drivers/mmc/core/card.h)
and [SD CID decoder](https://github.com/torvalds/linux/blob/master/drivers/mmc/core/sd.c).
Full CID, revision and manufacturing date can remain available in a future
diagnostic view or utility; this proposal does not implement that interface.
