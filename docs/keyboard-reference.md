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
DCC0–DCFF, and state is DDC4–DDE0. The hardened BDOS build has a 50.5 KiB TPA.

`tests/keyboard.cpp` exercises overlapping typing, shift capture, bounce,
repeat timing, queue ordering/overflow/wrap, NUL/control characters, DI/EI
callers, all main/alternate register preservation, and type-ahead during real
SD reads and writes. The existing suites also guard the interrupt stack while
running utilities, full-TPA applications, recovery and warm/cold restart.
