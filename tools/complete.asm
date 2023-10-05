; this file is only needed as a basis to
; run the verification targets and the
; dasm-export target

*=0x1000

wic64_include_return_to_portal = 1
!src <wic64.h>
!src <wic64.asm>

; these symbols must be mentionsne so that they
; are defined in the symbolfile and can be
; included in the dasm-export by export.rb

jsr wic64_execute
jsr wic64_detect
jsr wic64_return_to_portal