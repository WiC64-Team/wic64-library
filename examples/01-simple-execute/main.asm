* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.h"
!src "wic64.asm"
!src "macros.asm"

main:
    +wic64_execute get_ip, ip
    bcs timeout
    bne error

    +print ip
    +print newline
    rts

timeout:
    +print newline
    +print timeout_error
    rts

error:
    +wic64_execute status_request, response
    bcs timeout

    +print newline
    +print response
    rts

get_ip: !byte "R", WIC64_GET_IP, $00, $00
ip: !fill 32, $00

newline: !byte $0d, $00
timeout_error: !pet "?timeout error", $00

status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01
response: