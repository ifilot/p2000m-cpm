# P2000M Othello

This directory begins with a Z88DK CP/M toolchain smoke test. The planned game
will use the P2000M's 80x24 text terminal rather than the CX16's VERA
graphics, sprites, mouse, joystick, or sound system.

## Build the smoke test

With Docker available, run this from the repository root:

```sh
make -C programs/othello hello
```

This invokes the official `z88dk/z88dk` image and writes `build/HELLO.COM`.
The program prints `Hello from Z88DK on P2000M CP/M!` when run from drive A:.

## Build the terminal prototype

```sh
make -C programs/othello othello
```

Run `OTHELLO` from CP/M. This is the static interaction prototype: title,
playing-field layout, cursor movement, placement feedback, and quit handling
work, while game rules and the CPU move chooser are still to come.

## Run in the graphical emulator

With the sibling emulator checkout at the default location, run:

```sh
make -C programs/othello run
```

The target builds the program and graphical emulator, creates a disposable
`build/othello-run.img`, mounts the matching cartridge and card, enables the
CP/M co-board, and types `OTHELLO` after the `A>` prompt appears. Closing the
emulator returns control to Make. Override the checkout location with, for
example, `make -C programs/othello run EMULATOR=/path/to/p2000m-emulator`.
