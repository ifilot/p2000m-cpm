; ============================================================================
; programs/hello/hello.asm -- source tour and calling conventions
; ============================================================================
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
org 0x100

; ----------------------------------------------------------------------------
; Routine: hello_start
; Print a greeting through BDOS 9, then RET to the CCP.
;
; Inputs:   Standard CP/M COM entry at 0100h; CALL 5 and page-zero FCBs are available.
; Outputs:  RET uses the CCP-supplied warm-boot return address.
; Clobbers: AF, BC, DE, HL.
;
; CALL 5 takes C=function and DE=argument, returns HL with A=L/B=H,
; and preserves C, DE, IX, IY. No program calls emulator host services.
; ----------------------------------------------------------------------------
hello_start:
    ld de,message
    ld c,9
    call 5
    ret
message: db 'Hello from an original Z80 CP/M program on SD!',13,10,'$'
