; ============================================================================
; src/bdos.asm -- source tour and calling conventions
; ============================================================================
; Operating-system API layer. The public entry saves the application state;
; private handlers use RAM argument fields and the filesystem helpers below.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Original CP/M 2.2-compatible BDOS. User entry is at resident_base.
; BDOS changes to a private stack; all disk traffic calls this project's BIOS.

; ============================================================================
; PUBLIC CALL 5 ENTRY: save the caller and dispatch on function number
; Applications call 0005h with C=function and DE=argument. The page-zero
; jump reaches this code directly. Most implementation handlers use IX=DE.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: bdos_entry
; Invoke a BDOS service on a private system stack.
;
; Inputs:   C = function 0..40; DE = argument (character, FCB pointer, buffer, etc.).
; Outputs:  HL = result; A=L and B=H; C, DE, IX, IY and caller SP restored.
; Clobbers: AF, B, HL; service-specific memory/media changes.
;
; Function 0 does not return: warm_boot discards this frame. Other calls
; use bdos_stack_top, independent of the transient program stack. Not reentrant.
; ----------------------------------------------------------------------------
bdos_entry:
    ld (caller_sp),sp
    ld sp,bdos_stack_top
    push bc
    push de
    push ix
    push iy
    ld (argument),de
    push de
    pop ix
    ld a,c
    ld (function),a
    call bdos_dispatch
    ; Metadata-only operations commit before returning. Sequential/random
    ; writes remain buffered until CLOSE, eviction, reset or warm boot.
    ld a,(function)
    cp 19
    jr z,bdos_commit
    cp 22
    jr z,bdos_commit
    cp 23
    jr z,bdos_commit
    cp 30
    jr nz,bdos_return
bdos_commit:
    push hl
    call cache_flush
    pop hl
    or a
    jr z,bdos_return
    ld hl,0xff
bdos_return:
    pop iy
    pop ix
    pop de
    pop bc
    ld a,l
    ld b,h
    ld sp,(caller_sp)
    ret

; ----------------------------------------------------------------------------
; Routine: bdos_dispatch
; Tail-dispatch through the function-address table.
;
; Inputs:   A = function; IX = saved DE; argument/function RAM fields already set.
; Outputs:  Selected handler returns directly to bdos_entry; unknown functions give HL=0.
; Clobbers: AF, BC, DE, HL; IX may change in a handler.
;
; A is doubled to index little-endian words. JP (HL) deliberately avoids
; an extra return frame; handlers return with the caller already on the stack.
; ----------------------------------------------------------------------------
bdos_dispatch:
    cp 41
    jp nc,return_zero
    add a,a
    ld l,a
    ld h,0
    ld de,bdos_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    jp (hl)

; ============================================================================
; FUNCTION TABLE: one word for each CP/M function 0..40
; Function numbers are positional. The unconnected reader returns EOF,
; list/punch calls are no-ops, and reserved functions 38/39 return zero.
; ============================================================================

bdos_table:
    dw warm_boot,bdos_input,bdos_output,bdos_reader,return_zero,return_zero
    dw bdos_direct,bdos_iobyte,bdos_setio,bdos_string,bdos_line,bdos_status
    dw bdos_version,bdos_reset,bdos_select,fs_open,fs_close,fs_first,fs_next
    dw fs_delete,fs_read,fs_write,fs_make,fs_rename,bdos_login,bdos_current
    dw bdos_dma,bdos_alloc,bdos_protect,bdos_ro,fs_attributes,bdos_dpb,bdos_user
    dw fs_random_read,fs_random_write,fs_size,fs_setrandom,bdos_reset_drives
    dw return_zero,return_zero,fs_random_write

; ============================================================================
; RESULT ADAPTERS: normalize scalar BDOS results to HL
; These helpers are tail-jump exits. The public entry later copies L to A
; and H to B; individual handler flags are not part of the public BDOS API.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: return_zero
; Return the scalar BDOS result zero.
;
; Inputs:   No inputs.
; Outputs:  HL=0; A and flags unchanged.
; Clobbers: HL only.
; ----------------------------------------------------------------------------
return_zero:
    ld hl,0
    ret

; ----------------------------------------------------------------------------
; Routine: return_ff
; Return the scalar failure/not-found value FFh.
;
; Inputs:   No inputs.
; Outputs:  HL=00FFh, A=FFh; flags unchanged.
; Clobbers: A, HL.
;
; Falls into return_a rather than adding another CALL/RET.
; ----------------------------------------------------------------------------
return_ff:
    ld a,0xff

; ----------------------------------------------------------------------------
; Routine: return_a
; Widen an 8-bit result to the BDOS return word.
;
; Inputs:   A = scalar result.
; Outputs:  HL=zero-extended A; A and flags unchanged.
; Clobbers: HL only.
; ----------------------------------------------------------------------------
return_a:
    ld l,a
    ld h,0
    ret

; ============================================================================
; CONSOLE SERVICES: characters, direct I/O and dollar-terminated strings
; These are internal BDOS handlers. argument contains the original DE;
; handler register use is broader than the protected public CALL 5 interface.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: bdos_input
; BDOS 1: wait for a console character and echo it.
;
; Inputs:   No register arguments.
; Outputs:  HL = received character (0..255).
; Clobbers: AF, C, HL.
;
; The BIOS read does not echo; this handler explicitly calls CONOUT.
; ----------------------------------------------------------------------------
bdos_input:
    call console_input
    push af
    ld c,a
    call console_output
    pop af
    jp return_a

; ----------------------------------------------------------------------------
; Routine: bdos_output
; BDOS 2: output the argument character.
;
; Inputs:   Low byte of [argument] = original E character.
; Outputs:  HL=0.
; Clobbers: A, C, HL; terminal state changes.
; ----------------------------------------------------------------------------
bdos_output:
    ld a,(argument)
    ld c,a
    call console_output
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: bdos_reader
; BDOS 3: return EOF for the unconnected reader.
;
; Inputs:   No inputs.
; Outputs:  HL=001Ah.
; Clobbers: A, HL.
; ----------------------------------------------------------------------------
bdos_reader:
    ld a,0x1a
    jp return_a

; ----------------------------------------------------------------------------
; Routine: bdos_direct
; BDOS 6: nonblocking console input or direct output.
;
; Inputs:   Low byte of [argument]=FFh to poll/read, otherwise the output character.
; Outputs:  HL=character or zero if no input; output returns zero.
; Clobbers: AF, C, HL.
;
; A NUL character and no character both return zero, as this BDOS call
; defines; the BIOS still distinguishes NUL readiness internally.
; ----------------------------------------------------------------------------
bdos_direct:
    ld a,(argument)
    cp 0xff
    jp nz,bdos_output
    call console_status
    or a
    jp z,return_zero
    call console_input
    jp return_a

; ----------------------------------------------------------------------------
; Routine: bdos_iobyte
; BDOS 7: read the compatibility I/O byte.
;
; Inputs:   No inputs.
; Outputs:  HL = byte at 0003h.
; Clobbers: A, HL.
; ----------------------------------------------------------------------------
bdos_iobyte:
    ld a,(3)
    jp return_a

; ----------------------------------------------------------------------------
; Routine: bdos_setio
; BDOS 8: store the compatibility I/O byte.
;
; Inputs:   Low byte of [argument] = new IOBYTE.
; Outputs:  HL=0; [0003h] updated.
; Clobbers: A, HL.
;
; This implementation stores the value but does not reroute physical devices.
; ----------------------------------------------------------------------------
bdos_setio:
    ld a,(argument)
    ld (3),a
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: bdos_string
; BDOS 9: print bytes until a dollar terminator.
;
; Inputs:   [argument] -> dollar-terminated string in CPU memory.
; Outputs:  HL=0 after output; the dollar itself is not printed.
; Clobbers: AF, C, HL.
;
; HL walks the string; CONOUT preserves it while consuming C.
; ----------------------------------------------------------------------------
bdos_string:
    ld hl,(argument)
bdos_string_loop:
    ld a,(hl)
    cp '$'
    jp z,return_zero
    ld c,a
    call console_output
    inc hl
    jr bdos_string_loop

; ----------------------------------------------------------------------------
; Routine: bdos_status
; BDOS 11: return console readiness as 0 or 1.
;
; Inputs:   No inputs.
; Outputs:  HL=1 if ready, otherwise zero.
; Clobbers: AF, HL.
; ----------------------------------------------------------------------------
bdos_status:
    call console_status
    and 1
    jp return_a

; ============================================================================
; BUFFERED INPUT: line editing and echo (BDOS 10)
; The caller buffer is [maximum,count,characters...]. IX remains its base
; while HL/DE address the append position. Counts exclude the terminating CR.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: bdos_line
; Read an editable line without exceeding the caller capacity.
;
; Inputs:   IX -> buffer; (IX+0)=maximum characters, data begins at IX+2.
; Outputs:  HL=0; (IX+1)=length and following bytes contain the line.
; Clobbers: AF, BC, DE, HL; caller buffer; IX preserved.
;
; CR/LF finishes. Backspace/DEL erase, Ctrl-U/Ctrl-X kill the line, and
; Ctrl-C on an empty line enters warm_boot instead of returning.
; ----------------------------------------------------------------------------
bdos_line:
    ld (ix+1),0
line_key:
    call console_input
    cp 13
    jr z,line_done
    cp 10
    jr z,line_done
    cp 3
    jr nz,line_not_abort
    ld a,(ix+1)
    or a
    jp z,warm_boot
    jr line_key
line_not_abort:
    cp 8
    jr z,line_back
    cp 127
    jr z,line_back
    cp 21
    jr z,line_kill
    cp 24
    jr z,line_kill
    cp 32
    jr c,line_key
    ld c,a
    ld a,(ix+1)
    cp (ix+0)
    jr nc,line_key
    ld e,a
    ld d,0
    push ix
    pop hl
    add hl,de
    inc hl
    inc hl
    ld (hl),c
    inc (ix+1)
    call console_output
    jr line_key
line_back:
    ld a,(ix+1)
    or a
    jr z,line_key
    call line_erase
    jr line_key
line_kill:
    ld a,(ix+1)
    or a
    jr z,line_key
    call line_erase
    jr line_kill

; ----------------------------------------------------------------------------
; Routine: line_erase
; Remove one buffered character and erase its displayed cell.
;
; Inputs:   IX -> input buffer; (IX+1)>0 (caller checks this).
; Outputs:  (IX+1) decremented; terminal receives BS, space, BS.
; Clobbers: AF, C; all pointer registers preserved.
; ----------------------------------------------------------------------------
line_erase:
    dec (ix+1)
    ld c,8
    call console_output
    ld c,' '
    call console_output
    ld c,8
    jp console_output
line_done:
    ld c,13
    call console_output
    ld c,10
    call console_output
    jp return_zero

; ============================================================================
; SYSTEM/DISK STATE SERVICES: drive, DMA, protection and user area
; current_drive is the BDOS selection; page-zero byte 4 separately remembers
; the CCP drive so programs such as STAT can select drives without changing it.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: bdos_version
; BDOS 12: report the CP/M 2.2 interface version.
;
; Inputs:   No inputs.
; Outputs:  HL=0022h (single-user CP/M version 2.2).
; Clobbers: HL only.
; ----------------------------------------------------------------------------
bdos_version:
    ld hl,0x22
    ret

; ----------------------------------------------------------------------------
; Routine: bdos_reset
; BDOS 13: reset logical disk state and default DMA.
;
; Inputs:   No inputs.
; Outputs:  HL=0; drive A selected, protection/login masks cleared, DMA=0080h.
; Clobbers: AF, HL; current_drive, read_only, logged, page-zero drive, user_dma.
;
; It does not format SRAM; formatting belongs exclusively to cold_boot.
; ----------------------------------------------------------------------------
bdos_reset:
    call cache_flush
    or a
    jp nz,return_ff
    call cache_invalidate
    xor a
    ld (current_drive),a
    ld (read_only),a
    ld (read_only+1),a
    ld (logged),a
    ld (logged+1),a
    ld (4),a
    ld hl,0x80
    ld (user_dma),hl
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: bdos_select
; BDOS 14: choose the logical default drive.
;
; Inputs:   Low byte of [argument] = drive 0..11.
; Outputs:  HL=0 on valid selection, 00FFh otherwise.
; Clobbers: AF, HL; current_drive on success.
; ----------------------------------------------------------------------------
bdos_select:
    ld a,(argument)
    cp drive_count
    jp nc,return_ff
    push af
    call cache_flush
    or a
    jr z,bdos_select_ready
    pop af
    jp return_ff
bdos_select_ready:
    pop af
    ld (current_drive),a
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: bdos_login
; BDOS 24: return the logged-in drive bit vector.
;
; Inputs:   No inputs.
; Outputs:  HL = logged bits (bit 0 A:, bit 1 B:, bit 2 C:).
; Clobbers: A, HL.
; ----------------------------------------------------------------------------
bdos_login:
    ld hl,(logged)
    ret

; ----------------------------------------------------------------------------
; Routine: bdos_current
; BDOS 25: return the current logical drive.
;
; Inputs:   No inputs.
; Outputs:  HL = current_drive (0..11).
; Clobbers: A, HL.
; ----------------------------------------------------------------------------
bdos_current:
    ld a,(current_drive)
    jp return_a

; ----------------------------------------------------------------------------
; Routine: bdos_dma
; BDOS 26: set the application record-buffer address.
;
; Inputs:   [argument] = original DE, address of 128-byte DMA buffer.
; Outputs:  HL=0; user_dma updated.
; Clobbers: HL only; user_dma.
;
; The filesystem temporarily uses separate directory buffers for metadata;
; it restores the application DMA for data-record I/O.
; ----------------------------------------------------------------------------
bdos_dma:
    ld hl,(argument)
    ld (user_dma),hl
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: bdos_alloc
; BDOS 27: rebuild and return the current allocation bitmap.
;
; Inputs:   current_drive selects the volume.
; Outputs:  HL -> allocation bitmap, or 00FFh on failure.
; Clobbers: AF, BC, DE, HL; filesystem scratch, allocation map and directory cache.
; ----------------------------------------------------------------------------
bdos_alloc:
    call fs_current
    jp nz,return_ff
    call fs_rebuild
    jp nz,return_ff
    ld hl,(alloc_ptr)
    ret

; ----------------------------------------------------------------------------
; Routine: bdos_protect
; BDOS 28: mark the current drive logically read-only.
;
; Inputs:   current_drive = drive to protect.
; Outputs:  HL=0; corresponding read_only bit set.
; Clobbers: AF, B, HL.
; ----------------------------------------------------------------------------
bdos_protect:
    ld a,(current_drive)
    call drive_mask
    ld de,(read_only)
    ld a,l
    or e
    ld l,a
    ld a,h
    or d
    ld h,a
    ld (read_only),hl
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: bdos_ro
; BDOS 29: return the logical read-only drive vector.
;
; Inputs:   No inputs.
; Outputs:  HL = read_only bits.
; Clobbers: A, HL.
;
; This software mask is distinct from physical SD write protection, whose
; errors are reported by the card/BIOS when a write is attempted.
; ----------------------------------------------------------------------------
bdos_ro:
    ld hl,(read_only)
    ret

; ----------------------------------------------------------------------------
; Routine: bdos_dpb
; BDOS 31: return the disk parameter block for the selected drive.
;
; Inputs:   current_drive selects the volume.
; Outputs:  HL -> dpb_sd or dpb_ram; 00FFh on invalid selection.
; Clobbers: AF, BC, DE, HL; filesystem drive/geometry state.
; ----------------------------------------------------------------------------
bdos_dpb:
    call fs_current
    jp nz,return_ff
    ld hl,dpb_sd
    ld a,(fs_drive)
    cp ram_drive
    ret nz
    ld hl,dpb_ram
    ret

; ----------------------------------------------------------------------------
; Routine: bdos_user
; BDOS 32: set or query the CP/M user area.
;
; Inputs:   Low byte of [argument]=FFh to query; otherwise low four bits give user.
; Outputs:  HL = resulting user number (0..15).
; Clobbers: AF, HL; user_number when setting.
; ----------------------------------------------------------------------------
bdos_user:
    ld a,(argument)
    cp 0xff
    jr z,user_get
    and 15
    ld (user_number),a
user_get:
    ld a,(user_number)
    jp return_a

; ----------------------------------------------------------------------------
; Routine: bdos_reset_drives
; BDOS 37: reset selected login/protection bits.
;
; Inputs:   [argument] = 16-bit drive mask; selective reset covers A:..L:.
; Outputs:  HL=0; selected logged and read_only bits cleared.
; Clobbers: AF, B, HL.
; ----------------------------------------------------------------------------
bdos_reset_drives:
    call cache_flush
    or a
    jp nz,return_ff
    call cache_invalidate
    ld a,(argument)
    cpl
    ld b,a
    ld a,(read_only)
    and b
    ld (read_only),a
    ld a,(logged)
    and b
    ld (logged),a
    ld a,(argument+1)
    cpl
    ld b,a
    ld a,(read_only+1)
    and b
    ld (read_only+1),a
    ld a,(logged+1)
    and b
    ld (logged+1),a
    jp return_zero

; BDOS private state, kept above its resident-code region and outside the TPA.

; ============================================================================
; BDOS/FILESYSTEM WORKSPACE: absolute addresses outside the TPA
; These EQU symbols reserve no bytes in the assembled stream. cold_boot
; clears this workspace. Multi-byte words are little-endian; see docs/source-guide.md.
; ============================================================================

include 'bdos_workspace.inc'
include 'filesystem_exports.inc'
