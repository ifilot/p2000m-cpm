; ============================================================================
; programs/common/filetest.inc -- source tour and calling conventions
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
; TEST PROGRAM: destructive only to CPMTEST.DAT in the current user area
; The program creates/replaces its named test file, writes 600 patterned
; records per drive, then reads, seeks, checks size and deletes it.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: cpmtest_start
; Run the file-I/O exerciser on A: (CPMTEST) or L: (RAMTEST).
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
if test_ram_only
    ld a,11
endif
    ld (drive),a
    ld de,banner
    ld c,9
    call 5

; ----------------------------------------------------------------------------
; Routine: next_drive
; Initialize the work FCB and run the per-drive file test sequence.
;
; Inputs:   drive=0 (CPMTEST) or 11 (RAMTEST); console/BDOS initialized.
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
    ld hl,0
    ld (counter),hl
    ld (mismatch),hl
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
if test_ram_only
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jp nz,ram_exists
else
    ld de,fcb
    ld c,19
    call 5
endif
    ld a,1
    call phase_begin
    ld de,fcb
    ld c,22
    call 5
    cp 0xff
    jp z,failed
    call phase_ok
    ld de,buffer
    ld c,26
    call 5
    ld hl,0
    ld (counter),hl
    ld a,2
    call phase_begin
    call progress
write_loop:
    call check_abort
    call fill
    ld de,fcb
    ld c,21
    call 5
    or a
    jp nz,failed
    call advance
    jr nz,write_loop
    call phase_ok
    ld a,3
    call phase_begin
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
    call phase_ok
    ld hl,0
    ld (counter),hl
    ld a,4
    call phase_begin
    call progress
read_loop:
    call check_abort
    ld de,fcb
    ld c,20
    call 5
    or a
    jp nz,failed
    call verify
    call advance
    jr nz,read_loop
    call phase_ok
    ld a,5
    call phase_begin
    ld de,fcb
    ld c,20
    call 5
    cp 1
    jp nz,failed
    call phase_ok
    ld a,6
    call phase_begin
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
    call phase_ok
    ld a,7
    call phase_begin
    ld hl,513
    ld (counter),hl
    ld (fcb+33),hl
    ld de,fcb
    ld c,33
    call 5
    or a
    jp nz,failed
    call verify
    call phase_ok
    ld a,8
    call phase_begin
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
    call phase_ok
    ld a,(drive)
    add a,'A'
    ld e,a
    ld c,2
    call 5
    ld de,drive_pass
    call puts
    ld a,(drive)
    inc a
    ld (drive),a
if test_ram_only
    cp 12
else
    cp 1
endif
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
    push hl
    ld a,(progress_tick)
    dec a
    ld (progress_tick),a
    call z,progress
    pop hl
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
    jr nz,verify_failed
    inc hl
    djnz verify_byte
    ret
verify_failed:
    ld (expected_byte),a
    ld a,(hl)
    ld (actual_byte),a
    ld a,l
    ld (bad_offset),a
    ld a,1
    ld (mismatch),a
    jp failed

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
    call puts
    call phase_name
    call puts
    ld de,failure_drive
    ld c,9
    call 5
    ld a,(drive)
    add a,'A'
    ld e,a
    ld c,2
    call 5
    ld de,record_text
    call puts
    ld hl,(counter)
    call decimal
    ld de,code_text
    call puts
    ld a,(failure_value)
    call hex_byte
    ld a,(mismatch)
    or a
    jr z,failure_done
    ld de,offset_text
    call puts
    ld a,(bad_offset)
    call hex_byte
    ld de,expected_text
    call puts
    ld a,(expected_byte)
    call hex_byte
    ld de,actual_text
    call puts
    ld a,(actual_byte)
    call hex_byte
failure_done:
    ld de,crlf
    ld c,9
    call 5
    ld a,0xee
    ld (0x9000),a
    jp 0

; Console helpers use public BDOS only. Progress is updated every 30 completed
; records (5%); the initial zero count is shown before the first operation.
puts:
    ld c,9
    jp 5
phase_name:
    ld a,(phase)
    dec a
    add a,a
    ld l,a
    ld h,0
    ld de,phase_names
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ret
phase_begin:
    ld (phase),a
    ld de,indent
    call puts
    call phase_name
    call puts
    ld de,dots
    jp puts
phase_ok:
    ld de,ok_text
    jp puts
progress:
    push af
    push bc
    push de
    push hl
    ld a,30
    ld (progress_tick),a
    ld de,progress_start
    call puts
    call phase_name
    call puts
    ld de,bar_start
    call puts
    ld hl,(counter)
    ld de,30
    ld b,0
progress_divide:
    or a
    sbc hl,de
    jr c,progress_bar
    inc b
    jr progress_divide
progress_bar:
    ld a,b
    ld (bar_count),a
    ld b,20
progress_cell:
    push bc
    ld a,(bar_count)
    ld e,'.'
    or a
    jr z,progress_emit
    dec a
    ld (bar_count),a
    ld e,'#'
progress_emit:
    ld c,2
    call 5
    pop bc
    djnz progress_cell
    ld de,bar_end
    call puts
    ld hl,(counter)
    call decimal
    ld de,total_text
    call puts
    pop hl
    pop de
    pop bc
    pop af
    ret
; Print HL as three decimal digits (test record counts are 000..600).
decimal:
    ld de,100
    call decimal_digit
    ld de,10
    call decimal_digit
    ld a,l
    add a,'0'
    ld e,a
    ld c,2
    jp 5
decimal_digit:
    ld b,'0'-1
decimal_subtract:
    inc b
    or a
    sbc hl,de
    jr nc,decimal_subtract
    add hl,de
    push hl
    ld e,b
    ld c,2
    call 5
    pop hl
    ret
hex_byte:
    push af
    rrca
    rrca
    rrca
    rrca
    call hex_digit
    pop af
hex_digit:
    and 15
    add a,'0'
    cp '9'+1
    jr c,hex_emit
    add a,7
hex_emit:
    ld e,a
    ld c,2
    jp 5
; A cancellation is handled only between completed synchronous file operations.
; Close and retain the partial test file for inspection, then warm boot.
check_abort:
    ld c,6
    ld e,0xff
    call 5
    cp 3
    ret nz
    ld de,fcb
    ld c,16
    call 5
    ld de,abort_text
    call puts
    ld a,0xcc
    ld (0x9000),a
    jp 0

; ============================================================================
; TEST DATA: progress text, FCB, counters and aligned DMA buffer
; phase identifies create/write/close/read/EOF/size/delete in diagnostics.
; The DEFS before buffer is intentional: the test pattern depends on its low address.
; ============================================================================

if test_ram_only
banner: db 'RAMTEST: L: only, 600 records (75 KiB), both SRAM banks.',13,10
    db 'Preserves existing files. Escape then C aborts between records.',13,10,'$'
working: db ': RAMTEST.DAT - 600 records, 75 KiB',13,10,'$'
passed: db 'RAMTEST PASS',13,10,'$'
failure: db 13,10,'RAMTEST FAIL: $'
else
banner: db 'CPMTEST: A: only, 600 records (75 KiB).',13,10
    db 'Replaces CPMTEST.DAT. Escape then C aborts between records.',13,10,'$'
working: db ': CPMTEST.DAT - 600 records, 75 KiB',13,10,'$'
passed: db 'CPMTEST PASS',13,10,'$'
failure: db 13,10,'CPMTEST FAIL: $'
endif
failure_drive: db ' drive $'
crlf: db 13,10,'$'
phase_names: dw p_create,p_write,p_close,p_read,p_eof,p_size,p_random,p_delete
p_create: db 'Create file$'
p_write: db 'Write patterns$'
p_close: db 'Close and reopen$'
p_read: db 'Read and verify$'
p_eof: db 'Check EOF$'
p_size: db 'Check size: 600 records$'
p_random: db 'Random read: record 513$'
p_delete: db 'Delete and confirm absent$'
indent: db '  $'
dots: db ' ... $'
ok_text: db ' OK',13,10,'$'
drive_pass: db ': PASS',13,10,'$'
progress_start: db 13,'  $'
bar_start: db ' [$'
bar_end: db '] $'
total_text: db '/600$'
record_text: db ' record $'
code_text: db ' value 0x$'
offset_text: db 13,10,'  byte offset 0x$'
expected_text: db ' expected 0x$'
actual_text: db ' actual 0x$'
if test_ram_only
abort_text: db 13,10,'RAMTEST ABORTED: partial RAMTEST.DAT retained.',13,10,'$'
ram_exists:
    ld de,exists_text
    call puts
    ld a,0xee
    ld (0x9000),a
    jp 0
exists_text: db 'RAMTEST: L:RAMTEST.DAT already exists; no files changed.',13,10,'$'
else
abort_text: db 13,10,'CPMTEST ABORTED: partial CPMTEST.DAT retained.',13,10,'$'
endif
progress_tick: db 30
bar_count: db 0
mismatch: db 0
bad_offset: db 0
expected_byte: db 0
actual_byte: db 0
if test_ram_only
filename: db 'RAMTEST DAT'
else
filename: db 'CPMTEST DAT'
endif
drive: db 0
phase: db 0
failure_value: db 0
counter: dw 0
fcb: defs 36,0
defs 0x800-$,0
buffer: defs 128,0
