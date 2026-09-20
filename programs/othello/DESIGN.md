# P2000M Othello interaction design

## Scope for the first playable release

The game is an 8-by-8, human-versus-CPU Othello game. It uses the P2000M's
80-by-24 CP/M terminal and does not require a mouse, joystick, sound, files,
or special hardware beyond normal console input/output.

`O` is the human player and moves first. `X` is the CPU player. A game ends
after both players pass or all 64 squares are occupied.

## Screen regions

The renderer uses VT52 absolute positioning and only redraws cells and status
values that changed.

| Region | Position | Contents |
| --- | --- | --- |
| Header | Row 0 | `P2000M OTHELLO` and `HUMAN vs CPU` |
| Board labels | Rows 1–18, columns 3–41 | `A`–`H`, `1`–`8`, and the board grid |
| Board cells | Rows 3, 5, …, 17; columns 7, 11, …, 35 | Empty square, `O`, or `X` |
| Status panel | Rows 3–13, columns 51–79 | Player, CPU, score, turn, and controls |
| Message line | Row 20 | Contextual prompt or event message |
| Legal-move line | Row 22 | Number of legal moves or end-game prompt |

The board is represented as a compact 8-by-8 text grid. A selected cell is
shown with inverse video. Empty legal cells use a `.` marker; other empty
cells are blank. This makes legal choices visible without an extra mode or
colour.

## State flow

```text
TITLE --Enter--> PLAYING --game ends--> RESULT
  ^                 |                    |
  +------ Q --------+-------- Enter ------+
```

`Q` returns to CP/M only after confirmation on the title or result screen; in
the playing state it opens a confirmation prompt so an accidental key press
cannot lose a game.

## Title state

The title screen is deliberately brief:

```text
                         P2000M OTHELLO

                    HUMAN (O)  versus  CPU (X)

           Capture discs by enclosing one or more X discs.

           Arrow keys move     Space places a disc
           Enter starts        Q returns to CP/M
```

| Key | Action |
| --- | --- |
| Enter | Start a fresh game with the standard four central discs. |
| Q | Exit cleanly to CP/M. |
| Any other key | No action. |

## Playing state

### Human turn

The cursor begins on the first legal move after a new game and after each CPU
move. Arrow keys wrap around the board edges; this avoids dead-end cursor
movement and matches the feel of the original CX16 game.

| Key | Action |
| --- | --- |
| Up / Down / Left / Right | Move the selection one cell, wrapping at an edge. |
| Space or Enter | Attempt a move at the selected cell. |
| Q | Show `QUIT GAME? (Y/N)` on row 20. |

Placing a legal disc immediately redraws the placed disc, all flipped discs,
both scores, and the turn label. An invalid placement leaves the board
unchanged and shows `THAT SQUARE IS NOT A LEGAL MOVE.` until the next input.

If the human has no legal move, the game shows `YOU HAVE NO LEGAL MOVE — CPU
CONTINUES.` for a short delay, then makes the CPU turn. A pass is not an error
and does not require user input.

### CPU turn

The status panel reads `TURN: CPU` and the message line says `CPU IS THINKING
...`. The first CPU version uses the portable CX16 heuristic: choose a legal
move that flips the most discs, give corners a bonus, and choose among equal
scores deterministically. This is fast enough that the message should remain
visible for a fixed, short delay rather than exposing a flickering instant
turn.

After the delay, the CPU places its move and returns control to the human. If
it cannot move, the message reads `CPU HAS NO LEGAL MOVE — YOUR TURN.` and the
human continues.

## Result state

The final board remains visible. The status panel is replaced by the final
score and one of:

```text
YOU WIN!
CPU WINS.
DRAW GAME.
```

The message line says `ENTER: PLAY AGAIN    Q: RETURN TO CP/M`.

| Key | Action |
| --- | --- |
| Enter | Reset and begin a fresh game. |
| Q | Exit cleanly to CP/M. |

## Quit confirmation

The board remains unchanged while confirming. Row 20 reads `QUIT GAME? (Y/N)`.
`Y` returns to CP/M; `N`, Escape, or any other key restores the preceding
message and play state. The CPU is never interrupted because the prompt is
only available during the human turn.

## Implementation consequences

- Keep game state and rendering separate: the rules engine exposes legal
  moves, apply-move, score, and current player; the terminal module owns all
  escape sequences and cursor placement.
- Use CP/M BDOS direct console input/output (function 6) so raw arrow and
  positioning bytes are preserved.
- Use the P2000M native arrow input bytes already documented for SuperCalc:
  Up `0Bh`, Down `0Ah`, Left `08h`, Right `0Ch`.
- No timing-dependent animation is required. A bounded busy delay for the
  CPU status keeps the behaviour deterministic in the emulator and hardware.
