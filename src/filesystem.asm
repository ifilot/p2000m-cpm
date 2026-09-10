; CP/M directory/extent engine. 4 KiB/16-bit allocation on SD, 1 KiB/8-bit on SRAM.
; Directory sectors are cached within an operation; data writes are write-through.
drive_mask:
    ld b,a
    ld a,1
    inc b
mask_loop:
    dec b
    ret z
    add a,a
    jr mask_loop
fs_current:
    ld a,(current_drive)
    jr fs_use_drive
fs_setup:
    ld a,(ix+0)
    or a
    jr z,fs_current
    dec a
fs_use_drive:
    cp 3
    jp nc,disk_error
    ld (fs_drive),a
    ld c,a
    call disk_select
    ld a,(fs_drive)
    call drive_mask
    ld b,a
    ld a,(logged)
    or b
    ld (logged),a
    ld hl,0xffff
    ld (cache_record),hl
    ld a,(fs_drive)
    cp 2
    jr z,fs_ram_geometry
    ld hl,allocation_a
    or a
    jr z,fs_sd_geometry
    ld hl,allocation_b
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
fs_writable:
    ld a,(fs_drive)
    call drive_mask
    ld b,a
    ld a,(read_only)
    and b
    ret z
    jp disk_error

; HL = logical record, BC = DMA; A = 0 read / 1 write.
fs_io:
    ld (io_mode),a
    push bc
    push hl
    ld a,(fs_drive)
    cp 2
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
    jp z,disk_read
    jp disk_write

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
    ld (cache_record),hl
    ld bc,directory_buffer
    xor a
    call fs_io
    or a
    ret nz
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
fs_dir_flush:
    ld hl,(cache_record)
    ld bc,directory_buffer
    ld a,1
    jp fs_io
fs_scan_start:
    ld hl,0
    ld (scan_index),hl
    ret
fs_scan_advance:
    ld hl,(scan_index)
    inc hl
    ld (scan_index),hl
    ret
; Compare user and 11 filename bytes; '?' wildcards and attribute bits supported.
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
; HL entry -> DE logical extent number.
fs_entry_extent:
    push hl
    ld de,12
    add hl,de
    ld a,(hl)
    and 31
    ld e,a
    inc hl
    inc hl
    ld a,(hl)
    and 63
    ld l,a
    ld h,0
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    add hl,hl
    ld d,0
    add hl,de
    ex de,hl
    pop hl
    ret
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
fs_any_extent:
    ld hl,0xffff
    ld (wanted_extent),hl
    ret
; Derive 16-bit sequential record from EX/S2/CR. Carry flags overflow.
fs_position:
    ld a,(ix+14)
    and 63
    cp 16
    jr nc,fs_position_overflow
    ld h,a
    ld l,0
    srl h
    rr l
    srl h
    rr l
    srl h
    rr l
    ; HL = S2 * 32
    ld a,(ix+12)
    and 31
    or l
    ld l,a
    ld b,7
fs_position_shift:
    add hl,hl
    djnz fs_position_shift
    ld e,(ix+32)
    ld d,0
    add hl,de
    ld (rw_record),hl
    ret
fs_position_overflow:
    ld hl,0
    ld (rw_record),hl
    scf
    ret
fs_want_position:
    ld hl,(rw_record)
    ld b,7
fs_want_shift:
    srl h
    rr l
    djnz fs_want_shift
    ld (wanted_extent),hl
    ret
; Copy allocations and RC from entry_copy, retaining current logical position.
fs_sync_fcb:
    ld hl,entry_copy+16
    push ix
    pop de
    push de
    ld bc,16
    ex de,hl
    add hl,bc
    ex de,hl
    ldir
    pop de
    ld hl,(rw_record)
    ld a,l
    and 127
    ld (ix+32),a
    ld b,7
fs_sync_shift:
    srl h
    rr l
    djnz fs_sync_shift
    ld a,l
    and 31
    ld (ix+12),a
    ld a,l
    ld b,5
fs_sync_s2:
    srl h
    rr l
    djnz fs_sync_s2
    ld (ix+14),l
    ld (ix+13),0
    ld a,(entry_copy+12)
    ld b,a
    ld a,(extent_mask)
    and b
    ld b,a
    ld a,(extent_mask)
    and (ix+12)
    cp b
    ld a,128
    jr c,fs_sync_rc
    ld a,(entry_copy+15)
fs_sync_rc:
    ld (ix+15),a
    ret
fs_copy_entry:
    ld hl,(entry_ptr)
    ld de,entry_copy
    ld bc,32
    ldir
    ret
fs_result_index:
    ld a,(found_index)
    and 3
    jp return_a
fs_open:
    call fs_setup
    jp nz,return_ff
    call fs_position
    jp c,return_ff
    call fs_want_position
    call fs_find
    jp nz,return_ff
    call fs_copy_entry
    call fs_sync_fcb
    jp fs_result_index
fs_close:
    call fs_setup
    jp nz,return_ff
    call fs_any_extent
    call fs_find
    jp nz,return_ff
    ; All record/metadata updates have already reached the medium.
    jp fs_result_index
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

fs_first:
    call fs_setup
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
fs_multi_result:
    ld a,(any_match)
    or a
    jp z,return_ff
    jp return_zero
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
fs_attributes:
    call fs_setup
    jp nz,return_ff
    call fs_writable
    jp nz,return_ff
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
fs_mark:
    push de
    ld hl,(max_blocks)
    or a
    sbc hl,de
    pop de
    jp c,disk_error
    jp z,disk_error
    call fs_bit
    or (hl)
    ld (hl),a
    xor a
    ret
fs_rebuild:
    ld hl,(alloc_ptr)
    ld d,h
    ld e,l
    inc de
    ld bc,255
    ld a,(fs_drive)
    cp 2
    jr nz,fs_clear_map
    ld bc,15
fs_clear_map:
    ld (hl),0
    ldir
    ld hl,(alloc_ptr)
    ld (hl),0xf0
    ld a,(fs_drive)
    cp 2
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
    cp 2
    jr nz,fs_rebuild_pointer
    ld b,16
fs_rebuild_pointer:
    ld e,(hl)
    inc hl
    ld d,0
    ld a,(fs_drive)
    cp 2
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

fs_read:
fs_write:
    call fs_setup
    jp nz,return_ff
    call fs_position
    ld a,6
    jp c,return_a
    jr fs_rw_begin
fs_random_read:
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
    cp 2
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
    cp 2
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
    cp 2
    jr z,fs_data_io
    inc hl
    ld (hl),d
    jr fs_data_io
fs_eof:
    ld a,1
    jp return_a
fs_data_io:
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

fs_setrandom:
    call fs_position
    ld (ix+33),l
    ld (ix+34),h
    ld a,0
    adc a,0
    ld (ix+35),a
    jp return_zero
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

fs_scan_end:
    ld hl,(scan_index)
    ld de,(max_entries)
    or a
    sbc hl,de
    ret
