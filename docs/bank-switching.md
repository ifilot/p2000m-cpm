# Revised co-board bank switching: assessment

Reviewed against the sibling `p2000m-cpm-coboard` checkout at `b7ee7db`:
`pcb/modern-revised/p2000m-cpm-coboard.kicad_sch`,
`cupl/p2000m-cpm-coboard.pld` (initially revision 0.6), and `cupl/README.md`.
Hardware BANKTEST subsequently exposed a video overlap in revision 0.6;
revision 0.7 corrects the expansion address during banked 7000–7FFF accesses.
Physical retesting of revision 0.7 then failed at the co-board enable step.
Subsequent hardware testing confirmed working banking; the exact final CPLD
image was not recorded here. The CP/M boot command remains 80h, overlay disabled.
The schematic uses CY62128 SRAM; the CPLD equations define the interface below.
The corrected CPLD source passes verification and fitting. The emulator and bundled test core now implement the extra banks, and
[BANKTEST](../programs/banktest/README.md) is included on A: for physical tests.
The kernel still leaves the overlay disabled; the storage uses below remain
proposals.

## Hardware contract

| CPU addresses | Normal CP/M map | With overlay enabled |
| --- | --- | --- |
| 0000–3FFF | Motherboard RAM | Unchanged |
| 4000–7FFF | Expansion RAM | Selected co-board SRAM bank 1–7 |
| 8000–9FFF | Expansion RAM | Unchanged |
| A000–DFFF | Co-board SRAM bank 0 | Unchanged |
| E000–EFFF | Cartridge ROM | Unchanged |
| F000–FFFF | Video/attributes | Unchanged |

Seven additional banks of 16 KiB provide **112 KiB of extra storage**. They
are independent of the existing 128 KiB cartridge SRAM disk on ports 48h–4Dh.
The underlying expansion RAM remains intact while hidden by the overlay.

Use immediate `OUT (20h),A`, with A = `81h | (bank << 3)` for banks 1–7
(89h, 91h, 99h, A1h, A9h, B1h, B9h). Restore A=80h before returning to normal
CP/M execution. Bank zero does not overlay anything; A000–DFFF always accesses
bank zero. Reset and existing 80h/00h mode writes disable the overlay.

The bank number is latched from address lines A11–A13, not data bits D3–D5.
Immediate OUT puts A on the upper address bus. `OUT (C),A` instead takes those
bits from B and is not interchangeable. There is no control-register readback;
any interface permitting persistent selection needs a software shadow and
ownership rules. All ports 20h–2Fh alias the same latch.

## Recommendation

Implement optional banked **storage**, keeping the ordinary application map
and 50 KiB TPA. Start with a bank diagnostic and emulator support, then a
separate RAM drive (provisionally M:). With the existing 1 KiB allocation blocks
and a 2 KiB directory, 112 KiB raw would provide 110 KiB usable. Keeping it
separate from L: preserves L:'s existing geometry and behavior on older boards.
Drive limits, tables, allocation state and dashboard assumptions currently
describe twelve drives, so adding M: requires changes beyond a transfer routine.

An SD read cache is a useful alternative once the hardware is validated:
112 KiB holds at most 224 512-byte sectors, before any space reserved for tags
or other metadata. Repeated reads could benefit, but measure actual workloads
before choosing this over scratch storage. Start with clean read caching;
write-back would extend the existing dirty-cache ordering, flush and recovery
obligations. Do not allocate the same banks to both uses without an allocator.

This does not automatically increase the contiguous TPA or give existing
applications more addressable memory. Programs written for this interface
could keep data or overlays in banks. Moving BDOS into a bank would require
fixed-memory entry stubs and careful handling of application pointers hidden
by that same bank; it is a substantially larger redesign. A CP/M 3 conversion
is not needed to use these banks and would be a separate project.

## Why the middle window is manageable

The resident kernel at C900–D5FF, ROM routines, private BDOS/system stacks,
keyboard state and disk buffers all lie outside 4000–7FFF. These are suitable
places for a short bank-copy service. However, a caller's DMA buffer, stack or
code may occupy the window, including buffers crossing its boundaries.

Use a dedicated 128-byte bounce buffer in fixed memory for disk records:

1. On writes, copy the caller's record into the bounce buffer with the normal
   map selected.
2. Save the caller's stack pointer and interrupt state and use a fixed-memory
   stack before enabling the overlay. Direct BIOS callers can have a stack
   in the window even though BDOS already uses a private stack.
3. Select the bank and copy between the bank window and bounce buffer using
   code outside the window. Do not call ordinary BDOS services while banked.
4. Restore 80h before restoring the caller's stack, interrupt state or return
   path. On reads, copy the bounce buffer into the caller's DMA buffer only
   after restoring the normal map.

A 128-byte record divides a 16 KiB bank exactly, so aligned disk records never
straddle banks. The bounce buffer also handles application DMA buffers that
straddle 4000h or 8000h. Arbitrary-length future transfers would need splitting.
Do not reuse the live internal DMA or cache buffer without auditing its
contents and lifetime. Mask interrupts for the short mapped copy initially,
preserve their previous state, and audit NMI behavior separately (DI cannot
mask NMI). Interrupt entry itself can push onto a hidden application stack,
so fixed handler code alone is insufficient.

The disposable loader executes at 7000h during boot: keep the overlay disabled
until it has finished, including its boot display/retry services. A diagnostic
must also place its switching routine and stack outside the window.

## Implementation gates

- Completed: emulator models all seven banks, upper output address bits, reset
  and overlay-disable behavior. Unit tests cover the control combinations and
  real immediate, register and block output instructions.
- Provide an explicit configuration option initially. There is no advertised
  hardware ID. A later probe must save and restore touched RAM and check bank
  independence; a write/read through one bank is not sufficient on an old board.
- Completed: BANKTEST passed on hardware, including all seven banks, bank-zero
  isolation and underlying RAM preservation. A future storage driver still
  needs warm-boot preservation and cold-format tests.
- Test DMA below, inside, above and across both window boundaries, direct BIOS
  calls with a stack inside the window, interrupt-state restoration, and failure
  paths restoring the normal map.
- Budget resident code before implementation. The present layout has 246 bytes
  of resident code margin and 94 spare ROM bytes across two gaps. A complete
  driver will require relocation or a deliberate TPA tradeoff. Extra banked
  capacity does not remove the need for fixed-memory entry/copy code.

The immediate formatter change uses the existing cartridge SRAM only; it does
not enable the new overlay or change the hardware compatibility requirement.
