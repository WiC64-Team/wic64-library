* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_load_and_run = 1
!src "wic64.h"
!src "wic64.asm"
!src "print.asm"

main:
    +wic64_load_and_run request
    bcs timeout
    bne error

error:
    +wic64_execute status_request, response
    bcs timeout

    +print status_prefix
    +print response
    rts

timeout:
    +print timeout_error_message
    rts

timeout_error_message: !pet "?timeout error", $00

request: !byte "R", $01, <payload_size, >payload_size
payload: !text "http://x.wic64.net/m64/games-hs/gianasistershs.prg"

payload_size = * - payload

status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01

status_prefix: !pet "?request failed: ", $00

response: