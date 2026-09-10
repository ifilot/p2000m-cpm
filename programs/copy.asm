; COPY source destination -- preserves an existing destination.
; Both arguments are parsed by the CCP into the standard default FCBs.
org 0x100
    ld sp,0x8f00
    ld hl,0x5c
    ld de,source
    ld bc,16
    ldir
    ld hl,0x6c
    ld de,destination
    ld bc,16
    ldir
    ld a,(source+1)
    cp ' '
    jp z,usage
    ld a,(destination+1)
    cp ' '
    jp z,usage
    ld de,source
    ld c,15
    call 5
    cp 0xff
    jp z,error
    ld de,destination
    ld c,15
    call 5
    cp 0xff
    jp nz,exists
    ld de,destination
    ld c,22
    call 5
    cp 0xff
    jp z,error
    ld de,buffer
    ld c,26
    call 5
copy_record:
    ld de,source
    ld c,20
    call 5
    cp 1
    jr z,done
    or a
    jp nz,error
    ld de,destination
    ld c,21
    call 5
    or a
    jp nz,error
    jr copy_record
done:
    ld de,destination
    ld c,16
    call 5
    cp 0xff
    jr z,error
    ld de,success
    jr message
usage:
    ld de,usage_text
    jr message
exists:
    ld de,exists_text
    jr message
error:
    ld de,error_text
message:
    ld c,9
    call 5
    jp 0
usage_text: db 'Usage: COPY A:SOURCE.EXT B:TARGET.EXT',13,10,'$'
exists_text: db 'Destination exists; use ERA first to replace it.',13,10,'$'
error_text: db 'Copy failed; destination may be incomplete.',13,10,'$'
success: db 'Copy complete.',13,10,'$'
source: defs 36,0
destination: defs 36,0
buffer: defs 128,0
