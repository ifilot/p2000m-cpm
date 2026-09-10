; Real BDOS/SD workload that never polls the console. Keyboard IRQs must
; capture type-ahead while each reset forces another physical sector read.
org 0x100
    di
    ld sp,0x9500
    ei
    xor a
    ld (0x9000),a
    ld de,fcb
    ld c,15
    call 5
    cp 0xff
    jr z,failed
    ld de,output_fcb
    ld c,22
    call 5
    cp 0xff
    jr z,failed
again:
    ld c,13
    call 5
    ld de,fcb
    ld c,33
    call 5
    or a
    jr nz,failed
    ld de,buffer
    ld c,26
    call 5
    ld de,output_fcb
    ld c,21
    call 5
    or a
    jr nz,failed
    ld de,output_fcb
    ld c,16
    call 5
    cp 0xff
    jr z,failed
    ld hl,(remaining)
    dec hl
    ld (remaining),hl
    ld a,h
    or l
    jr nz,again
    ld de,output_fcb
    ld c,19
    call 5
    cp 0xff
    jr z,failed
    ld a,0xa5
    jr done
failed:
    ld a,0xee
done:
    ld (0x9000),a
    halt
    jr done
remaining: dw 2000
fcb: db 1,'HELLO   COM'
    defs 24,0
output_fcb: db 1,'IRQTYPE DAT'
    defs 24,0
buffer: defs 128,0x5a
