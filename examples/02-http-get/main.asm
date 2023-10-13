* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.h"
!src "wic64.asm"
!src "print.asm"

main:
    +wic64_execute http_get_request, response
    bcs timeout
    bne error

success:
    +print response
    rts

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

http_get_request: !byte "R", $01, <payload_size, >payload_size
http_get_payload: !text "http://x.wic64.net/test/message.txt"

payload_size = * - http_get_payload

status_request: !byte "R", $2a, $01, $00, $01

status_prefix: !pet "?request failed: ", $00

response: