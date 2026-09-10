; ============================================================================
; src/kernel.asm -- source tour and calling conventions
; ============================================================================
; Assembly root for the resident system. Read the include order bottom-up
; for addresses, then follow start -> cold_boot -> ccp_loop for execution.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Original SD-loaded CP/M-compatible kernel, CP/M 2.2 API.
include 'platform.inc'
include 'rom_exports.inc'
org kernel_load
jp start
db 'P2MCPM03'

; ============================================================================
; KERNEL ENTRY AND LINK ORDER
; ORG/DEFS boundaries are the memory layout. The include files below are
; assembled into one 14 KiB image, statically linked to ROM filesystem routines.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: start
; Enter the verified kernel loaded by the ROM.
;
; Inputs:   CPU executing at A000h with co-board mapping active.
; Outputs:  No return; jumps into BIOS cold_boot.
; Clobbers: SP; interrupts disabled; cold_boot then uses its documented registers.
; ----------------------------------------------------------------------------
start:
    di
    ld sp,system_stack_top
    ; Refuse older cartridges before invoking the new dashboard ROM services.
    ld hl,0xe012
    ld de,ui_signature
    ld b,24
kernel_rom_check:
    ld a,(de)
    cp (hl)
    jr nz,kernel_rom_mismatch
    inc hl
    inc de
    djnz kernel_rom_check
    jp cold_boot
kernel_rom_mismatch:
    ld hl,rom_mismatch_text
    ld de,0xf5a1
mismatch_print:
    ld a,(hl)
    or a
    jr z,mismatch_print_done
    ld (de),a
    inc hl
    inc de
    jr mismatch_print
mismatch_print_done:
    jp kernel_stop
ui_signature: db 'P2MUI03',0
include 'link_id.inc'
rom_mismatch_text: db 'BOOT STOPPED: update port-1 ROM to match this SD kernel.',0

; ----------------------------------------------------------------------------
; Routine: kernel_ready
; Optional sign-on entry into the command processor.
;
; Inputs:   BDOS vectors, disk state and console already initialized.
; Outputs:  No return; ccp_start prints the banner and enters the prompt.
; Clobbers: As ccp_start.
;
; Current warm_boot jumps directly to ccp_loop; this entry is retained
; without moving the following code or changing the kernel layout.
; ----------------------------------------------------------------------------
kernel_ready:
    jp ccp_start

; ----------------------------------------------------------------------------
; Routine: kernel_error
; Display a fatal BIOS initialization failure and halt.
;
; Inputs:   Mapped display/console available; error_banner is NUL-terminated.
; Outputs:  No return; enters kernel_stop.
; Clobbers: AF, C, HL.
; ----------------------------------------------------------------------------
kernel_error:
    ld hl,error_banner
    call 0xe00f
kernel_stop:
    halt
    jr kernel_stop
error_banner: db 'BIOS ERROR: invalid partition layout or SD read failure',0
; Bootstrap below the TPA limit is disposable after cold boot. All warm-boot
; paths, code and persistent state live at/above resident_base.
include 'cold_boot.asm'
cold_code_end:
defs resident_base-$,0
include 'bdos.asm'
include 'ccp.asm'
include 'bios.asm'
