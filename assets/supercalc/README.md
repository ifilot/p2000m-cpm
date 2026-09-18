# SuperCalc2 1.00 for CP/M-80

Historical Sorcim software, copyright 1983. These binaries retain their original
rights and are not covered by this project's GPLv3 license.

Source: [Deramp SuperCalc2 disk archive](https://deramp.com/downloads/altair/software/8_inch_floppy/CPM/CPM%202.2/SuperCalc2/),
`supercalc2.dsk` (337,664 bytes), downloaded 2026-09-18.
Source SHA-256: `b08ab3f8db3ee389061250fa1d781ed5b4d4824b3bfa5ff0345bbb423d396b52`.
[Original user manual](https://deramp.com/downloads/altair/software/manuals/SuperCalc2.pdf).

The image contains a Burcon CP/M filesystem with 137-byte physical sectors,
32 sectors/track, two reserved tracks, 2 KiB blocks and 128 directory entries.
Tracks below 6 use payload bytes 3–130; later tracks use bytes 7–134 and apply
an additional `(sector * 17) mod 32` translation after the BDOS skew table.
These details were checked against the [original Burcon BIOS source](https://deramp.com/downloads/altair/software/8_inch_floppy/CPM/CPM%202.2/Burcon%20CPM/BIOS.ASM).

## Installed files and configuration

The build puts the following on **D: CALC**:

- `SC2.COM`, `SC2.OVL`, `SC2.HLP`: spreadsheet, overlays and help.
- `INSTALL.COM`, `INSTALL.OVL`, `INSTALL.DAT`: matching Sorcim installer 2.00.
- Seven original `.CAL` sample worksheets.

Only `SC2.COM` is changed. Sorcim's own installer, running under the P2000M
emulator, wrote the P2000M terminal configuration. No application logic was
patched. Its differences are within the terminal configuration area at file
offsets 0080–027F (memory 0180–037F), including the cursor-addressing routine.
The other twelve files are byte-identical to the extracted files. Altair system
utilities and unrelated/older SDI files are excluded.

The terminal is `P2000M VT52`, 80x24, with `ESC Y` cursor addressing, `ESC H/J/K`
home/erasure, and `ESC p/q` inverse/normal active-cell attributes. Keyboard
lead-in is disabled; up/down/left/right are 0Bh/0Ah/08h/0Ch. One CRT attribute
is enabled, without guard characters. SuperCalc reports roughly 20 KiB free
worksheet memory at startup on this 50 KiB TPA.

To reproduce with the original installer: select DEC, then VT-52 and save.
Re-enter the terminal menu and press the unlisted `X` option for Dealer's
Custom Installation, then `N` to retain the VT52 defaults. In `C`, set the
keyboard lead-in to none and the four arrow codes above. In `B`, set cursor
attribute start/end to `1B 70` / `1B 71`. In `E`, set CRT attributes to 1 and
answer no to guard characters. In `F`, enter `P2000M VT52`. Exit with `X`,
choose `A` to save, and confirm `Y`. Wait for each menu before typing.

`terminal-profile.json` preserves the exact installer-generated area and the
original executable checksum. `SHA256SUMS` pins every installed file. To verify
and reproduce the import without running the installer again:

```sh
python3 tools/import_supercalc.py /path/to/supercalc2.dsk --output /tmp/supercalc
```

The importer checks the source hash, sector checksums, original executable and
all final file hashes before writing. Builds are offline and use these bundled
assets; `build-info.json` records their hashes.
