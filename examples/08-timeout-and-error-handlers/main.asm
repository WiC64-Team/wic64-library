* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.h"
!src "wic64.asm"
!src "print.asm"

main:
    +wic64_set_timeout_handler timeout
    +wic64_set_error_handler error

    +wic64_detect
    bcs device_not_present
    bne legacy_firmware

    jsr force_timeout

device_not_present:
    lda #$02
    sta $d020
    rts

legacy_firmware:
    lda #$08
    sta $d020
    rts

force_timeout:
    jsr force_timeout_deeper

force_timeout_deeper:
    +wic64_execute sleep_request, response, $01 ; will always time out

force_error:
    jsr force_error_deeper

force_error_deeper:
    +wic64_execute error_request, response ; will always return error

error:
    +wic64_execute status_request, response
    +print status_response_prefix
    +print response
    +print status_response_postfix
    rts ; will return to direct mode

timeout:
    +print timeout_error_message
    jsr delay
    jmp force_error

delay: !zone delay {
    lda #$0c
    sta .z
--- ldy #$00
--  ldx #$00
-   dex
    bne -
    dey
    bne --
    dec .z
    bne ---
    rts

.z: !byte $00
}

timeout_error_message:
!pet "expected timeout occurred", $0d
!byte $00

status_response_prefix:
!pet "expected error occurred: "
!byte $00

status_response_postfix:
!pet $0d, "program should now exit to direct mode", $0d
!byte $00

status_request: !byte "R", $2a, $01, $00, $01

sleep_request: !byte "R", WIC64_FORCE_TIMEOUT, $01, $00, $02

error_request: !byte "R", WIC64_FORCE_ERROR, $00, $00

response: