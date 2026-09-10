; ============================================================================
; src/cartridge.asm -- source tour and calling conventions
; ============================================================================
; Read this module first to understand power-on boot. Stock-map startup is
; followed by the mapped ROM loader, SPI primitives, then SD command/block I/O.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; Original P2000M boot cartridge. z80asm syntax, 16 KiB zero-padded image.
; ROM entry vectors after mapping: E000 boot, E003 read, E006 write, E009 init.
; Block I/O ABI: 32-bit little-endian LBA at rom_workspace, buffer at +4.
; Returns A=0 on success, A=1 on failure. Clobbers AF/BC/DE/HL.
include 'platform.inc'
include 'bdos_workspace.inc'
include 'kernel_exports.inc'
org 0x1000
; Bit 1 clear: do not ask the monitor to attempt floppy DOS before entry.
db 0x5c,0,0,0,0
db 'SD CPM     '
jp entry

; ============================================================================
; STOCK MAP: monitor entry and co-board handoff
; The monitor enters the signed ROM at 1000h. The short RAM trampoline
; bridges the OUT that changes which physical memory supplies the next opcode.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: entry
; Enter from the monitor and activate the CP/M memory map.
;
; Inputs:   Monitor has accepted the ROM header; co-board is physically installed.
; Outputs:  No return: control reaches boot at E000h after the map switch.
; Clobbers: AF, BC, DE, HL, SP; interrupts disabled.
;
; The two copies are intentional: numeric PC=9004h must still contain
; the continuation after the OUT changes the decoder. No CALL/RET spans it.
; ----------------------------------------------------------------------------
entry:
    di
    ld sp,0x9d00
    xor a
    out (0x10),a
    out (0x94),a
    ; The monitor's keyboard/CTC interrupts are no longer used by our polled
    ; console. Disable all four channels before applications can execute EI.
    ld a,3
    out (0x88),a
    out (0x89),a
    out (0x8a),a
    out (0x8b),a
    ; First title appears before bulk initialization; both screen maps alias.
    ld hl,0x5800
    ld de,0x5801
    ld bc,79
    ld (hl),0
    ldir
    ld hl,stock_banner
    ld de,0x5000
    call stock_print
    ld hl,stock_screen
    ld de,0x5000
    ld bc,1920
    ldir
    ld hl,0x5800
    ld de,0x5801
    ld bc,2047
    ld (hl),0
    ldir
    ld hl,0x5801
    call stock_inverse
    ld hl,0x5a81
    call stock_inverse
    ld hl,0x5bc1
    call stock_inverse
    ld hl,switch_code
    ld de,0x9000
    ld bc,switch_end-switch_code
    ldir
    ld hl,switch_code
    ld de,0xf000
    ld bc,switch_end-switch_code
    ldir
    jp 0x9000
stock_inverse:
    ld b,78
stock_inverse_loop:
    ld (hl),8
    inc hl
    djnz stock_inverse_loop
    ret
stock_print:
    ld a,(hl)
    or a
    ret z
    ld (de),a
    inc hl
    inc de
    jr stock_print
include 'boot_screen.inc'

; ----------------------------------------------------------------------------
; Routine: switch_code
; Trampoline copied into both sides of the memory-map transition.
;
; Inputs:   Execute the copied bytes at stock 9000h, not this ROM source address.
; Outputs:  No return: OUT (20h),80h selects co-board mode, then JP E000h.
; Clobbers: A; memory decoder changes.
;
; switch_end is a size marker, not a callable entry.
; ----------------------------------------------------------------------------
switch_code:
    ld a,0x80
    out (0x20),a
    jp 0xe000
switch_end:
defs 0x2000-$,0
org 0xe000
    jp boot
    jp sd_read
    jp sd_write
    jp sd_init
    jp boot_message        ; E00C: HL=NUL text, DE=video destination
    jp boot_activity       ; E00F: HL=text, replace activity row (18)
    db 'P2MUI02',0          ; E012: dashboard ABI guard for the SD kernel
    include 'link_id.inc'  ; E01A: 16-byte RAM/ROM cross-link fingerprint

lba: equ rom_workspace+0x00
buffer_ptr: equ rom_workspace+0x04
command_packet: equ rom_workspace+0x06
remaining: equ rom_workspace+0x0c

; ============================================================================
; MAPPED ROM: load and verify the SD kernel
; These entry addresses are part of the ROM/BIOS ABI. E003h reads a sector,
; E006h writes one, and E009h initializes SDHC. All remain in ROM after remapping.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: boot
; Load the fixed 14 KiB system image from the SD alignment gap.
;
; Inputs:   Co-board map active; no caller register values are required.
; Outputs:  No return: JP A000h on verified load, or boot_error on failure.
; Clobbers: AF, BC, DE, HL, SP; RAM 9600h header, DBC0h scratch, A000h-D7FFh kernel.
;
; LBA 15 describes the image. LBAs 16..47 carry it; HL is the destination
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
system_signature: db 'P2MSYS02'
signature: db 'P2MCPM02'
error_text: db 'SD BOOT ERROR: card I/O failed or timed out; see active stage above',0
header_error_text: db 'SD BOOT ERROR: invalid system header signature or kernel size',0
signature_error_text: db 'SD BOOT ERROR: kernel signature mismatch',0
checksum_error_text: db 'SD BOOT ERROR: kernel checksum mismatch',0

; Fixed-row output survives the map switch and identifies the failing stage.
; boot_message: HL=NUL string, DE=video address; clobbers AF/DE/HL.
boot_status: equ rom_workspace+0x10
boot_attempt: equ rom_workspace+0x12
boot_active: equ rom_workspace+0x13
boot_load_budget: equ rom_workspace+0x14
sd_last_command: equ rom_workspace+0x15
sd_last_response: equ rom_workspace+0x16
boot_message:
    ld a,(hl)
    or a
    jr z,boot_message_end
    ld (de),a
    inc hl
    inc de
    jr boot_message
boot_message_end:
    ld (boot_status),de
    ret
boot_ok:
    ret
; Replace only the activity row. BIOS and ROM use this same fixed region.
boot_activity:
    push hl
    ld hl,0xf5a0
    ld de,0xf5a1
    ld bc,79
    ld (hl),' '
    ldir
    pop hl
    ld de,0xf5a1
    jp boot_message
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
msg_mapped: db 'RAM enabled  /  ROM loader E000                 ',0
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

; Report recovery only during boot; retain the main stage's append cursor.
; Preserve caller registers/flags, including pending error strings and budgets.
boot_recovery:
    push af
    push bc
    push de
    push hl
    ld a,(boot_active)
    or a
    jr z,boot_recovery_done
    ld hl,(boot_status)
    push hl
    ld hl,msg_retry_status
    ld de,0xf3b1
    call boot_message
    pop hl
    ld (boot_status),hl
boot_recovery_done:
    pop hl
    pop de
    pop bc
    pop af
    ret
msg_retry_status: db '    RETRYING',0
msg_recovery: db '  Last command: 0x',0
msg_response: db ' response 0x',0

; Roughly 500 ms at 2.5 MHz. No clocks while deselected; preserve registers.
sd_retry_pause:
    push af
    push bc
    ld bc,48000
sd_retry_pause_loop:
    dec bc
    ld a,b
    or c
    jr nz,sd_retry_pause_loop
    pop bc
    pop af
    ret
; At least 1 ms between idle ACMD41 polls, rather than a tight command loop.
sd_init_pause:
    push af
    push bc
    ld bc,100
sd_init_pause_loop:
    dec bc
    ld a,b
    or c
    jr nz,sd_init_pause_loop
    pop bc
    pop af
    ret

; Byte-wide bridge: allow at least 32 T states between CLKSTART and read.

; ============================================================================
; SPI TRANSPORT: one byte, chip-select, and common return paths
; The cartridge exposes a transmit latch, a clock-start port and a receive
; latch. Reading port 40h alone does not clock another byte.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: spi_rx
; Clock a dummy FFh byte to receive one SPI byte.
;
; Inputs:   Selected card for data; deselected card for idle clocks.
; Outputs:  A = byte received.
; Clobbers: A only; F, BC, DE, HL, IX, IY preserved.
;
; Falls through into spi_tx after loading FFh. Eight NOPs provide the
; bridge time between starting the clocks and reading its receive latch.
; ----------------------------------------------------------------------------
spi_rx:
    ld a,0xff

; ----------------------------------------------------------------------------
; Routine: spi_tx
; Exchange one byte through the cartridge SPI bridge.
;
; Inputs:   A = transmit byte.
; Outputs:  A = receive byte.
; Clobbers: A only; flags and all other general registers preserved.
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; Routine: sd_close
; Deselect the card and supply an idle byte of clocks.
;
; Inputs:   No register inputs; valid in either selected or deselected state.
; Outputs:  A = receive latch after idle clocks (normally FFh).
; Clobbers: A only; flags and other registers preserved.
;
; Tail-calls spi_tx, so its RET returns to the original caller.
; ----------------------------------------------------------------------------
sd_close:
    ld a,0xff
    out (0x42),a
    jp spi_tx

; ----------------------------------------------------------------------------
; Routine: sd_fail
; Shared SD failure exit: release CS and return a BIOS-style error.
;
; Inputs:   Reached by a tail jump from a command or transfer routine.
; Outputs:  A=1; Z=0.
; Clobbers: AF.
;
; Other registers retain whatever the failing operation last put in them.
; ----------------------------------------------------------------------------
sd_fail:
    call sd_close
    ld a,1
    or a
    ret

; ----------------------------------------------------------------------------
; Routine: sd_ok
; Shared SD success exit: release CS and return success.
;
; Inputs:   Reached by a tail jump once a complete transaction has finished.
; Outputs:  A=0; Z=1; CY=0.
; Clobbers: AF.
; ----------------------------------------------------------------------------
sd_ok:
    call sd_close
    xor a
    ret

; HL points to six command bytes. CS remains asserted for data phase.

; ============================================================================
; SD COMMANDS: packet/reply handling and SDHC initialization
; Commands are six bytes: command number with bit 6 set, four big-endian
; argument bytes, and CRC/end bit. Data commands keep CS asserted for payload.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: sd_command
; Send a prepared command and poll for its R1 response.
;
; Inputs:   HL -> six-byte command packet.
; Outputs:  A = R1 response, or last byte on timeout; HL advanced by six; CS selected.
; Clobbers: AF, B, HL; C, DE, IX, IY preserved.
;
; B counts packet bytes, then the bounded reply poll. R1 has bit 7 clear;
; callers must test the response before entering a data phase.
; ----------------------------------------------------------------------------
sd_command:
    call sd_close
    out (0x43),a
    ld a,(hl)
    and 0x3f
    ld (sd_last_command),a
    or a
    jr z,cmd_ready
    ; Wait for a previously busy card before issuing a new command. CMD0
    ; bypasses this so that reset remains possible when readiness is lost.
    push bc
    ld bc,0xffff
cmd_ready_wait:
    call spi_rx
    cp 0xff
    jr z,cmd_ready_pop
    dec bc
    ld a,b
    or c
    jr nz,cmd_ready_wait
    pop bc
    ld a,0xff
    ld (sd_last_response),a
    ret
cmd_ready_pop:
    pop bc
cmd_ready:
    ld b,6
cmd_send:
    ld a,(hl)
    call spi_tx
    inc hl
    djnz cmd_send
    ld b,0                 ; up to 256 response bytes
cmd_reply:
    call spi_rx
    ld (sd_last_response),a
    bit 7,a
    ret z
    djnz cmd_reply
    ret

; ----------------------------------------------------------------------------
; Routine: sd_init
; Put a version-2 high-capacity card into SPI block-addressed mode.
;
; Inputs:   No register inputs; SDHC card and cartridge present.
; Outputs:  A=0/Z=1 if ready; A=1/Z=0 on unsupported card or timeout.
; Clobbers: AF, BC, DE, HL.
;
; CMD8 checks the echo pattern. DE counts ACMD41 attempts; CMD58 checks
; OCR ready and CCS bits, rejecting byte-addressed SDSC cards.
; ----------------------------------------------------------------------------
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
    jp z,sd_fail
    call sd_close
    call sd_init_pause
    jr init_wait
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

; ----------------------------------------------------------------------------
; Routine: block_command
; Construct a read/write command from the shared little-endian LBA.
;
; Inputs:   A = command byte (51h read or 58h write); [lba] = 32-bit sector.
; Outputs:  A = R1 reply; packet stored at command_packet; CS remains selected.
; Clobbers: AF, BC, DE, HL.
;
; The four LBA bytes are reversed while copying: RAM is little-endian,
; SD command arguments are transmitted most significant byte first.
; ----------------------------------------------------------------------------
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

; ============================================================================
; SD BLOCK I/O: exactly 512 bytes per request
; The BIOS handles CP/M 128-byte records; the ROM only transfers physical
; 512-byte sectors. buffer_ptr and lba are shared RAM mailboxes, not registers.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: sd_read
; Read one SDHC sector into the selected memory buffer.
;
; Inputs:   [lba] = physical sector; [buffer_ptr] = writable 512-byte destination.
; Outputs:  A=0/Z=1 on success, A=1/Z=0 on error; CS released on either path.
; Clobbers: AF, BC, DE, HL; destination bytes and command_packet.
;
; BC first bounds token polling, then counts 512 payload bytes. FEh is
; the start token; two trailing CRC bytes are consumed but not validated.
; ----------------------------------------------------------------------------
sd_read:
    ld a,3
sd_read_retry:
    push af
    call sd_read_once
    pop bc                 ; B = attempts remaining
    or a
    ret z
    dec b
    jp z,sd_fail
    push bc
    call boot_recovery
    call sd_retry_pause
    call sd_init
    pop bc
    ld a,b
    jr sd_read_retry
sd_read_once:
    ld a,0x51
    call block_command
    or a
    jp nz,sd_fail
    ld bc,0xffff
read_wait:
    call spi_rx
    ld (sd_last_response),a
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

; ----------------------------------------------------------------------------
; Routine: sd_write
; Write one SDHC sector and wait for the card to finish programming.
;
; Inputs:   [lba] = physical sector; [buffer_ptr] = readable 512-byte source.
; Outputs:  A=0/Z=1 only after accepted data and end of busy; otherwise A=1/Z=0.
; Clobbers: AF, BC, DE, HL; command_packet.
;
; The low five bits of the data-response token must equal 05h. Busy
; polling is bounded; returning success means this write is complete.
; ----------------------------------------------------------------------------
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
; Always-mapped filesystem code. Its state and buffers remain in RAM.
rom_driver_end:
defs rom_filesystem_base-$,0
include 'filesystem.asm'
rom_filesystem_end:
defs rom_end-$,0
