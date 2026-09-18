; Persistent VT52-style output parser, shared by all BDOS/BIOS output paths.
; Called inside console_output's register-saving wrapper: AF/BC/DE/HL scratch.
; State survives separate calls (including mixed BDOS 2/6/9 and BIOS CONOUT).
; ESC restarts a partial command; CAN cancels it; FF always clears normally.
; Unknown commands are consumed. Coordinates clamp to the 80x24 display.
terminal_escape:
    cp 27
    jr z,terminal_begin
    cp 24
    jr z,terminal_cancel
    cp 12
    jr z,terminal_formfeed
    ld a,(terminal_state)
    or a
    ret z                       ; CY=0: ordinary character
    ld b,a
    xor a
    ld (terminal_state),a
    ld a,c
    and 0x7f
    call terminal_command
    scf
    ret
terminal_begin:
    ld a,1
    ld (terminal_state),a
    scf
    ret
terminal_cancel:
    xor a
    ld (terminal_state),a
    scf
    ret
terminal_formfeed:
    xor a
    ld (terminal_state),a
    ret                         ; CY=0: existing FF handler
terminal_command:
    dec b
    jr z,terminal_opcode
    sub 32
    jr nc,terminal_coordinate
    xor a
terminal_coordinate:
    dec b
    jr nz,terminal_x
    cp 24
    jr c,terminal_y_valid
    ld a,23
terminal_y_valid:
    ld (terminal_row),a
    ld a,3
    ld (terminal_state),a
    ret
terminal_x:
    cp 80
    jr c,terminal_x_valid
    ld a,79
terminal_x_valid:
    ld (column),a
    ld e,a
    ld d,0
    ld hl,0xf000
    add hl,de
    ld a,(terminal_row)
    or a
    jr z,terminal_commit
    ld b,a
    ld de,80
terminal_row_loop:
    add hl,de
    djnz terminal_row_loop
terminal_commit:
    ld (cursor),hl
    ret
terminal_opcode:
    cp 'Y'
    jr z,terminal_address
    cp 'H'
    jr z,terminal_home
    cp 'J'
    jp z,terminal_erase_screen
    cp 'K'
    jp z,terminal_erase_line
    cp 'p'                      ; inverse video extension (not DEC VT52)
    jr z,terminal_inverse
    cp 'q'
    jr z,terminal_normal
    ld hl,(cursor)
    ld de,80
    cp 'A'
    jr z,terminal_up
    cp 'B'
    jr z,terminal_down
    cp 'C'
    jr z,terminal_right
    cp 'D'
    jr z,terminal_left
    ret
terminal_address:
    ld a,2
    ld (terminal_state),a
    ret
terminal_home:
    ld hl,0xf000
    ld (cursor),hl
    xor a
    ld (column),a
    ret
terminal_inverse:
    ld a,8
    jr terminal_set_attribute
terminal_normal:
    xor a
terminal_set_attribute:
    ld (terminal_attribute),a
    ret
terminal_up:
    or a
    sbc hl,de
    ld a,h
    cp 0xf0
    ret c
    jr terminal_commit
terminal_down:
    add hl,de
    push hl
    ld de,0xf780
    or a
    sbc hl,de
    pop hl
    ret nc
    jr terminal_commit
terminal_right:
    ld a,(column)
    cp 79
    ret z
    inc a
    inc hl
    jr terminal_horizontal
terminal_left:
    ld a,(column)
    or a
    ret z
    dec a
    dec hl
terminal_horizontal:
    ld (column),a
    jr terminal_commit
; Erase includes the cursor cell; leaves position and current rendition intact.
terminal_erase_screen:
    ld hl,0xf780
    ld de,(cursor)
    or a
    sbc hl,de
    ld b,h
    ld c,l
    ex de,hl
    jr terminal_erase
terminal_erase_line:
    ld a,(column)
    ld b,a
    ld a,80
    sub b
    ld c,a
    ld b,0
    ld hl,(cursor)
terminal_erase:
    ld (hl),' '
    set 3,h
    ld (hl),0
    res 3,h
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,terminal_erase
    ret
terminal_reset:
    xor a
    ld (terminal_state),a
    ld (terminal_attribute),a
    ret
terminal_state: db 0
terminal_row: db 0
terminal_attribute: db 0
