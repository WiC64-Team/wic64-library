; include the wic64 header file containing the macro definitions
!source "wic64.h"

; just a simple macro to print a string
!macro print .string {
    lda #<.string
    ldy #>.string
    jsr $ab1e
}

* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

* = $0810

main:
    +wic64_detect                           ; detect wic64 device and firmware
    bcs device_not_present                  ; carry set => wic64 not present or unresponsive
    bne legacy_firmware                     ; zero flag clear => legacy firmware detected

    +wic64_execute request, response        ; send request and receive the response
    bcs timeout                             ; carry set => timeout occurred
    bne error                               ; zero flag clear => error status code in accumulator

    +print response                         ; print the response and exit
    rts

device_not_present:                         ; print appropriate error message...
    +print device_error
    rts

legacy_firmware:
    +print firmware_error
    rts

timeout:
    +print timeout_error
    rts

error:
    ; get the error message of the last request
    +wic64_execute status_request, status_response
    bcs timeout

    +print status_response
    rts

; define request to get the current ip address
request !byte "R", WIC64_GET_IP, $00, $00

; reserve 16 bytes of memory for the response
response: !fill 16, 0

; define the request for the status message
status_request: !byte "R", WIC64_GET_STATUS_MESSAGE, $01, $00, $01

; reserve 40 bytes of memory for the status message
status_response: !fill 40, 0

device_error: !pet "?device not present or unresponsive", $00
firmware_error: !pet "?legacy firmware error", $00
timeout_error: !pet "?timeout error", $00

; include the actual wic64 routines
!source "wic64.asm"