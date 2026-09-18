# Headless P2000M test emulator

This is a source subset of `ifilot/p2000m-emulator`, bundled for reproducible
CP/M tests. The original snapshot is commit
`ecabb2b9411c08cd21ac0fdc415ff63c5309246f`. The machine and Z80 source files now
include the bank-switching changes also applied to the sibling emulator working
tree based on `0a0534349b54f632d7fe4d691501ec8b88281b13` (not yet committed).
The revised model has 128 KiB of co-board SRAM and captures bank selection from
the full 16-bit Z80 output address bus.
It contains the machine, SD/SRAM and floppy-controller models, the Z80 CPU,
and the 4 KiB monitor ROM. No Qt, GUI, character ROMs, zlib, or display renderer
is required. Tests inspect video RAM and inject keyboard matrix events directly;
the emulated frame clock still supplies the keyboard interrupt timing.

The Python runners compile these sources with GCC/G++ (C++17) into the existing
test executables. From the repository root, after building the firmware, run:

```sh
python3 -m unittest discover -s tests -v
python3 tools/test_emulator.py
python3 tools/test_programs.py
```

The two command-line runners also accept `--emulator /path/to/p2000m-emulator`
for comparison with another upstream checkout. Unit tests always use this copy.
The floppy model is retained because the machine owns it and its port/interrupt
behavior is part of the monitor's boot environment. No floppy media is bundled.
Unused bundled-software loading helpers remain for source parity; tests load
the monitor and freshly built cartridge explicitly.

## Provenance and updates

`src/core/` follows the snapshot and working-tree update described above;
`LICENSE` is copied from upstream.
`src/vendor/superzazu_z80/` preserves its upstream README and MIT license
(CPU base revision `d64fe10a2274e5e40019b1086bf7d8990cbc5f23`). Local changes
to `z80.c`/`z80.h` widen the output callback to 16 bits and provide A/BC output
addresses, including decremented B for block output. Input callbacks remain
unchanged. `tests/cpm_banking.cpp` mirrors the upstream emulator banking test;
`tests/test_banking.py` runs it and the BANKTEST diagnostic fault cases. The machine/device
code retains its GPL-3.0-or-later notice; the full GPLv3 text is in the root
`LICENSE`. Monitor provenance is in `assets/roms/README.md`; the historical
firmware is not relicensed as GPL.

To update, copy the same files from a reviewed emulator revision, update this
commit marker, and run the complete suite. Keep hardware behavior changes in
the upstream emulator first so both projects can share the same model.
