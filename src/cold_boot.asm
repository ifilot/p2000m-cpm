; Disposable cold initialization: overwritten by applications after boot.
; ----------------------------------------------------------------------------
; Routine: cold_boot
; Initialize a newly SD-loaded system and enter the command processor.
;
; Inputs:   ROM has verified/loaded the kernel; co-board mapping is active.
; Outputs:  No return: jumps to warm_start on success, kernel_error otherwise.
; Clobbers: AF, BC, DE, HL, SP; system state and all 128 KiB of cartridge SRAM.
;
; LDIR clears runtime BSS except the ROM workspace. Page-zero IOBYTE and saved command drive
; start at zero. disk_initialize validates the SD layout before formatting L:.
; ----------------------------------------------------------------------------
cold_boot:
    ld sp,system_stack_top
    ; Runtime BSS is not read from SD: ROM workspace must survive the load.
    ; Leave DBC0-DBFF (ROM state/CID) untouched until it is no longer needed.
    ld hl,0xd800
    ld de,0xd801
    ld bc,0x3bf
    ld (hl),0
    ldir
    ld hl,0xdc00
    ld de,0xdc01
    ld bc,0x3ff
    ld (hl),0
    ldir
    call cache_invalidate
    xor a
    ld (3),a
    ld (4),a
    ld hl,kernel_pair_text
    ld de,0xf0a1
    call 0xe00c
    ld hl,kernel_tpa_text
    ld de,0xf0f1
    call 0xe00c
    ld hl,boot_partitions
    call kernel_activity
    call disk_initialize
    or a
    jp nz,kernel_error
    xor a
    ld (rom_workspace+0x13),a           ; disable boot-only recovery display after disk setup
    ld hl,boot_vectors
    call kernel_activity
    ld hl,drive_row_0
    ld de,0xf411
    call 0xe00c
    ld hl,drive_row_1
    ld de,0xf461
    call 0xe00c
    ld hl,drive_row_2
    ld de,0xf4b1
    call 0xe00c
    ld hl,drive_row_3
    ld de,0xf501
    call 0xe00c
    ld hl,0xf641
    ld (cursor),hl
    ld a,1
    ld (column),a

    jp warm_start       ; initial dashboard already positions the prompt

; ----------------------------------------------------------------------------
; Routine: disk_initialize
; Validate the FAT32 and eleven-volume CP/M container and cold-format external SRAM.
;
; Inputs:   SDHC already initialized by ROM; no register arguments.
; Outputs:  A=0/Z=1 success, A=1/Z=0 on MBR or SD failure.
; Clobbers: AF, BC, DE, HL; disk state, sector buffer, ROM scratch and SRAM.
;
; D selects SRAM bank 0 then 1. HL walks all 65536 addresses in each
; bank; wrapping HL to zero completes a bank. E5h marks free directory slots.
; ----------------------------------------------------------------------------
disk_initialize:
    xor a
    ld (selected),a
    ld (track),a
    ld (track+1),a
    ld (record),a
    ld (record+1),a
    ld hl,0
    ld (rom_workspace+0x00),hl
    ld (rom_workspace+0x02),hl
    ld hl,sector_buffer
    ld (rom_workspace+0x04),hl
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
    ld a,(sector_buffer+450)
    cp 0x0c
    jp nz,disk_error
    ld hl,sector_buffer+454
    ld de,partition_fat
    ld b,8
    call compare_bytes
    jp nz,disk_error
    ld hl,sector_buffer+470
    ld de,partition_container
    ld b,8
    call compare_bytes
    jp nz,disk_error
    ; No overlapping extra MBR partitions are permitted in this fixed layout.
    ld hl,sector_buffer+478
    ld b,32
disk_extra_entries:
    ld a,(hl)
    or a
    jp nz,disk_error
    inc hl
    djnz disk_extra_entries
    ; Cold-boot format both SRAM banks. Warm boot deliberately skips this.
    ld hl,boot_partition_ok
    call kernel_activity
    ld hl,boot_ram_first
    call kernel_activity
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
    jr z,ram_format_done
    ld hl,boot_ram_second
    call kernel_activity
    jr ram_format_bank
ram_format_done:
    ld hl,boot_ram_ok
    call kernel_activity
    xor a
    ret

kernel_activity:
    push bc
    push de
    call 0xe00f
    pop de
    pop bc
    ret
boot_partitions: db '  CHECKING SD LAYOUT  /  eleven 8 MiB volumes A-K',0
boot_partition_ok: db '  SD LAYOUT VERIFIED  /  A-K ready',0
boot_ram_first: db '  INITIALIZING L: SCRATCH (RAM)  /  0/128 KiB',0
boot_ram_second: db '  INITIALIZING L: SCRATCH (RAM)  /  64/128 KiB',0
boot_ram_ok: db '  INITIALIZING L: SCRATCH (RAM)  /  128/128 KiB OK',0
boot_vectors: db '  BOOT COMPLETE  /  CP/M entry points installed',0

; ----------------------------------------------------------------------------
; Routine: compare_bytes
; Compare two fixed-length byte strings.
;
; Inputs:   HL -> first string; DE -> second string; B = count (1..255).
; Outputs:  Z=1 if equal; Z=0 at first mismatch. HL/DE advance through equal bytes.
; Clobbers: AF, B, DE, HL; C preserved.
;
; B=0 would loop for 256 bytes because DJNZ wraps; callers here use 8.
; ----------------------------------------------------------------------------
compare_bytes:
    ld a,(de)
    cp (hl)
    ret nz
    inc de
    inc hl
    djnz compare_bytes
    ret
partition_fat: db 0,8,0,0,0,0,2,0
partition_container: db 0,8,2,0,0,192,2,0

include 'kernel_screen.inc'
