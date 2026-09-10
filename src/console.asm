; ============================================================================
; src/console.asm -- source tour and calling conventions
; ============================================================================
; Hardware-facing console routines. Public wrappers preserve caller pointers;
; internal scanner/terminal routines use scratch registers for state machines.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Polled keyboard and 80x24 terminal. No monitor calls after memory remapping.
; Escape followed by a letter emits its control code; Escape Escape emits ESC.

; ============================================================================
; PUBLIC CONSOLE INPUT: nonblocking status and blocking character read
; The pending-byte value and ready flag are separate so that NUL is a valid
; character. key_poll generates one event per press, waiting for release.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: console_status
; Report whether one keyboard character is waiting.
;
; Inputs:   No inputs.
; Outputs:  A=FFh ready, A=0 otherwise; queued character is not consumed.
; Clobbers: AF only; BC, DE, HL, IX, IY preserved.
;
; The wrapper saves working registers used by the matrix scanner.
; ----------------------------------------------------------------------------
console_status:
    push bc
    push de
    push hl
    call key_poll
    ld a,(key_ready)
    or a
    jr z,status_done
    ld a,0xff
status_done:
    pop hl
    pop de
    pop bc
    ret

; ----------------------------------------------------------------------------
; Routine: console_input
; Wait for and consume one queued keyboard character.
;
; Inputs:   No inputs; interrupts need not be enabled.
; Outputs:  A = character, including NUL; key_ready is cleared.
; Clobbers: AF only; BC, DE, HL, IX, IY preserved.
;
; Loops on console_status. It does not echo; BDOS chooses whether to echo.
; ----------------------------------------------------------------------------
console_input:
    call console_status
    or a
    jr z,console_input
    ld a,(key_pending)
    push af
    xor a
    ld (key_ready),a
    pop af
    ret

; ============================================================================
; KEYBOARD SCANNER: row/bit state, shift tables and Escape prefix
; Rows 0..8 contain keys; row 9 supplies Shift bits. Matrix inputs are
; active low. This code talks directly to the keyboard, never the old monitor.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: key_poll
; Scan for a fresh key press without waiting for a future event.
;
; Inputs:   key_ready/key_mask/key_row/key_escape retain state between calls.
; Outputs:  A new character may be queued; no register return contract.
; Clobbers: AF, BC, DE, HL; key state variables.
;
; C=row, D=row sample, E=one-bit mask, B=bits remaining, HL=key table.
; An Escape press arms the prefix; the next key maps to its control character.
; ----------------------------------------------------------------------------
key_poll:
    ld a,(key_ready)
    or a
    ret nz
    ld a,(key_mask)
    or a
    jr z,key_scan_start
    ld b,a
    ld a,(key_row)
    ld c,a
    in a,(c)
    and b
    ret z
    xor a
    ld (key_mask),a
key_scan_start:
    ld hl,keys_normal
    in a,(9)
    and 0x81
    cp 0x81
    jr z,key_scan_normal
    ld hl,keys_shift
key_scan_normal:
    ld c,0
key_scan_row:
    in a,(c)
    ld d,a
    ld e,1
    ld b,8
key_scan_bit:
    ld a,d
    and e
    jr nz,key_scan_next
    ld a,(hl)
    or a
    jr nz,key_event
key_scan_next:
    inc hl
    sla e
    djnz key_scan_bit
    inc c
    ld a,c
    cp 9
    jr nz,key_scan_row
    ret
key_event:
    ld d,a
    ld a,c
    ld (key_row),a
    ld a,e
    ld (key_mask),a
    ld a,(key_escape)
    or a
    jr nz,key_control
    ld a,d
    cp 27
    jr nz,key_store
    ld a,1
    ld (key_escape),a
    ret
key_control:
    xor a
    ld (key_escape),a
    ld a,d
    cp 27
    jr z,key_store
    and 0x1f

key_store:
    ld (key_pending),a
    ld a,1
    ld (key_ready),a
    ret

; ============================================================================
; KEY TABLES: eight columns per keyboard row
; Zero entries are ignored keys, not NUL input. Shift selects a parallel
; table; the Escape prefix can generate NUL independently of the table.
; ============================================================================

keys_normal:
    db 8,'6',11,'Q','3','5','7','4'
    db 9,'H','Z','S','D','G','J','F'
    db 13,' ',0,'0','#',10,',',12
    db 0,'N','<','X','C','B','M','V'
    db 27,'Y','A','W','E','T','U','R'
    db 0,'9','*','/',8,'0','1','-'
    db '9','O','8','7',13,'P','8','@'
    db '3','.','2','1',']','/','K','2'
    db '6','L','5','4','=',';','I',':'
keys_shift:
    db 8,'&',11,'q','#','%',39,'$'
    db 9,'h','z','s','d','g','j','f'
    db 13,' ',0,'0','#',10,'<',12
    db 0,'n','>','x','c','b','m','v'
    db 27,'y','a','w','e','t','u','r'
    db 0,')','*','/',8,'_','!','='
    db '9','o','8','7',13,'p','(','`'
    db '3','>','2','1','[','?','k',34
    db '6','l','5','4','+','+','i','*'

; ============================================================================
; PUBLIC CONSOLE OUTPUT: 80-column text terminal
; The wrapper preserves all main registers. Internal terminal helpers below
; share cursor/column state and are not ABI-preserving wrappers themselves.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: console_output
; Output one 7-bit character or handle a simple terminal control.
;
; Inputs:   C = character.
; Outputs:  Video/cursor updated; all input registers and flags restored.
; Clobbers: No general registers or flags; cursor, column and video may change.
;
; CR moves to column zero; LF advances a row; BS moves left; TAB emits
; spaces to the next stop; FF clears. Other controls are ignored.
; ----------------------------------------------------------------------------
console_output:
    push af
    push bc
    push de
    push hl
    ld a,c
    and 0x7f
    cp 12
    jr z,terminal_clear
    cp 13
    jr z,terminal_cr
    cp 10
    jr z,terminal_lf
    cp 8
    jr z,terminal_bs
    cp 9
    jr z,terminal_tab
    cp 32
    jr c,terminal_done
    call terminal_char
    jr terminal_done
terminal_tab:
    ld a,' '
    call terminal_char
    ld a,(column)
    and 7
    jr nz,terminal_tab
    jr terminal_done
terminal_cr:
    ld hl,(cursor)
    ld a,(column)
    ld e,a
    ld d,0
    or a
    sbc hl,de
    ld (cursor),hl
    xor a
    ld (column),a
    jr terminal_done
terminal_lf:
    ld hl,(cursor)
    ld de,80
    add hl,de
    call terminal_scroll
    jr terminal_done
terminal_bs:
    ld a,(column)
    or a
    jr z,terminal_done
    dec a
    ld (column),a
    ld hl,(cursor)
    dec hl
    ld (cursor),hl
    jr terminal_done
terminal_clear:
    ld hl,0xf000
    ld de,0xf001
    ld bc,1919
    ld (hl),' '
    ldir
    ld hl,0xf800
    ld de,0xf801
    ld bc,1919
    ld (hl),0
    ldir
    ld hl,0xf000
    ld (cursor),hl
    xor a
    ld (column),a
terminal_done:
    pop hl
    pop de
    pop bc
    pop af
    ret

; ----------------------------------------------------------------------------
; Routine: terminal_char
; Store a printable character and advance/wrap the cursor.
;
; Inputs:   A = printable character; cursor/column are consistent.
; Outputs:  cursor/column updated; scroll performed if needed.
; Clobbers: AF, BC, DE, HL.
;
; Falls into terminal_scroll with HL pointing to the proposed next cursor.
; ----------------------------------------------------------------------------
terminal_char:
    ; ASCII '#' is sterling in the P2000 character ROM; native hash is 5Fh.
    cp '#'
    jr nz,terminal_native
    ld a,0x5f
terminal_native:
    ld hl,(cursor)
    ld (hl),a
    push hl
    ld de,0x0800
    add hl,de
    ld (hl),0
    pop hl
    inc hl
    ld a,(column)
    inc a
    cp 80
    jr c,terminal_column
    xor a
terminal_column:
    ld (column),a

; ----------------------------------------------------------------------------
; Routine: terminal_scroll
; Commit a cursor position, scrolling the screen if it passed the end.
;
; Inputs:   HL = proposed character cursor; column already reflects its column.
; Outputs:  [cursor] set, possibly 80 bytes lower after scrolling one line.
; Clobbers: AF, BC, DE, HL.
;
; F780h is the first byte after 24*80 visible characters. LDIR moves
; rows 1..23 up, and the final row is filled with spaces.
; ----------------------------------------------------------------------------
terminal_scroll:
    push hl
    ld de,0xf780
    or a
    sbc hl,de
    pop hl
    jr c,terminal_position
    push hl
    ld hl,0xf050
    ld de,0xf000
    ld bc,1840
    ldir
    ld hl,0xf730
    ld de,0xf731
    ld bc,79
    ld (hl),' '
    ldir
    ; Move inverse headings with their text; clear attributes in the new row.
    ld hl,0xf850
    ld de,0xf800
    ld bc,1840
    ldir
    ld hl,0xff30
    ld de,0xff31
    ld bc,79
    ld (hl),0
    ldir
    pop hl
    ld de,80
    or a
    sbc hl,de
terminal_position:
    ld (cursor),hl
    ret

; ============================================================================
; UNCONNECTED DEVICES: standard BIOS list/punch/reader stubs
; The system has no configured printer, punch or reader. Their BIOS vectors
; still exist so the 17-entry table remains compatible with CP/M programs.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: null_output
; Discard a character addressed to LIST or PUNCH.
;
; Inputs:   C = character (ignored).
; Outputs:  Returns immediately.
; Clobbers: None; all registers and flags preserved.
; ----------------------------------------------------------------------------
null_output:
    ret

; ----------------------------------------------------------------------------
; Routine: null_input
; Return end-of-file from the unconnected reader.
;
; Inputs:   No inputs.
; Outputs:  A=1Ah (Ctrl-Z).
; Clobbers: A only; flags preserved.
; ----------------------------------------------------------------------------
null_input:
    ld a,0x1a
    ret

; ----------------------------------------------------------------------------
; Routine: list_status
; Report the discard-only list device as ready.
;
; Inputs:   No inputs.
; Outputs:  A=FFh.
; Clobbers: A only; flags preserved.
; ----------------------------------------------------------------------------
list_status:
    ld a,0xff
    ret
column: db 0
key_pending: db 0
key_ready: db 0
key_row: db 0
key_mask: db 0
key_escape: db 0
