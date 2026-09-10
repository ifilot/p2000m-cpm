; Original SD-loaded CP/M-compatible kernel, CP/M 2.2 API.
org 0xa000
jp start
db 'P2MCPM01'
start:
    di
    ld sp,0x9d00
    jp cold_boot
kernel_ready:
    jp ccp_start
kernel_error:
    ld hl,error_banner
    call ccp_puts
kernel_stop:
    halt
    jr kernel_stop
error_banner: db 'BIOS ERROR: invalid partition layout or SD read failure',0
include 'ccp.asm'
defs 0xa800-$,0
include 'bdos.asm'
defs 0xc000-$,0
include 'bios.asm'
defs 0xe000-$,0
