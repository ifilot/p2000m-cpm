org 0x100
    ld a,(0x80)
    or a
    jr z,begin
    ld b,a
    ld hl,0x81
argument_loop:
    ld a,(hl)
    inc hl
    cp ' '
    jr z,argument_next
    and 0xdf
    cp 'F'
    jr nz,usage
    ld a,1
    ld (serial_force),a
argument_next:
    djnz argument_loop
begin:
    ld de,banner
    ld c,9
    call 5
    ld a,10
    ld (lines),a
next_line:
    ld hl,pattern
next_char:
    call serial_quit
    ret z
    ld a,(hl)
    or a
    jr z,line_done
    call serial_ready
    jr c,not_ready
    ld c,(hl)
    call serial_tx
    inc hl
    jr next_char
line_done:
    ld a,(lines)
    dec a
    ld (lines),a
    jr nz,next_line
    ret
not_ready:
    ld de,ready_error
    jr print_exit
usage:
    ld de,usage_text
print_exit:
    ld c,9
    jp 5
lines: db 0
banner: db 'SERTX: 300 baud, 8N1, 10 test lines. Q exits.',13,10,'$'
pattern: db 'P2000M RS232 Uu0123456789',13,10,0
ready_error: db 'READY inactive. Check pin 20; SERTX F bypasses handshake.',13,10,'$'
usage_text: db 'Usage: SERTX [F]',13,10,'$'
include 'serial_test.inc'
