; Read-only tables; DPH scratch words and all mutable state remain in RAM.
bdos_table:
    dw warm_boot,bdos_input,bdos_output,bdos_reader,return_zero,return_zero
    dw bdos_direct,bdos_iobyte,bdos_setio,bdos_string,bdos_line,bdos_status
    dw bdos_version,bdos_reset,bdos_select,fs_open,fs_close,fs_first,fs_next
    dw fs_delete,fs_read,fs_write,fs_make,fs_rename,bdos_login,bdos_current
    dw bdos_dma,bdos_alloc,bdos_protect,bdos_ro,fs_attributes,bdos_dpb,bdos_user
    dw fs_random_read,fs_random_write,fs_size,fs_setrandom,bdos_reset_drives
    dw return_zero,return_zero,fs_random_write

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
