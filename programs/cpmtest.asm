; ============================================================================
; programs/cpmtest.asm -- source tour and calling conventions
; ============================================================================
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Original transient exerciser, uses only the public CP/M CALL 5 interface.
org 0x100

; ============================================================================
; TEST PROGRAM: destructive only to CPMTEST.DAT in user area zero
; The program creates/replaces its named test file, writes 600 patterned
; records per drive, then reads, seeks, checks size and deletes it.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: cpmtest_start
; Run the original CP/M file-I/O exerciser on A:, B: and C:.
;
; Inputs:   Standard CP/M COM entry at 0100h; CALL 5 and page-zero FCBs are available.
; Outputs:  JP 0 transfers to warm boot and restarts the CCP; no local return.
; Clobbers: AF, BC, DE, HL, SP; the program installs its own stack.
;
; CALL 5 takes C=function and DE=argument, returns HL with A=L/B=H,
; and preserves C, DE, IX, IY. No program calls emulator host services.
; ----------------------------------------------------------------------------
cpmtest_start:
    ld sp,0x8f00
    xor a
    ld (0x9000),a
    ld (drive),a
    ld de,banner
    ld c,9
    call 5

; ----------------------------------------------------------------------------
; Routine: next_drive
; Initialize the work FCB and run the per-drive file test sequence.
;
; Inputs:   drive=0/1/2; console/BDOS initialized.
; Outputs:  No return; loops to the next drive, or reports pass/failure and JP 0.
; Clobbers: AF, BC, DE, HL; FCB, buffer, counter/phase and CPMTEST.DAT on each drive.
;
; The absolute byte at 9000h is an emulator-test completion marker: 00h
; running, A5h passed, EEh failed. The visible messages make it usable standalone.
; ----------------------------------------------------------------------------
next_drive:
    ld a,(drive)
    add a,'A'
    ld e,a
    ld c,2
    call 5
    ld de,working
    ld c,9
    call 5
    ld hl,fcb
    ld de,fcb+1
    ld bc,35
    ld (hl),0
    ldir
    ld a,(drive)
    inc a
    ld (fcb),a
    ld hl,filename
    ld de,fcb+1
    ld bc,11
    ldir
    ld de,fcb
    ld c,19
    call 5
    ld a,1
    ld (phase),a
    ld de,fcb
    ld c,22
    call 5
    cp 0xff
    jp z,failed
    ld de,buffer
    ld c,26
    call 5
    ld hl,0
    ld (counter),hl
write_loop:
    ld a,2
    ld (phase),a
    call fill
    ld de,fcb
    ld c,21
    call 5
    or a
    jp nz,failed
    call advance
    jr nz,write_loop
    ld a,3
    ld (phase),a
    ld de,fcb
    ld c,16
    call 5
    cp 0xff
    jp z,failed
    xor a
    ld (fcb+12),a
    ld (fcb+14),a
    ld (fcb+32),a
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jp z,failed
    ld hl,0
    ld (counter),hl
read_loop:
    ld a,4
    ld (phase),a
    ld de,fcb
    ld c,20
    call 5
    or a
    jp nz,failed
    call verify
    call advance
    jr nz,read_loop
    ld a,5
    ld (phase),a
    ld de,fcb
    ld c,20
    call 5
    cp 1
    jp nz,failed
    ld a,6
    ld (phase),a
    ld de,fcb
    ld c,35
    call 5
    ld hl,(fcb+33)
    ld de,600
    or a
    sbc hl,de
    jp nz,failed
    ld a,(fcb+35)
    or a
    jp nz,failed
    ld hl,513
    ld (counter),hl
    ld (fcb+33),hl
    ld de,fcb
    ld c,33
    call 5
    or a
    jp nz,failed
    call verify
    ld a,7
    ld (phase),a
    ld de,fcb
    ld c,19
    call 5
    cp 0xff
    jp z,failed
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jp nz,failed
    ld a,(drive)
    inc a
    ld (drive),a
    cp 3
    jp nz,next_drive
    ld de,passed
    ld c,9
    call 5
    ld a,0xa5
    ld (0x9000),a
    jp 0

; ----------------------------------------------------------------------------
; Routine: advance
; Increment the test record counter and check the 600-record limit.
;
; Inputs:   counter = most recently processed record.
; Outputs:  counter incremented; Z=1 when it becomes 600, Z=0 otherwise.
; Clobbers: AF, DE, HL; counter.
;
; HL returns counter-600, not the counter itself; reload counter for the next use.
; ----------------------------------------------------------------------------
advance:
    ld hl,(counter)
    inc hl
    ld (counter),hl
    ld de,600
    or a
    sbc hl,de
    ret

; ----------------------------------------------------------------------------
; Routine: fill
; Generate a distinct record pattern for the current counter.
;
; Inputs:   counter = record index; buffer is page-aligned at 0800h.
; Outputs:  buffer[0..127] filled with low-address XOR counter-high XOR counter-low.
; Clobbers: AF, B, DE, HL; C preserved.
;
; HL walks the DMA buffer, DE holds the record index and B counts bytes.
; ----------------------------------------------------------------------------
fill:
    ld hl,buffer
    ld de,(counter)
    ld b,128
fill_byte:
    ld a,l
    xor d
    xor e
    ld (hl),a
    inc hl
    djnz fill_byte
    ret

; ----------------------------------------------------------------------------
; Routine: verify
; Check all bytes of a record against the generated pattern.
;
; Inputs:   counter = expected record index; buffer contains the record just read.
; Outputs:  Returns on exact match; jumps to failed at first mismatch.
; Clobbers: AF, B, DE, HL; C preserved.
; ----------------------------------------------------------------------------
verify:
    ld hl,buffer
    ld de,(counter)
    ld b,128
verify_byte:
    ld a,l
    xor d
    xor e
    cp (hl)
    jp nz,failed
    inc hl
    djnz verify_byte
    ret

; ----------------------------------------------------------------------------
; Routine: failed
; Report test phase/drive and signal failure.
;
; Inputs:   A = failure value at branch; phase and drive identify the operation.
; Outputs:  No return; marker 9000h=EEh, then JP 0.
; Clobbers: AF, BC, DE, HL; failure_value and completion marker.
; ----------------------------------------------------------------------------
failed:
    ld (failure_value),a
    ld de,failure
    ld c,9
    call 5
    ld a,(phase)
    add a,'0'
    ld e,a
    ld c,2
    call 5
    ld de,failure_drive
    ld c,9
    call 5
    ld a,(drive)
    add a,'A'
    ld e,a
    ld c,2
    call 5
    ld de,crlf
    ld c,9
    call 5
    ld a,0xee
    ld (0x9000),a
    jp 0

; ============================================================================
; TEST DATA: progress text, FCB, counters and aligned DMA buffer
; phase identifies create/write/close/read/EOF/size/delete in diagnostics.
; The DEFS before buffer is intentional: the test pattern depends on its low address.
; ============================================================================

banner: db 'CPMTEST: 600 records per drive, extents, random I/O, size, delete',13,10,'$'
working: db ': testing...',13,10,'$'
passed: db 'CPMTEST PASS',13,10,'$'
failure: db 'CPMTEST FAIL phase $'
failure_drive: db ' drive $'
crlf: db 13,10,'$'
filename: db 'CPMTEST DAT'
drive: db 0
phase: db 0
failure_value: db 0
counter: dw 0
fcb: defs 36,0
defs 0x800-$,0
buffer: defs 128,0
