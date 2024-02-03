;---------------------------------------------------------
; Wic64 library
; Copyright 2023 Henning Liebenau
;---------------------------------------------------------
; Written in Acme cross assembler
;
; Please read the documentation at
;
; https://github.com/WiC64-Team/wic64-library/blob/master/README.md
;
; This file contains mostly technical comments.

!zone wic64 {
.origin = *

;---------------------------------------------------------
; Define wic64_wait_for_handshake_routine and the
; corresponding macro wic64_wait_for_handshake if optimizing
; for size.
;
; If not optimizing for size, the macro will already be
; defined by wic64.h

!if (wic64_optimize_for_size != 0) {
    wic64_wait_for_handshake_routine !zone {
        +wic64_wait_for_handshake_code
        ; rts is already done from macro code
    }

    !macro wic64_wait_for_handshake {
        jsr wic64_wait_for_handshake_routine
    }
}

;---------------------------------------------------------
; Implementation
;
; The code in this section is organized in a way that the
; critical setions in wic64_send and wic64_receive do not
; cross page boundaries if this library is included on or
; close to a page boundary.
;
; If wic64_debug is set to a non-zero value, a warning
; will be issued during assembly if critical sections
; happen to cross page boundaries.
;---------------------------------------------------------

wic64_send: ; EXPORT
    +wic64_set_source_pointer_from wic64_request
    jsr wic64_limit_bytes_to_transfer_to_remaining_bytes

.wic64_send_critical_begin:

.send_pages
    ldx wic64_bytes_to_transfer+1
    beq .send_remaining_bytes
    ldy #$00
wic64_fetch_instruction_pages = *
wic64_source_pointer_pages = *+1
-   lda $0000,y
    sta $dd01
    +wic64_wait_for_handshake
    iny
    bne -

    ; the following inc instruction will be
    ; replaced with an lda if a custom fetch
    ; instruction is installed
wic64_source_pointer_highbyte_inc = *
    inc wic64_source_pointer_pages+1
    dex
    bne -

.send_remaining_bytes
    ldx wic64_bytes_to_transfer
    beq .send_done

    ; skip copying current source pointer position
    ; if a custom fetch instruction is installed
    lda wic64_fetch_instruction_bytes
    cmp #wic64_lda_abs_y
    bne +

    ; copy the current source pointer position
    ; to the code sending the remaining bytes
    lda wic64_source_pointer_pages
    sta wic64_source_pointer_bytes
    lda wic64_source_pointer_pages+1
    sta wic64_source_pointer_bytes+1

+   ldy #$00
wic64_fetch_instruction_bytes = *
wic64_source_pointer_bytes = *+1
-   lda $0000,y
    sta $dd01
    +wic64_wait_for_handshake
    iny
    dex
    bne -

.wic64_send_critical_end:

.send_done
    +wic64_update_transfer_size_after_transfer
    clc
    rts

;---------------------------------------------------------

wic64_send_header: ; EXPORT
    ; ask esp to switch to input by setting pa2 high
    lda $dd00
    ora #$04
    sta $dd00

    ; switch userport to output
    lda #$ff
    sta $dd03

    ; assume standard protocol header sizes
    lda #$04
    sta wic64_request_header_size
    lda #$03
    sta wic64_response_header_size

    ; copy request header
    lda wic64_request
    sta .request_header_pointer
    lda wic64_request+1
    sta .request_header_pointer+1

    ldy #$05
.request_header_pointer = *+1
-   lda $0000,y
    sta .request_header,y
    dey
    bpl -

    ; read protocol byte (first byte)
    lda .request_header
    sta .protocol

    ; check for extended protocol
    cmp #"E"
    bne +

    ; adjust to extended protocol header sizes
    lda #$06
    sta wic64_request_header_size
    lda #$05
    sta wic64_response_header_size

    ; read payload size (third and fourth byte)
+   lda .request_header+2
    sta wic64_transfer_size

    lda .request_header+3
    sta wic64_transfer_size+1

.send_header:
    ldy #$00
-   lda .request_header,y
    sta $dd01
    +wic64_wait_for_handshake
    iny
    cpy wic64_request_header_size
    bne -

    ; assume the payload immediately follows the
    ; request header in memory
.advance_request_address_beyond_header:
    lda wic64_request
    clc
    adc wic64_request_header_size
    sta wic64_request
    lda wic64_request+1
    adc #$00
    sta wic64_request+1

    clc
    rts

;---------------------------------------------------------

wic64_receive_header: ; EXPORT
    ; switch userport to input
    lda #$00
    sta $dd03

    ; signal readiness to receive by pulling PA2 low
    lda $dd00
    and #!$04
    sta $dd00

    ; esp now sends a handshake to confirm change of direction
    +wic64_wait_for_handshake

    ; esp now expects a handshake (accessing $dd01 asserts PC2 line)
    lda $dd01

    ; receive response header
    ldx #$00
-   +wic64_wait_for_handshake
    lda $dd01
    sta .response_header,x
    inx
    cpx wic64_response_header_size
    bne -

    ; prepare receive
    lda wic64_response_size
    sta wic64_transfer_size
    sta wic64_bytes_to_transfer

    lda wic64_response_size+1
    sta wic64_transfer_size+1
    sta wic64_bytes_to_transfer+1

    ; test if an error condition is reported
    lda wic64_status
    beq .no_error_occurred

    ; skip calling error handler if suspended
    lda wic64_handlers_suspended
    beq .no_error_handler_installed

    ; test if an error handler is installed
    lda wic64_error_handler
    bne .handle_error
    lda wic64_error_handler+1
    bne .handle_error

.no_error_occurred:
.no_error_handler_installed:
    clc
    lda wic64_status
    rts

.handle_error:
    +wic64_finalize
    ldx wic64_error_handler_stackpointer
    txs
    jmp (wic64_error_handler)

;---------------------------------------------------------

wic64_receive: ; EXPORT
    +wic64_set_destination_pointer_from wic64_response
    jsr wic64_limit_bytes_to_transfer_to_remaining_bytes

.wic64_receive_critical_begin:

.receive_pages:
    ldx wic64_bytes_to_transfer+1
    beq .receive_remaining_bytes
    ldy #$00

-   +wic64_wait_for_handshake
    lda $dd01
wic64_store_instruction_pages = *
wic64_destination_pointer_pages = *+1
    sta $0000,y
    iny
    bne -

    ; the following inc instruction will be
    ; replaced with an lda if a custom store
    ; instruction is installed
wic64_destination_pointer_highbyte_inc = *
    inc wic64_destination_pointer_pages+1
    dex
    bne -

.receive_remaining_bytes:
    ldx wic64_bytes_to_transfer
    beq .receive_done

    ; skip copying current destination pointer position
    ; if a custom store instruction is installed
    lda wic64_store_instruction_bytes
    cmp #wic64_sta_abs_y
    bne +

    ; copy the current destination pointer position
    ; to the code receiving the remaining bytes
    lda wic64_destination_pointer_pages
    sta wic64_destination_pointer_bytes
    lda wic64_destination_pointer_pages+1
    sta wic64_destination_pointer_bytes+1

+   ldy #$00
-   +wic64_wait_for_handshake
    lda $dd01
wic64_store_instruction_bytes = *
wic64_destination_pointer_bytes = *+1
    sta $0000,y

    iny
    dex
    bne -

.wic64_receive_critical_end:

.receive_done:
    +wic64_update_transfer_size_after_transfer
    clc
    rts

;---------------------------------------------------------

wic64_prepare_transfer_of_remaining_bytes: ; EXPORT
    lda wic64_transfer_size
    sta wic64_bytes_to_transfer
    lda wic64_transfer_size+1
    sta wic64_bytes_to_transfer+1
    rts

;---------------------------------------------------------

wic64_update_transfer_size_after_transfer: ;EXPORT
    lda wic64_transfer_size
    sec
    sbc wic64_bytes_to_transfer
    sta wic64_transfer_size

    lda wic64_transfer_size+1
    sbc wic64_bytes_to_transfer+1
    sta wic64_transfer_size+1
    bcs +

    lda #$00
    sta wic64_transfer_size
    sta wic64_transfer_size+1

+   clc
    rts

;---------------------------------------------------------

wic64_limit_bytes_to_transfer_to_remaining_bytes:
    lda .protocol
    cmp #"E"
    beq ++

    lda wic64_transfer_size+1
    cmp wic64_bytes_to_transfer+1
    bcc +
    bne ++

    lda wic64_transfer_size
    cmp wic64_bytes_to_transfer
    bcc +
    jmp ++

+   jsr wic64_prepare_transfer_of_remaining_bytes

++  clc
    rts

;---------------------------------------------------------

wic64_initialize: ; EXPORT
    ; always start with a cleared FLAG2 bit in $dd0d
    lda $dd0d

    ; make sure timeout is at least $01
    lda wic64_timeout
    cmp #$01
    bcs +

    lda #$01
    sta wic64_timeout

    ; automatically discard response if requested,
    ; only set if execute is called without response
    ; and no custom store instruction has been set
+   lda wic64_auto_discard_response
    bne +

    +wic64_set_store_instruction wic64_nop_instruction

    ; remember current state of cpu interrupt flag
+   php
    pla
    and #$04
    sta .user_irq_flag

    ; disable irqs during transfers unless the user
    ; chooses otherwise
    lda wic64_dont_disable_irqs
    bne +
    sei

+   ; ensure pa2 is set to output
    lda $dd02
    ora #$04
    sta $dd02

    ; clear carry -- will be set if transfer times out
    clc
    rts

;---------------------------------------------------------

wic64_finalize: ; EXPORT
    ; switch userport back to input - we want to have both sides
    ; in input mode when idle, only switch to output if necessary
    lda #$00
    sta $dd03

    ; always exit with a cleared FLAG2 bit in $dd0d as well
    lda $dd0d

    ; reset to user timeout
    lda wic64_configured_timeout
    sta wic64_timeout

    ; reset store instruction and auto discard setting
    lda wic64_auto_discard_response
    bne +

    +wic64_reset_store_instruction
    lda #$01
    sta wic64_auto_discard_response

    ; restore user interrupt flag and rts
+   lda .user_irq_flag
    bne +

    cli
    jmp .finalize_done

+   sei

.finalize_done:
    lda wic64_status
    rts

;---------------------------------------------------------

wic64_handle_timeout:
    ; call stack when not optimized for size (wait_for_handshake macro)
    ;
    ; - user code
    ;   - wic64_* api subroutine
    ;   - wait_for_handshake macro
    ;
    ; call stack when optimized for size (wait_for_handshake subroutine)
    ;
    ; - user code
    ;   - wic64_* api subroutine
    ;     - wait_for_handshake subroutine
    ;
    ; we need to be able to rts to the user routine, so if the
    ; code is optimized for size, we discard the last return
    ; address on the stack:

    !if (wic64_optimize_for_size != 0) {
        pla
        pla
    }

    ; finalize automatically on timeouts
    jsr wic64_finalize

    ; set carry to indicate timeout
    sec

    lda wic64_handlers_suspended
    beq .no_timeout_handler

    ; check for user timeout handler != $0000
    lda wic64_timeout_handler
    bne .call_timeout_handler
    lda wic64_timeout_handler+1
    bne .call_timeout_handler

.no_timeout_handler:
    ; the user will have to handle the timeout manually
    ; after each wic64_* call
    rts

.call_timeout_handler:
    ; reset stackpointer to the stacklevel
    ; from which the handler was installed
    ldx wic64_timeout_handler_stackpointer
    txs
    jmp (wic64_timeout_handler)

;---------------------------------------------------------
; wic64_execute
;---------------------------------------------------------

wic64_execute: ; EXPORT
    +wic64_initialize
    +wic64_send_header
    bcs +

    +wic64_send
    bcs +

    +wic64_receive_header
    bcs +

    +wic64_receive
    bcs +

    +wic64_finalize
+   rts

;---------------------------------------------------------
; wic64_detect
;---------------------------------------------------------

wic64_detect: !zone wic64_detect { ; EXPORT

    ; Detects whether a Wic64 is present at all and also tests if the firmware
    ; is of version 2.0.0 or greater.

    ; If no wic is present, the carry flag will be set
    ; If it is a legacy version, the zero flag will be cleared

    ; This routine sends a version request using the standard protocol.

    lda #$00
    sta wic64_handlers_suspended

    lda #$01
    sta wic64_timeout

    +wic64_initialize

    ; The legacy firmware will accept all request bytes even if it doesn't
    ; understand them, so if sending the request header times out, no device is
    ; present at all, regardless of which firmware is running.

    +wic64_send_header .request
    bcs .return

    ; Set response size to the distinct value of $55 before receiving response
    ; header. Firmware 2.0.0 will send a response between 6 and 30 bytes, so if
    ; the response size still contains $55 after receiving the response header
    ; we know that a legacy firmware is running.

    lda #$55
    sta wic64_response_size

    +wic64_receive_header
    ; ignore possible timeout from legacy firmware

    lda wic64_response_size
    cmp #$55
    beq .legacy_firmware

.new_firmware:
    ; Simply send the appropriate amount of handshakes and ignore the response
    ; data, as this avoids having to reserve memory to store the response. Since
    ; the response size never exceeds 30 bytes, the loop can be kept simple.

    ; A small delay is required here to give the firmware enough time to
    ; properly reqister each handshake.

    ldy wic64_response_size
-   lda $dd01
    nop
    nop
    dey
    bne -

    lda #$00
    sta wic64_status

    clc               ; carry clear => device present
    jmp .return

.legacy_firmware:
    lda #$01
    sta wic64_status
    clc               ; carry clear => device present

.return:
    +wic64_finalize

    ; resume handlers
    lda #$01
    sta wic64_handlers_suspended

    lda wic64_status  ; zero flag set => new firmware, clear => legacy firmware
    rts

.request: !byte "R", WIC64_GET_VERSION_STRING, $00, $00
}

;---------------------------------------------------------
; wic64_reset_store_instruction
;---------------------------------------------------------

wic64_reset_store_instruction:
    lda #wic64_sta_abs_y
    sta wic64_store_instruction_pages
    sta wic64_store_instruction_bytes

    lda #wic64_inc_abs
    sta wic64_destination_pointer_highbyte_inc
    rts

;---------------------------------------------------------
; wic64_reset_store_instruction
;---------------------------------------------------------

wic64_reset_fetch_instruction:
    lda #wic64_lda_abs_y
    sta wic64_store_instruction_pages
    sta wic64_store_instruction_bytes

    lda #wic64_inc_abs
    sta wic64_destination_pointer_highbyte_inc
    rts

;---------------------------------------------------------
; wic64_load_and_run
;---------------------------------------------------------

!if (wic64_include_load_and_run != 0) {

wic64_load_and_run: ; EXPORT
    +wic64_initialize
    +wic64_send_header
    bcc +
    rts

+   +wic64_send
    bcc +
    rts

+   +wic64_receive_header
    bcc +
    rts

+   beq .ready_to_receive
    rts

.ready_to_receive:
    ; manually receive and discard the load address
    +wic64_wait_for_handshake
    lda $dd01

    +wic64_wait_for_handshake
    lda $dd01

    ; copy .receive_and_run routine to tape buffer
    ldx #$00
-   lda .receive_and_run,x
    sta .tapebuffer,x
    inx
    cpx #.receive_and_run_size
    bne -

    ; substract the two load address bytes we already
    ; received from the response size and store the
    ; result in the corresponding tapebuffer location

    lda wic64_transfer_size
    sec
    sbc #$02
    sta .response_size
    lda wic64_transfer_size+1
    sbc #$00
    sta .response_size+1

    jmp .tapebuffer

;---------------------------------------------------------

.tapebuffer = $0334
.basic_end_pointer = $2d
.basic_reset_program_pointer = $a68e
.kernal_init_io = $fda3
.kernal_reset_vectors = $ff8a
.basic_perform_run = $a7ae

.receive_and_run:
!pseudopc .tapebuffer {

    ; the receiving code does not include timeout detection
    ; due to the size restrictions of the tapebuffer area.
    ; But if we end up here, the ESP is already sending the
    ; response, so it is unlikely that a timeout is going to
    ; occur unless the ESP is reset manually during transfer.
    ;
    ; However, we will still make sure that the user can at
    ; least press runstop/restore if this code gets stuck in
    ; an infinite loop.

    ; bank in kernal
    lda #$37
    sta $01

    ; make sure nmi vector points to default nmi handler
    lda #$47
    sta $0318
    lda #$fe
    sta $0319

    ; transfer pages
    ldx .response_size+1
    beq ++

    ldy #$00
-   lda $dd0d
    and #$10
    beq -
    lda $dd01
.destination_pointer_pages = *+1
    sta $0801,y
    iny
    bne -

    inc .destination_pointer_pages+1
    dex
    bne -

    ; transfer remaining bytes
++  ldx .response_size
    beq ++

    lda .destination_pointer_pages
    sta .destination_pointer_bytes
    lda .destination_pointer_pages+1
    sta .destination_pointer_bytes+1

    ldy #$00
-   lda $dd0d
    and #$10
    beq -
    lda $dd01
.destination_pointer_bytes = *+1
    sta $0000,y
    iny
    dex
    bne -

++  ; adjust basic end pointer
    lda #$01
    sta .basic_end_pointer
    lda #$08
    sta .basic_end_pointer+1

    lda .response_size
    clc
    adc .basic_end_pointer
    sta .basic_end_pointer

    lda .basic_end_pointer+1
    adc .response_size+1
    sta .basic_end_pointer+1

    ; reset stack pointer
    ldx #$ff
    txs

    ; clear keyboard buffer
    lda #$00
    sta $c6

    ; reset system to defaults
+   jsr .kernal_init_io
    jsr .kernal_reset_vectors
    jsr .basic_reset_program_pointer

    ; run program
    jmp .basic_perform_run

.response_size: !word $0000
} ; end of !pseudopc .tapebuffer

.receive_and_run_end:
.receive_and_run_size = .receive_and_run_end - .receive_and_run

;---------------------------------------------------------
; wic64_enter_portal
;---------------------------------------------------------

!if (wic64_include_enter_portal != 0) {

wic64_enter_portal: ; EXPORT
    +wic64_load_and_run .portal_request
    rts

} ; end of !if wic64_include_enter_portal != 0

;---------------------------------------------------------

} ; end of !if wic64_include_load_and_run != 0

;--------------------------------------------------------
; Data Section
;--------------------------------------------------------

wic64_data_section_start: ; EXPORT

;---------------------------------------------------------
; Globals
;---------------------------------------------------------

wic64_timeout:              !byte $02    ; EXPORT
wic64_dont_disable_irqs:    !byte $00    ; EXPORT
wic64_request_header_size:  !byte $04
wic64_response_header_size: !byte $03

wic64_request:           !word $0000     ; EXPORT
wic64_response:          !word $0000     ; EXPORT
wic64_transfer_size:     !word $0000     ; EXPORT
wic64_bytes_to_transfer: !word $0000     ; EXPORT

.response_header:
wic64_status:               !byte $00           ; EXPORT
wic64_response_size:        !word $0000, $0000  ; EXPORT

; these label should be local, but unfortunately acmes
; limited scoping requires these labels to be defined
; as global labels:

wic64_configured_timeout: !byte $02
wic64_timeout_handler: !word $0000
wic64_timeout_handler_stackpointer: !byte $00
wic64_error_handler: !word $0000
wic64_error_handler_stackpointer: !byte $00
wic64_handlers_suspended: !byte $01
wic64_counters: !byte $00, $00, $00
wic64_nop_instruction: !byte $ea, $ea, $ea
wic64_auto_discard_response: !byte $01

;---------------------------------------------------------
; Locals
;---------------------------------------------------------

.protocol: !byte $00
.user_irq_flag: !byte $00
.request_header: !fill 6, 0

!if (wic64_include_enter_portal != 0) {

.portal_request:
!text "R", WIC64_HTTP_GET, <.portal_url_size, >.portal_url_size
.portal_url:
!text "http://x.wic64.net/menue.prg"
.portal_url_end:

.portal_url_size = .portal_url_end - .portal_url
}

;--------------------------------------------------------;

wic64_data_section_end: ; EXPORT

;---------------------------------------------------------

!ifdef wic64_build_report {
    !if (wic64_build_report != 0) {

        !warn "wic64.asm included at origin ", .origin

        !warn "wic64_send: critical section: ", .wic64_send_critical_begin, " - ", .wic64_send_critical_end
        !if (>.wic64_send_critical_begin != >.wic64_send_critical_end) {
            !warn "!! wic64_send: critical section crosses page boundary !!"
        }

        !warn "wic64_receive: critical section: ", .wic64_receive_critical_begin, " - ", .wic64_receive_critical_end
        !if (>.wic64_receive_critical_begin != >.wic64_receive_critical_end) {
            !warn "!! wic64_receive: critical section crosses page boundary !!"
        }

        !warn "wic64_include_load_and_run = ", wic64_include_load_and_run
        !warn "wic64_include_enter_portal = ", wic64_include_enter_portal
        !warn "wic64_optimize_for_size = ", wic64_optimize_for_size

        !if (wic64_include_load_and_run != 0) {
            !warn "wic64 tapebuffer code size is ", .receive_and_run_size, " bytes"
            !if (.receive_and_run_size > 199) {
                !error "wic64 tapebuffer code does not fit into $0334-$03FB (max. 199 bytes)"
            }
        }
    }
}

} ; end of !zone WiC64