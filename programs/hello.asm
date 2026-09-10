org 0x100
    ld de,message
    ld c,9
    call 5
    ret
message: db 'Hello from an original Z80 CP/M program on SD!',13,10,'$'
