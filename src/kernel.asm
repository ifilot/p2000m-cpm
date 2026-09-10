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
org 0xa000
jp start
db 'P2MCPM01'

; ============================================================================
; KERNEL ENTRY AND LINK ORDER
; ORG/DEFS boundaries are the memory layout. The include files below are
; assembled into one 16 KiB image; no dynamic linker or emulator trap is involved.
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
    ld sp,0x9d00
    jp cold_boot

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
    call ccp_puts
kernel_stop:
    halt
    jr kernel_stop
error_banner: db 'BIOS ERROR: invalid partition layout or SD read failure',0
include 'ccp.asm'
defs 0xa800-$,0
include 'bdos.asm'
defs 0xc000-$,0
include 'bios.asm'
defs 0xe000-$,0
