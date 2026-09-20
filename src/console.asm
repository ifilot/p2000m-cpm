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
; Interrupt-driven keyboard and 80x24 terminal. No monitor calls after memory remapping.
; Escape followed by a letter emits its control code; Escape Escape emits ESC.

include 'keyboard.asm'

; ============================================================================
; KEY TABLES: eight columns per keyboard row
; Zero entries are ignored keys, not NUL input. Shift selects a parallel
; table: letters are lowercase normally and uppercase with either Shift key.
; The Escape prefix can generate NUL independently of the table.
; NL/UK physical layout audited against Maintenance 2 (REL 2.2) and the
; photographed keyboard; see docs/keyboard-reference.md. Main-row 0 is X5/Y5,
; minus is X5/Y7; keypad DEFINE/0 is X2/Y3 (not X5/Y5).
; CP/M ASCII approximations: sterling -> #, degree -> #, acute -> apostrophe.
; Keypad STOP retains its printable dot; CLEAR/00/LOCK are untranslated.
; ============================================================================

keys_normal:
    db 8,'6',11,'q','3','5','7','4'
    db 9,'h','z','s','d','g','j','f'
    db '.', ' ',0,'0','#',10,',',12
    db 0,'n','<','x','c','b','m','v'
    db 27,'y','a','w','e','t','u','r'
    db 0,'9','+','-',8,'0','1','-'
    db '9','o','8','7',13,'p','8','@'
    db '3','.','2','1',']','/','k','2'
    db '6','l','5','4',39,';','i',':'
keys_shift:
    db 8,'&',11,'Q','#','%',39,'$'
    db 9,'H','Z','S','D','G','J','F'
    db '.', ' ',0,'=','#',10,',',12
    db 0,'N','>','X','C','B','M','V'
    db 27,'Y','A','W','E','T','U','R'
    db 0,')','*','/',8,'=','!','_'
    db '9','O','8','7',13,'P','(',39
    db '3','.','2','1','[','?','K',34
    db '6','L','5','4',96,'+','I','*'

; ============================================================================
; PUBLIC CONSOLE OUTPUT: 80-column text terminal
; The wrapper preserves all main registers. Internal terminal helpers below
; share cursor/column state and are not ABI-preserving wrappers themselves.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: console_output
; Output one 7-bit character or feed the persistent terminal parser.
;
; Inputs:   C = character.
; Outputs:  Video/cursor updated; all input registers and flags restored.
; Clobbers: No general registers or flags; cursor, column and video may change.
;
; CR moves to column zero; LF advances a row; BS moves left; TAB emits
; spaces to the next stop; FF clears. ESC commands are in terminal.asm;
; CAN cancels a partial command. See docs/terminal.md for the output contract.
; ----------------------------------------------------------------------------
console_output:
    push af
    push bc
    push de
    push hl
    ld a,c
    and 0x7f
    call terminal_escape
    jr c,terminal_done
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
    call terminal_home
    call terminal_erase_screen
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
    ; CP/M ASCII punctuation differs from the native P2000 character ROM.
    ld hl,terminal_glyphs
    ld b,5
terminal_glyph_loop:
    cp (hl)
    inc hl
    jr z,terminal_glyph_found
    inc hl
    djnz terminal_glyph_loop
    jr terminal_native
terminal_glyph_found:
    ld a,(hl)
terminal_native:
    ld hl,(cursor)
    ld (hl),a
    push hl
    ld de,0x0800
    add hl,de
    ld a,(terminal_attribute)
    ld (hl),a
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

; ASCII -> native glyph. Translate only at rendering, never in CONIN.
terminal_glyphs:
    db '#',0x5f,'_',0x60,'[',0x0f,']',0x10,96,0x0a
