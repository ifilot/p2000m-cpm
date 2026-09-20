# P2000M Othello

Othello uses the P2000M's 80x24 text terminal rather than the CX16's VERA
graphics, sprites, mouse, joystick, or sound system. It is compiled as a CP/M
program with Z88DK's stand-alone Docker image.

Press `H` on the title or playing screen for rules, controls, the game version,
the compilation date, and the author credit for Ivo Filot embedded in the
executable.

## Build the game

```sh
make -C programs/othello othello
```

Run `J:OTHELLO` from CP/M. The title, playing field, cursor, legal-move markers,
placement, flipping, scoring, pass detection, end detection, and quit handling
are active. The CPU chooses the move with the largest immediate flip count,
with a strong preference for corners and deterministic tie-breaking.

## Run in the graphical emulator

With the sibling emulator checkout at the default location, run:

```sh
make -C programs/othello run
```

The target builds the program and graphical emulator, creates a disposable
`build/othello-run.img`, mounts the matching cartridge and card, enables the
CP/M co-board, and types `J:OTHELLO` after the `A>` prompt appears. Closing the
emulator returns control to Make. Override the checkout location with, for
example, `make -C programs/othello run EMULATOR=/path/to/p2000m-emulator`.

## Test the rules

```sh
python3 -m unittest tests.test_othello -v
```

The deterministic property suite compares the production engine with an
independent reference implementation across arbitrary fields and complete
randomly played games. The fixed random seed makes any failure reproducible.
