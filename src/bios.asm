; ============================================================================
; src/bios.asm -- source tour and calling conventions
; ============================================================================
; Hardware boundary of the system: CP/M calls above, P2000M I/O ports below.
; Keep the vector order fixed and keep cold-only SRAM formatting out of warm boot.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; CP/M 2.2 BIOS jump table at C000. Disk I/O exclusively uses port-2 SD/SRAM.

; ============================================================================
; BIOS ABI: fixed 17-entry CP/M 2.2 jump table
; Each entry is a three-byte JP at C000h + 3*index. Do not insert data
; between entries: applications derive addresses from the warm-boot vector.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: bios
; Cold-boot vector and base of the public BIOS entry table.
;
; Inputs:   Register inputs depend on the selected table entry; see each target.
; Outputs:  Entry zero transfers to cold_boot; this table itself has no RET.
; Clobbers: As specified by the target routine.
;
; The order is BOOT, WBOOT, CONST, CONIN, CONOUT, LIST, PUNCH, READER,
; HOME, SELDSK, SETTRK, SETSEC, SETDMA, READ, WRITE, LISTST, SECTRAN.
; ----------------------------------------------------------------------------
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

; ============================================================================
; SYSTEM LIFECYCLE: cold initialization versus warm restart
; Only cold boot clears BDOS state and formats cartridge SRAM. Warm boot
; reinstalls page-zero vectors and the default DMA without touching C: data.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: cold_boot
; Initialize a newly SD-loaded system and enter the command processor.
;
; Inputs:   ROM has verified/loaded the kernel; co-board mapping is active.
; Outputs:  No return: falls into warm_boot on success, kernel_error otherwise.
; Clobbers: AF, BC, DE, HL, SP; system state and all 128 KiB of cartridge SRAM.
;
; LDIR clears 9F00h..9FFFh. Page-zero IOBYTE and saved command drive
; start at zero. disk_initialize validates the SD layout before formatting C:.
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; Routine: warm_boot
; Restart the resident CCP without reformatting the RAM drive.
;
; Inputs:   [0004h] = saved CCP drive (0..2); invalid values fall back to A:.
; Outputs:  No return: enters ccp_loop with DMA=0080h and standard page-zero jumps.
; Clobbers: AF, BC, DE, HL, SP; current_drive, user_dma, DMA, page-zero vectors.
;
; 0005h jumps to 9800h, which jumps to the BDOS implementation. This
; reports the TPA boundary below system stacks even though BDOS lives higher.
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; Routine: disk_initialize
; Validate the two CP/M partitions and cold-format external SRAM.
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
partition_a: db 0,8,2,0,0,64,0,0
partition_b: db 0,72,2,0,0,64,0,0

; ============================================================================
; DISK SELECTION: latch the parameters for the next record transfer
; SETTRK/SETSEC/SETDMA do not perform I/O. The subsequent READ or WRITE
; validates geometry and consumes the latched values. Sectors are zero-based.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: disk_home
; Set logical track zero without mechanical seeking.
;
; Inputs:   No inputs.
; Outputs:  [track]=0; BC=0.
; Clobbers: BC only; flags preserved.
;
; Falls through into disk_track; no floppy seek command is issued.
; ----------------------------------------------------------------------------
disk_home:
    ld bc,0

; ----------------------------------------------------------------------------
; Routine: disk_track
; Latch the zero-based track.
;
; Inputs:   BC = zero-based track.
; Outputs:  [track] = BC; no I/O yet.
; Clobbers: No registers or flags; only the named RAM word.
; ----------------------------------------------------------------------------
disk_track:
    ld (track),bc
    ret

; ----------------------------------------------------------------------------
; Routine: disk_sector
; Latch the zero-based logical sector within the track.
;
; Inputs:   BC = zero-based logical sector within the track.
; Outputs:  [record] = BC; no I/O yet.
; Clobbers: No registers or flags; only the named RAM word.
; ----------------------------------------------------------------------------
disk_sector:
    ld (record),bc
    ret

; ----------------------------------------------------------------------------
; Routine: disk_dma
; Latch the address of a 128-byte CPU-memory buffer.
;
; Inputs:   BC = address of a 128-byte CPU-memory buffer.
; Outputs:  [dma] = BC; no I/O yet.
; Clobbers: No registers or flags; only the named RAM word.
; ----------------------------------------------------------------------------
disk_dma:
    ld (dma),bc
    ret

; ----------------------------------------------------------------------------
; Routine: disk_select
; Select A:, B: or C: and return its disk parameter header.
;
; Inputs:   C=0/1/2 for A:/B:/C:; CP/M E login flag is not needed by fixed media.
; Outputs:  HL -> DPH on success; HL=0 for an unsupported drive.
; Clobbers: AF, DE, HL; BC, IX, IY preserved.
;
; Each DPH is 16 bytes. A:/B: share geometry but have separate allocation
; maps. An invalid selection leaves the previous drive selected.
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; Routine: disk_translate
; Identity sector translation for contiguous logical records.
;
; Inputs:   BC = zero-based logical sector; DE translation table is ignored.
; Outputs:  HL=BC.
; Clobbers: HL only; flags preserved.
;
; No interleave/skew table is needed for solid-state media.
; ----------------------------------------------------------------------------
disk_translate:
    ld h,b
    ld l,c
    ret

; ----------------------------------------------------------------------------
; Routine: disk_error
; Return the BIOS nonrecoverable-error code.
;
; Inputs:   No register inputs.
; Outputs:  A=1/Z=0.
; Clobbers: AF only.
; ----------------------------------------------------------------------------
disk_error:
    ld a,1
    or a
    ret

; ============================================================================
; RECORD I/O: deblock SD sectors or address SRAM directly
; The BIOS public record size is 128 bytes. One SD physical sector contains
; four records; SRAM is accessed byte by byte without an auto-increment port.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: disk_read
; Read the latched 128-byte record into DMA.
;
; Inputs:   [selected], [track], [record], [dma] describe the request.
; Outputs:  A=0/Z=1 success, A=1/Z=0 failure; DMA receives 128 bytes on success.
; Clobbers: AF, BC, DE, HL; sector_buffer and shared ROM scratch.
; ----------------------------------------------------------------------------
disk_read:
    xor a
    jr disk_transfer

; ----------------------------------------------------------------------------
; Routine: disk_write
; Write the DMA record synchronously to the selected drive.
;
; Inputs:   Latched disk/DMA state; C is the CP/M write hint (0/1/2), ignored here.
; Outputs:  A=0/Z=1 success, A=1/Z=0 failure.
; Clobbers: AF, BC, DE, HL; selected media, sector_buffer and ROM scratch.
;
; All writes are write-through, including directory writes, so no dirty
; sector cache needs flushing at CLOSE or warm boot.
; ----------------------------------------------------------------------------
disk_write:
    ld a,1

; ----------------------------------------------------------------------------
; Routine: disk_transfer
; Common record transfer dispatcher and SD deblocking path.
;
; Inputs:   A=0 read or 1 write; disk selection/geometry/DMA are latched in RAM.
; Outputs:  A=0 success or A=1 failure, with matching Z flag.
; Clobbers: AF, BC, DE, HL.
;
; SD LBA = partition base + track*32 + sector/4. The low two sector
; bits pick a 128-byte slice. Writes first read all 512 bytes to retain neighbours.
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; Routine: ram_transfer
; Transfer one logical record through the SRAM address/data ports.
;
; Inputs:   [writing]=0/1; [track]=0..31, [record]=0..31; [dma] -> 128 bytes.
; Outputs:  A=0/Z=1 success, A=1/Z=0 for out-of-range geometry.
; Clobbers: AF, BC, DE, HL; SRAM or DMA depending on direction.
;
; Track bit 4 selects the 64 KiB bank. Remaining address bits encode
; (track & 15)*4096 + record*128. HL is SRAM address, DE is CPU DMA pointer.
; ----------------------------------------------------------------------------
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

; ----------------------------------------------------------------------------
; Routine: ram_address
; Load the SRAM bank-relative address latch.
;
; Inputs:   HL = 16-bit address within the bank already selected through port 4Bh.
; Outputs:  Ports 49h/48h hold H/L; A=L.
; Clobbers: A only; flags and other registers preserved.
; ----------------------------------------------------------------------------
ram_address:
    ld a,h
    out (0x49),a
    ld a,l
    out (0x48),a
    ret

include 'console.asm'

; ============================================================================
; DISK TABLES AND BUFFERS: DPH links to DPB and allocation bitmap
; DPH = translation, three scratch words, directory buffer, DPB, checksum
; vector, allocation vector. A zero checksum vector denotes fixed media here.
; ============================================================================

dph_a: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_a
dph_b: dw 0,0,0,0,directory_buffer,dpb_sd,0,allocation_b
dph_c: dw 0,0,0,0,directory_buffer,dpb_ram,0,allocation_c
dpb_sd:
    dw 128                ; SPT: 128 records of 128 bytes per logical track
    db 5,31,1             ; BSH/BLM/EXM: 4 KiB blocks, two 16 KiB extents/entry
    dw 2047,511           ; DSM/DRM: last block and last directory entry
    db 0xf0,0             ; AL0/AL1: reserve first four blocks for directory
    dw 0,0                ; CKS/OFF: no checksum vector or reserved tracks
dpb_ram:
    dw 32                 ; SPT: 32 records per logical track
    db 3,7,0              ; BSH/BLM/EXM: 1 KiB blocks, one extent/entry
    dw 127,63             ; DSM/DRM: 128 blocks and 64 directory entries
    db 0xc0,0             ; AL0/AL1: first two blocks hold directory
    dw 0,0                ; CKS/OFF: fixed media, no reserved tracks
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
