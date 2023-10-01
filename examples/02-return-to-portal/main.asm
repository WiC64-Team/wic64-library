chrout = $ffd2
strout = $ab1e

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_return_to_portal = 1
!src "wic64.h"
!src "wic64.asm"

main:
    ; this should simply load the portal program from wic64.net
    ; and run it:
    +wic64_return_to_portal

    ; If we end up here, something has gone wrong.
    ; The server might be down or busy in this case.
    ; You might try again for a few times and then give
    ; up and advise the user to try again later.
    ; Here we'll just report the error and exit.

    lda #<error_message
    ldy #>error_message
    jsr strout
    rts

error_message: !pet "?portal load error", 0