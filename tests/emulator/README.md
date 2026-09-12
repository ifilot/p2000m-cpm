# Headless P2000M test emulator

This is an unmodified source subset of `ifilot/p2000m-emulator` at commit
`ecabb2b9411c08cd21ac0fdc415ff63c5309246f`, bundled for reproducible CP/M tests.
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

`src/core/` and `LICENSE` are copied from the upstream revision above.
`src/vendor/superzazu_z80/` preserves its upstream README and MIT license
(CPU revision `d64fe10a2274e5e40019b1086bf7d8990cbc5f23`). The machine/device
code retains its GPL-3.0-or-later notice; the full GPLv3 text is in the root
`LICENSE`. Monitor provenance is in `assets/roms/README.md`; the historical
firmware is not relicensed as GPL.

To update, copy the same files from a reviewed emulator revision, update this
commit marker, and run the complete suite. Keep hardware behavior changes in
the upstream emulator first so both projects can share the same model.
