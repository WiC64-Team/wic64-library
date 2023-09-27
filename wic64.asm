;---------------------------------------------------------
; Wic64 library (C)2023 WiC64-Team
;---------------------------------------------------------
; Written in Acme cross assembler
;
; Please read the documentation if you want to know how to
; use this library. This file contains mostly technical
; comments.

!zone wic64 {

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
        ; rts is already handled in macro code
    }

    !macro wic64_wait_for_handshake {
        jsr wic64_wait_for_handshake_routine
    }
}

;--------------------------------------------------------
; Data Section
;--------------------------------------------------------

wic64_data_section_start: ; EXPORT

;---------------------------------------------------------
; Globals
;---------------------------------------------------------

wic64_timeout:           !byte $01    ; EXPORT
wic64_dont_disable_irqs: !byte $00    ; EXPORT
wic64_request:           !word $0000  ; EXPORT
wic64_response:          !word $0000  ; EXPORT
wic64_transfer_size:     !word $0000  ; EXPORT
wic64_response_size:     !word $0000  ; EXPORT
wic64_bytes_to_transfer: !word $0000  ; EXPORT

; these label should be local, but unfortunately acmes
; limited scoping requires these labels to be defined
; as global labels:

wic64_counters: !byte $00, $00, $00
wic64_user_timeout_handler: !word $0000

;---------------------------------------------------------
; Locals
;---------------------------------------------------------

.user_irq_flag: !byte $00
.timeout_handler: !word $0000
.dont_update_transfer_size_next_time: !byte $01

!if (wic64_include_return_to_portal != 0) {

.portal_request:
!text "R", $01, .portal_url_end - .portal_url, $00
.portal_url:
!text "http://x.wic64.net/menue.prg"
.portal_url_end:

.portal_retries: !byte $00
}

;--------------------------------------------------------;

wic64_data_section_end: ; EXPORT

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

wic64_prepare_transfer_of_remaining_bytes: ; EXPORT
    lda wic64_transfer_size
    sta wic64_bytes_to_transfer
    lda wic64_transfer_size+1
    sta wic64_bytes_to_transfer+1
    rts

;---------------------------------------------------------

wic64_update_transfer_size_after_transfer: ;EXPORT
    lda .dont_update_transfer_size_next_time
    beq +

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

+   lda #$01
    sta .dont_update_transfer_size_next_time
    clc
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

    ; remember current state of cpu interrupt flag
+   php
    pla
    and #!$04
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

wic64_send_header: ; EXPORT
    ; ask esp to switch to input by setting pa2 high
    lda $dd00
    ora #$04
    sta $dd00

    ; switch userport to output
    lda #$ff
    sta $dd03

    ; read payload size (third and fourth byte)
    +wic64_set_zeropage_pointer_from wic64_request

    ldy #$02
    lda (wic64_zeropage_pointer),y
    sta wic64_transfer_size

    iny
    lda (wic64_zeropage_pointer),y
    sta wic64_transfer_size+1

.send_header:
    lda #$04
    sta wic64_bytes_to_transfer
    lda #$00
    sta wic64_bytes_to_transfer+1

    ; don't substract 4 from payload size
    lda #$00
    sta .dont_update_transfer_size_next_time

+   jsr wic64_send

.advance_zeropage_pointer:
    ; advance pointer beyond header
    lda wic64_zeropage_pointer
    clc
    adc #$04
    sta wic64_zeropage_pointer
    lda wic64_zeropage_pointer+1
    adc #$00
    sta wic64_zeropage_pointer+1

    clc
    rts

;---------------------------------------------------------

wic64_send: ; EXPORT
    ldx wic64_bytes_to_transfer+1
    beq .send_remaining_bytes

.send_pages
    ldy #$00

.wic64_send_critical_begin:

-   lda (wic64_zeropage_pointer),y
    sta $dd01
    +wic64_wait_for_handshake

    iny
    bne -

.wic64_send_critical_end:

    inc wic64_zeropage_pointer+1
    dex
    bne -

.send_remaining_bytes
    ldx wic64_bytes_to_transfer
    beq .send_done

    ldy #$00
-   lda (wic64_zeropage_pointer),y
    sta $dd01
    +wic64_wait_for_handshake

    iny
    dex
    bne -

.send_done
    +wic64_update_transfer_size_after_transfer
    clc
    rts

;---------------------------------------------------------

wic64_receive_header: ; EXPORT
    ; switch userport to input
    lda #$00
    sta $dd03

    ; ask esp to switch to output by pulling PA2 low
    lda $dd00
    and #!$04
    sta $dd00

    ; esp now sends a handshake to confirm change of direction
    +wic64_wait_for_handshake

    ; esp now expects a handshake (accessing $dd01 asserts PC2 line)
    lda $dd01

    ; receive the response size
    +wic64_wait_for_handshake
    lda $dd01
    sta wic64_response_size
    sta wic64_transfer_size
    sta wic64_bytes_to_transfer

    +wic64_wait_for_handshake
    lda $dd01
    sta wic64_response_size+1
    sta wic64_transfer_size+1
    sta wic64_bytes_to_transfer+1

    clc
    rts

;---------------------------------------------------------

wic64_receive: ; EXPORT
    +wic64_set_zeropage_pointer_from wic64_response

    ldx wic64_bytes_to_transfer+1
    beq .receive_remaining_bytes

.receive_pages:
    ldy #$00

.wic64_receive_critical_begin:

-   +wic64_wait_for_handshake
    lda $dd01
    sta (wic64_zeropage_pointer),y
    iny
    bne -

.wic64_receive_critical_end:

    inc wic64_zeropage_pointer+1
    dex
    bne -

.receive_remaining_bytes:
    ldx wic64_bytes_to_transfer
    beq .receive_done

    ldy #$00
-   +wic64_wait_for_handshake
    lda $dd01
    sta (wic64_zeropage_pointer),y

    iny
    dex
    bne -

.receive_done:
    +wic64_update_transfer_size_after_transfer
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

    ; remove user timeout handler
    +wic64_branch_on_timeout $0000

    ; restore user interrupt flag and rts
    lda .user_irq_flag
    beq +

    cli
    rts

+   sei
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

    ; if a timeout handler was installed, jmp to the given
    ; address on the same call stack level as the user code
    ; calling the wic64_* subroutine, else just rts.

    ; save user timeout handler temporarily
    ; (will be unset by wic64_finalize)
    lda wic64_user_timeout_handler
    sta .timeout_handler
    lda wic64_user_timeout_handler+1
    sta .timeout_handler+1

    ; finalize automatically on timeouts
    jsr wic64_finalize

    ; set carry to indicate timeout
    sec

    ; check for user timeout handler != $0000
    lda .timeout_handler
    bne .call_timeout_handler
    lda .timeout_handler+1
    bne .call_timeout_handler

.no_timeout_handler:
    ; the user will have to handle the error manually
    ; after each wic64_* call
    rts

.call_timeout_handler:
    ; discard return address on stack and jump, i.e.
    ; act as if we simply branch inside the users routine
    ; itself (one level up)
    pla
    pla
    jmp (.timeout_handler)

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
; wic64_load_and_run
;---------------------------------------------------------

!if (wic64_include_load_and_run != 0) {

wic64_load_and_run: ; EXPORT
    sei

    lda #$00
    sta wic64_dont_disable_irqs

    +wic64_initialize
    +wic64_send_header
    bcs +

    +wic64_send
    bcs +

    +wic64_receive_header
    bcs +

.check_response_size:
    ; if the response size is 2 bytes or less,
    ; we can assume that an error has occured,
    ; e.g. a 404, server was busy, or the
    ; requested command did not return data, etc.
    lda wic64_transfer_size+1
    bne .ready_to_receive

    lda #$02
    cmp wic64_transfer_size
    bcc .ready_to_receive

.server_error:
    ; we still adhere to protocol and finish the transfer
    ; by receiving the response to the tape buffer
    +wic64_set_zeropage_pointer_to .tapebuffer

    jsr wic64_receive

    sec ; indicate error to caller in any case
+   rts

.ready_to_receive:
    ; receive and discard load address
    +wic64_wait_for_handshake
    lda $dd01

    +wic64_wait_for_handshake
    lda $dd01

    ; default to loading to $0801 instead
    +wic64_set_zeropage_pointer_to $0801

    ; copy receive-and-run-routine to tape buffer
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
    ldx .response_size+1
    beq ++

    ldy #$00
-   lda $dd0d
    and #$10
    beq -
    lda $dd01
    sta (wic64_zeropage_pointer),y
    iny
    bne -

    inc wic64_zeropage_pointer+1
    dex
    bne -

++  ldx .response_size
    beq ++

    ldy #$00
-   lda $dd0d
    and #$10
    beq -
    lda $dd01
    sta (wic64_zeropage_pointer),y

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

    ldx #$ff
    txs

+   jsr .kernal_init_io
    jsr .kernal_reset_vectors
    jsr .basic_reset_program_pointer
    jmp .basic_perform_run

.response_size: !word $0000
} ; end of !pseudopc .tapebuffer

.receive_and_run_end:
.receive_and_run_size = .receive_and_run_end - .receive_and_run

;---------------------------------------------------------
; wic64_return_to_portal
;---------------------------------------------------------

!if (wic64_include_return_to_portal != 0) {

wic64_return_to_portal: ; EXPORT
    ; if the portal loads sucessfully, this routine
    ; never returns. This if it returns, something went
    ; wrong (e.g. no network, server busy, etc)

    ; retry at most 16 times
    lda #$10
    sta .portal_retries

-   +wic64_load_and_run .portal_request

    ; failed to load portal, keep trying...
    dec .portal_retries
    bne -

    ; max number of retries reached, return and let
    ; the caller handle this further
    rts

} ; end of !if wic64_include_return_to_portal != 0

;---------------------------------------------------------

} ; end of !if wic64_include_load_and_run != 0

;---------------------------------------------------------

!if (wic64_use_unused_labels != 0) {
    jsr wic64_execute
    jsr wic64_return_to_portal
}

;---------------------------------------------------------

!ifdef wic64_debug {
    !if (wic64_debug != 0) {
        !if (>.wic64_send_critical_begin != >.wic64_send_critical_end) {
            !warn "wic64_send: critical section crosses page boundary"
            !warn "wic64_send: critical: ", .wic64_send_critical_begin, " - ", .wic64_send_critical_end
        }

        !if (>.wic64_receive_critical_begin != >.wic64_receive_critical_end) {
            !warn "wic64_receive: critical section crosses page boundary"
            !warn "wic64_receive: critical: ", .wic64_receive_critical_begin, " - ", .wic64_receive_critical_end
        }

        !warn "wic64_zeropage_pointer = ", wic64_zeropage_pointer
        !warn "wic64_include_load_and_run = ", wic64_include_load_and_run
        !warn "wic64_include_return_to_portal = ", wic64_include_return_to_portal
        !warn "wic64_optimize_for_size = ", wic64_optimize_for_size

        !if (wic64_include_load_and_run != 0) {
            !warn "Tapebuffer code is ", .receive_and_run_size, " bytes"
        }
    }
}

} ; end of !zone WiC64