org 0x100
    ld de,banner
    ld c,9
    call 5
poll:
    call serial_quit
    ret z
    in a,(0x20)
    and 3
    ld d,a
    ld a,(last)
    cp d
    jr z,poll
    ld a,d
    ld (last),a
    ld de,label
    ld c,9
    call 5
    ld a,(last)
    call serial_hex
    ld de,newline
    ld c,9
    call 5
    jr poll
last: db 0xff
banner: db 'SERPINS: input bits 0=PRI, 1=READY (0=ready). Q exits.',13,10,'No output pins are driven.',13,10,'$'
label: db 'IN20 & 03 = $'
newline: db 13,10,'$'
include 'serial_test.inc'
