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

; These helpers share the ROM tail with CRC16, leaving space for cartridge
; activity control below the fixed IM2 vector. No additional resident RAM.
; CRC7 accumulator E uses bits 7..1; polynomial x^7+x^3+1, initial zero.
; A=input byte; clobbers AF/B/E, preserves C/D/HL.
sd_crc7_byte:
    xor e
    ld b,8
crc7_bit:
    add a,a
    jr nc,crc7_next
    xor 0x12
crc7_next:
    djnz crc7_bit
    ld e,a
    ret

; Consume both wire CRC bytes, including on mismatch. Z=valid; clobbers AF/DE.
sd_crc16_check:
    call spi_rx
    xor d
    ld d,a
    call spi_rx
    xor e
    or d
    ret
