; ============================================================================
; src/ccp.asm -- source tour and calling conventions
; ============================================================================
; Interactive shell and COM loader. Related built-ins, loader paths and parser
; helpers are kept together; local branch labels belong to their enclosing routine.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Original command processor: DIR, TYPE, ERA, REN, USER and transient COM files.

; ============================================================================
; COMMAND PROCESSOR: prompt, line input and dispatch
; The CCP is resident above the TPA. Built-ins use BDOS just like transient
; programs; only display helpers call the BIOS console directly.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: ccp_start
; Print the optional sign-on banner and enter the prompt loop.
;
; Inputs:   System vectors and BDOS state initialized.
; Outputs:  No return; falls into ccp_loop.
; Clobbers: AF, BC, DE, HL, SP; console state.
; ----------------------------------------------------------------------------
ccp_start:
    ld hl,start_banner
    call ccp_puts

; ----------------------------------------------------------------------------
; Routine: ccp_loop
; Read, uppercase and dispatch a command line.
;
; Inputs:   current_drive selects the prompt; keyboard/console and BDOS available.
; Outputs:  No return; commands loop back here or launch a transient program.
; Clobbers: AF, BC, DE, HL, IY, SP; command buffers and default DMA.
;
; SP is reset so errors and program warm boots cannot leak command frames.
; The original argument remainder is retained for the standard command tail.
; ----------------------------------------------------------------------------
ccp_loop:
    ld sp,0x9d00
    call cache_flush
    or a
    jp nz,warm_boot
    ld de,0x80
    ld c,26
    call bdos_entry
    ld a,(current_drive)
    add a,'A'
    ld c,a
    call console_output
    ld c,'>'
    call console_output
    ld de,command_line
    ld c,10
    call bdos_entry
    ld a,(command_line+1)
    or a
    jr z,ccp_loop
    ld b,a
    ld hl,command_line+2
ccp_upper:
    ld a,(hl)
    cp 'a'
    jr c,ccp_upper_next
    cp 'z'+1
    jr nc,ccp_upper_next
    sub 32
    ld (hl),a
ccp_upper_next:
    inc hl
    djnz ccp_upper
    ld (hl),0
    ld hl,command_line+2
    ld de,command_fcb
    call parse_fcb
    jp c,ccp_error
    ld (argument_text),hl
    ld a,(command_fcb+1)
    cp ' '
    jr nz,ccp_dispatch
    ld a,(command_fcb)
    or a
    jp z,ccp_loop
    dec a
    ld (4),a
    ld e,a
    ld c,14
    call bdos_entry
    jp ccp_loop

; ----------------------------------------------------------------------------
; Routine: ccp_dispatch
; Match an eight-character command name or load a COM file.
;
; Inputs:   command_fcb contains the first token; argument_text points at its delimiter.
; Outputs:  No return; jumps to a built-in handler or ccp_load.
; Clobbers: AF, BC, DE, HL.
;
; commands stores eight-byte padded names followed by two-byte code pointers.
; ----------------------------------------------------------------------------
ccp_dispatch:
    ld hl,commands
ccp_compare_command:
    ld a,(hl)
    or a
    jp z,ccp_load
    push hl
    ld de,command_fcb+1
    ld b,8
ccp_compare_byte:
    ld a,(de)
    cp (hl)
    jr nz,ccp_compare_skip
    inc de
    inc hl
    djnz ccp_compare_byte
    ld e,(hl)
    inc hl
    ld d,(hl)
    pop hl
    ex de,hl
    jp (hl)
ccp_compare_skip:
    pop hl
    ld de,10
    add hl,de
    jr ccp_compare_command

; ============================================================================
; BUILT-IN TABLE: eight-byte names followed by handler addresses
; The trailing zero ends the table. Unknown names are treated as transient
; program filenames, with COM supplied when no extension was typed.
; ============================================================================

commands:
    db 'DIR     '
    dw ccp_dir
    db 'TYPE    '
    dw ccp_type
    db 'ERA     '
    dw ccp_erase
    db 'REN     '
    dw ccp_rename
    db 'USER    '
    dw ccp_user
    db 'SAVE    '
    dw ccp_save
    db 0

; ============================================================================
; FILE COMMANDS: argument parsing, DIR, ERA, TYPE and REN
; The common FCB parser fills command_fcb, which is separate from the
; application default FCBs at 005Ch and 006Ch.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: ccp_argument
; Parse the command remainder into the work FCB.
;
; Inputs:   argument_text -> remainder of command line.
; Outputs:  HL -> delimiter after token; command_fcb filled; CY=1 on bad syntax.
; Clobbers: AF, BC, DE, HL, IY.
;
; Calls parse_fcb; it returns the delimiter so REN can recognize its equals sign.
; ----------------------------------------------------------------------------
ccp_argument:
    ld hl,(argument_text)
    ld de,command_fcb
    call parse_fcb
    ret

; ----------------------------------------------------------------------------
; Routine: ccp_dir
; List matching filenames using BDOS Search First/Next.
;
; Inputs:   argument_text -> command remainder; BDOS/DMA initialized.
; Outputs:  No return; enters ccp_loop or ccp_error.
; Clobbers: AF, BC, DE, HL, IY; command buffers and service-specific media.
;
; An omitted name becomes eleven question marks. The returned slot
; selects one of the four 32-byte entries copied to the default DMA buffer.
; ----------------------------------------------------------------------------
ccp_dir:
    call ccp_argument
    jp c,ccp_error
    ld a,(command_fcb+1)
    cp ' '
    jr nz,ccp_dir_search
    ld hl,command_fcb+1
    ld b,11
ccp_dir_all:
    ld (hl),'?'
    inc hl
    djnz ccp_dir_all
ccp_dir_search:
    xor a
    ld (dir_column),a
    ld de,command_fcb
    ld c,17
ccp_dir_next:
    call bdos_entry
    cp 0xff
    jr z,ccp_dir_done
    add a,a
    add a,a
    add a,a
    add a,a
    add a,a
    ld l,a
    ld h,0
    ld de,0x80
    add hl,de
    inc hl
    ld b,8
ccp_dir_name:
    ld a,(hl)
    and 0x7f
    ld c,a
    call console_output
    inc hl
    djnz ccp_dir_name
    ld c,'.'
    call console_output
    ld b,3
ccp_dir_ext:
    ld a,(hl)
    and 0x7f
    ld c,a
    call console_output
    inc hl
    djnz ccp_dir_ext
    ld a,(dir_column)
    inc a
    cp 4
    jr z,ccp_dir_wrap
    ld (dir_column),a
    ld c,' '
    call console_output
    ld c,':'
    call console_output
    ld c,' '
    call console_output
    jr ccp_dir_continue
ccp_dir_wrap:
    xor a
    ld (dir_column),a
    call ccp_newline
ccp_dir_continue:
    ld c,18
    ld de,command_fcb
    jr ccp_dir_next
ccp_dir_done:
    ld a,(dir_column)
    or a
    call nz,ccp_newline
    jp ccp_loop

; ----------------------------------------------------------------------------
; Routine: ccp_erase
; Delete matching file entries with BDOS 19.
;
; Inputs:   argument_text -> command remainder; BDOS/DMA initialized.
; Outputs:  No return; enters ccp_loop or ccp_error.
; Clobbers: AF, BC, DE, HL, IY; command buffers and service-specific media.
;
; The FCB may contain wildcards. A missing/protected/error result goes
; to the shared command error path; no direct disk operations occur here.
; ----------------------------------------------------------------------------
ccp_erase:
    call ccp_argument
    jp c,ccp_error
    ld de,command_fcb
    ld c,19
    call bdos_entry
    inc a
    jp z,ccp_error
    jp ccp_loop

; ----------------------------------------------------------------------------
; Routine: ccp_type
; Display sequential text records until EOF or Ctrl-Z.
;
; Inputs:   argument_text -> command remainder; BDOS/DMA initialized.
; Outputs:  No return; enters ccp_loop or ccp_error.
; Clobbers: AF, BC, DE, HL, IY; command buffers and service-specific media.
;
; HL walks the 0080h DMA record; B counts its 128 bytes. Ctrl-Z is
; the CP/M text terminator even when more padded bytes remain in the record.
; ----------------------------------------------------------------------------
ccp_type:
    call ccp_argument
    jp c,ccp_error
    ld de,command_fcb
    ld c,15
    call bdos_entry
    inc a
    jp z,ccp_error
ccp_type_record:
    ld de,command_fcb
    ld c,20
    call bdos_entry
    or a
    jp nz,ccp_loop
    ld hl,0x80
    ld b,128
ccp_type_char:
    ld a,(hl)
    cp 0x1a
    jp z,ccp_loop
    ld c,a
    call console_output
    inc hl
    djnz ccp_type_char
    jr ccp_type_record

; ----------------------------------------------------------------------------
; Routine: ccp_rename
; Parse REN new=old and invoke BDOS 23.
;
; Inputs:   argument_text -> command remainder; BDOS/DMA initialized.
; Outputs:  No return; enters ccp_loop or ccp_error.
; Clobbers: AF, BC, DE, HL, IY; command buffers and service-specific media.
;
; The new 16-byte filename prefix is saved before parsing the old name.
; Both names must specify the same drive; the new prefix goes at FCB+16.
; ----------------------------------------------------------------------------
ccp_rename:
    call ccp_argument
    jp c,ccp_error
    call skip_spaces
    ld a,(hl)
    cp '='
    jp nz,ccp_error
    inc hl
    push hl
    ld hl,command_fcb
    ld de,rename_target
    ld bc,16
    ldir
    pop hl
    ld de,command_fcb
    call parse_fcb
    jp c,ccp_error
    ld a,(rename_target)
    ld b,a
    ld a,(command_fcb)
    cp b
    jp nz,ccp_error
    ld hl,rename_target
    ld de,command_fcb+16
    ld bc,16
    ldir
    ld de,command_fcb
    ld c,23
    call bdos_entry
    inc a
    jp z,ccp_error
    jp ccp_loop

; ============================================================================
; STATE/MEMORY COMMANDS: USER namespace and SAVE memory pages
; USER accepts 0..15. SAVE counts 256-byte pages starting at 0100h and
; writes them as pairs of 128-byte CP/M records without executing that memory.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: ccp_user
; Parse a user number and select it through BDOS 32.
;
; Inputs:   argument_text -> decimal user 0..15.
; Outputs:  No return; prompt on success or common error on invalid syntax.
; Clobbers: AF, BC, DE, HL.
; ----------------------------------------------------------------------------
ccp_user:
    ld hl,(argument_text)
    call skip_spaces
    ld a,(hl)
    sub '0'
    cp 10
    jp nc,ccp_error
    ld e,a
    inc hl
    ld a,(hl)
    or a
    jr z,ccp_user_set
    ld a,e
    cp 1
    jp nz,ccp_error
    ld a,(hl)
    sub '0'
    cp 6
    jp nc,ccp_error
    add a,10
    ld e,a
    inc hl
    ld a,(hl)
    or a
    jp nz,ccp_error
ccp_user_set:
    ld c,32
    call bdos_entry
    jp ccp_loop

; ----------------------------------------------------------------------------
; Routine: ccp_save
; Save N pages of TPA memory to a newly created file.
;
; Inputs:   argument_text -> decimal page count, space, filename.
; Outputs:  No return; file written then prompt, or ccp_error.
; Clobbers: AF, BC, DE, HL, IY; command FCB, DMA and medium.
;
; DE accumulates decimal pages with a limit of 151. save_records is twice
; that count, while load_address walks CPU memory in 128-byte increments.
; ----------------------------------------------------------------------------
ccp_save:
    ld hl,(argument_text)
    call skip_spaces
    ld de,0
save_number:
    ld a,(hl)
    cp ' '
    jr z,save_filename
    sub '0'
    cp 10
    jp nc,ccp_error
    ld c,a
    push hl
    ld h,d
    ld l,e
    add hl,hl
    add hl,hl
    add hl,de
    add hl,hl
    ld e,c
    ld d,0
    add hl,de
    ld a,h
    or a
    jp nz,ccp_error
    ld a,l
    cp 152
    jp nc,ccp_error
    ex de,hl
    pop hl
    inc hl
    jr save_number
save_filename:
    ex de,hl
    add hl,hl
    ld (save_records),hl
    ex de,hl
    ld de,command_fcb
    call parse_fcb
    jp c,ccp_error
    ld de,command_fcb
    ld c,22
    call bdos_entry
    cp 0xff
    jp z,ccp_error
    ld hl,0x100
    ld (load_address),hl
save_record:
    ld hl,(save_records)
    ld a,h
    or l
    jr z,save_close
    dec hl
    ld (save_records),hl
    ld de,(load_address)
    ld c,26
    call bdos_entry
    ld de,command_fcb
    ld c,21
    call bdos_entry
    or a
    jp nz,ccp_error
    ld hl,(load_address)
    ld de,128
    add hl,de
    ld (load_address),hl
    jr save_record
save_close:
    ld de,command_fcb
    ld c,16
    call bdos_entry
    cp 0xff
    jp z,ccp_error
    jp ccp_loop

; ============================================================================
; TRANSIENT LOADER: FCB open, bounded COM load, page-zero arguments
; The reported TPA is 0100h..97FFh. A final read at the limit uses a scratch
; buffer to distinguish an exactly full COM file from an oversized one.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: ccp_load
; Open a transient COM file and load its sequential records.
;
; Inputs:   command_fcb contains drive/name; argument_text still points to arguments.
; Outputs:  No return; ccp_execute on EOF, ccp_error on open/read/size failure.
; Clobbers: AF, BC, DE, HL; TPA, load_address, DMA and work FCB.
;
; No extension means COM. At address 9800h data goes to file_buffer
; instead of system memory; receiving another record then rejects the program.
; ----------------------------------------------------------------------------
ccp_load:
    ld a,(command_fcb+9)
    cp ' '
    jr nz,ccp_load_open
    ld hl,com_extension
    ld de,command_fcb+9
    ld bc,3
    ldir
ccp_load_open:
    ld de,command_fcb
    ld c,15
    call bdos_entry
    inc a
    jp z,ccp_error
    ld hl,0x100
    ld (load_address),hl
ccp_load_record:
    ld de,(load_address)
    ld a,d
    cp 0x98
    jr c,ccp_load_dma
    ld de,file_buffer
ccp_load_dma:
    ld c,26
    call bdos_entry
    ld de,command_fcb
    ld c,20
    call bdos_entry
    or a
    jr nz,ccp_execute
    ld hl,(load_address)
    ld a,h
    cp 0x98
    jp nc,ccp_error
    ld de,128
    add hl,de
    ld (load_address),hl
    jr ccp_load_record

; ----------------------------------------------------------------------------
; Routine: ccp_execute
; Install default FCBs/command tail and enter the loaded program.
;
; Inputs:   A=last read status (must be EOF=1); loaded TPA and argument_text valid.
; Outputs:  No return to this routine: JP 0100h; RET in the program reaches warm_boot.
; Clobbers: AF, BC, DE, HL, IY, SP; page-zero FCBs/tail and default DMA.
;
; Only 16 bytes are cleared for the second default FCB: it overlaps the
; first FCB allocation area. The return stack at 9A00h stays outside the TPA.
; ----------------------------------------------------------------------------
ccp_execute:
    cp 1
    jp nz,ccp_error
    ld hl,(argument_text)
    ld de,0x5c
    call parse_fcb
    ld de,0x6c
    call parse_fcb_short
    ld hl,(argument_text)
    ld de,0x81
    ld b,0
ccp_tail:
    ld a,(hl)
    or a
    jr z,ccp_tail_done
    ld (de),a
    inc hl
    inc de
    inc b
    jr ccp_tail
ccp_tail_done:
    ld a,b
    ld (0x80),a
    ld a,13
    ld (de),a
    ld de,0x80
    ld c,26
    call bdos_entry
    ld sp,0x9a00
    ld hl,warm_boot
    push hl
    ld a,(current_drive)
    jp 0x100

; ----------------------------------------------------------------------------
; Routine: ccp_error
; Print the common command/file/I/O failure message.
;
; Inputs:   Entered by JP from any command failure path.
; Outputs:  No return; enters ccp_loop, which resets SP.
; Clobbers: AF, C, HL, then prompt-loop working registers.
; ----------------------------------------------------------------------------
ccp_error:
    ld hl,error_message
    call ccp_puts
    jp ccp_loop

; ============================================================================
; SHARED TEXT/PARSER HELPERS: strings, whitespace and CP/M FCB syntax
; Public subroutine headers below describe callable entry points. The
; parse_* branch labels inside the parser are local control-flow continuations.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: ccp_puts
; Print a NUL-terminated string through the BIOS console.
;
; Inputs:   HL -> string.
; Outputs:  HL points at the terminating zero; Z=1, A=0.
; Clobbers: AF, C, HL; B, DE, IX, IY preserved.
; ----------------------------------------------------------------------------
ccp_puts:
    ld a,(hl)
    or a
    ret z
    ld c,a
    call console_output
    inc hl
    jr ccp_puts

; ----------------------------------------------------------------------------
; Routine: ccp_newline
; Output CR followed by LF.
;
; Inputs:   No inputs.
; Outputs:  C=10; cursor moves to the next line start.
; Clobbers: C only; flags and other registers preserved.
; ----------------------------------------------------------------------------
ccp_newline:
    ld c,13
    call console_output
    ld c,10
    jp console_output

; ----------------------------------------------------------------------------
; Routine: skip_spaces
; Advance a text pointer past ASCII spaces.
;
; Inputs:   HL -> text.
; Outputs:  HL -> first non-space; A = that character; Z=0 on return.
; Clobbers: AF, HL.
;
; Only spaces are skipped, not tabs or other controls.
; ----------------------------------------------------------------------------
skip_spaces:
    ld a,(hl)
    cp ' '
    ret nz
    inc hl
    jr skip_spaces
; Parse an 8.3 token at HL into FCB DE, returning HL at its delimiter.

; ----------------------------------------------------------------------------
; Routine: parse_fcb
; Parse an optional drive and 8.3 token into a full FCB.
;
; Inputs:   HL -> command text; DE -> writable 36-byte FCB.
; Outputs:  HL -> delimiter; IY -> FCB; CY=0 success, CY=1 on rejected syntax.
; Clobbers: AF, BC, DE, HL, IY; all 36 FCB bytes.
;
; Initial zeroing clears extents, allocation and random fields; the
; name/type are space-padded. A star fills the rest of its field with question marks.
; ----------------------------------------------------------------------------
parse_fcb:
    ld b,36
    jr parse_clear

; ----------------------------------------------------------------------------
; Routine: parse_fcb_short
; Parse the second default FCB without clearing past its 16-byte prefix.
;
; Inputs:   HL -> next token; DE -> 16-byte destination prefix.
; Outputs:  As parse_fcb, but clears only the prefix.
; Clobbers: AF, BC, DE, HL, IY; destination prefix.
;
; Shares parse_clear. This avoids overwriting the command tail/DMA area
; when the second default FCB starts at 006Ch.
; ----------------------------------------------------------------------------
parse_fcb_short:
    ld b,16
parse_clear:
    push de
    xor a
parse_clear_byte:
    ld (de),a
    inc de
    djnz parse_clear_byte
    pop de
    push de
    pop iy
    push hl
    inc de
    ld b,11
    ld a,' '
parse_spaces:
    ld (de),a
    inc de
    djnz parse_spaces
    pop hl
    call skip_spaces
    ld a,(hl)
    or a
    ret z
    inc hl
    ld a,(hl)
    dec hl
    cp ':'
    jr nz,parse_name
    ld a,(hl)
    sub 'A'-1
    cp drive_count+1
    jr nc,parse_bad
    or a
    jr z,parse_bad
    ld (iy+0),a
    inc hl
    inc hl
parse_name:
    push iy
    pop de
    inc de
    ld b,8
parse_character:
    ld a,(hl)
    or a
    ret z
    cp ' '
    ret z
    cp '='
    ret z
    cp '.'
    jr z,parse_extension
    cp '*'
    jr z,parse_star
    ld c,a
    ld a,b
    or a
    jr z,parse_bad
    ld a,c
    ld (de),a
    inc de
    dec b
    inc hl
    jr parse_character
parse_star:
    ld a,b
    or a
    jr z,parse_star_done
    ld a,'?'
    ld (de),a
    inc de
    djnz parse_star+0
parse_star_done:
    inc hl
    jr parse_character
parse_extension:
    push iy
    pop de
    push hl
    ld hl,9
    add hl,de
    ex de,hl
    pop hl
    ld b,3
    inc hl
    jr parse_character
parse_bad:
    scf
    ret

; ============================================================================
; RESIDENT CCP DATA: messages, command buffer and private FCB
; All of these bytes are outside the advertised application TPA. The
; command buffer reserves a count byte and room for the terminating NUL.
; ============================================================================

start_banner: equ implementation_text
error_message: db 'Error: command, file or disk operation failed',13,10,0
com_extension: db 'COM'
command_line: db 126,0
    defs 128,0
command_fcb: defs 36,0
rename_target: defs 16,0
argument_text: dw 0
load_address: dw 0

save_records: dw 0
dir_column: db 0
