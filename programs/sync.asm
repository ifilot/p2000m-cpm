; Commit cached SD writes and reset logical disk state through CP/M BDOS 13.
org 0x100
    ld c,13
    call 5
    or a
    ld de,success
    jr z,report
    ld de,failure
report:
    ld c,9
    call 5
    jp 0
success: db 'SYNC: SD cache flushed; default drive A:.',13,10,'$'
failure: db 'SYNC FAILED: dirty data retained; restore original card and retry.',13,10,'$'
