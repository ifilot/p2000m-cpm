org 0x100
    ld de,banner
    ld c,9
    call 5
    in a,(0x20)
    and 1
    ld (serial_rx_idle),a
    ld de,listening
    ld c,9
    call 5
receive:
    call serial_quit
    ret z
    call serial_rx
    jr nc,received
    cp 1
    jr z,receive
    ld de,framing
    ld c,9
    call 5
    jr receive
received:
    call serial_hex
    ld de,newline
    ld c,9
    call 5
    jr receive
banner: db 'SERRX: 300 baud, 8N1. Keep PC TX idle during startup.',13,10,'$'
listening: db 'Listening; send slowly (100 ms/byte). Q exits.',13,10,'$'
framing: db 'FRAMING ERROR',13,10,'$'
newline: db 13,10,'$'
include 'serial_test.inc'
