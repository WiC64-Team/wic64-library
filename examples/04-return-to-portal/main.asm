* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_return_to_portal = 1
!src "wic64.h"
!src "wic64.asm"
!src "print.asm"

main:
    ; this should simply load the portal program from wic64.net
    ; and run it:
    +wic64_return_to_portal

    ; If we end up here, something has gone wrong...
    bcs timeout
    bne error

timeout:
    +print timeout_error_message
    rts

error:
    +wic64_execute status_request, response
    bcs timeout

    +print status_prefix
    +print response
    rts

timeout_error_message: !pet $0d, "?timeout error", $00
status_prefix: !pet $0d, "?request failed: ", $00

status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01
response: