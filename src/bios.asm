; ============================================================================
; src/bios.asm -- source tour and calling conventions
; ============================================================================
; Hardware boundary of the system: CP/M calls above, P2000M I/O ports below.
; Keep the vector order fixed and keep cold-only SRAM formatting out of warm boot.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; CP/M 2.2 BIOS jump table. Disk I/O exclusively uses port-2 SD/SRAM.

; ============================================================================
; BIOS ABI: fixed 17-entry CP/M 2.2 jump table
; Each entry is a three-byte JP at bios + 3*index. Do not insert data
; between entries: applications derive addresses from the warm-boot vector.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: bios
; Cold-boot vector and base of the public BIOS entry table.
;
; Inputs:   Register inputs depend on the selected table entry; see each target.
; Outputs:  Entry zero transfers to cold_restart; this table itself has no RET.
; Clobbers: As specified by the target routine.
;
; The order is BOOT, WBOOT, CONST, CONIN, CONOUT, LIST, PUNCH, READER,
; HOME, SELDSK, SETTRK, SETSEC, SETDMA, READ, WRITE, LISTST, SECTRAN.
; ----------------------------------------------------------------------------
bios:
    jp cold_restart
    jp warm_boot
    jp console_status
    jp console_input
    jp console_output
    jp null_output
    jp null_output
    jp null_input
    jp disk_home
    jp disk_select
    jp disk_track
    jp disk_sector
    jp disk_dma
    jp disk_read
    jp disk_write
    jp list_status
    jp disk_translate
    jp cache_flush         ; extension: vector 17, bios + 51

; ============================================================================
; SYSTEM LIFECYCLE: cold initialization versus warm restart
; Only cold boot clears BDOS state and formats cartridge SRAM. Warm boot
; reinstalls page-zero vectors and the default DMA without touching L: data.
; ============================================================================

; Restore the system's CTC/IM2 ownership before entering the CCP.
keyboard_enable:
    di
    ld a,3
    out (0x88),a
    out (0x89),a
    out (0x8a),a
    out (0x8b),a
    im 2
    ld a,0xe7
    ld i,a
    ld a,0xf8
    out (0x88),a             ; channel 3 vector FE -> ROM word E7FE
    ld a,0xd5
    out (0x8b),a
    ld a,1
    out (0x8b),a
    ei
    ret

; Cold restart flushes first; failure preserves state via warm-boot recovery.
cold_restart:
    call cache_flush
    or a
    jp nz,warm_boot     ; retain dirty state; user can restore card and retry
    jp rom_restart

; ----------------------------------------------------------------------------
; Routine: warm_boot
; Restart the resident CCP without reformatting the RAM drive.
;
; Inputs:   [0004h] = saved CCP drive (0..11); invalid values fall back to A:.
; Outputs:  No return: enters ccp_loop with DMA=0080h and standard page-zero jumps.
; Clobbers: AF, BC, DE, HL, SP; current_drive, user_dma, DMA, page-zero vectors.
;
; 0005h jumps directly to BDOS at the TPA boundary, below system stacks.
; ----------------------------------------------------------------------------
warm_boot:
    ld sp,system_stack_top
    ; Applications may return after a bare CR or without a final newline.
    call ccp_newline
warm_start:
    call keyboard_enable
warm_flush:
    call cache_flush
    or a
    jr z,warm_flushed
    ld hl,flush_error_text
    call ccp_puts
warm_flush_key:
    call console_input
    and 0xdf
    cp 'R'
    jr nz,warm_flush_key
    jr warm_flush
warm_flushed:
    ld a,(4)
    and 15
    cp drive_count
    jr c,warm_drive
    xor a
warm_drive:
    ld (current_drive),a
    ld a,0xc3
    ld (0),a
    ld hl,bios+3
    ld (1),hl
    ld a,0xc3
    ld (5),a
    ld hl,bdos_entry
    ld (6),hl
    ld hl,0x80
    ld (user_dma),hl
    ld bc,0x80
    call disk_dma
    jp ccp_loop
flush_error_text: db 13,10,'SD flush failed: dirty data retained. Restore original card.',13,10
    db 'Press R to retry; do not reset or remove power.',13,10,0

; ============================================================================
; DISK TABLES AND BUFFERS: DPH links to DPB and allocation bitmap
; DPH = translation, three scratch words, directory buffer, DPB, checksum
; vector, allocation vector. A zero checksum vector denotes fixed media here.
; ============================================================================

dph_a: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_b: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_c: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_d: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_e: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_f: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_g: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_h: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_i: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_j: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_k: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_l: dw 0,0,0,0,directory_buffer,dpb_ram,0,allocation_c
include 'implementation.inc'
column: db 0
selected: db 0
writing: db 0
track: dw 0
record: dw 0
dma: dw 0x80
cursor: dw 0xf000

resident_code_end:
; DEFS rejects negative padding: never silently grow into either system stack.
defs resident_code_limit-$,0
defs kernel_end-$,0
