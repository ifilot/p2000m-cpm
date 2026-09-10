; Polled keyboard and 80x24 terminal. No monitor calls after memory remapping.
; Escape followed by a letter emits its control code; Escape Escape emits ESC.
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
terminal_char:
    ld hl,(cursor)
    ld (hl),a
    inc hl
    ld a,(column)
    inc a
    cp 80
    jr c,terminal_column
    xor a
terminal_column:
    ld (column),a
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
    pop hl
    ld de,80
    or a
    sbc hl,de
terminal_position:
    ld (cursor),hl
    ret
null_output:
    ret
null_input:
    ld a,0x1a
    ret
list_status:
    ld a,0xff
    ret
column: db 0
key_pending: db 0
key_ready: db 0
key_row: db 0
key_mask: db 0
key_escape: db 0
