; MORE file -- a sequential, paged viewer for CP/M text files.
; The CCP parses the single filename into the default FCB at 005Ch.
org 0x100

start:
    ld a,(0x5d)
    cp ' '
    jr z,usage
    ld de,0x5c
    ld c,15                  ; OPEN default FCB
    call 5
    cp 0xff
    jr z,not_found
    ld de,buffer
    ld c,26                  ; Set DMA address.
    call 5

next_record:
    ld de,0x5c
    ld c,20                  ; Read sequential record.
    call 5
    or a
    jr nz,done
    ld hl,buffer
    ld (cursor),hl
    ld a,128
    ld (remaining),a

next_byte:
    ld hl,(cursor)
    ld a,(hl)
    inc hl
    ld (cursor),hl
    ld hl,remaining
    dec (hl)
    cp 0x1a                  ; CP/M text EOF.
    jr z,done
    push af
    ld e,a
    ld c,2
    call 5
    pop af
    cp 10                    ; Count LF, not CR.
    jr nz,continue
    ld hl,lines
    inc (hl)
    ld a,(hl)
    cp 20
    jr c,continue
    ld de,prompt_text
    ld c,9
    call 5
    ld c,1                   ; Any key advances; Ctrl-C stops.
    call 5
    cp 3
    jr z,done
    ld de,crlf
    ld c,9
    call 5
    xor a
    ld (lines),a

continue:
    ld a,(remaining)
    or a
    jr nz,next_byte
    jr next_record

done:
    ld de,0x5c
    ld c,16                  ; Close the FCB, even after EOF.
    call 5
    ret

usage:
    ld de,usage_text
    jr report
not_found:
    ld de,missing_text
report:
    ld c,9
    call 5
    ret

usage_text:   db 'Usage: MORE [drive:]FILE.EXT',13,10,'$'
missing_text: db 'MORE: file not found.',13,10,'$'
prompt_text:  db 13,10,'-- More -- press any key (Ctrl-C stops) $'
crlf:         db 13,10,'$'
cursor:       dw 0
remaining:    db 0
lines:        db 0
buffer:       defs 128,0
