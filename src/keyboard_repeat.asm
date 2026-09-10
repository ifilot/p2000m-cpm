; Place the infrequent repeat path in the ROM tail, after the filesystem.
key_repeat:
    ld hl,(key_repeat_ptr)
    ld a,h
    or a
    ret z
    ld a,(key_repeat_mask)
    and (hl)
    ret z
    ld hl,key_repeat_count
    dec (hl)
    ret nz
    ld (hl),2
    ld a,(key_repeat_char)
    jp key_enqueue
