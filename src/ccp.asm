; Original command processor: DIR, TYPE, ERA, REN, USER and transient COM files.
ccp_start:
    ld hl,start_banner
    call ccp_puts
ccp_loop:
    ld sp,0x9d00
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
ccp_argument:
    ld hl,(argument_text)
    ld de,command_fcb
    call parse_fcb
    ret
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
    ld de,command_fcb
    ld c,17
ccp_dir_next:
    call bdos_entry
    cp 0xff
    jp z,ccp_loop
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
    call ccp_newline
    ld c,18
    ld de,command_fcb
    jr ccp_dir_next
ccp_erase:
    call ccp_argument
    jp c,ccp_error
    ld de,command_fcb
    ld c,19
    call bdos_entry
    inc a
    jp z,ccp_error
    jp ccp_loop
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
ccp_error:
    ld hl,error_message
    call ccp_puts
    jp ccp_loop
ccp_puts:
    ld a,(hl)
    or a
    ret z
    ld c,a
    call console_output
    inc hl
    jr ccp_puts
ccp_newline:
    ld c,13
    call console_output
    ld c,10
    jp console_output
skip_spaces:
    ld a,(hl)
    cp ' '
    ret nz
    inc hl
    jr skip_spaces
; Parse an 8.3 token at HL into FCB DE, returning HL at its delimiter.
parse_fcb:
    ld b,36
    jr parse_clear
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
    cp 4
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
start_banner: db 'P2000M SD CP/M 2.2 - A: B: SD, C: 128 KiB RAM',13,10,0
error_message: db 'Error: command, file or disk operation failed',13,10,0
com_extension: db 'COM'
command_line: db 126,0
    defs 128,0
command_fcb: defs 36,0
rename_target: defs 16,0
argument_text: dw 0
load_address: dw 0

save_records: dw 0
