; Two write-back SD sector caches. Only the BIOS calls the ROM sector routines.
; Directory sectors (SD track zero) have a separate buffer. Commit data before
; metadata; failed writes retain tag, bytes and dirty state. Failed fills never
; publish a valid tag. LBA keys include all 32 bits and therefore the drive.
;
; Descriptor: valid, dirty, LBA[4], buffer pointer[2]. Workspace DC90-DCAD
; follows allocation_c and precedes file_buffer at DD00. Buffers D800/DE00.
cache_data: equ 0xdc90
cache_directory: equ 0xdc98
cache_request: equ 0xdca0
cache_fault: equ 0xdca4
cache_hint: equ 0xdca5
cache_reads: equ 0xdca6
cache_writes: equ 0xdca8
cache_hits: equ 0xdcaa
cache_write_attempts: equ 0xdcac

; Reset tags only after a successful flush. Statistics survive logical resets.
cache_invalidate:
    xor a
    ld (cache_data),a
    ld (cache_data+1),a
    ld (cache_directory),a
    ld (cache_directory+1),a
    ld (cache_fault),a
    ld hl,sector_buffer
    ld (cache_data+6),hl
    ld hl,0xde00
    ld (cache_directory+6),hl
    ret

; Public extended BIOS vector 17 (C033): flush both caches. A=0 success, 1
; failure; IX/IY preserved. Dirty data is retained on every failure path.
cache_flush:
    push ix
    ld a,(cache_fault)
    or a
    jr z,cache_flush_begin
    ; An explicit retry may follow removal/reinsertion of the original card.
    ; Reinitialize its protocol without discarding any buffered data.
    call 0xe009
    or a
    jr nz,cache_flush_return
cache_flush_begin:
    ld ix,cache_data
    call cache_flush_slot
    or a
    jr nz,cache_flush_return
    ld ix,cache_directory
    call cache_flush_slot
    or a
    jr nz,cache_flush_return
    xor a
    ld (cache_fault),a
cache_flush_return:
    pop ix
    ret

cache_flush_slot:
    ld a,(ix+1)
    or a
    ret z
    ld l,(ix+2)
    ld h,(ix+3)
    ld (0x9e00),hl
    ld l,(ix+4)
    ld h,(ix+5)
    ld (0x9e02),hl
    ld l,(ix+6)
    ld h,(ix+7)
    ld (0x9e04),hl
    ld hl,(cache_write_attempts)
    inc hl
    ld (cache_write_attempts),hl
    call 0xe006
    or a
    jr nz,cache_flush_failed
    ld hl,(cache_writes)
    inc hl
    ld (cache_writes),hl
    xor a
    ld (ix+1),a
    ret
cache_flush_failed:
    ld a,1
    ld (cache_fault),a
    or a
    ret

; Entry: cache_request = physical LBA, writing, record, DMA and hint latched.
; Preserve the filesystem's FCB in IX across all cache operations.
cache_transfer:
    push ix
    call cache_transfer_inner
    pop ix
    ret
cache_transfer_inner:
    ld a,(cache_fault)
    or a
    jp nz,disk_error
    ld ix,cache_data
    ld hl,(track)
    ld a,h
    or l
    jr nz,cache_lookup
    ld ix,cache_directory
cache_lookup:
    ld a,(ix+0)
    or a
    jr z,cache_miss
    ld hl,(cache_request)
    ld a,l
    cp (ix+2)
    jr nz,cache_miss
    ld a,h
    cp (ix+3)
    jr nz,cache_miss
    ld hl,(cache_request+2)
    ld a,l
    cp (ix+4)
    jr nz,cache_miss
    ld a,h
    cp (ix+5)
    jr nz,cache_miss
    ld hl,(cache_hits)
    inc hl
    ld (cache_hits),hl
    jr cache_copy
cache_miss:
    ; A directory eviction must first commit any data it might reference.
    ld hl,(track)
    ld a,h
    or l
    jr nz,cache_evict_data
    ld a,(ix+1)
    or a
    jr z,cache_evicted      ; a clean directory miss need not flush file data
    call cache_flush
    jr cache_evicted
cache_evict_data:
    call cache_flush_slot
cache_evicted:
    or a
    ret nz
    xor a
    ld (ix+0),a             ; a partial failed read is never a cache hit
    ld hl,(cache_request)
    ld (0x9e00),hl
    ld hl,(cache_request+2)
    ld (0x9e02),hl
    ld l,(ix+6)
    ld h,(ix+7)
    ld (0x9e04),hl
    ld hl,(cache_reads)
    inc hl
    ld (cache_reads),hl
    call 0xe003
    or a
    ret nz
    ld hl,(cache_request)
    ld (ix+2),l
    ld (ix+3),h
    ld hl,(cache_request+2)
    ld (ix+4),l
    ld (ix+5),h
    ld (ix+0),1
cache_copy:
    ld a,(record)
    and 3
    rrca
    ld e,a
    and 1
    ld d,a
    ld a,e
    and 0x80
    ld e,a                 ; DE = (record & 3) * 128
    ld l,(ix+6)
    ld h,(ix+7)
    add hl,de
    ld de,(dma)
    ld bc,128
    ld a,(writing)
    or a
    jr nz,cache_store
    ldir
    xor a
    ret
cache_store:
    ex de,hl
    ldir
    ld (ix+1),1
    ld a,(cache_hint)
    cp 1                   ; CP/M immediate directory-write barrier
    jp z,cache_flush
    xor a
    ret
