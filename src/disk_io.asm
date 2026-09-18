; ROM-resident BIOS disk operations. All latched state and DPHs remain in RAM.
; ============================================================================
; DISK SELECTION: latch the parameters for the next record transfer
; SETTRK/SETSEC/SETDMA do not perform I/O. The subsequent READ or WRITE
; validates geometry and consumes the latched values. Sectors are zero-based.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: disk_home
; Set logical track zero without mechanical seeking.
;
; Inputs:   No inputs.
; Outputs:  [track]=0; BC=0.
; Clobbers: BC only; flags preserved.
;
; Falls through into disk_track; no floppy seek command is issued.
; ----------------------------------------------------------------------------


disk_home:
    ld bc,0

; ----------------------------------------------------------------------------
; Routine: disk_track
; Latch the zero-based track.
;
; Inputs:   BC = zero-based track.
; Outputs:  [track] = BC; no I/O yet.
; Clobbers: No registers or flags; only the named RAM word.
; ----------------------------------------------------------------------------
disk_track:
    ld (track),bc
    ret

; ----------------------------------------------------------------------------
; Routine: disk_sector
; Latch the zero-based logical sector within the track.
;
; Inputs:   BC = zero-based logical sector within the track.
; Outputs:  [record] = BC; no I/O yet.
; Clobbers: No registers or flags; only the named RAM word.
; ----------------------------------------------------------------------------
disk_sector:
    ld (record),bc
    ret

; ----------------------------------------------------------------------------
; Routine: disk_dma
; Latch the address of a 128-byte CPU-memory buffer.
;
; Inputs:   BC = address of a 128-byte CPU-memory buffer.
; Outputs:  [dma] = BC; no I/O yet.
; Clobbers: No registers or flags; only the named RAM word.
; ----------------------------------------------------------------------------
disk_dma:
    ld (dma),bc
    ret

; ----------------------------------------------------------------------------
; Routine: disk_select
; Select A: through L: and return its disk parameter header.
;
; Inputs:   C=0..11 for A:..L:; CP/M E login flag is not needed by fixed media.
; Outputs:  HL -> DPH on success; HL=0 for an unsupported drive.
; Clobbers: AF, DE, HL; BC, IX, IY preserved.
;
; Each DPH is 16 bytes. A:..K: share geometry and a rebuilt scratch allocation
; maps. An invalid selection leaves the previous drive selected.
; ----------------------------------------------------------------------------
disk_select:
    ld hl,0
    ld a,c
    cp drive_count
    ret nc
    ld a,(selected)
    cp c
    jr z,disk_select_ready
    push bc
    call cache_flush
    pop bc
    ld hl,0
    or a
    ret nz
disk_select_ready:
    ld a,c
    ld (selected),a
    add a,a
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,dph_a
    add hl,de
    ret

; ----------------------------------------------------------------------------
; Routine: disk_translate
; Identity sector translation for contiguous logical records.
;
; Inputs:   BC = zero-based logical sector; DE translation table is ignored.
; Outputs:  HL=BC.
; Clobbers: HL only; flags preserved.
;
; No interleave/skew table is needed for solid-state media.
; ----------------------------------------------------------------------------
disk_translate:
    ld h,b
    ld l,c
    ret

; ----------------------------------------------------------------------------
; Routine: disk_error
; Return the BIOS nonrecoverable-error code.
;
; Inputs:   No register inputs.
; Outputs:  A=1/Z=0.
; Clobbers: AF only.
; ----------------------------------------------------------------------------
disk_error:
    ld a,1
    or a
    ret

; ============================================================================
; RECORD I/O: deblock SD sectors or address SRAM directly
; The BIOS public record size is 128 bytes. One SD physical sector contains
; four records; SRAM is accessed byte by byte without an auto-increment port.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: disk_read
; Read the latched 128-byte record into DMA.
;
; Inputs:   [selected], [track], [record], [dma] describe the request.
; Outputs:  A=0/Z=1 success, A=1/Z=0 failure; DMA receives 128 bytes on success.
; Clobbers: AF, BC, DE, HL; sector_buffer and shared ROM scratch.
; ----------------------------------------------------------------------------
disk_read:
    xor a
    jr disk_transfer

; ----------------------------------------------------------------------------
; Routine: disk_write
; Write the DMA record to the selected drive (buffered for SD).
;
; Inputs:   Latched disk/DMA state; C=1 requests immediate ordered commit.
; Outputs:  A=0/Z=1 accepted (committed for C=1), A=1/Z=0 failure.
; Clobbers: AF, BC, DE, HL; selected media, sector_buffer and ROM scratch.
;
; Hints 0/2 are buffered; CLOSE/reset/warm boot and vector 17 flush them.
; SRAM remains immediate. Hint 2 conservatively reads the sector on a miss.
; ----------------------------------------------------------------------------
disk_write:
    ld a,c
    ld (cache_hint),a
    ld a,1

; ----------------------------------------------------------------------------
; Routine: disk_transfer
; Common record transfer dispatcher and SD deblocking path.
;
; Inputs:   A=0 read or 1 write; disk selection/geometry/DMA are latched in RAM.
; Outputs:  A=0 success or A=1 failure, with matching Z flag.
; Clobbers: AF, BC, DE, HL.
;
; SD LBA = partition base + track*32 + sector/4. The low two sector
; bits pick a 128-byte slice. Cache misses read 512 bytes to retain neighbours.
; ----------------------------------------------------------------------------
disk_transfer:
    ld (writing),a
    ld a,(selected)
    cp ram_drive
    jp z,ram_transfer
    jp nc,disk_error
    ld hl,(track)
    ld a,h
    cp 2
    jp nc,disk_error
    ld de,(record)
    ld a,d
    or a
    jp nz,disk_error
    ld a,e
    cp 128
    jp nc,disk_error
    ; Physical SD sector offset = track * 32 + record / 4.
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    srl e
    srl e
    add hl,de
    ld de,0x0800
    add hl,de
    ld a,(selected)
    srl a
    srl a
    add a,2
    ld c,a
    ld b,0
    ld a,(selected)
    and 3
    rrca
    rrca
    ld d,a
    ld e,0
    add hl,de
    jr nc,sd_base
    inc bc
sd_base:
    ld (cache_request),hl
    ld (cache_request+2),bc
    jp cache_transfer

; ----------------------------------------------------------------------------
; Routine: ram_transfer
; Transfer one logical record through the SRAM address/data ports.
;
; Inputs:   [writing]=0/1; [track]=0..31, [record]=0..31; [dma] -> 128 bytes.
; Outputs:  A=0/Z=1 success, A=1/Z=0 for out-of-range geometry.
; Clobbers: AF, BC, DE, HL; SRAM or DMA depending on direction.
;
; Track bit 4 selects the 64 KiB bank. Remaining address bits encode
; (track & 15)*4096 + record*128. HL is SRAM address, DE is CPU DMA pointer.
; ----------------------------------------------------------------------------
ram_transfer:
    ld hl,(track)
    ld a,h
    or a
    jp nz,disk_error
    ld a,l
    cp 32
    jp nc,disk_error
    ld de,(record)
    ld a,d
    or a
    jp nz,disk_error
    ld a,e
    cp 32
    jp nc,disk_error
    ld a,l
    and 16
    rrca
    rrca
    rrca
    rrca
    out (0x4b),a
    ; Within each bank: track low nibble * 4096 + record * 128.
    ld a,l
    and 15
    rlca
    rlca
    rlca
    rlca
    ld h,a
    ld l,0
    ld a,e
    srl a
    or h
    ld h,a
    ld a,e
    and 1
    rrca
    ld l,a
    ld de,(dma)
    ld b,128
    ld a,(writing)
    or a
    jr nz,ram_write
    inc a                  ; READ LED for physical SRAM accesses only
    out (0x44),a
ram_read_byte:
    call ram_address
    in a,(0x4d)
    ld (de),a
    inc de
    inc hl
    djnz ram_read_byte
    xor a
    out (0x44),a
    ret
ram_write:
    ld a,2                 ; same WRITE LED as SD sector writes
    out (0x44),a
ram_write_byte:
    call ram_address
    ld a,(de)
    out (0x4d),a
    inc de
    inc hl
    djnz ram_write_byte
    xor a
    out (0x44),a
    ret

; ----------------------------------------------------------------------------
; Routine: ram_address
; Load the SRAM bank-relative address latch.
;
; Inputs:   HL = 16-bit address within the bank already selected through port 4Bh.
; Outputs:  Ports 49h/48h hold H/L; A=L.
; Clobbers: A only; flags and other registers preserved.
; ----------------------------------------------------------------------------
ram_address:
    ld a,h
    out (0x49),a
    ld a,l
    out (0x48),a
    ret
