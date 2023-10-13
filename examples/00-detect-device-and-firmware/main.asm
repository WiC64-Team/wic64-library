* = $0801 ; 10 SYS 2064 ($0810)
!byte $0c, $08, $0a, $00, $9e, $20, $32, $30, $36, $34, $00, $00, $00

*=$0810
jmp main

!src "wic64.h"
!src "wic64.asm"
!src "print.asm"

main:
    +wic64_detect
    bcs device_not_present
    bne legacy_firmware

    +print new_firmware_text
    jmp done

device_not_present:
    +print device_not_present_error
    jmp done

legacy_firmware:
    +print legacy_firmware_text
    jmp done

done:
    rts

device_not_present_error: !pet "?device not present error", $0d, $00
legacy_firmware_text: !pet "legacy firmware detected", $0d, $00
new_firmware_text: !pet "firmware 2.0.0 or later detected", $0d, $00

