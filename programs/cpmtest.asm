; Original transient exerciser, uses only the public CP/M CALL 5 interface.
org 0x100
    ld sp,0x8f00
    xor a
    ld (0x9000),a
    ld (drive),a
    ld de,banner
    ld c,9
    call 5
next_drive:
    ld a,(drive)
    add a,'A'
    ld e,a
    ld c,2
    call 5
    ld de,working
    ld c,9
    call 5
    ld hl,fcb
    ld de,fcb+1
    ld bc,35
    ld (hl),0
    ldir
    ld a,(drive)
    inc a
    ld (fcb),a
    ld hl,filename
    ld de,fcb+1
    ld bc,11
    ldir
    ld de,fcb
    ld c,19
    call 5
    ld a,1
    ld (phase),a
    ld de,fcb
    ld c,22
    call 5
    cp 0xff
    jp z,failed
    ld de,buffer
    ld c,26
    call 5
    ld hl,0
    ld (counter),hl
write_loop:
    ld a,2
    ld (phase),a
    call fill
    ld de,fcb
    ld c,21
    call 5
    or a
    jp nz,failed
    call advance
    jr nz,write_loop
    ld a,3
    ld (phase),a
    ld de,fcb
    ld c,16
    call 5
    cp 0xff
    jp z,failed
    xor a
    ld (fcb+12),a
    ld (fcb+14),a
    ld (fcb+32),a
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jp z,failed
    ld hl,0
    ld (counter),hl
read_loop:
    ld a,4
    ld (phase),a
    ld de,fcb
    ld c,20
    call 5
    or a
    jp nz,failed
    call verify
    call advance
    jr nz,read_loop
    ld a,5
    ld (phase),a
    ld de,fcb
    ld c,20
    call 5
    cp 1
    jp nz,failed
    ld a,6
    ld (phase),a
    ld de,fcb
    ld c,35
    call 5
    ld hl,(fcb+33)
    ld de,600
    or a
    sbc hl,de
    jp nz,failed
    ld a,(fcb+35)
    or a
    jp nz,failed
    ld hl,513
    ld (counter),hl
    ld (fcb+33),hl
    ld de,fcb
    ld c,33
    call 5
    or a
    jp nz,failed
    call verify
    ld a,7
    ld (phase),a
    ld de,fcb
    ld c,19
    call 5
    cp 0xff
    jp z,failed
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jp nz,failed
    ld a,(drive)
    inc a
    ld (drive),a
    cp 3
    jp nz,next_drive
    ld de,passed
    ld c,9
    call 5
    ld a,0xa5
    ld (0x9000),a
    jp 0
advance:
    ld hl,(counter)
    inc hl
    ld (counter),hl
    ld de,600
    or a
    sbc hl,de
    ret
fill:
    ld hl,buffer
    ld de,(counter)
    ld b,128
fill_byte:
    ld a,l
    xor d
    xor e
    ld (hl),a
    inc hl
    djnz fill_byte
    ret
verify:
    ld hl,buffer
    ld de,(counter)
    ld b,128
verify_byte:
    ld a,l
    xor d
    xor e
    cp (hl)
    jp nz,failed
    inc hl
    djnz verify_byte
    ret
failed:
    ld (failure_value),a
    ld de,failure
    ld c,9
    call 5
    ld a,(phase)
    add a,'0'
    ld e,a
    ld c,2
    call 5
    ld de,failure_drive
    ld c,9
    call 5
    ld a,(drive)
    add a,'A'
    ld e,a
    ld c,2
    call 5
    ld de,crlf
    ld c,9
    call 5
    ld a,0xee
    ld (0x9000),a
    jp 0
banner: db 'CPMTEST: 600 records per drive, extents, random I/O, size, delete',13,10,'$'
working: db ': testing...',13,10,'$'
passed: db 'CPMTEST PASS',13,10,'$'
failure: db 'CPMTEST FAIL phase $'
failure_drive: db ' drive $'
crlf: db 13,10,'$'
filename: db 'CPMTEST DAT'
drive: db 0
phase: db 0
failure_value: db 0
counter: dw 0
fcb: defs 36,0
defs 0x800-$,0
buffer: defs 128,0
