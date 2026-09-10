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
include 'memory.inc'

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
    ; Exercise real SD reads, dirty cache writes, close and reset while the
    ; entire reclaimed 9800-C3FF region contains application-owned sentinels.
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jp nz,failed
    ld de,fcb
    ld c,22
    call 5
    cp 0xff
    jr z,failed
    ld de,tpa_limit-128
    ld c,26
    call 5
    ld de,fcb
    ld c,21
    call 5
    or a
    jr nz,failed
    ld de,fcb
    ld c,16
    call 5
    cp 0xff
    jr z,failed
    ld c,13
    call 5
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jr z,failed
    xor a
    ld (fcb+32),a
    ld de,tpa_limit-128
    ld c,26
    call 5
    ld de,fcb
    ld c,20
    call 5
    or a
    jr nz,failed
    ld de,fcb
    ld c,19
    call 5
    cp 0xff
    jr z,failed
    ld hl,0x9800
    ld bc,tpa_limit-0x9800
tpa_guard_loop:
    ld a,(hl)
    cp 0xa5
    jr nz,failed
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,tpa_guard_loop
    ld a,(tpa_limit-1)
    cp 0xa5
    jr nz,failed
    ld a,(tpa_limit-257)
    cp 0xa5
    jr nz,failed
    ld de,passed
    jr print

; ----------------------------------------------------------------------------
; Routine: failed
; Choose a failure message if a top-of-TPA sentinel was overwritten.
;
; Inputs:   A BDOS operation or reclaimed-TPA sentinel comparison failed.
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
fcb: db 1,'TPABOUNDTMP'
    defs 24,0
defs tpa_limit-$,0xa5
