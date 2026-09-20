# Microsoft COBOL-80

These preserved CP/M-80 binaries are installed on drive F: by the normal image
build. They are Microsoft COBOL-80 4.65: `COBOL.COM`, its four overlays,
Link-80, the standard libraries, and the ANSI terminal driver.

Source: [Deramp's CP/M Software archive](https://deramp.com/downloads/microsoft/CPM%20Software/COBOL-80/),
downloaded from the individual files on 2026-09-20. The files are historical
third-party software; this project's GPL licence does not apply to them.

Compile and link a program on F::

```text
F>COBOL =EXAMPLE
F>L80 EXAMPLE/N,EXAMPLE/E
A>F:EXAMPLE
```

The toolchain and generated files use CP/M 8.3 names. `COBOL.COM` requires its
`.OVR` files to remain on the current drive. `RUNCOB.COM` is also supplied on
A: because the historical launcher opens its executor through the default FCB.
