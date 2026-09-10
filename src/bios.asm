; CP/M 2.2 BIOS jump table at C000. Disk I/O exclusively uses port-2 SD/SRAM.
bios:
    jp cold_boot
    jp warm_boot
    jp console_status
    jp console_input
    jp console_output
    jp null_output
    jp null_output
    jp null_input
    jp disk_home
    jp disk_select
    jp disk_track
    jp disk_sector
    jp disk_dma
    jp disk_read
    jp disk_write
    jp list_status
    jp disk_translate

cold_boot:
    ld sp,0x9d00
    ld hl,0x9f00
    ld de,0x9f01
    ld bc,255
    ld (hl),0
    ldir
    xor a
    ld (3),a
    ld (4),a
    call disk_initialize
    or a
    jp nz,kernel_error
    ld hl,start_banner
    call ccp_puts
warm_boot:
    ld sp,0x9d00
    ld a,(4)
    and 15
    cp 3
    jr c,warm_drive
    xor a
warm_drive:
    ld (current_drive),a
    ld a,0xc3
    ld (0),a
    ld hl,bios+3
    ld (1),hl
    ld a,0xc3
    ld (5),a
    ld (0x9800),a
    ld hl,0x9800
    ld (6),hl
    ld hl,bdos_entry
    ld (0x9801),hl
    ld hl,0x80
    ld (user_dma),hl
    ld bc,0x80
    call disk_dma
    jp ccp_loop

disk_initialize:
    xor a
    ld (selected),a
    ld (track),a
    ld (track+1),a
    ld (record),a
    ld (record+1),a
    ld hl,0
    ld (0x9e00),hl
    ld (0x9e02),hl
    ld hl,sector_buffer
    ld (0x9e04),hl
    call 0xe003
    or a
    ret nz
    ld hl,(sector_buffer+510)
    ld de,0xaa55
    or a
    sbc hl,de
    jp nz,disk_error
    ; Validate the exact supported layout before permitting CP/M writes.
    ld a,(sector_buffer+466)
    cp 0x52
    jp nz,disk_error
    ld a,(sector_buffer+482)
    cp 0x52
    jp nz,disk_error
    ld hl,sector_buffer+470
    ld de,partition_a
    ld b,8
    call compare_bytes
    jp nz,disk_error
    ld hl,sector_buffer+486
    ld de,partition_b
    ld b,8
    call compare_bytes
    jp nz,disk_error
    ; Cold-boot format both SRAM banks. Warm boot deliberately skips this.
    ld d,0
ram_format_bank:
    ld a,d
    out (0x4b),a
    ld hl,0
ram_format_byte:
    ld a,h
    out (0x49),a
    ld a,l
    out (0x48),a
    ld a,0xe5
    out (0x4d),a
    inc hl
    ld a,h
    or l
    jr nz,ram_format_byte
    inc d
    ld a,d
    cp 2
    jr nz,ram_format_bank
    xor a
    ret
compare_bytes:
    ld a,(de)
    cp (hl)
    ret nz
    inc de
    inc hl
    djnz compare_bytes
    ret
partition_a: db 0,8,2,0,0,64,0,0
partition_b: db 0,72,2,0,0,64,0,0

disk_home:
    ld bc,0
disk_track:
    ld (track),bc
    ret
disk_sector:
    ld (record),bc
    ret
disk_dma:
    ld (dma),bc
    ret
disk_select:
    ld hl,0
    ld a,c
    cp 3
    ret nc
    ld (selected),a
    add a,a
    add a,a
    add a,a
    add a,a
    ld e,a
    ld d,0
    ld hl,dph_a
    add hl,de
    ret
disk_translate:
    ld h,b
    ld l,c
    ret
disk_error:
    ld a,1
    or a
    ret

disk_read:
    xor a
    jr disk_transfer
disk_write:
    ld a,1
disk_transfer:
    ld (writing),a
    ld a,(selected)
    cp 2
    jp z,ram_transfer
    jp nc,disk_error
    ld hl,(track)
    ld a,h
    cp 2
    jp nc,disk_error
    ld de,(record)
    ld a,d
    or a
    jp nz,disk_error
    ld a,e
    cp 128
    jp nc,disk_error
    ; Physical SD sector offset = track * 32 + record / 4.
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    srl e
    srl e
    add hl,de
    ld de,0x0800
    ld a,(selected)
    or a
    jr z,sd_base
    ld de,0x4800
sd_base:
    add hl,de
    ld (0x9e00),hl
    ld hl,0x0002
    ld (0x9e02),hl
    ld hl,sector_buffer
    ld (0x9e04),hl
    call 0xe003
    or a
    ret nz
    ld a,(record)
    and 3
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,sector_buffer
    add hl,de
    ld de,(dma)
    ld bc,128
    ld a,(writing)
    or a
    jr nz,sd_record_write
    ldir
    xor a
    ret
sd_record_write:
    ex de,hl
    ldir
    ; Write through: directory writes and warm boot need no cache flush.
    jp 0xe006

ram_transfer:
    ld hl,(track)
    ld a,h
    or a
    jp nz,disk_error
    ld a,l
    cp 32
    jp nc,disk_error
    ld de,(record)
    ld a,d
    or a
    jp nz,disk_error
    ld a,e
    cp 32
    jp nc,disk_error
    ld a,l
    and 16
    rrca
    rrca
    rrca
    rrca
    out (0x4b),a
    ; Within each bank: track low nibble * 4096 + record * 128.
    ld a,l
    and 15
    rlca
    rlca
    rlca
    rlca
    ld h,a
    ld l,0
    ld a,e
    srl a
    or h
    ld h,a
    ld a,e
    and 1
    rrca
    ld l,a
    ld de,(dma)
    ld b,128
    ld a,(writing)
    or a
    jr nz,ram_write_byte
ram_read_byte:
    call ram_address
    in a,(0x4d)
    ld (de),a
    inc de
    inc hl
    djnz ram_read_byte
    xor a
    ret
ram_write_byte:
    call ram_address
    ld a,(de)
    out (0x4d),a
    inc de
    inc hl
    djnz ram_write_byte
    xor a
    ret
ram_address:
    ld a,h
    out (0x49),a
    ld a,l
    out (0x48),a
    ret

include 'console.asm'

dph_a: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_b: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_b
dph_c: dw 0,0,0,0,directory_buffer,dpb_ram,0,allocation_c
dpb_sd:
    dw 128
    db 5,31,1
    dw 2047,511
    db 0xf0,0
    dw 0,0
dpb_ram:
    dw 32
    db 3,7,0
    dw 127,63
    db 0xc0,0
    dw 0,0
selected: db 0
writing: db 0
track: dw 0
record: dw 0
dma: dw 0x80
cursor: dw 0xf000

defs 0xd800-$,0
sector_buffer: defs 512,0
directory_buffer: defs 128,0
allocation_a: defs 256,0
allocation_b: defs 256,0
allocation_c: defs 16,0
