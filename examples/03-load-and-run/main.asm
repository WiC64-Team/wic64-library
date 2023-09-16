* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_load_and_run = 1
!src "wic64.asm"

main:
    +wic64_load_and_run gianna
    rts ; should never be reached

gianna:
!text "W", gianna_url_end - gianna_url + 4, $00, $01
gianna_url:
!text "http://x.wic64.net/m64/games-hs/gianasistershs.prg"
gianna_url_end: