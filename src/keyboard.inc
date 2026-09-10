; Keyboard state uses previously reserved BSS; no application RAM is consumed.
key_rows: equ 0xddc4           ; nine pairs: raw sample, debounced pressed bits
key_head: equ 0xddd6
key_tail: equ 0xddd7
key_escape: equ 0xddd8
key_repeat_ptr: equ 0xddd9     ; pointer to selected row's debounced byte
key_repeat_count: equ 0xdddb
key_repeat_mask: equ 0xdddc
key_repeat_char: equ 0xdddd
key_overflow: equ 0xddde       ; sticky flag: newest event dropped when FIFO full
key_saved_sp: equ 0xdddf
