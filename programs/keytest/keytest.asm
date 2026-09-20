; P2000M SD CP/M raw keyboard wiring diagnostic, z80asm COM at 0100h.
; The Field Support Manual, 3.1.2 / fig. 3.2, specifies ten active-low
; input rows at ports 00h..09h, eight Y bits each. See README for provenance.
; No translated input is used to identify keys. DI keeps the resident scanner
; from consuming Escape or accumulating type-ahead while we own the matrix.
; The normal CP/M warm boot restores interrupts/CTC. No mapping/port writes.
    org 0x100
start:
    ld sp,stack_top
    ld c,6
    ld e,12
    call 5
    di
    ld hl,screen_text
    ld de,0xf000
    ld bc,1920
    ldir
    ld hl,0xf800
    ld de,0xf801
    ld bc,1919
    ld (hl),0
    ldir
    xor a
    ld (exiting),a
scan:
    ; B=0 gives a deterministic high I/O address byte on every read.
    ld bc,0
    ld hl,rows
sample:
    in a,(c)
    ld (hl),a
    inc hl
    inc c
    ld a,c
    cp 10
    jr nz,sample
    ld ix,rows
    ld iy,0xf000+5*80+10
    ld c,10
paint_row:
    ; Hex raw value at column 4, then eight independently inverted tiles.
    push iy
    pop hl
    ld de,-6
    add hl,de
    ld a,(ix+0)
    rrca
    rrca
    rrca
    rrca
    call hex_digit
    ld a,(ix+0)
    call hex_digit
    push iy
    pop hl
    ld de,0x0800
    add hl,de
    ld e,(ix+0)
    ld d,8
paint_bit:
    rr e
    ld a,0
    jr c,paint_tile
    ld a,8                  ; P2000M inverse attribute
paint_tile:
    ld b,7
paint_cell:
    ld (hl),a
    inc hl
    djnz paint_cell
    inc hl                  ; leave the separator normal
    dec d
    jr nz,paint_bit
    ld de,80
    add iy,de
    inc ix
    dec c
    jr nz,paint_row
    ld a,(exiting)
    or a
    jr nz,wait_release
    ld a,(rows+9)
    and 0x81
    jp nz,scan
    ld a,(rows+4)
    and 1
    jp nz,scan
    ld a,1
    ld (exiting),a
    ld hl,release_text
    ld de,0xf000+20*80
    ld bc,80
    ldir
wait_release:
    ; Only the exit chord must release: another stuck wire must not trap us.
    ld a,(rows+9)
    and 0x81
    cp 0x81
    jp nz,scan
    ld a,(rows+4)
    and 1
    jp z,scan
    ; Require a quiet release interval, still repainting held keys otherwise.
    ld bc,20000
release_delay:
    dec bc
    ld a,b
    or c
    jr nz,release_delay
    in a,(9)
    and 0x81
    cp 0x81
    jp nz,scan
    in a,(4)
    and 1
    jp z,scan
    ; DI BIOS CONST scans twice to synchronize the driver's release state.
    ; Drain through BIOS, not BDOS 6: a queued NUL is still a real character.
    ld hl,(1)               ; warm-boot vector is BIOS+3
    ld de,3
    add hl,de               ; CONST is BIOS+6
    ld (status_call+1),hl
    ld de,3
    add hl,de               ; CONIN is BIOS+9
    ld (input_call+1),hl
flush:
status_call:
    call 0
    or a
    jr z,finish
input_call:
    call 0
    jr flush
finish:
    ld c,6
    ld e,12
    call 5
    jp 0                    ; reinitializes IM2/CTC and enables interrupts
hex_digit:
    and 15
    add a,'0'
    cp '9'+1
    jr c,hex_store
    add a,7
hex_store:
    ld (hl),a
    inc hl
    ret
rows: defs 10,255
exiting: db 0
release_text:
    db 'Exit selected: release both SHIFT keys and ESC.                                  '
screen_text:
include 'screen.inc'
    defs 128,0
stack_top:
