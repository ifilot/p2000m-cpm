; ============================================================================
; tests/tpalimit.asm -- source tour and calling conventions
; ============================================================================
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Exactly fills the advertised TPA. The CCP's return stack must be outside it.
org 0x100

; ----------------------------------------------------------------------------
; Routine: tpa_test_start
; Check that a maximum-size COM file and its top bytes survive entry.
;
; Inputs:   Standard CP/M COM entry at 0100h; CALL 5 and page-zero FCBs are available.
; Outputs:  RET uses the CCP-supplied warm-boot return address.
; Clobbers: AF, BC, DE, HL.
;
; CALL 5 takes C=function and DE=argument, returns HL with A=L/B=H,
; and preserves C, DE, IX, IY. No program calls emulator host services.
; ----------------------------------------------------------------------------
tpa_test_start:
    ld a,(0x97ff)
    cp 0xa5
    jr nz,failed
    ld a,(0x96ff)
    cp 0xa5
    jr nz,failed
    ld de,passed
    jr print

; ----------------------------------------------------------------------------
; Routine: failed
; Choose a failure message if a top-of-TPA sentinel was overwritten.
;
; Inputs:   Comparison at entry failed for 97FFh or 96FFh.
; Outputs:  Falls to print and returns through the CCP-provided stack.
; Clobbers: DE, then print registers.
; ----------------------------------------------------------------------------
failed:
    ld de,error

; ----------------------------------------------------------------------------
; Routine: print
; Print the selected result using only standard BDOS.
;
; Inputs:   DE -> dollar-terminated result string.
; Outputs:  RET returns to CCP; no private stack is installed.
; Clobbers: AF, BC, HL; DE preserved by BDOS.
; ----------------------------------------------------------------------------
print:
    ld c,9
    call 5
    ret
passed: db 'TPA LIMIT PASS',13,10,'$'
error: db 'TPA LIMIT FAIL',13,10,'$'
defs 0x9800-$,0xa5
