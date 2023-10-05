*=0x1000
wic64_include_load_and_run = 1
wic64_include_return_to_portal = 1
!src <wic64.h>
!src <wic64.asm>
jsr wic64_execute
jsr wic64_detect
jsr wic64_return_to_portal