; Exactly fills the advertised TPA. The CCP's return stack must be outside it.
org 0x100
    ld a,(0x97ff)
    cp 0xa5
    jr nz,failed
    ld a,(0x96ff)
    cp 0xa5
    jr nz,failed
    ld de,passed
    jr print
failed:
    ld de,error
print:
    ld c,9
    call 5
    ret
passed: db 'TPA LIMIT PASS',13,10,'$'
error: db 'TPA LIMIT FAIL',13,10,'$'
defs 0x9800-$,0xa5
