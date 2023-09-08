chrout = $ffd2
strout = $ab1e

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_return_to_portal = 1
!src "wic64.asm"

main:
    jsr just_make_it_look_nice

    ; this should simply load the portal program from wic64.net
    ; and run it:
    +wic64_return_to_portal

    ; If we end up here, something has gone wrong.
    ; The server might be down or busy in this case.
    ; You might try again for a few times and then give
    ; up and advise the user to try again later.
    ; Here we'll just report the error and exit.
    lda #$05
    sta $0286

    lda #<error_message
    ldy #>error_message
    jsr strout
    rts

error_message: !text "?PORTAL LOAD ERROR", 0

just_make_it_look_nice
    ; TODO: move this to the portal startup code
    sei

    ; sync to screen
-   lda $d012
    bne -
    bit $d011
    bmi -

    ; screen off
    lda $d011
    and #!$10
    sta $d011

    ; all black
    lda #$00
    sta $d020
    sta $d021
    sta $0286

    ; clear screen
    lda #$93
    jsr chrout

    ; screen back on
    lda $d011
    ora #$10
    sta $d011

    cli
    rts
