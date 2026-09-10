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
; Original P2000M boot cartridge. z80asm syntax, 8 KiB physical image.
; ROM entry vectors after mapping: E000 boot, E003 read, E006 write, E009 init.
; Block I/O ABI: 32-bit little-endian LBA at 9E00, buffer address at 9E04.
; Returns A=0 on success, A=1 on failure. Clobbers AF/BC/DE/HL.
org 0x1000
db 0x5e,0,0,0,0
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

; ============================================================================
; MAPPED ROM: load and verify the SD kernel
; These entry addresses are part of the ROM/BIOS ABI. E003h reads a sector,
; E006h writes one, and E009h initializes SDHC. All remain in ROM after remapping.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: boot
; Load the fixed 16 KiB system image from the SD alignment gap.
;
; Inputs:   Co-board map active; no caller register values are required.
; Outputs:  No return: JP A000h on verified load, or boot_error on failure.
; Clobbers: AF, BC, DE, HL, SP; RAM 9600h header, 9E00h scratch, A000h-DFFFh kernel.
;
; LBA 15 describes the image. LBAs 16..47 carry it; HL is the destination
; and remaining counts sectors. The checksum adds all bytes modulo 65536.
; ----------------------------------------------------------------------------
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
