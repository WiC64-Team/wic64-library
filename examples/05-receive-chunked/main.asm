bitmap     = $2000
screen     = $0400
color      = $d800
background = $d021

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.asm"

main:
    ; sync to top
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

    ; bitmap mode on
    lda $d011
    ora #$20
    sta $d011

    ; multicolor on
    lda $d016
    ora #$10
    sta $d016

    ; screen offset $0400
    ; bitmap offset $2000
    lda #$18
    sta $d018

    +wic64_initialize
    +wic64_branch_on_timeout handle_timeout

    +wic64_send koala_request

    +wic64_receive_response_header
    +wic64_receive load_address, 2
    +wic64_receive bitmap, 8000
    +wic64_receive screen, 1000
    +wic64_receive color, 1000
    +wic64_receive background

    +wic64_finalize

    ; sync to top
-   lda $d012
    bne -
    bit $d011
    bmi -

    ; screen on
    lda $d011
    ora #$10
    sta $d011

    jmp *

handle_timeout:
    lda #$02
    sta $d020
    jmp *

koala_request:
!text "W", koala_request_url_end - koala_request_url + 4, $00, $01

koala_request_url:
!text "http://x.wic64.net/koa/0770.koa"
koala_request_url_end:

load_address: !word $0000