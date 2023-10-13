* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

!src "wic64.h"
!src "wic64.asm"
!src "print.asm"

main:
    +wic64_execute get_ip, ip
    bcs timed_out

    +print ip
    +print newline
    rts

timed_out:
    +print newline
    +print timeout_error
    rts

get_ip: !byte "R", $06, $00, $00
ip: !fill 32, $00

newline: !byte $0d, $00
timeout_error: !pet "?timeout error", $00
