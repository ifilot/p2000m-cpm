; Single source of truth for the resident layout (also read by host tools).
boot_loader_base: equ 0x7000
keyboard_stack_bottom: equ 0xdc00
keyboard_stack_top: equ 0xdc80
keyboard_queue: equ 0xdcc0
kernel_load: equ 0xa000
kernel_end: equ 0xd800
kernel_bytes: equ 0x3800
kernel_sectors: equ 28
tpa_limit: equ 0xc900
resident_base: equ 0xc900
rom_filesystem_base: equ 0xe800
rom_end: equ 0xf000
resident_code_limit: equ 0xd600
bdos_stack_bottom: equ 0xd600
bdos_stack_top: equ 0xd700
system_stack_bottom: equ 0xd700
system_stack_top: equ 0xd800
; CCP and initial transient stacks share space: they never run concurrently.
transient_stack_bottom: equ 0xd700
transient_stack_top: equ 0xd800
bdos_workspace: equ 0xdb80
rom_workspace: equ 0xdbc0
sector_buffer: equ 0xd800
directory_buffer: equ 0xda00
allocation_a: equ 0xda80
allocation_c: equ 0xdc80
