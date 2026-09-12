# RAMTEST

Runs the 75 KiB file checks on L: to exercise the SRAM filesystem across both
banks. This is a filesystem test, not an exhaustive SRAM cell test.

Run `RAMTEST` on A:. It requires 75 KiB free on L: and refuses an existing
`L:RAMTEST.DAT`. Escape then C cancels; cancellation may leave the test file.
