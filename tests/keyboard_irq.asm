; Busy application with known main/alternate registers. No console polling.
org 0x100
    jp start
    dw spin,finish
start:
    di
    ld sp,0x9500
    ld hl,0x1245
    push hl
    pop af
    ld bc,0x2345
    ld de,0x3456
    ld hl,0x4567
    ld ix,0x5678
    ld iy,0x6789
    exx
    ex af,af'
    ld hl,0x2381
    push hl
    pop af
    ld bc,0x789a
    ld de,0x89ab
    ld hl,0x9abc
    exx
    ex af,af'
    ei
spin:
    jp spin
finish:
    di
    ld (0x9100),bc
    ld (0x9102),de
    ld (0x9104),hl
    ld (0x9106),ix
    ld (0x9108),iy
    ld (0x910a),sp
    push af
    pop hl
    ld (0x910c),hl
    exx
    ex af,af'
    ld (0x9110),bc
    ld (0x9112),de
    ld (0x9114),hl
    push af
    pop hl
    ld (0x9116),hl
    ld a,0xa5
    ld (0x9118),a
    halt
