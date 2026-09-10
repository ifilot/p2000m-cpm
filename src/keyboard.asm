; CTC channel 3: one video field per interrupt (50 Hz), as in P2000M CP/M.
; ISR owns the producer; CONIN owns the consumer. DI callers run the scanner
; synchronously. No BDOS, disk, console-output or shared SD state in the ISR.


keyboard_interrupt:
    ld (key_saved_sp),sp
    ld sp,keyboard_stack_top
    push af
    push bc
    push de
    push hl
    push ix
    call key_scan
    call key_repeat
    pop ix
    pop hl
    pop de
    pop bc
    pop af
    ld sp,(key_saved_sp)
    ei
    reti

; CONST preserves BC/DE/HL/IX/IY and the caller's interrupt enable state.
; With DI, two immediate samples retain synchronous BIOS input semantics.
; Repeat is timed only by the ISR, never by application polling frequency.
console_status:
    push bc
    push de
    push hl
    push ix
    ld a,i
    jp pe,key_status
    call key_scan
    call key_scan
key_status:
    ld a,(key_head)
    ld b,a
    ld a,(key_tail)
    sub b
    jr z,key_status_done
    ld a,0xff
key_status_done:
    pop ix
    pop hl
    pop de
    pop bc
    ret

console_input:
    call console_status
    or a
    jr z,console_input
    push hl
    ld a,(key_tail)
    or 0xc0
    ld l,a
    ld h,0xdc
    ld a,(hl)
    push af
    ld a,(key_tail)
    inc a
    and 63
    ld (key_tail),a          ; release slot only after reading its byte
    pop af
    pop hl
    ret

; Each matrix bit changes its debounced state after two equal samples.
; HL traverses the selected character table; C=row, D=bit mask, E=new presses.
key_scan:
    ld hl,keys_normal
    in a,(9)
    and 0x81
    cp 0x81
    jr z,key_scan_begin
    ld hl,keys_shift
key_scan_begin:
    ld ix,key_rows
    ld c,0
key_scan_row:
    in a,(c)
    cpl
    ld d,a
    xor (ix+0)
    cpl
    ld e,a                 ; bits whose raw value is stable
    ld a,d
    ld (ix+0),a
    xor (ix+1)
    and e
    xor (ix+1)             ; new stable state
    ld d,a
    ld a,(ix+1)
    cpl
    and d
    ld e,a                 ; new presses only; releases do not create events
    ld (ix+1),d
    or a
    jr nz,key_scan_changes
    ld de,8
    add hl,de              ; skip the bit loop for rows without new presses
    jr key_scan_row_done
key_scan_changes:
    ld d,1
    ld b,8
key_scan_bit:
    ld a,e
    and d
    jr z,key_scan_next
    ld a,(hl)
    or a
    call nz,key_event
key_scan_next:
    inc hl
    rlc d
    djnz key_scan_bit
key_scan_row_done:
    inc ix
    inc ix
    inc c
    ld a,c
    cp 9
    jr nz,key_scan_row
    ret

; Translate the Escape control prefix at enqueue time, not at consumption.
key_event:
    push bc
    push de
    push hl
    ld b,a
    ld a,(key_escape)
    or a
    ld a,b
    jr nz,key_control
    cp 27
    jr nz,key_event_ready
    ld a,1
    ld (key_escape),a
    ld hl,0
    ld (key_repeat_ptr),hl
    jr key_event_done
key_control:
    cp 27
    jr z,key_control_ready
    and 0x1f
key_control_ready:
    ld b,a
    xor a
    ld (key_escape),a
    ld a,b
key_event_ready:
    ld (key_repeat_char),a
    push ix
    pop hl
    inc hl
    ld (key_repeat_ptr),hl
    ld a,d
    ld (key_repeat_mask),a
    ld a,51                ; this frame's repeat tick reduces it to 50
    ld (key_repeat_count),a
    ld a,(key_repeat_char)
    call key_enqueue
key_event_done:
    pop hl
    pop de
    pop bc
    ret

key_enqueue:
    ld b,a
    ld a,(key_head)
    inc a
    and 63
    ld c,a
    ld a,(key_tail)
    cp c
    jr z,key_full
    ld a,(key_head)
    or 0xc0
    ld l,a
    ld h,0xdc
    ld (hl),b
    ld a,c
    ld (key_head),a         ; publish only after writing the complete event
    ret
key_full:
    ld a,1
    ld (key_overflow),a     ; retain older queued input; drop newest on overflow
    ret
