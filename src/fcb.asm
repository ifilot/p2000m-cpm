; Resident FCB decoding and synchronization, shared by the ROM filesystem.

; DE must reference a data block, never directory storage or a wrapped address.
; A zero allocation slot means a hole; callers handle it before entering here.
; Clobbers AF/HL; preserves DE. Invalid pointers enter bdos_disk_error.
fs_validate_block:
    ld hl,(max_blocks)
    or a
    sbc hl,de
    jp c,bdos_disk_error
    jp z,bdos_disk_error
    ld a,(fs_drive)
    cp ram_drive
    ld hl,4
    jr nz,fs_validate_min
    ld hl,2
fs_validate_min:
    or a
    sbc hl,de
    ret c
    ret z
    jp bdos_disk_error

; ----------------------------------------------------------------------------
; Routine: fs_entry_extent
; Decode an entry logical extent number from EX and S2.
;
; Inputs:   HL -> 32-byte directory entry.
; Outputs:  DE = (S2 & 63)*32 + (EX & 31); original HL restored.
; Clobbers: AF, DE; BC, HL, IX preserved.
; ----------------------------------------------------------------------------
fs_entry_extent:
    push hl
    ld de,12
    add hl,de
    ld a,(hl)
    and 31
    ld e,a
    inc hl
    inc hl
    ld a,(hl)
    and 63
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,0
    add hl,de
    ex de,hl
    pop hl
    ret


; ----------------------------------------------------------------------------
; Routine: fs_position
; Convert the FCB sequential position into a record number.
;
; Inputs:   IX -> FCB with EX/S2/CR set.
; Outputs:  HL and rw_record = record, CY=0 when valid. CY=1 on overflow.
;           Invalid masked S2>=16 returns zero; final-add overflow returns low 16 bits.
; Clobbers: AF, BC, DE, HL.
;
; Record = ((S2 & 63)*32 + (EX & 31))*128 + CR. The separate
; overflow path rejects S2>=16 rather than silently wrapping an 8 MiB file.
; ----------------------------------------------------------------------------
fs_position:
    ld a,(ix+14)
    and 63
    cp 16
    jr nc,fs_position_overflow
    ld h,a
    ld l,0
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ; HL = S2 * 32
    ld a,(ix+12)
    and 31
    or l
    ld l,a
    ld b,7
fs_position_shift:
    add hl,hl
    djnz fs_position_shift
    ld e,(ix+32)
    ld d,0
    add hl,de
    ld (rw_record),hl
    ret

; ----------------------------------------------------------------------------
; Routine: fs_position_overflow
; Return an invalid sequential-position result.
;
; Inputs:   Tail-entered for S2 outside the supported 8 MiB logical-file range.
; Outputs:  HL=0, rw_record=0, CY=1.
; Clobbers: F, HL.
; ----------------------------------------------------------------------------
fs_position_overflow:
    ld hl,0
    ld (rw_record),hl
    scf
    ret


; ----------------------------------------------------------------------------
; Routine: fs_sync_fcb
; Copy allocation/length metadata while retaining the logical position.
;
; Inputs:   IX -> FCB; entry_copy holds the matched entry; rw_record is position.
; Outputs:  FCB EX/S1/S2/RC/allocation/CR updated; IX unchanged.
; Clobbers: AF, BC, DE, HL; FCB bytes 12..32.
;
; On SD, directory EX may describe the second logical extent while the
; caller is reading the first. In that case RC is reported as 128, not the tail RC.
; ----------------------------------------------------------------------------
fs_sync_fcb:
    ld hl,entry_copy+16
    push ix
    pop de
    push de
    ld bc,16
    ex de,hl
    add hl,bc
    ex de,hl
    ldir
    pop de
    ld hl,(rw_record)
    ld a,l
    and 127
    ld (ix+32),a
    ld b,7
fs_sync_shift:
    srl h
    rr l
    djnz fs_sync_shift
    ld a,l
    and 31
    ld (ix+12),a
    ld a,l
    ld b,5
fs_sync_s2:
    srl h
    rr l
    djnz fs_sync_s2
    ld (ix+14),l
    ld (ix+13),0
    ld a,(entry_copy+12)
    ld b,a
    ld a,(extent_mask)
    and b
    ld b,a
    ld a,(extent_mask)
    and (ix+12)
    cp b
    ld a,128
    jr c,fs_sync_rc
    ld a,(entry_copy+15)
fs_sync_rc:
    ld (ix+15),a
    ret
