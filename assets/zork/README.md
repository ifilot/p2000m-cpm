# Zork I, II, and III

Preserved CP/M text adventures by Infocom. Each game consists of a `.COM`
interpreter and its matching `.DAT` file. The build copies all six files
unchanged onto drive C:. Select C: and run `ZORK1`, `ZORK2`, or `ZORK3`.

Copied from `ifilot/p2000c-cpm-transfer`, directory `programs/games/zork`,
at commit `bb0aa2e2a9228aba0467ead7cc86ee6a4df10411`:
[source snapshot](https://github.com/ifilot/p2000c-cpm-transfer/tree/bb0aa2e2a9228aba0467ead7cc86ee6a4df10411/programs/games/zork).
That directory does not document an earlier binary source or a license grant;
these historical binaries retain their original rights and are not covered
by this project's GPLv3 grant.

`tools/build.py` uses this directory by default and records each file's SHA-256
in `build/build-info.json`. Use `--zork-dir` only to supply an alternative set.
The emulator program tests verify startup and `LOOK` for all three games.
