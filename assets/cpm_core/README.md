# Bundled CP/M 2.2 utilities

These preserved programs are installed in user area 0 of drive A: by the normal
image build. They are unmodified third-party CP/M programs, separate from the
original Z80 operating-system implementation in this project.

ASM, DDT, ED, LOAD, PIP and STAT were copied byte-for-byte from the user-supplied
`../p2000m-emulator/assets/software/cpm_core` directory. That checkout records
[ifilot/p2000c-cpm-disk-tool, commit 37f7ae0035044362c383b4818e5d664353f15baa](https://github.com/ifilot/p2000c-cpm-disk-tool/tree/37f7ae0035044362c383b4818e5d664353f15baa/files/core)
as their upstream source.

DUMP was absent from the supplied folder. `dump.com` is the unchanged
`A/0/DUMP.COM` member of
[RunCPM's DISK/A0.zip, commit 79396be665d6ec263a2728b20b177f4149647ed8](https://github.com/MockbaTheBorg/RunCPM/blob/79396be665d6ec263a2728b20b177f4149647ed8/DISK/A0.zip).
Archive SHA-256: `52882689181d0ad17acbc113097e92b223395674dd4b16d6d8765f4643c9b518`.
The archive's `DISK/1STREAD.ME` identifies its standard DRI distribution and
retains rights with the original authors; this project's original source does
not confer a new license on these historical programs.

| Program | Bytes | SHA-256 |
| --- | ---: | --- |
| `ASM.COM` | 8,192 | `ef403388a04f18d735984fe497f9fa5dbb48f114b52dab323e33e82073133c2c` |
| `DDT.COM` | 4,864 | `d79890f0a637aee317a255bdac6b27215b1ad4452a1b6da822828bcba5a49ecf` |
| `DUMP.COM` | 384 | `f8dd3bb2c9c2082742307f5992f13f2d3057f9e40c55433637c0d59eac338044` |
| `ED.COM` | 6,656 | `0397b96b6d48ba92a0b41cdf974bf8ad31e4d49783f1ff7eed9e701b6a8870db` |
| `LOAD.COM` | 1,792 | `c885d061a5dcb3830ab1c29a13e34d3c0560cc3faf569bc55b195c0330a9cbd6` |
| `PIP.COM` | 7,424 | `7f9e12a92e2bcfd814b5b680a2f7d5c2a2c50c9a5ef94a6891dcaa3527f08ec2` |
| `STAT.COM` | 5,248 | `614d0b1d66466177e5b2bf585251d53d1e24eda34ada136b4ae178ab5944dc73` |
