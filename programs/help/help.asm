; HELP -- compact offline reference for the P2000M SD CP/M image.
org 0x100

    ld de,help_text
    ld c,9
    call 5
    ret

help_text:
    db 'P2000M SD CP/M help',13,10
    db 'A: system: HELP MORE COPY SYNC and diagnostics.',13,10
    db 'B: BDS C and serial tools.  C: Zork.  D: SuperCalc2.',13,10
    db 'E: MBASIC.  F: MS COBOL-80.  L: temporary SRAM disk.',13,10,13,10
    db 'Commands: DIR [files]  TYPE file  ERA file  REN new=old',13,10
    db '          COPY source destination  PIP dest=source',13,10
    db '          MORE textfile  DUMP file  STAT [file]',13,10,13,10
    db 'Run A:SYNC before reset or power-off to flush SD writes.',13,10
    db 'Use HELP alone; MORE needs FILE.EXT. CP/M names are 8.3.',13,10,'$'
