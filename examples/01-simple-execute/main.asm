strout = $ab1e

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.h"
!src "wic64.asm"

!macro print .string {
    lda #<.string
    ldy #>.string
    jsr strout
}

main:
    +print newline

    +wic64_execute get_ip, ip
    bcs timeout

    +print ip
    +print newline
    rts

timeout:
    +print timeout_text
    +print newline
    rts

get_ip: !byte "R", $06, $00, $00
ip: !fill 32, $00

newline: !text $0d, $00
timeout_text: !text "?TIMEOUT ERROR", $00
