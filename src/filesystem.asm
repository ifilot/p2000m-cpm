; ============================================================================
; src/filesystem.asm -- source tour and calling conventions
; ============================================================================
; On-disk format engine shared by SD and SRAM. Helpers come first, followed
; by file lifecycle/search/mutation, allocation, record I/O, and position queries.
;
; Headers use Inputs / Outputs / Clobbers; unlisted registers are preserved.
; Preservation applies to returning paths only.
; "Clobbers" includes result registers and anything a called routine may alter.
; AF includes flags; CY denotes carry (not the C register). SP is balanced
; on returning paths unless stated. No routine uses the alternate register set.
; Labels without a Routine header are local branches or data, not public calls.
; See docs/source-guide.md for units, call flow and tests.
;
; CP/M directory/extent engine. 4 KiB/16-bit allocation on SD, 1 KiB/8-bit on SRAM.
; A per-operation directory record buffer sits above the BIOS sector caches.

; ============================================================================
; DRIVE CONTEXT: choose geometry and map logical drive bits
; Three units recur below: records are 128 bytes, blocks are 1 or 4 KiB,
; and logical extents are 16 KiB. A physical SD directory entry spans two extents.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: drive_mask
; Convert a drive number to its login/protection mask.
;
; Inputs:   A = drive index 0..11.
; Outputs:  HL = 1 << drive; B=0. Supports all sixteen CP/M drive bits.
; Clobbers: AF, B, HL; C, DE preserved.
; ----------------------------------------------------------------------------
drive_mask:
    ld b,a
    ld hl,1
    inc b
mask_loop:
    dec b
    ret z
    add hl,hl
    jr mask_loop

; ----------------------------------------------------------------------------
; Routine: fs_current
; Set filesystem context from the current BDOS drive.
;
; Inputs:   [current_drive] = 0..11.
; Outputs:  A=0/Z=1 on success; A=1/Z=0 on invalid drive.
; Clobbers: AF, BC, DE, HL; geometry, selected drive, login mask, directory cache tag.
;
; Falls into the same context setup used for an explicit FCB drive.
; ----------------------------------------------------------------------------
fs_current:
    ld a,(current_drive)
    jr fs_use_drive

; ----------------------------------------------------------------------------
; Routine: fs_setup
; Choose an FCB explicit drive or the current default.
;
; Inputs:   IX -> FCB; byte 0 is 0=default, 1=A:, 2=B:, 3=C:.
; Outputs:  A=0/Z=1 success, A=1/Z=0 invalid drive.
; Clobbers: AF, BC, DE, HL; filesystem/BIOS drive and geometry state.
;
; IX remains the FCB base throughout the filesystem helpers.
; ----------------------------------------------------------------------------
fs_setup:
    ld a,(ix+0)
    or a
    jr z,fs_current
    dec a

; ----------------------------------------------------------------------------
; Routine: fs_use_drive
; Install geometry and allocation-map pointers for a given drive.
;
; Inputs:   A = zero-based drive 0..11.
; Outputs:  A=0/Z=1 success, A=1/Z=0 failure.
; Clobbers: AF, BC, DE, HL; context globals.
;
; SD: 512 entries, 2048 blocks, shift=5, EXM=1. SRAM: 64 entries,
; 128 blocks, shift=3, EXM=0. Cache tag FFFFh forces the first directory read.
; ----------------------------------------------------------------------------
fs_use_drive:
    cp drive_count
    jp nc,disk_error
    ld (fs_drive),a
    ld c,a
    call disk_select
    ld a,h
    or l
    jp z,disk_error
    ld a,(fs_drive)
    call drive_mask
    ld de,(logged)
    ld a,l
    or e
    ld l,a
    ld a,h
    or d
    ld h,a
    ld (logged),hl
    ld hl,0xffff
    ld (cache_record),hl
    ld a,(fs_drive)
    cp ram_drive
    jr z,fs_ram_geometry
    ld hl,allocation_a
    ; Shared scratch bitmap: rebuilt before every allocation and BDOS 27.
fs_sd_geometry:
    ld (alloc_ptr),hl
    ld hl,512
    ld (max_entries),hl
    ld hl,2048
    ld (max_blocks),hl
    ld a,5
    ld (block_shift),a
    ld a,1
    ld (extent_mask),a
    xor a
    ret
fs_ram_geometry:
    ld hl,allocation_c
    ld (alloc_ptr),hl
    ld hl,64
    ld (max_entries),hl
    ld hl,128
    ld (max_blocks),hl
    ld a,3
    ld (block_shift),a
    xor a
    ld (extent_mask),a
    ret

; ----------------------------------------------------------------------------
; Routine: fs_writable
; Test the software read-only mask for the active filesystem drive.
;
; Inputs:   [fs_drive] is already selected.
; Outputs:  A=0/Z=1 if writable; A=1/Z=0 if protected.
; Clobbers: AF, B; C, DE, HL, IX preserved.
;
; File attributes and physical-card errors are checked separately.
; ----------------------------------------------------------------------------
fs_writable:
    push de
    push hl
    ld a,(fs_drive)
    call drive_mask
    ld de,(read_only)
    ld a,l
    and e
    ld b,a
    ld a,h
    and d
    or b
    pop hl
    pop de
    ret z
    jp disk_error

; HL = logical record, BC = DMA; A = 0 read / 1 write.

; ============================================================================
; BIOS ADAPTER: linear logical record -> track/sector/DMA
; The filesystem works with absolute 128-byte record numbers within a volume.
; The BIOS expects track plus sector, so this helper divides by SPT=128 or 32.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_io
; Perform one BIOS read or buffered write of a logical record.
;
; Inputs:   HL = record number; BC -> 128-byte DMA; A=0 read, A=1 write; fs_drive set.
; Outputs:  A=0/Z=1 success; failure enters bdos_disk_error and never returns.
; Clobbers: AF, BC, DE, HL; io_mode, BIOS latches, media/DMA and ROM scratch.
;
; The DMA pointer and record are saved on the stack while shifts derive
; track. E holds the shift count, C the sector, before the BIOS calls.
; ----------------------------------------------------------------------------
fs_io:
    ld (io_mode),a
    push bc
    push hl
    ld a,(fs_drive)
    cp ram_drive
    ld a,l
    jr z,fs_io_ram
    and 127
    ld b,7
    jr fs_io_sector
fs_io_ram:
    and 31
    ld b,5
fs_io_sector:
    ld e,b
    ld c,a
    ld b,0
    call disk_sector
    pop hl
    ld b,e
fs_io_shift:
    srl h
    rr l
    djnz fs_io_shift
    ld b,h
    ld c,l
    call disk_track
    pop bc
    call disk_dma
    ld a,(io_mode)
    or a
    jr z,fs_io_read
    ld c,0                 ; filesystem commits explicitly at its boundaries
    call disk_write
    jr fs_io_result
fs_io_read:
    call disk_read
fs_io_result:
    or a
    jp nz,bdos_disk_error
    ret

; ============================================================================
; DIRECTORY CACHE: four 32-byte entries per logical record
; scan_index is an entry number, cache_record is a 128-byte record number,
; and entry_ptr points inside directory_buffer. Do not confuse these units.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_dir_get
; Fetch the directory entry selected by scan_index.
;
; Inputs:   fs context set; [scan_index] = entry index.
; Outputs:  A=0/Z=1 and HL=[entry_ptr] on success; A=1/Z=0 at end or I/O failure.
; Clobbers: AF, BC, DE, HL; directory_buffer, cache_record, entry_ptr.
;
; Index/4 chooses the directory record; (index & 3)*32 chooses its entry.
; Callers that distinguish end-of-directory from I/O errors use fs_scan_end first.
; ----------------------------------------------------------------------------
fs_dir_get:
    ld hl,(scan_index)
    ld de,(max_entries)
    or a
    sbc hl,de
    jp nc,disk_error
    ld hl,(scan_index)
    srl h
    rr l
    srl h
    rr l
    push hl
    ld de,(cache_record)
    or a
    sbc hl,de
    pop hl
    jr z,fs_dir_cached
    push hl
    ld bc,directory_buffer
    xor a
    call fs_io
    pop hl
    or a
    ret nz
    ld (cache_record),hl    ; publish the directory-record tag only after success
fs_dir_cached:
    ld a,(scan_index)
    and 3
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld de,directory_buffer
    add hl,de
    ld (entry_ptr),hl
    xor a
    ret

; ----------------------------------------------------------------------------
; Routine: fs_dir_flush
; Write the cached directory record through the BIOS.
;
; Inputs:   cache_record identifies directory_buffer, which contains edited entries.
; Outputs:  A=0/Z=1 success, A=1/Z=0 failure.
; Clobbers: AF, BC, DE, HL; disk contents.
;
; The current entire 128-byte directory record is written, not just one entry.
; ----------------------------------------------------------------------------
fs_dir_flush:
    ld hl,(cache_record)
    ld bc,directory_buffer
    ld a,1
    jp fs_io

; ----------------------------------------------------------------------------
; Routine: fs_scan_start
; Start a directory scan at entry zero.
;
; Inputs:   No inputs.
; Outputs:  HL=0; scan_index=0.
; Clobbers: HL only; flags preserved.
; ----------------------------------------------------------------------------
fs_scan_start:
    ld hl,0
    ld (scan_index),hl
    ret

; ----------------------------------------------------------------------------
; Routine: fs_scan_advance
; Advance the directory scan to the next entry.
;
; Inputs:   scan_index = current entry.
; Outputs:  HL and scan_index = previous index + 1.
; Clobbers: HL only; flags preserved.
; ----------------------------------------------------------------------------
fs_scan_advance:
    ld hl,(scan_index)
    inc hl
    ld (scan_index),hl
    ret
; Compare user and 11 filename bytes; '?' wildcards and attribute bits supported.

; ============================================================================
; MATCHING: user/name/attribute masking and extent groups
; Directory byte 0 is a user number or E5h (unused). Bytes 1..11 hold name
; and extension; their high bits are attributes and do not participate in names.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_name_match
; Compare the selected entry against the FCB name pattern.
;
; Inputs:   IX -> FCB; entry_ptr -> directory entry; user_number selects the user.
; Outputs:  Z=1 if user/name match, otherwise Z=0; question marks match any character.
; Clobbers: AF, BC, DE, HL; IX preserved.
;
; B counts eleven characters; DE walks the FCB while HL walks the entry.
; ----------------------------------------------------------------------------
fs_name_match:
    ld hl,(entry_ptr)
    ld a,(user_number)
    cp (hl)
    ret nz
    inc hl
    push ix
    pop de
    inc de
    ld b,11
fs_name_byte:
    ld a,(de)
    and 0x7f
    cp '?'
    jr z,fs_name_next
    ld c,a
    ld a,(hl)
    and 0x7f
    cp c
    ret nz
fs_name_next:
    inc hl
    inc de
    djnz fs_name_byte
    xor a
    ret
; ----------------------------------------------------------------------------
; Routine: fs_extent_match
; Compare physical extent groups, or accept the wildcard sentinel.
;
; Inputs:   entry_ptr -> candidate; wanted_extent = logical extent, or FFFFh for any.
; Outputs:  Z=1 if matched, Z=0 otherwise; no scalar result contract.
; Clobbers: AF, DE, HL.
;
; Masking out EXM collapses the two SD logical extents in one directory
; entry into the same group. SRAM EXM=0 keeps one logical extent per entry.
; ----------------------------------------------------------------------------
fs_extent_match:
    ld hl,(wanted_extent)
    ld a,h
    and l
    inc a
    ret z
    ld hl,(entry_ptr)
    call fs_entry_extent
    ld a,(extent_mask)
    cpl
    and e
    ld e,a
    ld hl,(wanted_extent)
    ld a,(extent_mask)
    cpl
    and l
    ld l,a
    or a
    sbc hl,de
    ret

; ----------------------------------------------------------------------------
; Routine: fs_find
; Scan for the first matching name and physical extent group.
;
; Inputs:   IX -> FCB; fs context, wanted_extent and user_number set.
; Outputs:  A=0/Z=1, HL=entry_ptr and found_index set; A=1/Z=0 otherwise.
; Clobbers: AF, BC, DE, HL; scan/cache/entry globals.
;
; Uses fs_name_match then fs_extent_match. FFFFh means any extent.
; ----------------------------------------------------------------------------
fs_find:
    call fs_scan_start
fs_find_loop:
    call fs_dir_get
    or a
    ret nz
    call fs_name_match
    jr nz,fs_find_next
    call fs_extent_match
    jr z,fs_found
fs_find_next:
    call fs_scan_advance
    jr fs_find_loop
fs_found:
    ld hl,(scan_index)
    ld (found_index),hl
    ld hl,(entry_ptr)
    xor a
    ret

; ----------------------------------------------------------------------------
; Routine: fs_any_extent
; Set the wildcard extent sentinel for name-only operations.
;
; Inputs:   No inputs.
; Outputs:  HL=FFFFh; wanted_extent=FFFFh.
; Clobbers: HL only; flags preserved.
; ----------------------------------------------------------------------------
fs_any_extent:
    ld hl,0xffff
    ld (wanted_extent),hl
    ret
; Derive 16-bit sequential record from EX/S2/CR. Carry flags overflow.

; ============================================================================
; FCB POSITION: logical records, extents, and allocation copies
; FCB offsets: EX=12, S1=13, S2=14, RC=15, allocation=16..31, CR=32,
; random record R0/R1/R2=33..35. CR may equal 128 at a sequential boundary.
; ============================================================================


; ----------------------------------------------------------------------------
; Routine: fs_want_position
; Derive the logical extent to find from a record number.
;
; Inputs:   rw_record = logical record within a file.
; Outputs:  HL and wanted_extent = rw_record / 128.
; Clobbers: AF, B, HL; other pointers preserved.
; ----------------------------------------------------------------------------
fs_want_position:
    ld hl,(rw_record)
    ld b,7
fs_want_shift:
    srl h
    rr l
    djnz fs_want_shift
    ld (wanted_extent),hl
    ret
; ----------------------------------------------------------------------------
; Routine: fs_copy_entry
; Save the current directory entry across scans and allocation work.
;
; Inputs:   entry_ptr -> cached 32-byte entry.
; Outputs:  entry_copy receives those 32 bytes.
; Clobbers: AF, BC, DE, HL.
;
; The copy is necessary because rebuilding the allocation map reuses
; the directory cache, and would otherwise destroy the pending file metadata.
; ----------------------------------------------------------------------------
fs_copy_entry:
    ld hl,(entry_ptr)
    ld de,entry_copy
    ld bc,32
    ldir
    ret

; ----------------------------------------------------------------------------
; Routine: fs_result_index
; Convert the found directory index to the standard BDOS return slot.
;
; Inputs:   found_index = absolute directory entry index.
; Outputs:  HL = found_index & 3, the slot within a 128-byte directory record.
; Clobbers: AF, HL.
; ----------------------------------------------------------------------------
fs_result_index:
    ld a,(found_index)
    and 3
    jp return_a

; ============================================================================
; FILE LIFECYCLE: open/close/create and persistent entry updates
; These handlers return a directory slot 0..3 or FFh. Their IX FCB pointer
; is established by the BDOS dispatcher; CALL 5 protects the application registers.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_open
; BDOS 15: locate an extent and populate the caller FCB.
;
; Inputs:   IX -> FCB with drive/name and EX/S2; CR is preserved, not used to select.
; Outputs:  HL=slot 0..3 on success, 00FFh if invalid/missing/error.
;           Success binds wildcard name/type to the matched entry.
; Clobbers: AF, BC, DE, HL; FCB and filesystem scratch.
; ----------------------------------------------------------------------------
fs_open:
    call fs_setup
    jp nz,return_ff
    ; Some period programs (notably LINK-80's MS COBOL launcher) initialize
    ; only the drive/name/type portion of an FCB.  CP/M OPEN starts at extent
    ; zero in that case; do not reject garbage S2 beyond this volume's range.
    ld a,(ix+14)
    and 63
    cp 16
    jr c,fs_open_extent_valid
    xor a
    ld (ix+12),a
    ld (ix+13),a
    ld (ix+14),a
fs_open_extent_valid:
    ld a,(ix+32)
    push af
    ld (ix+32),0           ; CR is not part of OPEN's extent selection
    call fs_position
    pop bc
    ld (ix+32),b
    jp c,return_ff
    call fs_want_position
    call fs_find
    jp nz,return_ff
    call fs_copy_entry
    ld hl,entry_copy+1
    push ix
    pop de
    inc de
    ld bc,11
    ldir                  ; bind wildcard OPEN to the matched filename/attributes
    ld a,(ix+32)
    push af
    call fs_sync_fcb
    pop af
    ld (ix+32),a
    jp fs_result_index

; ----------------------------------------------------------------------------
; Routine: fs_close
; BDOS 16: commit pending data/metadata, then confirm the named file exists.
;
; Inputs:   IX -> FCB with drive/name.
; Outputs:  HL=slot 0..3 if found, 00FFh otherwise.
; Clobbers: AF, BC, DE, HL; scan state.
;
; No dirty FCB is merged here: fs_write stages allocation/length in the BIOS
; cache. CLOSE commits data before metadata and returns FFh on flush failure.
; ----------------------------------------------------------------------------
fs_close:
    call cache_flush
    or a
    jp nz,return_ff
    call fs_setup
    jp nz,return_ff
    call fs_any_extent
    call fs_find
    jp nz,return_ff
    ; All record/metadata updates have already reached the medium.
    jp fs_result_index

; ----------------------------------------------------------------------------
; Routine: fs_make
; BDOS 22: create a new empty file without replacing an existing one.
;
; Inputs:   IX -> FCB with drive/name; user_number selects namespace.
; Outputs:  HL=slot 0..3 and FCB initialized, or 00FFh on failure.
; Clobbers: AF, BC, DE, HL; directory, FCB and scratch.
;
; Checks any existing extent first, then creates extent zero with no blocks.
; ----------------------------------------------------------------------------
fs_make:
    call fs_setup
    jp nz,return_ff
    call fs_writable
    jp nz,return_ff
    call fs_any_extent
    call fs_find
    jp z,return_ff
    ld hl,0
    ld (rw_record),hl
    call fs_want_position
    call fs_create_extent
    jp nz,return_ff
    call fs_sync_fcb
    jp fs_result_index

; ----------------------------------------------------------------------------
; Routine: fs_create_extent
; Allocate an unused directory entry for wanted_extent.
;
; Inputs:   IX -> FCB name; wanted_extent and fs context set; caller checks write access.
; Outputs:  A=0/Z=1 success, A=1/Z=0 on full directory or I/O error; found_index set.
; Clobbers: AF, BC, DE, HL; entry_copy, directory/cache state and medium.
;
; Only metadata is created here. Allocation pointers remain zero until
; a write allocates a data block. E5h identifies a reusable directory slot.
; ----------------------------------------------------------------------------
fs_create_extent:
    call fs_scan_start
fs_free_entry:
    call fs_dir_get
    or a
    ret nz
    ld a,(hl)
    cp 0xe5
    jr z,fs_create_here
    call fs_scan_advance
    jr fs_free_entry
fs_create_here:
    ld hl,(scan_index)
    ld (found_index),hl
    ld hl,entry_copy
    ld de,entry_copy+1
    ld bc,31
    ld (hl),0
    ldir
    ld a,(user_number)
    ld (entry_copy),a
    push ix
    pop hl
    inc hl
    ld de,entry_copy+1
    ld bc,11
    ldir
    ld hl,(wanted_extent)
    ld a,l
    and 31
    ld (entry_copy+12),a
    ld b,5
fs_create_s2:
    srl h
    rr l
    djnz fs_create_s2
    ld a,l
    ld (entry_copy+14),a
    jp fs_store_entry

; ----------------------------------------------------------------------------
; Routine: fs_store_entry
; Persist entry_copy at the remembered directory index.
;
; Inputs:   found_index = target slot; entry_copy = complete replacement entry.
; Outputs:  A=0/Z=1 success, A=1/Z=0 failure.
; Clobbers: AF, BC, DE, HL; directory buffer and medium.
;
; Reloads the correct directory record in case another scan displaced it.
; ----------------------------------------------------------------------------
fs_store_entry:
    ld hl,(found_index)
    ld (scan_index),hl
    call fs_dir_get
    or a
    ret nz
    ex de,hl
    ld hl,entry_copy
    ld bc,32
    ldir
    jp fs_dir_flush

; ============================================================================
; DIRECTORY ENUMERATION: saved pattern and search continuation
; Search First copies the caller pattern, because DMA output may overwrite
; caller memory. Search Next uses that saved pattern rather than the new DE argument.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_first
; BDOS 17: begin wildcard directory enumeration.
;
; Inputs:   IX -> 36-byte FCB; user_dma -> 128-byte result buffer.
; Outputs:  HL=slot 0..3 and DMA contains its directory record; 00FFh if none/error.
; Clobbers: AF, BC, DE, HL, IX; saved search state and user DMA.
;
; Sets search_index=0 and falls through into fs_next. EX=? lists all
; physical extents; otherwise the requested extent group is matched.
; DR=? scans raw entries on the current drive, including free slots/all users.
; ----------------------------------------------------------------------------
fs_first:
    ld a,(ix+0)
    cp '?'
    jr nz,fs_first_normal
    call fs_current
    jr fs_first_ready
fs_first_normal:
    call fs_setup
fs_first_ready:
    jp nz,return_ff
    push ix
    pop hl
    ld de,search_fcb
    ld bc,36
    ldir
    ld a,(fs_drive)
    ld (search_drive),a
    ld a,(user_number)
    ld (search_user),a
    ld a,1
    ld (search_active),a
    ld hl,0
    ld (search_index),hl

; ----------------------------------------------------------------------------
; Routine: fs_next
; BDOS 18: continue the saved directory search.
;
; Inputs:   search_active, search_drive, search_fcb and search_index from Search First.
; Outputs:  HL=slot 0..3 with DMA record, or 00FFh at end/error.
; Clobbers: AF, BC, DE, HL, IX; search/cache state and user DMA.
;
; IX is switched to search_fcb. The surrounding public BDOS entry restores
; the application IX when the handler returns.
; ----------------------------------------------------------------------------
fs_next:
    ld a,(search_active)
    or a
    jp z,return_ff
    ld a,(search_drive)
    call fs_use_drive
    jp nz,return_ff
    ld ix,search_fcb
    ld hl,(search_index)
    ld (scan_index),hl
fs_search_loop:
    call fs_dir_get
    or a
    jr nz,fs_search_end
    ld a,(ix+0)
    cp '?'
    jr z,fs_search_hit     ; raw directory scan includes free slots and all users
    call fs_name_match
    jr nz,fs_search_skip
    ; Search EX '?' includes all extents; otherwise compare physical group.
    ld a,(ix+12)
    cp '?'
    jr z,fs_search_hit
    and 31
    ld l,a
    ld h,0
    ld (wanted_extent),hl
    call fs_extent_match
    jr nz,fs_search_skip
fs_search_hit:
    ld hl,(scan_index)
    ld (found_index),hl
    inc hl
    ld (search_index),hl
    ld hl,directory_buffer
    ld de,(user_dma)
    ld bc,128
    ldir
    jp fs_result_index
fs_search_skip:
    call fs_scan_advance
    jr fs_search_loop
fs_search_end:
    xor a
    ld (search_active),a
    jp return_ff

; ============================================================================
; DIRECTORY MUTATION: wildcard deletion, rename and attribute bits
; These operations scan all matching extents, not only the first. Attribute
; bits are masked out during name comparison, then preserved or edited explicitly.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_delete
; BDOS 19: mark matching directory entries unused.
;
; Inputs:   IX -> FCB pattern; selected namespace and software protection checked.
; Outputs:  HL=0 if at least one entry deleted, 00FFh if none/protected/I/O error.
; Clobbers: AF, BC, DE, HL; matching directory entries.
;
; Read-only files are rejected. Space is reclaimed on the next allocation
; map rebuild; no data blocks need clearing to delete a file.
; ----------------------------------------------------------------------------
fs_delete:
    call fs_setup
    jp nz,return_ff
    call fs_writable
    jp nz,return_ff
    xor a
    ld (any_match),a
    call fs_scan_start
fs_delete_loop:
    call fs_scan_end
    jp z,fs_multi_result
    call fs_dir_get
    or a
    jp nz,return_ff
    call fs_name_match
    jr nz,fs_delete_next
    ld hl,(entry_ptr)
    ld de,9
    add hl,de
    bit 7,(hl)
    jp nz,return_ff
    ld hl,(entry_ptr)
    ld (hl),0xe5
    call fs_dir_flush
    or a
    jp nz,return_ff
    ld a,1
    ld (any_match),a
fs_delete_next:
    call fs_scan_advance
    jr fs_delete_loop

; ----------------------------------------------------------------------------
; Routine: fs_multi_result
; Return success only if a multi-entry operation changed something.
;
; Inputs:   any_match = zero or nonzero.
; Outputs:  HL=0 if changed, 00FFh otherwise.
; Clobbers: AF, HL.
; ----------------------------------------------------------------------------
fs_multi_result:
    ld a,(any_match)
    or a
    jp z,return_ff
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: fs_rename
; BDOS 23: rename all matching extents without overwriting a destination.
;
; Inputs:   IX -> FCB: old name bytes 1..11, new name bytes 17..27.
; Outputs:  HL=0 if renamed, 00FFh if missing/collision/protected/error.
; Clobbers: AF, BC, DE, HL; directory; IX restored after destination search.
;
; The destination lookup temporarily adds 16 to IX. Mutation preserves
; existing attribute bits while replacing only the low seven filename bits.
; ----------------------------------------------------------------------------
fs_rename:
    call fs_setup
    jp nz,return_ff
    call fs_writable
    jp nz,return_ff
    ; Reject an existing destination before altering any directory entries.
    push ix
    ld de,16
    add ix,de
    call fs_any_extent
    call fs_find
    pop ix
    jp z,return_ff
    jr fs_modify

; ----------------------------------------------------------------------------
; Routine: fs_attributes
; BDOS 30: copy requested filename attribute bits into matching entries.
;
; Inputs:   IX -> FCB; high bits of name/type bytes carry desired attributes.
; Outputs:  HL=0 if any entry updated, 00FFh otherwise.
; Clobbers: AF, BC, DE, HL; directory and cache state.
; ----------------------------------------------------------------------------
fs_attributes:
    call fs_setup
    jp nz,return_ff
    call fs_writable
    jp nz,return_ff

; ----------------------------------------------------------------------------
; Routine: fs_modify
; Shared entry loop for rename and attribute updates.
;
; Inputs:   IX -> FCB; fs context is writable; function=23 rename or 30 attributes.
; Outputs:  HL=0 if changed, 00FFh if no match or failure.
; Clobbers: AF, BC, DE, HL; matching directory records.
;
; Low name bits and high attribute bits are handled separately. Every
; modified directory record is written before advancing the scan.
; ----------------------------------------------------------------------------
fs_modify:
    xor a
    ld (any_match),a
    call fs_scan_start
fs_modify_loop:
    call fs_scan_end
    jp z,fs_multi_result
    call fs_dir_get
    or a
    jp nz,return_ff
    call fs_name_match
    jr nz,fs_modify_next
    ld hl,(entry_ptr)
    inc hl
    push ix
    pop de
    inc de
    ld a,(function)
    cp 23
    jr nz,fs_attribute_bytes
    push hl
    ld bc,8
    add hl,bc
    bit 7,(hl)
    pop hl
    jp nz,return_ff
    push hl
    ld hl,16
    add hl,de
    ex de,hl
    pop hl
    ld b,11
fs_rename_byte:
    ld a,(de)
    and 0x7f
    ld c,a
    ld a,(hl)
    and 0x80
    or c
    ld (hl),a
    inc hl
    inc de
    djnz fs_rename_byte
    jr fs_modify_flush
fs_attribute_bytes:
    ld b,11
fs_attribute_byte:
    ld a,(de)
    and 0x80
    ld c,a
    ld a,(hl)
    and 0x7f
    or c
    ld (hl),a
    inc hl
    inc de
    djnz fs_attribute_byte
fs_modify_flush:
    call fs_dir_flush
    or a
    jp nz,return_ff
    ld a,1
    ld (any_match),a
fs_modify_next:
    call fs_scan_advance
    jr fs_modify_loop

; Allocation map: bit 7 represents block zero, as CP/M specifies.

; ============================================================================
; ALLOCATION: rebuild CP/M bitmaps and initialize new blocks
; CP/M maps block zero to bit 7, not bit 0. SD allocation pointers are
; 16-bit little-endian words; RAM-drive pointers are single bytes.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_bit
; Calculate a bitmap byte address and mask for a block.
;
; Inputs:   DE = block number; alloc_ptr -> bitmap.
; Outputs:  HL -> bitmap byte; A = 80h >> (block & 7); DE preserved.
; Clobbers: AF, B, HL; C, DE, IX preserved.
;
; The byte index is block/8. This helper does not read or modify the bit.
; ----------------------------------------------------------------------------
fs_bit:
    push de
    ld a,e
    and 7
    ld b,a
    ld a,0x80
    inc b
fs_bit_shift:
    dec b
    jr z,fs_bit_address
    srl a
    jr fs_bit_shift
fs_bit_address:
    ld h,d
    ld l,e
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ld de,(alloc_ptr)
    add hl,de
    pop de
    ret

; ----------------------------------------------------------------------------
; Routine: fs_mark
; Set a block's allocation bit after checking its range.
;
; Inputs:   DE = block number; max_blocks and alloc_ptr match the active drive.
; Outputs:  A=0/Z=1 success; A=1/Z=0 if block >= max_blocks; DE preserved.
; Clobbers: AF, B, HL; allocation bitmap.
; ----------------------------------------------------------------------------
fs_mark:
    ld a,d
    or e
    call nz,fs_validate_block
    call fs_bit
    or (hl)
    ld (hl),a
    xor a
    ret

; ----------------------------------------------------------------------------
; Routine: fs_rebuild
; Reconstruct the allocation bitmap from all active directory entries.
;
; Inputs:   fs context and allocation pointer initialized.
; Outputs:  A=0/Z=1 success, A=1/Z=0 on I/O or invalid block pointer.
; Clobbers: AF, BC, DE, HL; bitmap, directory cache and scan state.
;
; Start with reserved directory blocks marked. Each user 0..15 entry
; contributes 8 word pointers (SD) or 16 byte pointers (SRAM). Free E5h entries skip.
; ----------------------------------------------------------------------------
fs_rebuild:
    ld hl,(alloc_ptr)
    ld d,h
    ld e,l
    inc de
    ld bc,255
    ld a,(fs_drive)
    cp ram_drive
    jr nz,fs_clear_map
    ld bc,15
fs_clear_map:
    ld (hl),0
    ldir
    ld hl,(alloc_ptr)
    ld (hl),0xf0
    ld a,(fs_drive)
    cp ram_drive
    jr nz,fs_rebuild_start
    ld (hl),0xc0
fs_rebuild_start:
    call fs_scan_start
fs_rebuild_entry:
    ld hl,(scan_index)
    ld de,(max_entries)
    or a
    sbc hl,de
    jr z,fs_rebuild_done
    call fs_dir_get
    or a
    ret nz
    ld a,(hl)
    cp 16
    jr nc,fs_rebuild_next
    ld de,16
    add hl,de
    ld b,8
    ld a,(fs_drive)
    cp ram_drive
    jr nz,fs_rebuild_pointer
    ld b,16
fs_rebuild_pointer:
    ld e,(hl)
    inc hl
    ld d,0
    ld a,(fs_drive)
    cp ram_drive
    jr z,fs_rebuild_mark
    ld d,(hl)
    inc hl
fs_rebuild_mark:
    push bc
    push hl
    call fs_mark
    pop hl
    pop bc
    or a
    ret nz
    djnz fs_rebuild_pointer
fs_rebuild_next:
    call fs_scan_advance
    jr fs_rebuild_entry
fs_rebuild_done:
    xor a
    ret

; ----------------------------------------------------------------------------
; Routine: fs_allocate
; Find a free block, mark it and zero its physical records.
;
; Inputs:   fs context writable; no live data may alias file_buffer.
; Outputs:  A=0/Z=1 with rw_block set; A=1/Z=0 on full disk or I/O failure.
; Clobbers: AF, BC, DE, HL; bitmap, file_buffer, zeroing counters and medium.
;
; The directory copy is kept separately while rebuild scans all entries.
; Zeroing happens before its allocation pointer is committed to a file entry.
; ----------------------------------------------------------------------------
fs_allocate:
    call fs_rebuild
    or a
    ret nz
    ld de,0
fs_allocate_loop:
    call fs_bit
    and (hl)
    jr z,fs_allocate_found
    inc de
    ld hl,(max_blocks)
    or a
    sbc hl,de
    jr nz,fs_allocate_loop
    jp disk_error
fs_allocate_found:
    ld (rw_block),de
    call fs_mark
    ; Always initialize a new block. Function 40 is therefore also satisfied.
    ld hl,file_buffer
    ld de,file_buffer+1
    ld bc,127
    ld (hl),0
    ldir
    ld hl,(rw_block)
    ld a,(block_shift)
    ld b,a
    ld a,1
fs_zero_scale:
    add hl,hl
    add a,a
    djnz fs_zero_scale
    ld (zero_record),hl
    ld (zero_count),a
fs_zero_loop:
    ld hl,(zero_record)
    ld bc,file_buffer
    ld a,1
    call fs_io
    or a
    ret nz
    ld hl,(zero_record)
    inc hl
    ld (zero_record),hl
    ld a,(zero_count)
    dec a
    ld (zero_count),a
    jr nz,fs_zero_loop
    xor a
    ret

; ============================================================================
; RECORD ENGINE: sequential and random reads/writes share one path
; rw_record is a position inside a file. Allocation lookup converts it to
; a physical block and then a volume-relative record passed to fs_io.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_read
; BDOS 20: read at EX/S2/CR, advancing only after success.
;
; Inputs:   IX -> FCB; function=20; user_dma -> 128-byte destination.
; Outputs:  HL=0 success, 1 EOF/unwritten, 6 overflow, or other failure status.
; Clobbers: AF, BC, DE, HL; FCB position, DMA and filesystem scratch.
;
; This label aliases fs_write; the function byte selects direction later.
; ----------------------------------------------------------------------------
fs_read:

; ----------------------------------------------------------------------------
; Routine: fs_write
; BDOS 21: write at EX/S2/CR, allocating blocks/extents as required.
;
; Inputs:   IX -> FCB; function=21; user_dma -> 128-byte source.
; Outputs:  HL=0 success; nonzero failure (including full/protected/error/overflow).
; Clobbers: AF, BC, DE, HL; FCB, directory, allocation map, medium and scratch.
;
; Shares the sequential-position setup with fs_read, then enters fs_rw_begin.
; ----------------------------------------------------------------------------
fs_write:
    call fs_setup
    jp nz,return_ff
    call fs_position
    ld a,6
    jp c,return_a
    jr fs_rw_begin

; ----------------------------------------------------------------------------
; Routine: fs_random_read
; BDOS 33: read at the 24-bit R0/R1/R2 position without incrementing it.
;
; Inputs:   IX -> FCB; function=33; R2 must be zero; user_dma -> destination.
; Outputs:  HL=0 success; 1 unwritten record, 4 missing extent, 6 overflow, or error.
; Clobbers: AF, BC, DE, HL; FCB sequential-position fields, DMA and scratch.
;
; Aliases fs_random_write: direction comes from function, not the entry address.
; ----------------------------------------------------------------------------
fs_random_read:

; ----------------------------------------------------------------------------
; Routine: fs_random_write
; BDOS 34/40: write the requested random record.
;
; Inputs:   IX -> FCB; function=34 or 40; R2=0; user_dma -> source record.
; Outputs:  HL=0 success; nonzero full/protected/I/O/overflow status.
; Clobbers: AF, BC, DE, HL; FCB, allocation/directory state and medium.
;
; All newly allocated blocks are zero-filled here, so function 40
; requires no separate transfer engine. Random R0/R1/R2 are not advanced.
; ----------------------------------------------------------------------------
fs_random_write:
    call fs_setup
    jp nz,return_ff
    ld a,(ix+35)
    or a
    ld a,6
    jp nz,return_a
    ld l,(ix+33)
    ld h,(ix+34)
    ld (rw_record),hl

; ----------------------------------------------------------------------------
; Routine: fs_rw_begin
; Resolve the requested extent and perform the selected record operation.
;
; Inputs:   rw_record set; IX -> FCB; fs context and function identify read/write mode.
; Outputs:  HL = BDOS record status; updates FCB after successful I/O.
; Clobbers: AF, BC, DE, HL; directory cache, entry_copy, allocation state, DMA/media.
;
; Work proceeds as extent lookup -> length/protection checks -> block
; lookup/allocation -> data I/O -> metadata commit -> FCB synchronization.
; ----------------------------------------------------------------------------
fs_rw_begin:
    call fs_want_position
    call fs_find
    jr z,fs_rw_entry
    ld a,(function)
    cp 20
    jp z,fs_eof
    cp 33
    ld a,4
    jp z,return_a
    call fs_writable
    jp nz,return_ff
    call fs_any_extent
    call fs_find
    jp nz,return_ff
    ld hl,(entry_ptr)
    ld de,9
    add hl,de
    bit 7,(hl)
    jp nz,return_ff
    call fs_want_position
    call fs_create_extent
    or a
    ld a,5
    jp nz,return_a
fs_rw_entry:
    call fs_copy_entry
    ; Check file/drive write protection for all write variants.
    ld a,(function)
    cp 20
    jr z,fs_read_length
    cp 33
    jr z,fs_read_length
    call fs_writable
    jp nz,return_ff
    ld a,(entry_copy+9)
    and 0x80
    jp nz,return_ff
    jr fs_block_lookup
fs_read_length:
    ld hl,entry_copy
    call fs_entry_extent
    ex de,hl
    ld b,7
fs_length_shift:
    add hl,hl
    djnz fs_length_shift
    ld a,(entry_copy+15)
    ld e,a
    ld d,0
    add hl,de
    jr c,fs_block_lookup
    ld de,(rw_record)
    or a
    sbc hl,de
    jp c,fs_eof
    jp z,fs_eof
fs_block_lookup:
    ld a,(rw_record)
    ld c,a
    ld a,(block_shift)
    ld b,a
    ld a,c
    and 127
    ld c,a
    ld a,(extent_mask)
    or a
    jr z,fs_block_shift
    ld a,(rw_record)
    ld c,a
fs_block_shift:
    srl c
    djnz fs_block_shift
    ld a,(fs_drive)
    cp ram_drive
    jr z,fs_pointer_offset
    sla c
fs_pointer_offset:
    ld b,0
    ld hl,entry_copy+16
    add hl,bc
    ld (rw_offset),hl
    ld e,(hl)
    ld d,0
    ld a,(fs_drive)
    cp ram_drive
    jr z,fs_pointer_read
    inc hl
    ld d,(hl)
fs_pointer_read:
    ld (rw_block),de
    ld a,d
    or e
    jr nz,fs_data_io
    ld a,(function)
    cp 20
    jp z,fs_eof
    cp 33
    jp z,fs_eof
    call fs_allocate
    or a
    ld a,2
    jp nz,return_a
    ld hl,(rw_offset)
    ld de,(rw_block)
    ld (hl),e
    ld a,(fs_drive)
    cp ram_drive
    jr z,fs_data_io
    inc hl
    ld (hl),d
    jr fs_data_io

; ----------------------------------------------------------------------------
; Routine: fs_eof
; Return the record-not-present/EOF status.
;
; Inputs:   Reached by a tail branch from the record engine.
; Outputs:  HL=1.
; Clobbers: A, HL.
; ----------------------------------------------------------------------------
fs_eof:
    ld a,1
    jp return_a

; ----------------------------------------------------------------------------
; Routine: fs_data_io
; Translate the allocated block into a volume record and transfer data.
;
; Inputs:   rw_block allocated; rw_record, function, user_dma and entry_copy valid.
; Outputs:  HL = BDOS result; successful sequential calls leave CR incremented.
; Clobbers: AF, BC, DE, HL; DMA/media, entry metadata, FCB and scratch.
;
; Data is written before the new high-water mark is persisted. CR=128
; is deliberately left for fs_position to fold into the next extent on next call.
; ----------------------------------------------------------------------------
fs_data_io:
    ld de,(rw_block)
    call fs_validate_block
    ld hl,(rw_block)
    ld a,(block_shift)
    ld b,a
    ld a,1
fs_data_scale:
    add hl,hl
    add a,a
    djnz fs_data_scale
    dec a
    ld b,a
    ld a,(rw_record)
    and b
    ld e,a
    ld d,0
    add hl,de
    ld bc,(user_dma)
    ld a,(function)
    cp 20
    jr z,fs_data_read
    cp 33
    jr z,fs_data_read
    ld a,1
    call fs_io
    or a
    jp nz,return_a
    ; Advance the entry high-water mark only if this record extends it.
    ld hl,entry_copy
    call fs_entry_extent
    ex de,hl
    ld b,7
fs_old_end:
    add hl,hl
    djnz fs_old_end
    ld a,(entry_copy+15)
    ld e,a
    ld d,0
    add hl,de
    jr c,fs_metadata_store
    ld de,(rw_record)
    or a
    sbc hl,de
    jr c,fs_extend
    jr z,fs_extend
    jr fs_metadata_store
fs_extend:
    ld hl,(wanted_extent)
    ld a,l
    and 31
    ld (entry_copy+12),a
    ld b,5
fs_extend_s2:
    srl h
    rr l
    djnz fs_extend_s2
    ld a,l
    ld (entry_copy+14),a
    ld a,(rw_record)
    and 127
    inc a
    ld (entry_copy+15),a
fs_metadata_store:
    call fs_store_entry
    or a
    jp nz,return_a
    jr fs_rw_done
fs_data_read:
    xor a
    call fs_io
    or a
    jp nz,return_a
fs_rw_done:
    call fs_sync_fcb
    ld a,(function)
    cp 20
    jr z,fs_sequential_advance
    cp 21
    jp nz,return_zero
fs_sequential_advance:
    ; CP/M leaves CR=128 until the next operation advances the extent.
    inc (ix+32)
    jp return_zero

; ============================================================================
; POSITION QUERIES: sequential-to-random conversion and file length
; A CP/M file can have sparse extents. Size is the maximum extent end,
; not the number of allocated records. 65536 records needs the R2 high byte.
; ============================================================================

; ----------------------------------------------------------------------------
; Routine: fs_setrandom
; BDOS 36: record the current sequential position in R0/R1/R2.
;
; Inputs:   IX -> FCB with EX/S2/CR.
; Outputs:  HL=0; FCB random word set and R2 receives overflow carry.
; Clobbers: AF, BC, DE, HL; rw_record, FCB bytes 33..35.
; ----------------------------------------------------------------------------
fs_setrandom:
    call fs_position
    ld (ix+33),l
    ld (ix+34),h
    ld a,0
    adc a,0
    ld (ix+35),a
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: fs_size
; BDOS 35: scan all matching extents for the logical file size.
;
; Inputs:   IX -> FCB name/drive; user_number selects namespace.
; Outputs:  HL=0 and FCB R0/R1/R2=size in records, or 00FFh on error.
; Clobbers: AF, BC, DE, HL; FCB random fields and scan/size scratch.
;
; Each candidate contributes extent*128 + RC. Carry records an exact
; 65536-record result without wrapping it to an apparent empty file.
; ----------------------------------------------------------------------------
fs_size:
    call fs_setup
    jp nz,return_ff
    ld hl,0
    ld (size_max),hl
    xor a
    ld (size_overflow),a
    call fs_scan_start
fs_size_loop:
    call fs_scan_end
    jr z,fs_size_done
    call fs_dir_get
    or a
    jp nz,return_ff
    call fs_name_match
    jr nz,fs_size_next
    ld hl,(entry_ptr)
    call fs_entry_extent
    push hl
    ex de,hl
    ld b,7
fs_size_shift:
    add hl,hl
    djnz fs_size_shift
    ex de,hl
    pop hl
    ld bc,15
    add hl,bc
    ld l,(hl)
    ld h,0
    add hl,de
    jr nc,fs_size_compare
    ld a,1
    ld (size_overflow),a
fs_size_compare:
    push hl
    ld de,(size_max)
    or a
    sbc hl,de
    pop hl
    jr c,fs_size_next
    ld (size_max),hl
fs_size_next:
    call fs_scan_advance
    jr fs_size_loop
fs_size_done:
    ld hl,(size_max)
    ld a,(size_overflow)
    or a
    jr z,fs_size_save
    ld hl,0
fs_size_save:
    ld (ix+33),l
    ld (ix+34),h
    ld (ix+35),a
    jp return_zero

; ----------------------------------------------------------------------------
; Routine: fs_scan_end
; Test whether the directory entry scan has reached its limit.
;
; Inputs:   scan_index and max_entries initialized.
; Outputs:  Z=1 exactly at the end; HL=scan_index-max_entries.
; Clobbers: F, DE, HL; A and BC preserved.
;
; Shared scan helper; delete/modify/size call it before fs_dir_get so an
; I/O failure is not confused with normal end-of-directory.
; ----------------------------------------------------------------------------
fs_scan_end:
    ld hl,(scan_index)
    ld de,(max_entries)
    or a
    sbc hl,de
    ret
