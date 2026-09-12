# BDS C 1.60

These unchanged files come from Leor Zolman's distribution:
https://www.bdsoft.com/resources/bdsc.html
https://www.bdsoft.com/dist/bdsc-all.zip

Archive SHA-256:
`bf5ab207081acb50729471fd29bf40ee63b3800e7617144e358e7533da558c0c`

The author released BDS C, its sources and documentation into the public
domain on September 20, 2002. The CP/M-80 `bdsc160` files are used, not the
ZCPR3 variant. COM, CRL, CCC, LBR and DOC files come from `bdsc160/`;
`STDIO.H` comes from `bdsc160/work/STDIO.H`.

Drive B: includes both compiler passes (`CC`, `CC2`), linker (`CLINK`),
runtime (`C.CCC`), libraries (`DEFF.CRL`, `DEFF2.CRL`), standard header,
configuration/library tools, and source/example archives with extraction tools.
The build manifest records each installed file's SHA-256.

From B:, run `CC CDEMO`, `CLINK CDEMO`, then `CDEMO`.
CC automatically chains to CC2. BDS C implements an older C dialect;
use its supplied STDIO.H and documentation when writing programs.
