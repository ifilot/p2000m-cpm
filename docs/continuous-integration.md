# Continuous integration and releases

The `Build, test, and release` GitHub Actions workflow runs for every pushed
commit and tag, and can also be started manually. It:

1. builds the cartridge, kernel, programs, and complete SD-card image;
2. runs the host-side assembly, linker, filesystem, and image tests;
3. compiles the headless harnesses against the bundled P2000M emulator core and
   runs the boot, hardware-interface, BDOS, application, and fault-injection
   suites; and
4. uploads the cartridge, compressed SD image, manifest, and checksums as a
   short-lived workflow artifact.

A tag additionally creates a GitHub Release after all tests pass. The release
contains `cartridge.bin`, both compressed and uncompressed SD-card images,
`build-info.json`, and `SHA256SUMS`. Tags may use `v0.4.0` or `0.4.0` form, but
their version must match `VERSION`.

## Stand-alone emulator tests

The full suite runs using only this repository and Python 3.11+, `z80asm`,
and GCC/G++. Its C++ harnesses use the CPU/device implementation and monitor
ROM bundled in `tests/emulator` to execute the assembled Z80 system. It needs
no Qt, visualization libraries, emulator checkout, or `EMULATOR_TOKEN` secret.
The [snapshot guide](../tests/emulator/README.md) records provenance and the
upstream revision, and explains how to update the copied core.

The core preserves the upstream hardware models, including frame-driven CTC
interrupts, keyboard matrix, memory mapping, and SD/SRAM behavior. Tests inspect
screen memory directly, so rendering and character ROMs are unnecessary.

Zork COM/DAT files are bundled in `assets/zork` and copied unchanged into drive
C: of the SD image. Their [provenance](../assets/zork/README.md) records the
source revision. Builds and tests use only files from this repository; CI still
installs the compiler and assembler through the runner's package manager.
The optional boot-preview image renderer still
uses the sibling emulator's character ROMs; it is not part of CI or testing.
