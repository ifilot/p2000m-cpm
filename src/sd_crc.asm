; SD CRC16 (x^16+x^12+x^5+1), initial DE=0, no final XOR.
; A=input; DE=updated CRC; preserves BC/HL, clobbers AF.
; Fold a whole byte without a lookup table or eight per-bit iterations:
; x = input ^ old_high; x ^= x >> 4;
; crc = (old_low << 8) ^ (x << 12) ^ (x << 5) ^ x.
sd_crc16_byte:
    push bc
    xor d
    ld d,a
    rrca
    rrca
    rrca
    rrca
    and 0x0f
    xor d
    ld d,a
    rrca
    rrca
    rrca
    ld b,a
    and 0x1f
    xor e
    ld e,a
    ld a,b
    and 0xe0
    xor d
    ld b,a
    ld a,d
    rlca
    rlca
    rlca
    rlca
    and 0xf0
    xor e
    ld d,a
    ld e,b
    pop bc
    ret
