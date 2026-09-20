# Historical P2000M CP/M keyboard audit

Examined the local `cartridge_mcpm.bin` (banner 82.05.18), together with
`cpm_seeters_system.p2000m.img` and `mcpm_system.p2000m.img`, supplied in
`/mnt/d/PROGRAMMING/p2000m/p2000m-cpm-coboard/software`.
The disk names are not proof of historical attribution. Both disks use the
same cartridge keyboard driver; their input tables have small differences.

## Interrupt architecture

The cartridge's entry calls E042, which jumps to initialization at E08C.
After resetting all four CTC channels, it installs:

```asm
IM 2
LD HL,E411h
LD (DFF6h),HL
LD A,DFh
LD I,A
LD A,F0h
OUT (88h),A       ; CTC interrupt vector base
; Other initialization intervenes here.
LD A,D5h
OUT (8Bh),A      ; channel 3, counter mode, interrupt enabled
LD A,01h
OUT (8Bh),A      ; one video-field pulse per interrupt
```

Channel 3 supplies vector F6, so IM2 reads DFF6/DFF7 and enters E411.
The local monitor source reference, `p2000m-drive-test/references/`
`p2000t-monitor/Startup.asm`, documents the same D5/01 setup and the video
field pulse every 20 ms. The emulator also triggers CTC channel 3 per frame.

This is periodic polling **inside an interrupt handler**, not an interrupt
generated separately by each key. It is independent of application console
calls while interrupts are enabled. The CP/M cartridge contains its own
scanner; it does not call the original monitor through the changed memory map.

## Driver entry points and state

Addresses here are mapped cartridge/RAM addresses, not raw file offsets.
For mapped E000-EFFF, cartridge file offset = address - D000.

| Address | Observed function |
| --- | --- |
| E000 -> E3D9 | Console status: tests DFEA bit 4 |
| E003 -> E3E2 | Console input: waits for ready, clears it, translates the pending key |
| E411 | Keyboard interrupt handler |
| DFF6-DFF7 | IM2 channel-3 vector containing E411 |
| DF87-DF88 | Saved interrupted stack pointer |
| DFE0 | Repeat countdown |
| DFE1-DFE9 | Nine sampled matrix rows |
| DFEA | Modifier/control flags and pending-key flag |
| DFEB | Previous selected key index |
| DFEC | Pending key index |
| DFDE-DFDF | Pointer to keyboard translation tables supplied by the disk BIOS |

The handler saves the interrupted SP, switches to a private stack below DF87,
samples the matrix/modifiers, updates the selected key and repeat countdown,
restores the interrupted context and returns with RETI. It also contains
legacy peripheral housekeeping and a callback at DFED; those are not needed
for our SD-cartridge keyboard driver.

The repeat countdown is initially 50 ticks. At expiry it publishes another
key and reloads 2 ticks: approximately one second initial delay and 40 ms
between repeats at 50 Hz.

There is **one pending key, not a type-ahead FIFO**. It selects a key from
the sampled matrix rather than queuing every new matrix transition. Character
translation takes place in CONIN using the flags then present in DFEA.
Copying this literally would preserve limitations during bursts of typing.

## Execution check

A temporary headless harness booted both supplied disks with the unchanged
historical cartridge using the sibling emulator. Copies of the floppy images
were used; the supplied files were not modified. After boot, an EI spin loop
replaced the application, with no console calls. Pressing the A matrix key
produced these observations (values shown here in decimal):

- After one frame: ready set, key index 34, countdown 50.
- Clear ready; after another 49 frames: no new ready flag, countdown 1.
- After the next frame: ready set again, countdown 2.

This confirms background scanning and repeat timing in the emulator. It is
not a new hardware validation of these historical binaries.

## Recommended reproduction in the SD implementation

Use the same CTC channel 3, video-field cadence, IM2 dispatch and ROM-resident
ISR architecture. Keep BIOS CONST/CONIN as the application interface. Preserve
our lowercase/Shift-uppercase mapping instead of importing historical tables.

Add a small FIFO, record per-key transitions, and capture modifiers when an
event is queued. The ISR must preserve registers, use protected stack space,
and never call BDOS, the filesystem or SD routines. Queue access must be safe
against interrupt arrival. Retain a polling fallback for console calls made
with interrupts disabled; background capture cannot be guaranteed while an
application holds DI. Check DDT's interrupt-mode/register use explicitly.

The CTC must be enabled only after vector, state and stack initialization;
cold restart must disable it before changing the memory map. ISR code, state
and stack must remain outside the reclaimable boot regions and advertised TPA.
Test busy-loop and SD-I/O type-ahead, overlapping keys, Shift boundaries,
repeat, overflow, DI callers, warm/cold restart, and full-size COM execution.

## Implemented adaptation

The updated 0.3.0 build implements this architecture in `src/keyboard.asm` and
`src/keyboard_repeat.asm`, with a 63-character FIFO and independent two-sample
key debounce. It retains the corrected lowercase/Shift-uppercase mapping.
The vector is E7FE, the private interrupt stack is DC00–DC7F, the queue is
DCC0–DCFF, and state is DDC4–DDE0. The hardened BDOS build has a 50 KiB TPA.

`tests/keyboard.cpp` exercises overlapping typing, shift capture, bounce,
repeat timing, queue ordering/overflow/wrap, NUL/control characters, DI/EI
callers, all main/alternate register preservation, and type-ahead during real
SD reads and writes. The existing suites also guard the interrupt stack while
running utilities, full-TPA applications, recovery and warm/cold restart.

Main-row `0` (X5/Y5) and numeric-pad DEFINE/`0` (X2/Y3) both give `=`
with either Shift key. The adjacent main-row minus (X5/Y7) gives `-` / `_`. The cursor-left and cursor-right keys enqueue 08h and 0Ch respectively.
Those control bytes are delivered unchanged through BIOS CONIN; full-screen
programs such as SuperCalc2 interpret them as input, independently of the
VT52-style sequences used for screen output.

## Interactive wiring diagnostic

[`KEYTEST.COM`](../programs/keytest/) displays all ten raw matrix rows and
inverts each held key tile, including Shift/Lock and unmapped positions. It
uses the Field Support Manual's port interface and inverse-video test approach;
see its guide for the precise manual references, controls and test coverage.

## Physical NL/UK map audit (2026-09-20)

The earlier audit mislabeled **X5/Y5 as numeric-pad zero** and used the
existing driver table as the KEYTEST legend source. That was not an independent
verification. X5/Y5 is the main-row zero; numeric-pad DEFINE/0 is X2/Y3.
The pre-correction source already contained `=` at shifted X5/Y5, but lacked
it at shifted X2/Y3. It also incorrectly used `=` for shifted X5/Y7.

The user's keyboard photograph identifies `0 / =`, adjacent `- / _`, the
acute/grave key, `@ / apostrophe`, `] / [`, unshifted comma/period, and the
keypad minus/divide, plus/multiply, CLEAR, 00 and STOP/dot keys. KEYTEST now
shows those physical keycaps, including sterling and degree in native video.

Independent wiring evidence comes from Philips **Maintenance 2**, whose banner
reports **P2000-M & T MAINTENANCE PROGRAM REL 2.2**:

- [Original binary](https://github.com/p2000t/software/blob/main/cartridges/Maintenance%202.bin),
  downloaded 2026-09-20; 16,384 bytes; SHA-256
  `6057b7b1e5ea556062466c50c2c636f338cc5177f624efe4cca8d3faa49fe672`.
- File offset **0986h**: 74 little-endian screen addresses used by its keyboard
  test. Routine **2802h** indexes this table by key number; scanner **27C9h**
  forms row × 8 + bit. The two final entries are the Shift keys.
- The national selection table at file **0A1Ah** has 17-byte records. Selecting
  **5, NL OR UK**, picks the normal keyboard table at file **0E15h** and the
  shifted table 72 bytes later at **0E5Dh**. Routine **3CD7h** reads these tables.
- Booted the unmodified cartridge in the bundled emulator, selected **5** and
  then **3 (KEYBOARD)**, and checked its displayed layout. The keyboard-test
  screen places X5/Y5 at row 7/column 22 and X5/Y7 at row 7/column 24, immediately
  after the main-row 9. Numeric-pad zero is at row 15/column 33.
  Screen coordinates here are zero-based in the maintenance program's display.

| Physical key | Port / bit | CP/M normal | CP/M shifted |
| --- | --- | --- | --- |
| Main-row 0 | 05h / 5 | `0` | `=` |
| Main-row minus | 05h / 7 | `-` | `_` |
| Keypad DEFINE / 0 | 02h / 3 | `0` | `=` |
| Keypad plus / multiply | 05h / 2 | `+` | `*` |
| Keypad minus / divide | 05h / 3 | `-` | `/` |
| Keypad STOP / dot | 02h / 0 | `.` | `.` |
| Main comma | 02h / 6 | `,` | `,` |
| Main period | 07h / 1 | `.` | `.` |
| Main semicolon / plus | 08h / 5 | `;` | `+` |
| Right / left bracket | 07h / 4 | `]` | `[` |
| At / apostrophe | 06h / 7 | `@` | apostrophe |
| Acute / grave | 08h / 4 | apostrophe | grave |

This remains a CP/M ASCII mapping. Acute uses the ASCII apostrophe;
sterling and degree retain the existing `#` fallback. Historical dead-accent,
STOP, CLEAR, double-zero and Shift Lock functions are not emulated; STOP's
key emits its ordinary dot, while CLEAR/00/LOCK remain untranslated. KEYTEST
shows their contacts and physical legends independently of these conventions.

**Input bytes and screen codes must be kept separate.** CP/M underscore is
ASCII 5Fh, but native video 5Fh draws hash. CONOUT now renders underscore with
native 60h; hash remains native 5Fh. Square brackets use native 0Fh/10h and
ASCII grave uses native 0Ah. Key input and saved files retain ASCII bytes.
The maintenance shifted-minus entry is 60h, consistent with its native
underscore; copying 60h directly into a CP/M input table would emit grave.

The IRQ and DI input tests check these physical positions under both Shift
keys. SuperCalc's `SCKEYS` scenario explicitly presses X5/Y5, X5/Y7 and X2/Y3;
it checks GoTo, a negative number, a displayed filename underscore, and cursor
left/right. It does not select arbitrary keys by their expected output.

**Installation:** these routines live in the port-1 **cartridge ROM**. Install
the rebuilt `cartridge.bin` and its matching SD kernel, plus the new KEYTEST.COM.
Copying KEYTEST or updating only the SD kernel cannot replace the keyboard
translation tables. The changed link identity rejects a mismatched ROM/kernel.
