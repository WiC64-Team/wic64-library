* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.h"
!src "wic64.asm"

bitmap  = $2000
screen  = $0400
color   = $d800
bgcolor = $d021

main:
    ; first display the embedded koala image
    jsr screen_off
    jsr bitmap_mode
    jsr display_embedded_koala
    jsr screen_on

    +wic64_initialize
    +wic64_set_timeout_handler handle_timeout

    ; then send the image data from the relevant memory areas
    ; in a single echo request
    +wic64_send_header echo_request
    +wic64_send bitmap, 8000
    +wic64_send screen, 1000
    +wic64_send color, 1000
    +wic64_send bgcolor

    jsr delete_koala_from_memory

    ; receive the image data again and transfer it back
    ; to the relevant memory areas
    +wic64_receive_header
    +wic64_receive bitmap, 8000
    +wic64_receive screen, 1000
    +wic64_receive color, 1000
    +wic64_receive bgcolor

    +wic64_finalize
    +wic64_unset_timeout_handler

    ; the image should now be displayed again
    jmp *

echo_request: !byte "R", WIC64_ECHO, <10000, >10000

handle_timeout:
    lda #$02
    sta $d020
    jmp *

sync_to_top:
-   lda $d012
    bne -
    bit $d011
    bmi -
    rts

screen_off:
    jsr sync_to_top
    lda $d011
    and #!$10
    sta $d011
    rts

screen_on:
    jsr sync_to_top
    lda $d011
    ora #$10
    sta $d011
    rts

bitmap_mode:
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

    rts

display_embedded_koala:
    ; copy embedded data to screen, color ram
    ; and set background color
    ldx #$0

-   lda embedded_screen_data,x
    sta $0400,x
    lda embedded_screen_data+$0100,x
    sta $0500,x
    lda embedded_screen_data+$0200,x
    sta $0600,x
    lda embedded_screen_data+$02e8,x
    sta $06e8,x

    lda embedded_color_data,x
    sta $d800,x
    lda embedded_color_data+$0100,x
    sta $d900,x
    lda embedded_color_data+$0200,x
    sta $da00,x
    lda embedded_color_data+$02e8,x
    sta $dae8,x

    inx
    bne -

    lda embedded_bgcolor
    sta $d021
    rts

delete_koala_from_memory:
    ptr = $50

!macro fill_pages .addr, .pages, .value {
    lda #<.addr
    sta ptr
    lda #>.addr
    sta ptr+1

    inx
    ldx #.pages
    ldy #$00
    lda #.value

-   sta (ptr),y
    dey
    bne -
    inc ptr+1
    dex
    bne -
}

    +fill_pages bitmap, $20, $00
    +fill_pages screen, $04, $20
    +fill_pages color, $04, $00
    lda #$00
    sta $d020
    rts

* = $2000
embedded_bitmap_data:
!bin "picture.koa", 8000, 2

embedded_screen_data:
!bin "picture.koa", 1000, 2+8000

embedded_color_data:
!bin "picture.koa", 1000, 2+8000+1000

embedded_bgcolor:
!bin "picture.koa", 1, 2+8000+1000+1000