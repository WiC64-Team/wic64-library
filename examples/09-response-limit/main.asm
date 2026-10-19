; Tests wic64_set_response_limit: each line shows pass or fail.
;
; 1. An echo of 1000 bytes with a limit of 256 is refused (carry set,
;    wic64_response_size = 1000) and nothing after the buffer is written.
; 2. The next response (an echo of 100 bytes) is stored as usual.
; 3. An "R" response after an "E" response: the "R" header has no upper
;    16 bits of the size, so wic64_response_size+2/+3 still hold those of
;    the "E" response. They are set here as a response over 64kb leaves
;    them; the echo of 100 bytes is still stored.
; 4. An "E" response over 64kb (an HTTP GET of 100kb) is refused and
;    received completely: every byte is counted. Needs internet; without
;    it, the line shows skipped.

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810
jmp main

wic64_include_response_limit = 1

!src "wic64.h"
!src "wic64.asm"
!src "macros.asm"

buffer = $3000
buffer_size = 256
canary = buffer + buffer_size
canary_size = $0400

main:
    +wic64_detect
    bcc +
    +print no_wic64
    rts

+   +wic64_set_response_limit buffer_size

test_refused:
    +print text_refused
    jsr fill_canary
    +wic64_execute echo_1000, buffer
    bcc fail_1
    lda wic64_response_size
    cmp #<1000
    bne fail_1
    lda wic64_response_size+1
    cmp #>1000
    bne fail_1
    jsr canary_intact
    bcs fail_1
    +print pass
    jmp test_next
fail_1:
    +print fail

test_next:
    +print text_next
    jsr echo_100_stored
    bcs fail_2
    +print pass
    jmp test_stale
fail_2:
    +print fail

test_stale:
    +print text_stale
    lda #$01                    ; as an "E" response over 64kb leaves it
    sta wic64_response_size+2
    jsr echo_100_stored
    bcs fail_3
    +print pass
    jmp test_large_e
fail_3:
    +print fail

test_large_e:
    +print text_large_e
    lda #$00
    sta wic64_response_size+2   ; not left over from test 3
    sta wic64_response_size+3
    sta drained
    sta drained+1
    sta drained+2
    lda #$20                    ; count what is received without storing:
    sta wic64_nop_instruction   ; jsr count instead of the three nops
    lda #<count
    sta wic64_nop_instruction+1
    lda #>count
    sta wic64_nop_instruction+2
    +wic64_execute get_100kb, buffer, $10
    php
    lda #wic64_nop              ; the nops again
    sta wic64_nop_instruction
    sta wic64_nop_instruction+1
    sta wic64_nop_instruction+2
    plp
    bcc skipped_4               ; not refused: no internet, an error
    lda wic64_response_size+3   ; size larger than the limit, not a timeout
    bne +
    lda wic64_response_size+2
    beq skipped_4
+   ldx #$02                    ; every byte received
-   lda drained,x
    cmp wic64_response_size,x
    bne fail_4
    dex
    bpl -
    jsr echo_100_stored         ; and the next request works
    bcs fail_4
    +print pass
    rts
fail_4:
    +print fail
    rts
skipped_4:
    +print skipped
    rts

; Returns carry clear if an echo of 100 bytes is stored in the buffer.
echo_100_stored:
    lda #$00
    tax
-   sta buffer,x
    inx
    bne -
    +wic64_execute echo_100, buffer
    bcs ++
    ldx #99
-   lda buffer,x
    cmp #$77
    bne +
    dex
    bpl -
    clc
    rts
+   sec
++  rts

fill_canary:
    ldx #$00
    lda #$aa
-   !for .p, 0, (canary_size >> 8) - 1 {
        sta canary + .p * $100,x
    }
    inx
    bne -
    rts

; Returns carry clear if nothing after the buffer was written.
canary_intact:
    ldx #$00
-   !for .p, 0, (canary_size >> 8) - 1 {
        lda canary + .p * $100,x
        cmp #$aa
        bne +
    }
    inx
    bne -
    clc
    rts
+   sec
    rts

; Counts a byte received; keeps X and Y.
count:
    inc drained
    bne +
    inc drained+1
    bne +
    inc drained+2
+   rts

drained: !byte $00, $00, $00

no_wic64:     !pet "no wic64 found", $0d, $00
text_refused: !pet "1000 bytes, limit 256: ", $00
text_next:    !pet "next response stored: ", $00
text_stale:   !pet "r after e over 64kb:  ", $00
text_large_e: !pet "e over 64kb drained:  ", $00
pass:         !pet "pass", $0d, $00
fail:         !pet "fail", $0d, $00
skipped:      !pet "skipped", $0d, $00

echo_1000: !byte "R", WIC64_ECHO, <1000, >1000
!fill 1000, $55

echo_100: !byte "R", WIC64_ECHO, 100, 0
!fill 100, $77

get_100kb: !byte "E", WIC64_HTTP_GET, <(url_end - url), >(url_end - url), 0, 0
url: !text "http://speedtest.tele2.net/100KB.zip"
url_end:
