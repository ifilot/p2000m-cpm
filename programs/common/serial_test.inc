; Standalone P2000M diagnostics: software serial at 300 baud, 8N1, 2.5 MHz.
; Port 10h bit 7: PRD (inverted relative to UART data); other bits stay zero,
; matching this CP/M's output-latch ownership. Never OUT to mapping port 20h.
; These routines are not installed as BIOS devices.

serial_quit:
    push bc
    push de
    push hl
    ld c,6
    ld e,0xff
    call 5
    pop hl
    pop de
    pop bc
    and 0xdf
    cp 'Q'
    ret

; READY is active low. Bound missing-handshake waits; preserve BC/DE/HL.
serial_ready:
    ld a,(serial_force)
    or a
    ret nz
    push bc
    ld bc,0
serial_ready_wait:
    in a,(0x20)
    and 2
    jr z,serial_ready_ok
    dec bc
    ld a,b
    or c
    jr nz,serial_ready_wait
    pop bc
    scf
    ret
serial_ready_ok:
    pop bc
    or a
    ret

; C=byte. Preserve BC/DE/HL and caller interrupt state. AF clobbered.
; OUT-to-OUT interval: 26*317+94 = 8336 T states (299.90 baud).
serial_tx:
    push bc
    push de
    push hl
    ld a,i
    push af
    di
    ld e,c
    ld d,1
    sla e
    rl d
    ld b,10
serial_tx_bit:
    ld a,e
    and 1
    xor 1
    rrca
    out (0x10),a
    call serial_delay
    srl d
    rr e
    djnz serial_tx_bit
    pop af
    pop hl
    pop de
    pop bc
    jp po,serial_tx_done
    ei
serial_tx_done:
    ret
serial_delay:
    ld hl,317
serial_delay_loop:
    dec hl
    ld a,h
    or l
    jr nz,serial_delay_loop
    ret
serial_half_delay:
    ld hl,157
    jr serial_delay_loop

; A=byte, CY=0 on success; CY=1 and A=1 timeout / A=2 framing error.
; PRI idle polarity is calibrated before the PC starts sending. Preserve
; BC/DE/HL/IFF. Interrupts are masked only across the sampled character.
serial_rx:
    push bc
    push de
    push hl
    ld a,i
    push af
    ld a,(serial_rx_idle)
    ld d,a
    ld bc,0
serial_rx_wait_idle:
    in a,(0x20)
    and 1
    xor d
    jr z,serial_rx_start_wait
    dec bc
    ld a,b
    or c
    jr nz,serial_rx_wait_idle
    jr serial_rx_timeout
serial_rx_start_wait:
    ld bc,0
serial_rx_wait:
    in a,(0x20)
    and 1
    xor d
    jr nz,serial_rx_start
    dec bc
    ld a,b
    or c
    jr nz,serial_rx_wait
serial_rx_timeout:
    ld a,1
    jr serial_rx_exit
serial_rx_start:
    di
    call serial_half_delay
    in a,(0x20)
    and 1
    xor d
    jr z,serial_rx_framing
    ld b,8
    ld e,0
serial_rx_bit:
    call serial_delay
    in a,(0x20)
    xor d
    and 1
    xor 1
    rrca
    rr e
    djnz serial_rx_bit
    call serial_delay
    in a,(0x20)
    and 1
    xor d
    jr nz,serial_rx_framing
    ld a,e
    ld (serial_rx_value),a
    xor a
    jr serial_rx_exit
serial_rx_framing:
    ld a,2
serial_rx_exit:
    ld (serial_rx_status),a
    pop af
    pop hl
    pop de
    pop bc
    jp po,serial_rx_result
    ei
serial_rx_result:
    ld a,(serial_rx_status)
    or a
    jr nz,serial_rx_error
    ld a,(serial_rx_value)
    or a
    ret
serial_rx_error:
    scf
    ret

serial_hex:
    push af
    rrca
    rrca
    rrca
    rrca
    call serial_nibble
    pop af
serial_nibble:
    and 15
    add a,'0'
    cp '9'+1
    jr c,serial_digit
    add a,7
serial_digit:
    push bc
    push de
    push hl
    ld e,a
    ld c,2
    call 5
    pop hl
    pop de
    pop bc
    ret
serial_force: db 0
serial_rx_idle: db 1
serial_rx_value: db 0
serial_rx_status: db 0
