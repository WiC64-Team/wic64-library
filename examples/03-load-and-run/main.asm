* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_load_and_run = 1
!src "wic64.h"
!src "wic64.asm"

main:
    +wic64_load_and_run request
    rts ; should never be reached

request: !byte "R", $01, <payload_size, >payload_size
payload: !text "http://x.wic64.net/m64/games-hs/gianasistershs.prg"

payload_size = * - payload