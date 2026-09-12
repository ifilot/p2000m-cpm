# P2000M serial-port experiments

The built-in serial printer port is software-timed, not a UART. The Philips
[P2000M/T Field Support Manual](https://electrickery.hosting.philpem.me.uk/comp/p2000c/doc/P2000MT_FSupp.pdf)
documents the shared CPU-board interface in sections 3.2 (printed pages 3-7
and 3-8) and the connector in section 3.8.7 (printed page 3-31).
The [documented P2000T monitor disassembly](https://github.com/p2000t/documentation/tree/main/programming/Monitor%20Documented%20Disassembly)
provides a second reference for transmit polarity, READY and baud timing.

- Output: port `10h`, bit 7, PRD; 1 starts a frame, 0 is idle/stop.
- Input: port `20h`, bit 0, PRI; the receiver measures idle polarity at startup.
- Handshake: port `20h`, bit 1, READY; 0 means ready.
- Port `10h` also controls cassette signals and keyboard interrupt enable.
  These diagnostics leave its other bits zero, as required by this CP/M setup.
  They do not write port `20h`, which controls memory mapping on the co-board.

The manual describes reception as normally unused except for testing. These
programs are experiments, not evidence that every P2000M revision is identical.
BIOS READER/PUNCH/LIST remain stubs; this does **not** add production BDOS serial
redirection. The COM programs add no resident memory cost.

## Wiring

Use a **real RS232-level adapter**, such as a USB-to-RS232 adapter with a DB9
connector. The P2000 interface uses bipolar RS232 levels, nominally +/-12 V.
Do not connect a 3.3 V/5 V TTL USB-UART or bare logic-analyzer input directly.
Power equipment down before wiring; verify connector pin numbers, not wire colors.

| P2000M DB25 | Signal at P2000M | PC DB9 |
| --- | --- | --- |
| 3 | PRO, transmit output | 2, receive input |
| 2 | PRI, receive input | 3, transmit output |
| 7 | Signal ground | 5, signal ground |
| 20 | READY input, optional | 7, RTS output |

The P2000 pin directions differ from a conventional PC DB25 serial port.
Do not assume a generic null-modem cable has this wiring. Leave other pins
disconnected, especially the strapped handshake outputs on pins 5 and 6.
For three-wire testing, omit READY and use `SERTX F`.

## Programs And PC Companion

Build output contains `SERPINS.COM`, `SERTX.COM`, and `SERRX.COM`; all three are
also installed on B: alongside BDS C. All tests use **300 baud, 8 data bits,
no parity, one stop bit**, with PC software/hardware flow control disabled.
Press Q on the P2000 to exit; a receiver timeout makes quitting bounded.

Install the PC helper dependency once:

```sh
python -m pip install pyserial
```

Substitute your adapter for `COM3` (for example `/dev/ttyUSB0` on Linux).

1. Run `B:SERPINS` on the P2000. Run
   `python tools/serial_pc.py COM3 pins` on the PC. The helper changes RTS and
   BREAK every three seconds. Bit 1 of the displayed `IN20 & 03` should follow
   READY; bit 0 should change with BREAK. SERPINS never drives output pins.
2. Run `python tools/serial_pc.py COM3 receive`, then `B:SERTX` on the P2000
   (`B:SERTX F` without READY). Expect ten lines of
   `P2000M RS232 Uu0123456789`, each followed by CR/LF. An inactive READY
   produces an explicit bounded error rather than hanging.
3. Run `python tools/serial_pc.py COM3 send`, then `B:SERRX` on the P2000.
   Keep PC transmit idle until SERRX says `Listening`, then press Enter on the
   PC. Expect `55`, `75`, `30` through `39`, `0D`, `0A`, one hex byte per line.
   The helper spaces bytes by 100 ms so display work cannot lose the next byte.

SERRX rejects false starts and bad stop bits. Its polling receiver is not
suitable for unpaced streams. Both TX and RX preserve the caller's interrupt
state; interrupts are disabled during each frame, about 33 ms at 300 baud.
Keyboard scanning can therefore be delayed during transmission. Higher rates
and buffered BIOS integration should follow physical validation, not precede it.

## Verification And Feedback

Automated tests execute the actual assembled routines in the existing Z80
core. They cover all 256 bytes, both PRI polarities, both interrupt states,
exact transmit timing (8,336 T-states/bit at 2.5 MHz, approximately 299.9 baud),
READY timeout/bypass, false starts, framing errors, register preservation, and
safe output-port values. Complete-program tests check pin display, the ten-line
transmit pattern, argument handling and receive display. Image tests verify
the installed COM files byte-for-byte.

The emulator does not currently model the real serial connector; these tests
use synthetic input waveforms. Physical electrical levels, cable wiring and
your machine's clock/polarity still need hardware confirmation.
Please record the adapter model, wiring, idle/RTS/BREAK readings, received PC
bytes and SERRX output. Those results will tell us whether a faster driver
and useful BIOS device routing are practical.

The companion uses the documented
[pyserial API](https://pyserial.readthedocs.io/en/latest/pyserial_api.html).
