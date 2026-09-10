; Original CP/M 2.2-compatible BDOS. User entry trampoline is at 9800.
; BDOS changes to a private stack; all disk traffic calls this project's BIOS.
bdos_entry:
    ld (caller_sp),sp
    ld sp,0x9b80
    push bc
    push de
    push ix
    push iy
    ld (argument),de
    push de
    pop ix
    ld a,c
    ld (function),a
    call bdos_dispatch
    pop iy
    pop ix
    pop de
    pop bc
    ld a,l
    ld b,h
    ld sp,(caller_sp)
    ret
bdos_dispatch:
    cp 41
    jp nc,return_zero
    add a,a
    ld l,a
    ld h,0
    ld de,bdos_table
    add hl,de
    ld e,(hl)
    inc hl
    ld d,(hl)
    ex de,hl
    jp (hl)
bdos_table:
    dw warm_boot,bdos_input,bdos_output,bdos_reader,return_zero,return_zero
    dw bdos_direct,bdos_iobyte,bdos_setio,bdos_string,bdos_line,bdos_status
    dw bdos_version,bdos_reset,bdos_select,fs_open,fs_close,fs_first,fs_next
    dw fs_delete,fs_read,fs_write,fs_make,fs_rename,bdos_login,bdos_current
    dw bdos_dma,bdos_alloc,bdos_protect,bdos_ro,fs_attributes,bdos_dpb,bdos_user
    dw fs_random_read,fs_random_write,fs_size,fs_setrandom,bdos_reset_drives
    dw return_zero,return_zero,fs_random_write
return_zero:
    ld hl,0
    ret
return_ff:
    ld a,0xff
return_a:
    ld l,a
    ld h,0
    ret
bdos_input:
    call console_input
    push af
    ld c,a
    call console_output
    pop af
    jp return_a
bdos_output:
    ld a,(argument)
    ld c,a
    call console_output
    jp return_zero
bdos_reader:
    ld a,0x1a
    jp return_a
bdos_direct:
    ld a,(argument)
    cp 0xff
    jp nz,bdos_output
    call console_status
    or a
    jp z,return_zero
    call console_input
    jp return_a
bdos_iobyte:
    ld a,(3)
    jp return_a
bdos_setio:
    ld a,(argument)
    ld (3),a
    jp return_zero
bdos_string:
    ld hl,(argument)
bdos_string_loop:
    ld a,(hl)
    cp '$'
    jp z,return_zero
    ld c,a
    call console_output
    inc hl
    jr bdos_string_loop
bdos_status:
    call console_status
    and 1
    jp return_a
bdos_line:
    ld (ix+1),0
line_key:
    call console_input
    cp 13
    jr z,line_done
    cp 10
    jr z,line_done
    cp 3
    jr nz,line_not_abort
    ld a,(ix+1)
    or a
    jp z,warm_boot
    jr line_key
line_not_abort:
    cp 8
    jr z,line_back
    cp 127
    jr z,line_back
    cp 21
    jr z,line_kill
    cp 24
    jr z,line_kill
    cp 32
    jr c,line_key
    ld c,a
    ld a,(ix+1)
    cp (ix+0)
    jr nc,line_key
    ld e,a
    ld d,0
    push ix
    pop hl
    add hl,de
    inc hl
    inc hl
    ld (hl),c
    inc (ix+1)
    call console_output
    jr line_key
line_back:
    ld a,(ix+1)
    or a
    jr z,line_key
    call line_erase
    jr line_key
line_kill:
    ld a,(ix+1)
    or a
    jr z,line_key
    call line_erase
    jr line_kill
line_erase:
    dec (ix+1)
    ld c,8
    call console_output
    ld c,' '
    call console_output
    ld c,8
    jp console_output
line_done:
    ld c,13
    call console_output
    ld c,10
    call console_output
    jp return_zero
bdos_version:
    ld hl,0x22
    ret
bdos_reset:
    xor a
    ld (current_drive),a
    ld (read_only),a
    ld (logged),a
    ld (4),a
    ld hl,0x80
    ld (user_dma),hl
    jp return_zero
bdos_select:
    ld a,(argument)
    cp 3
    jp nc,return_ff
    ld (current_drive),a
    jp return_zero
bdos_login:
    ld a,(logged)
    jp return_a
bdos_current:
    ld a,(current_drive)
    jp return_a
bdos_dma:
    ld hl,(argument)
    ld (user_dma),hl
    jp return_zero
bdos_alloc:
    call fs_current
    jp nz,return_ff
    call fs_rebuild
    jp nz,return_ff
    ld hl,(alloc_ptr)
    ret
bdos_protect:
    ld a,(current_drive)
    call drive_mask
    ld b,a
    ld a,(read_only)
    or b
    ld (read_only),a
    jp return_zero
bdos_ro:
    ld a,(read_only)
    jp return_a
bdos_dpb:
    call fs_current
    jp nz,return_ff
    ld hl,dpb_sd
    ld a,(fs_drive)
    cp 2
    ret nz
    ld hl,dpb_ram
    ret
bdos_user:
    ld a,(argument)
    cp 0xff
    jr z,user_get
    and 15
    ld (user_number),a
user_get:
    ld a,(user_number)
    jp return_a
bdos_reset_drives:
    ld a,(argument)
    cpl
    ld b,a
    ld a,(read_only)
    and b
    ld (read_only),a
    ld a,(logged)
    and b
    ld (logged),a
    jp return_zero

; BDOS private state, kept below its resident-code region and outside the TPA.
caller_sp: equ 0x9f00
argument: equ 0x9f02
function: equ 0x9f04
current_drive: equ 0x9f05
user_number: equ 0x9f06
user_dma: equ 0x9f07
read_only: equ 0x9f09
logged: equ 0x9f0a
fs_drive: equ 0x9f0b
alloc_ptr: equ 0x9f0c
block_shift: equ 0x9f0e
extent_mask: equ 0x9f0f
max_entries: equ 0x9f10
max_blocks: equ 0x9f12
scan_index: equ 0x9f14
cache_record: equ 0x9f16
entry_ptr: equ 0x9f18
wanted_extent: equ 0x9f1a
rw_record: equ 0x9f1c
rw_block: equ 0x9f1e
rw_offset: equ 0x9f20
found_index: equ 0x9f22
saved_index: equ 0x9f24
search_index: equ 0x9f26
search_drive: equ 0x9f28
search_user: equ 0x9f29
search_active: equ 0x9f2a
any_match: equ 0x9f2b
size_max: equ 0x9f2c
size_overflow: equ 0x9f2e
zero_record: equ 0x9f30
zero_count: equ 0x9f32
io_mode: equ 0x9f33
entry_copy: equ 0xdd80
search_fcb: equ 0xdda0
file_buffer: equ 0xdd00
include 'filesystem.asm'
