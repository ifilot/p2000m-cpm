; Revised P2000M co-board banking diagnostic. z80asm, CP/M COM at 0100h.
; Destroys banks 1-7. Saves/restores normal 4000-7FFF at 8000-BFFF.
; Code, state and private stack remain below 4000h. No BDOS while mapped.
    org 0x100
start:
    ld (entry_sp),sp
    ld a,i
    di
    ld sp,0x3f00
    push af
    pop hl
    ld a,l
    ld (entry_flags),a
    ld a,0x80
    out (0x20),a
    ld hl,0x4000
    ld de,0x8000
    ld bc,0x4000
    ldir
    call restore_interrupts
    ld de,banner
    call puts
    ; Seed underlying expansion RAM so a missing overlay is detected.
    di
    ld hl,0x4000
    ld d,0x55
    call fill_window
    xor a
    ld (phase),a
pass:
    call restore_interrupts
    ld de,writing_text
    call puts
    ld a,1
    ld (bank),a
write_bank:
    call show_bank
    di
    call save_guards
    call select_bank
    call fill_window
    call check_guards
    jp nz,failed
    call normal_map
    ld a,(bank)
    inc a
    ld (bank),a
    cp 8
    jr nz,write_bank
    ld de,verifying_text
    call puts
    ld a,1
    ld (bank),a
verify_bank:
    call show_bank
    di
    call save_guards
    call select_bank
    call verify_window
    jp nz,failed
    call check_guards
    jp nz,failed
    call normal_map
    ld a,(bank)
    inc a
    ld (bank),a
    cp 8
    jr nz,verify_bank
    ; Test the hidden expansion RAM after all writes, including old boards
    ; which ignore the bank controls. Bank zero is also required to disable
    ; the overlay rather than expose fixed resident SRAM at 4000h.
    di
    xor a
    ld (bank),a
    ld a,0x81
    out (0x20),a
    ld d,0x55
    ld hl,0x4000
    call verify_window
    jp nz,failed
    call normal_map
    ld a,(phase)
    or a
    jr nz,passed
    dec a
    ld (phase),a
    jp pass
passed:
    call restore_window
    ld de,pass_text
    call puts
    jp finish
failed:
    ; verify_window/check_guards return HL=address, C=expected, A=actual.
    ld (bad_address),hl
    ld (actual),a
    ld a,c
    ld (expected),a
    call restore_window
    ld de,fail_text
    call puts
    ld a,(bank)
    call hex_byte
    ld de,address_text
    call puts
    ld hl,(bad_address)
    ld a,h
    call hex_byte
    ld hl,(bad_address)
    ld a,l
    call hex_byte
    ld de,expected_text
    call puts
    ld a,(expected)
    call hex_byte
    ld de,actual_text
    call puts
    ld a,(actual)
    call hex_byte
    ld de,newline
    call puts
finish:
    di
    ld sp,(entry_sp)
    ld a,(entry_flags)
    and 4
    ret z
    ei
    ret

; Always restore the normal map before touching saved expansion RAM or BDOS.
restore_window:
    di
    ld a,0x80
    out (0x20),a
    ld hl,0x8000
    ld de,0x4000
    ld bc,0x4000
    ldir
    jp restore_interrupts
normal_map:
    ld a,0x80
    out (0x20),a
restore_interrupts:
    ld a,(entry_flags)
    and 4
    ret z
    ei
    ret

; Bank-specific address pattern, then its complement on the second pass.
; Pattern includes both address bytes, detecting stuck/aliased address lines.
select_bank:
    ld a,(bank)
    rlca
    rlca
    rlca
    or 0x81
    out (0x20),a
    ld a,(phase)
    ld d,a
    ld a,(bank)
    xor d
    ld d,a
    ld hl,0x4000
    ret
fill_window:
    ld a,h
    xor l
    xor d
    ld (hl),a
    inc hl
    bit 7,h
    jr z,fill_window
    ret
verify_window:
    ld a,h
    xor l
    xor d
    ld c,a
    ld a,(hl)
    cp c
    ret nz
    inc hl
    bit 7,h
    jr z,verify_window
    xor a
    ret

; Boundary/fixed-RAM probes are read-only. Check while the bank is selected.
save_guards:
    ld ix,guard_addresses
    ld de,guard_values
    ld b,6
save_guard:
    ld l,(ix+0)
    ld h,(ix+1)
    ld a,(hl)
    ld (de),a
    inc de
    inc ix
    inc ix
    djnz save_guard
    ret
check_guards:
    ld ix,guard_addresses
    ld de,guard_values
    ld b,6
check_guard:
    ld l,(ix+0)
    ld h,(ix+1)
    ld a,(de)
    ld c,a
    ld a,(hl)
    cp c
    ret nz
    inc de
    inc ix
    inc ix
    djnz check_guard
    xor a
    ret
show_bank:
    ld a,(bank)
    add a,'0'
    ld e,a
    ld c,2
    call 5
    ret
puts:
    ld c,9
    jp 5
hex_byte:
    push af
    rrca
    rrca
    rrca
    rrca
    call hex_digit
    pop af
hex_digit:
    and 15
    add a,'0'
    cp '9'+1
    jr c,hex_emit
    add a,7
hex_emit:
    ld e,a
    ld c,2
    jp 5
entry_sp: dw 0
entry_flags: db 0
phase: db 0
bank: db 0
bad_address: dw 0
expected: db 0
actual: db 0
guard_addresses: dw 0x3fff,0x8000,0xa000,0xbfff,0xc000,0xdfff
guard_values: defs 6
banner: db 'BANKTEST - revised co-board 112 KiB banking test',13,10
    db 'Overwrites banks 1-7; preserves normal window RAM.',13,10,'$'
writing_text: db 13,10,'Write banks:  $'
verifying_text: db 13,10,'Verify banks: $'
pass_text: db 13,10,'BANKTEST PASS - 7 banks, 2 patterns, normal RAM intact',13,10,'$'
fail_text: db 13,10,'BANKTEST FAIL bank $'
address_text: db ' addr $'
expected_text: db ' expected $'
actual_text: db ' got $'
newline: db 13,10,'$'
