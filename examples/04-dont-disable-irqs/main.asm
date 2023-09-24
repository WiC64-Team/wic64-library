blank_screen = 1

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

; include wic64 lib
!src "wic64.h"
!src "wic64.asm"

; include sidfile, skipping header data
* = $1000
!bin "music.sid",,$7e

main:
    jsr play_music_in_irq

    ; wait for initial key release
-   jsr $ffe4
    cmp #$00
    bne -

loop:
    ; any key except runstop executes
-   jsr $ffe4
    cmp #$00
    beq -
    cmp #$03
    beq -

    ; purple border during transfer
    lda #$04
    sta $d020

    ; turn off screen
    lda $d011
    and #!$10
    sta $d011

    ; don't disable irqs during transfers
    +wic64_dont_disable_irqs

    ; execute simple echo command
    +wic64_execute request, response

    ; turn screen back on
    lda $d011
    ora #$10
    sta $d011

    bcc success

failure:
    ; red border
    lda #$02
    sta $d020
    jmp loop

success:
    ; green border
    lda #$05
    sta $d020
    jmp loop

play_music_in_irq:
    sei

    ; stop all cia interrupts
    lda #$7f
    sta $dc0d
    sta $dd0d

    ; clear cia interrupt flags
    lda $dc0d
    lda $dd0d

    ; setup irq vector
    lda #<irq
    sta $0314
    lda #>irq
    sta $0315

    ; setup rasterline $018
    lda #$18
    sta $d012

    lda $d011
    and #$7f
    sta $d011

    ; enable raster irq
    lda $d01a
    ora #$01
    sta $d01a

    ; init sid player
    lda #$00
    tax
    tay
    jsr $1000

    cli
    rts

irq:
    ; play sid
    inc $d020
    jsr $1003
    dec $d020

    ; ack irq
    lda #$ff
    sta $d019

    jmp $ea31

; simply send and receive 32k of data using the echo command
request: !byte 'W', $04, $80, $fe

response:
