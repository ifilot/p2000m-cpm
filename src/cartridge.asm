; Original P2000M boot cartridge. z80asm syntax, 8 KiB physical image.
; ROM entry vectors after mapping: E000 boot, E003 read, E006 write, E009 init.
; Block I/O ABI: 32-bit little-endian LBA at 9E00, buffer address at 9E04.
; Returns A=0 on success, A=1 on failure. Clobbers AF/BC/DE/HL.
org 0x1000
db 0x5e,0,0,0,0
db 'SD CPM     '
jp entry
entry:
    di
    ld sp,0x9d00
    xor a
    out (0x10),a
    out (0x94),a
    ; The 8 KiB cartridge uses linear RAM mapping: stock 9000 -> 3000.
    ; Duplicate the post-OUT continuation at its *old numeric* PC in RAM.
    ; The OUT itself executes in stock RAM; the next fetch uses mapped RAM.
    ld hl,switch_code
    ld de,0x9000
    ld bc,switch_end-switch_code
    ldir
    ld hl,switch_code
    ld de,0xf000
    ld bc,switch_end-switch_code
    ldir
    jp 0x9000
switch_code:
    ld a,0x80
    out (0x20),a
    jp 0xe000
switch_end:
defs 0x2000-$,0xff
org 0xe000
    jp boot
    jp sd_read
    jp sd_write
    jp sd_init

lba: equ 0x9e00
buffer_ptr: equ 0x9e04
command_packet: equ 0x9e06
remaining: equ 0x9e0c

boot:
    di
    ld sp,0x9d00
    ld hl,0xf000
    ld de,0xf001
    ld bc,0x7ff
    ld (hl),' '
    ldir
    ld hl,0xf800
    ld de,0xf801
    ld bc,0x7ff
    ld (hl),0
    ldir
    call sd_init
    or a
    jp nz,boot_error
    ld hl,15
    ld (lba),hl
    ld hl,0
    ld (lba+2),hl
    ld hl,0x9600
    ld (buffer_ptr),hl
    call sd_read
    or a
    jp nz,boot_error
    ld hl,system_signature
    ld de,0x9600
    ld b,8
header_check:
    ld a,(de)
    cp (hl)
    jp nz,boot_error
    inc de
    inc hl
    djnz header_check
    ld hl,(0x9608)
    ld de,0x4000
    or a
    sbc hl,de
    jp nz,boot_error
    ld hl,16
    ld (lba),hl
    ld hl,0
    ld (lba+2),hl
    ld hl,0xa000
    ld (buffer_ptr),hl
    ld a,32
    ld (remaining),a
boot_read:
    call sd_read
    or a
    jp nz,boot_error
    ld hl,(lba)
    inc hl
    ld (lba),hl
    ld hl,(buffer_ptr)
    ld de,512
    add hl,de
    ld (buffer_ptr),hl
    ld a,(remaining)
    dec a
    ld (remaining),a
    jr nz,boot_read
    ld hl,signature
    ld de,0xa003
    ld b,8
boot_check:
    ld a,(de)
    cp (hl)
    jp nz,boot_error
    inc de
    inc hl
    djnz boot_check
    ld hl,0xa000
    ld bc,0x4000
    ld de,0
kernel_checksum:
    ld a,(hl)
    add a,e
    ld e,a
    jr nc,kernel_checksum_next
    inc d
kernel_checksum_next:
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,kernel_checksum
    ld hl,(0x960a)
    or a
    sbc hl,de
    jp nz,boot_error
    jp 0xa000
boot_error:
    ld hl,error_text
    ld de,0xf000
boot_print:
    ld a,(hl)
    or a
    jr z,boot_halt
    ld (de),a
    inc hl
    inc de
    jr boot_print
boot_halt:
    halt
    jr boot_halt
system_signature: db 'P2MSYS01'
signature: db 'P2MCPM01'
error_text: db 'SD BOOT ERROR: check card and system image',0

; Byte-wide bridge: allow at least 32 T states between CLKSTART and read.
spi_rx:
    ld a,0xff
spi_tx:
    out (0x40),a
    out (0x41),a
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    in a,(0x40)
    ret
sd_close:
    ld a,0xff
    out (0x42),a
    jp spi_tx
sd_fail:
    call sd_close
    ld a,1
    or a
    ret
sd_ok:
    call sd_close
    xor a
    ret

; HL points to six command bytes. CS remains asserted for data phase.
sd_command:
    call sd_close
    out (0x43),a
    ld b,6
cmd_send:
    ld a,(hl)
    call spi_tx
    inc hl
    djnz cmd_send
    ld b,16
cmd_reply:
    call spi_rx
    bit 7,a
    ret z
    djnz cmd_reply
    ret

sd_init:
    call sd_close
    ld b,10
power_clocks:
    call spi_rx
    djnz power_clocks
    ld hl,c0
    call sd_command
    cp 1
    jp nz,sd_fail
    ld hl,c8
    call sd_command
    cp 1
    jp nz,sd_fail
    call spi_rx
    or a
    jp nz,sd_fail
    call spi_rx
    or a
    jp nz,sd_fail
    call spi_rx
    cp 1
    jp nz,sd_fail
    call spi_rx
    cp 0xaa
    jp nz,sd_fail
    ld de,1000
init_wait:
    ld hl,c55
    call sd_command
    cp 2
    jp nc,sd_fail
    ld hl,c41
    call sd_command
    or a
    jr z,init_ocr
    cp 1
    jp nz,sd_fail
    dec de
    ld a,d
    or e
    jr nz,init_wait
    jp sd_fail
init_ocr:
    ld hl,c58
    call sd_command
    or a
    jp nz,sd_fail
    call spi_rx
    and 0xc0
    cp 0xc0
    jp nz,sd_fail
    call spi_rx
    call spi_rx
    call spi_rx
    jp sd_ok
c0: db 0x40,0,0,0,0,0x95
c8: db 0x48,0,0,1,0xaa,0x87
c55: db 0x77,0,0,0,0,1
c41: db 0x69,0x40,0,0,0,1
c58: db 0x7a,0,0,0,0,1

block_command:
    ld (command_packet),a
    ld hl,lba+3
    ld de,command_packet+1
    ld b,4
block_arg:
    ld a,(hl)
    ld (de),a
    dec hl
    inc de
    djnz block_arg
    ld a,1
    ld (de),a
    ld hl,command_packet
    jp sd_command

sd_read:
    ld a,0x51
    call block_command
    or a
    jp nz,sd_fail
    ld bc,0xffff
read_wait:
    call spi_rx
    cp 0xfe
    jr z,read_payload
    cp 0xff
    jp nz,sd_fail
    dec bc
    ld a,b
    or c
    jr nz,read_wait
    jp sd_fail
read_payload:
    ld hl,(buffer_ptr)
    ld bc,512
read_byte:
    call spi_rx
    ld (hl),a
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,read_byte
    call spi_rx
    call spi_rx
    jp sd_ok

sd_write:
    ld a,0x58
    call block_command
    or a
    jp nz,sd_fail
    ld a,0xfe
    call spi_tx
    ld hl,(buffer_ptr)
    ld bc,512
write_byte:
    ld a,(hl)
    call spi_tx
    inc hl
    dec bc
    ld a,b
    or c
    jr nz,write_byte
    call spi_rx
    call spi_rx
    call spi_rx
    and 0x1f
    cp 5
    jp nz,sd_fail
    ld bc,0xffff
write_wait:
    call spi_rx
    cp 0xff
    jp z,sd_ok
    dec bc
    ld a,b
    or c
    jr nz,write_wait
    jp sd_fail
