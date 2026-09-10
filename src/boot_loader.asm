; Disposable RAM loader copied from stock ROM 3000 to co-board RAM 7000.
; ----------------------------------------------------------------------------
; Routine: boot
; Load the fixed 14 KiB system image from the SD alignment gap.
;
; Inputs:   Co-board map active; no caller register values are required.
; Outputs:  No return: JP A000h on verified load, or boot_error on failure.
; Clobbers: AF, BC, DE, HL, SP; RAM 9600h header, DBC0h scratch, A000h-D7FFh kernel.
;
; LBA 15 describes the image. LBAs 16..43 carry it; HL is the destination
; and remaining counts sectors. The checksum adds all bytes modulo 65536.
; ----------------------------------------------------------------------------
boot:
    di
    ld sp,0x9d00
    ld a,1
    ld (boot_active),a
    ld a,3
    ld (boot_load_budget),a
    ld hl,msg_mapped
    ld de,0xf1f1
    call boot_message
    ld hl,msg_ready_status
    ld de,0xf221
    call boot_message
boot_load_start:
    ld hl,msg_starting_status
    ld de,0xf3b1
    call boot_message
    ld hl,msg_init_activity
    call boot_activity
    ld hl,msg_sd
    ld de,0xf381
    call boot_message
    ld a,1
    ld (boot_attempt),a
boot_sd_retry:
    ld a,(boot_attempt)
    add a,'0'
    ld (0xf381+msg_attempt-msg_sd),a
    call sd_init
    or a
    jr z,boot_sd_ready
    ld a,(boot_attempt)
    cp 8
    jp z,boot_error
    inc a
    ld (boot_attempt),a
    call boot_recovery
    call sd_retry_pause
    jr boot_sd_retry
boot_sd_ready:
    ld hl,msg_ready_status
    ld a,(boot_attempt)
    cp 1
    jr z,boot_sd_status
    ld hl,msg_recovered_status
boot_sd_status:
    ld de,0xf3b1
    call boot_message
    call boot_cid
    ld hl,msg_header
    call boot_activity
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
    jp nz,header_error
    inc de
    inc hl
    djnz header_check
    ld hl,(0x9608)
    ld de,kernel_bytes
    or a
    sbc hl,de
    jp nz,header_error
    ld hl,16
    push hl
    call boot_ok
    ld hl,msg_loading_status
    ld de,0xf271
    call boot_message
    ld hl,msg_load
    call boot_activity
    pop hl
    ld (lba),hl
    ld hl,0
    ld (lba+2),hl
    ld hl,kernel_load
    ld (buffer_ptr),hl
    ld a,kernel_sectors
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
    call boot_progress
    ld a,(remaining)
    or a
    jr nz,boot_read
    call boot_ok
    ld hl,msg_check
    call boot_activity
    ld hl,signature
    ld de,kernel_load+3
    ld b,8
boot_check:
    ld a,(de)
    cp (hl)
    jp nz,signature_error
    inc de
    inc hl
    djnz boot_check
    ld hl,0xa000
    ld bc,kernel_bytes
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
    jp nz,checksum_error
    call boot_ok
    ld hl,msg_enter
    call boot_activity
    ld hl,msg_verified
    ld de,0xf241
    call boot_message
    ld hl,msg_ready_status
    ld de,0xf271
    call boot_message
    jp kernel_load

; ----------------------------------------------------------------------------
; Routine: boot_error
; Report a failed SD/header/checksum validation and stop.
;
; Inputs:   Co-board map active; video RAM is F000h.
; Outputs:  No return; HALT loop with interrupts disabled.
; Clobbers: AF, DE, HL.
;
; This is also a tail-jump error exit from the loader, not a recovery path.
; ----------------------------------------------------------------------------
boot_error:
    ld hl,error_text
    jr boot_error_show
header_error:
    ld hl,header_error_text
    jr boot_content_error
signature_error:
    ld hl,signature_error_text
    jr boot_content_error
checksum_error:
    ld hl,checksum_error_text
boot_content_error:
    ld a,(boot_load_budget)
    dec a
    ld (boot_load_budget),a
    jr z,boot_error_show
    call boot_recovery
    call sd_retry_pause
    jp boot_load_start
boot_error_show:
    call boot_activity
    ld hl,msg_recovery
    ld de,0xf5f0
    call boot_message
    ld a,(sd_last_command)
    call boot_hex
    ld hl,msg_response
    call boot_message
    ld a,(sd_last_response)
    call boot_hex
boot_halt:
    halt
    jr boot_halt
system_signature: db 'P2MSYS03'
signature: db 'P2MCPM03'
error_text: db 'SD BOOT ERROR: card I/O failed or timed out; see active stage above',0
header_error_text: db 'SD BOOT ERROR: invalid system header signature or kernel size',0
signature_error_text: db 'SD BOOT ERROR: kernel signature mismatch',0
checksum_error_text: db 'SD BOOT ERROR: kernel checksum mismatch',0

; Update completed kernel sectors in decimal, preserving the loader registers.
boot_progress:
    push af
    push bc
    push de
    push hl
    ld a,kernel_sectors
    ld hl,remaining
    sub (hl)
    ld b,'0'
boot_tens:
    cp 10
    jr c,boot_digits
    sub 10
    inc b
    jr boot_tens
boot_digits:
    add a,'0'
    ld hl,0xf5a1+msg_load_count-msg_load
    ld (hl),b
    inc hl
    ld (hl),a
    pop hl
    pop de
    pop bc
    pop af
    ret
msg_mapped: db 'RAM enabled  /  RAM loader 7000                 ',0
msg_init_activity: db '  INITIALIZING SD  /  reset and SPI negotiation',0
msg_sd: db 'SPI mode  /  attempt '
msg_attempt: db '1/8',0
msg_header: db '  CHECKING SYSTEM HEADER  /  SD sector 15',0
msg_load: db '  LOADING KERNEL  /  SD 16-43 -> A000-D7FF   '
msg_load_count: db '00/28 sectors',0
msg_check: db '  CHECKING KERNEL  /  signature and checksum',0
msg_enter: db '  STARTING KERNEL  /  entry A000',0
msg_verified: db 'A000-D7FF  /  signature + checksum               ',0
msg_ready_status: db '          OK',0
msg_starting_status: db '    STARTING',0
msg_loading_status: db '     LOADING',0
msg_recovered_status: db '   RECOVERED',0

; CMD10 returns the 16-byte CID; byte 0 is the manufacturer ID (MID).
; Keep this on row 10; the BIOS begins its console log on row 11.
; An unavailable CID is reported explicitly and does not prevent data boot.
boot_cid:
    ld hl,msg_cid_wait
    call boot_activity
    ld hl,c10
    call sd_command
    or a
    jr nz,boot_cid_fail
    ld bc,0xffff
boot_cid_wait:
    call spi_rx
    cp 0xfe
    jr z,boot_cid_read
    cp 0xff
    jr nz,boot_cid_fail
    dec bc
    ld a,b
    or c
    jr nz,boot_cid_wait
boot_cid_fail:
    call sd_close
    ld hl,msg_cid_missing
    ld de,0xf2e1
    call boot_message
    ld hl,msg_cid_failed_status
    ld de,0xf311
    jp boot_message
boot_cid_read:
    ld hl,rom_workspace+0x20
    ld b,16
boot_cid_byte:
    call spi_rx
    ld (hl),a
    inc hl
    djnz boot_cid_byte
    call spi_rx
    call spi_rx
    call sd_close
    ld de,0xf2e5        ; row 9 column 21, after 'MID '
    ld a,(rom_workspace+0x20)
    call boot_hex
    ld de,0xf2f0        ; row 9 column 32, after 'OEM '
    ld hl,rom_workspace+0x21
    ld b,2
    call boot_cid_ascii
    ld de,0xf339        ; row 10 column 25, after 'Product '
    ld hl,rom_workspace+0x23
    ld b,5
    call boot_cid_ascii
    ld de,0xf34a        ; row 10 column 42, after 'Serial '
    ld hl,rom_workspace+0x29
    ld b,4
boot_cid_hex:
    ld a,(hl)
    call boot_hex
    inc hl
    djnz boot_cid_hex
    ld de,0xf311        ; row 9, right status field
    ld hl,msg_ready_status
    jp boot_message
boot_cid_ascii:
    ld a,(hl)
    cp 32
    jr c,boot_cid_dot
    cp 127
    jr nc,boot_cid_dot
    cp '#'
    jr nz,boot_cid_store
    ld a,0x5f
    jr boot_cid_store
boot_cid_dot:
    ld a,'.'
boot_cid_store:
    ld (de),a
    inc de
    inc hl
    djnz boot_cid_ascii
    ret
; A -> two hex characters at DE, preserving BC/HL.
boot_hex:
    push af
    rrca
    rrca
    rrca
    rrca
    call boot_nibble
    pop af
boot_nibble:
    and 15
    add a,'0'
    cp '9'+1
    jr c,boot_hex_store
    add a,7
boot_hex_store:
    ld (de),a
    inc de
    ret
c10: db 0x4a,0,0,0,0,1
msg_cid_wait: db '  READING CARD IDENTITY  /  CMD10',0
msg_cid_missing: db 'CID unavailable (CMD10 failed)                 ',0
msg_cid_failed_status: db ' UNAVAILABLE',0

msg_recovery: db '  Last command: 0x',0
msg_response: db ' response 0x',0
