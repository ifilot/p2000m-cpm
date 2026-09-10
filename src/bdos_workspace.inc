; Address-only shared state. Never allocates bytes in ROM.
caller_sp: equ bdos_workspace+0x00  ; word: application stack saved across CALL 5
argument: equ bdos_workspace+0x02  ; word: original DE supplied to BDOS
function: equ bdos_workspace+0x04  ; byte: current BDOS function number
current_drive: equ bdos_workspace+0x05  ; byte: default drive, A=0/B=1/C=2
user_number: equ bdos_workspace+0x06  ; byte: current CP/M user area 0..15
user_dma: equ bdos_workspace+0x07  ; word: application 128-byte transfer buffer
read_only: equ bdos_workspace+0x34  ; word: logical write-protection bitmask A..P
logged: equ bdos_workspace+0x36  ; word: logged-in drive bitmask A..P
fs_drive: equ bdos_workspace+0x0b  ; byte: drive selected for current FCB
alloc_ptr: equ bdos_workspace+0x0c  ; word: selected drive allocation bitmap address
block_shift: equ bdos_workspace+0x0e  ; byte: log2(records per allocation block)
extent_mask: equ bdos_workspace+0x0f  ; byte: logical extents per directory entry minus one
max_entries: equ bdos_workspace+0x10  ; word: directory entry count (not last index)
max_blocks: equ bdos_workspace+0x12  ; word: allocation block count
scan_index: equ bdos_workspace+0x14  ; word: current directory entry index
cache_record: equ bdos_workspace+0x16  ; word: cached directory record; FFFFh invalid
entry_ptr: equ bdos_workspace+0x18  ; word: entry address within directory_buffer
wanted_extent: equ bdos_workspace+0x1a  ; word: extent being searched
rw_record: equ bdos_workspace+0x1c  ; word: zero-based file record position
rw_block: equ bdos_workspace+0x1e  ; word: allocated disk block for transfer
rw_offset: equ bdos_workspace+0x20  ; word: address of allocation slot being updated
found_index: equ bdos_workspace+0x22  ; word: matched or free directory slot
saved_index: equ bdos_workspace+0x24  ; word: reserved workspace; currently unused
search_index: equ bdos_workspace+0x26  ; word: resumable SEARCH FIRST/NEXT position
search_drive: equ bdos_workspace+0x28  ; byte: saved search drive
search_user: equ bdos_workspace+0x29  ; byte: saved search user area
search_active: equ bdos_workspace+0x2a  ; byte: whether SEARCH NEXT has a context
any_match: equ bdos_workspace+0x2b  ; byte: accumulated matching-entry flag
size_max: equ bdos_workspace+0x2c  ; word: low 16 bits of maximum file record count
size_overflow: equ bdos_workspace+0x2e  ; byte: high size byte (65536 records needs 17 bits)
zero_record: equ bdos_workspace+0x30  ; word: next record to zero in a new block
zero_count: equ bdos_workspace+0x32  ; byte: remaining records to zero
io_mode: equ bdos_workspace+0x33  ; byte: 0=read, nonzero=write
entry_copy: equ 0xdd80  ; 32-byte directory-entry staging buffer
search_fcb: equ 0xdda0  ; 36-byte private search FCB
file_buffer: equ 0xdd00  ; 128-byte internal DMA buffer
