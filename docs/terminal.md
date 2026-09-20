# Console controls and SuperCalc

The console is 80 columns by 24 rows. Escape sequences are interpreted by BIOS
CONOUT, so BDOS functions 2, 6 and 9 share exactly the same parser. No new BDOS
function numbers are needed. State persists between output calls. Warm boot
cancels an unfinished sequence and restores normal video before printing the
prompt. Cold boot initializes the same state from the kernel image.

## Output contract

`ESC` means byte 1Bh. Coordinates are zero-based, encoded as a single byte
with 32 added: row 0/column 0 is `ESC Y 20h 20h`; row 23/column 79 is
`ESC Y 37h 6Fh`. Send the row first. This is binary encoding, not decimal text.
The cursor is the next output position; these commands do not draw a cursor.

| Bytes | Effect |
| --- | --- |
| `ESC Y row+32 col+32` | Absolute cursor position |
| `ESC H` | Home to row 0, column 0 |
| `ESC A`, `ESC B` | Move one row up/down, without scrolling |
| `ESC C`, `ESC D` | Move one column right/left, without wrapping |
| `ESC J` | Erase from cursor through the end of the screen |
| `ESC K` | Erase from cursor through the end of the line |
| `ESC p`, `ESC q` | Inverse/normal video for subsequent characters (extensions) |
| FF (`0Ch`) | Cancel a partial escape, clear screen and home |
| CAN (`18h`) | Cancel a partial escape without moving or clearing |
| CR, LF, BS, TAB | Existing carriage return, line feed, backspace and space-filling tabs |

Erasure includes the cursor cell, clears both text and attributes, and preserves
position and the selected rendition. Movement and absolute coordinates clamp
at the screen edges. An ESC restarts an incomplete command; an unknown escape
command is consumed. Output is seven-bit. Printable text still wraps at column
80 and scrolls at the bottom; scrolling moves attributes with their characters.

The positioning and erasure commands follow the [DECscope User's Manual,
sections on advanced cursor movement and screen erasure](https://manualzz.com/doc/6499589/dec-vt50--vt50h--vt52-series-video-terminal-user-manual).
This is a **VT52-style subset**, not full VT52 or ANSI/VT100 emulation. Reverse
index, terminal identification, graphics/keypad modes and ANSI CSI sequences
are not implemented. `ESC p/q` are explicitly extensions, not DEC commands.

Use BDOS 6 (C=6, E=byte) for binary cursor sequences. BDOS 9 treats `$` as its
terminator: encoded coordinate 4 is 24h (`$`), so it cannot carry every cursor
address. BDOS 2 also accepts every seven-bit output byte but retains cooked
Ctrl-S/Ctrl-C handling; BDOS 6 does not consume type-ahead for flow control.

Example: print `X` at row 4, column 10, using independent BDOS calls:

```asm
    ld hl,sequence
    ld b,5
next_byte:
    push bc
    push hl
    ld e,(hl)
    ld c,6
    call 5
    pop hl
    pop bc
    inc hl
    djnz next_byte
    ret
sequence: db 27,'Y',32+4,32+10,'X'
```

## Bundled SuperCalc2

**SuperCalc2 1.00 for CP/M-80 is installed and configured on D: CALC.** Start it
with `D:` followed by `SC2`, then press Return at the title screen. Select `?`
for its original help pages. No installation step is required for the bundled
copy; retain `SC2.OVL` and `SC2.HLP` alongside the executable.

The `P2000M VT52` profile was saved by Sorcim's original installer inside the
emulator. It uses the supported positioning and erasure commands, inverse video
for the active cell, and the P2000's physical arrows without an ESC prefix.
It does not require ANSI/VT100, bank switching or any new BDOS function.

| Setting | Installed value |
| --- | --- |
| Screen | 80 columns, 24 rows |
| Cursor addressing | `ESC Y`, then row+32 and column+32 |
| Home / erase line / erase screen | `ESC H` / `ESC K` / `ESC J` |
| Active-cell highlighting | `ESC p` / `ESC q` |
| CRT attributes | One, without guard characters |
| Keyboard prefix | None |
| Up / down / left / right | 0Bh / 0Ah / 08h / 0Ch |

SuperCalc receives these through CP/M BIOS CONIN, directly from the keyboard
FIFO. The VT52 profile governs SuperCalc's display output only; it is not an
input driver. Shift + main-row `0` (X5/Y5) or keypad DEFINE/`0` (X2/Y3) produces `=`.
The main-row minus key (X5/Y7) produces `-`, or ASCII `_` with Shift.
CONOUT renders ASCII underscore with native video code 60h, preserving its
ASCII byte in application input and files. See the
[physical map audit](keyboard-reference.md#physical-nluk-map-audit-2026-09-20).

The original installer and seven sample worksheets are also bundled. See
[provenance and reproducible installation](../assets/supercalc/README.md),
[usage](user-guide.md#supercalc2), and the
[Sorcim manual](https://deramp.com/downloads/altair/software/manuals/SuperCalc2.pdf).
The installer has a Dealer's Custom Installation menu accessed with `X` from
the terminal list; the provenance notes record each setting. Re-selecting its
stock VT52 profile will discard the native-key and inverse-video configuration.

The SuperCalc2 regression tests run the original binary on the real CP/M kernel
and emulator CPU, using the physical keyboard matrix. Run them with:

```sh
python3 tools/build.py
python3 -m unittest discover -s tests -p test_supercalc.py -v
```

They cover:

- Startup, both welcome help pages, and inverse selection without clipping.
- Addition, subtraction, multiplication, division, parentheses, precedence,
  negative decimals, `SUM`, and automatic recalculation through dependent cells.
- All four arrows, top/left boundaries, scrolling across the visible row and
  column limits, GoTo through Z100, and preservation of entered values.
- Save, save-as, overwrite, and reload in a fresh emulator process. The original
  and overwritten versions are checked separately, including live formulas.
- A missing-file error, Ctrl-C cancellation, preservation of worksheet data,
  and a successful subsequent load.
- Loading `SAMPLE.CAL`, checking income-statement totals, saving a copy, and
  reopening and recalculating that copy after changing sales.

Each scenario checks return to CP/M and subsequent program execution. The
harness also checks stack guards; host-side checks verify the saved CAL files,
all bundled SuperCalc assets, and preservation of the FAT32 partition. Tests
use disposable copies of the built SD image. These are application integration
regressions, not source-level unit tests of Sorcim's proprietary program.

The application reports roughly 20 KiB of worksheet memory on the 50 KiB TPA
(about 16 KiB with `SAMPLE.CAL` loaded). Extra banked RAM does not automatically
increase this. Printing, every advanced spreadsheet command, and actual
P2000M hardware operation have not been qualified by these tests.
