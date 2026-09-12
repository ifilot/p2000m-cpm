; ============================================================================
; programs/copy/copy.asm -- source tour and calling conventions
; ============================================================================
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; COPY source destination -- preserves an existing destination.
; Both arguments are parsed by the CCP into the standard default FCBs.
org 0x100

; ============================================================================
; COPY PROGRAM: copy argument prefixes before either OPEN changes an FCB
; Default FCBs overlap at 005Ch/006Ch. Preserve both 16-byte prefixes into
; independent 36-byte FCBs before opening the source or creating the destination.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: copy_start
; Copy between two FCB-named files without replacing the destination.
;
; Inputs:   Standard CP/M COM entry at 0100h; CALL 5 and page-zero FCBs are available.
; Outputs:  JP 0 transfers to warm boot and restarts the CCP; no local return.
; Clobbers: AF, BC, DE, HL, SP; the program installs its own stack.
;
; CALL 5 takes C=function and DE=argument, returns HL with A=L/B=H,
; and preserves C, DE, IX, IY. No program calls emulator host services.
; ----------------------------------------------------------------------------
copy_start:
    ld sp,0x8f00
    ld hl,0x5c
    ld de,source
    ld bc,16
    ldir
    ld hl,0x6c
    ld de,destination
    ld bc,16
    ldir
    ld a,(source+1)
    cp ' '
    jp z,usage
    ld a,(destination+1)
    cp ' '
    jp z,usage
    ld de,source
    ld c,15
    call 5
    cp 0xff
    jp z,error
    ld de,destination
    ld c,15
    call 5
    cp 0xff
    jp nz,exists
    ld de,destination
    ld c,22
    call 5
    cp 0xff
    jp z,error
    ld de,buffer
    ld c,26
    call 5

; ----------------------------------------------------------------------------
; Routine: copy_record
; Read one source record and write it to the destination.
;
; Inputs:   source/destination FCBs open; DMA points to buffer.
; Outputs:  No return; loops, then reaches done at EOF or error on failure.
; Clobbers: AF, BC, DE, HL; FCB positions, buffer and destination file.
; ----------------------------------------------------------------------------
copy_record:
    ld de,source
    ld c,20
    call 5
    cp 1
    jr z,done
    or a
    jp nz,error
    ld de,destination
    ld c,21
    call 5
    or a
    jp nz,error
    jr copy_record

; ----------------------------------------------------------------------------
; Routine: done
; Close the destination and report success.
;
; Inputs:   All source records copied; destination FCB valid.
; Outputs:  No return; message prints status and warm-boots.
; Clobbers: AF, BC, DE, HL.
; ----------------------------------------------------------------------------
done:
    ld de,destination
    ld c,16
    call 5
    cp 0xff
    jr z,error
    ld de,success
    jr message

; ----------------------------------------------------------------------------
; Routine: usage
; Select the usage message when an argument is empty.
;
; Inputs:   Entered by a conditional JP from program startup.
; Outputs:  No return; message then warm boot.
; Clobbers: DE, then message registers.
; ----------------------------------------------------------------------------
usage:
    ld de,usage_text
    jr message

; ----------------------------------------------------------------------------
; Routine: exists
; Refuse to overwrite a destination successfully opened earlier.
;
; Inputs:   Destination OPEN returned a valid directory slot.
; Outputs:  No return; report existing file and warm-boot.
; Clobbers: DE, then message registers.
; ----------------------------------------------------------------------------
exists:
    ld de,exists_text
    jr message

; ----------------------------------------------------------------------------
; Routine: error
; Report a failed source/create/read/write/close operation.
;
; Inputs:   Entered on non-success from a BDOS service.
; Outputs:  No return; report possible partial destination and warm-boot.
; Clobbers: DE, then message registers.
; ----------------------------------------------------------------------------
error:
    ld de,error_text

; ----------------------------------------------------------------------------
; Routine: message
; Print the selected dollar-terminated status and warm-boot.
;
; Inputs:   DE -> dollar-terminated message.
; Outputs:  No return: JP 0 after BDOS 9.
; Clobbers: AF, BC, HL; DE preserved by BDOS.
; ----------------------------------------------------------------------------
message:
    ld c,9
    call 5
    jp 0

; ============================================================================
; PROGRAM DATA: messages, independent FCBs and one DMA record
; source/destination each reserve all 36 FCB bytes. buffer holds exactly
; one 128-byte record; data is streamed rather than loading an entire file.
; ============================================================================

usage_text: db 'Usage: COPY A:SOURCE.EXT B:TARGET.EXT',13,10,'$'
exists_text: db 'Destination exists; use ERA first to replace it.',13,10,'$'
error_text: db 'Copy failed; destination may be incomplete.',13,10,'$'
success: db 'Copy complete.',13,10,'$'
source: defs 36,0
destination: defs 36,0
buffer: defs 128,0
