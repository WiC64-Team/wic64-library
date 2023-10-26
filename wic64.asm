;---------------------------------------------------------
; Wic64 library (C)2023 WiC64-Team
;---------------------------------------------------------
; Written in Acme cross assembler
;
; Please read the documentation if you want to know how to
; use this library. This file contains mostly technical
; comments.

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
    +wic64_set_zeropage_pointer_from wic64_request

.wic64_send_critical_begin:

.send_pages
    ldx wic64_bytes_to_transfer+1
    beq .send_remaining_bytes
    ldy #$00

-   lda (wic64_zeropage_pointer),y
    sta $dd01
    +wic64_wait_for_handshake

    iny
    bne -

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

.wic64_send_critical_end:

.send_done
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

    ; assume standard protocol
    lda #$04
    sta wic64_request_header_size
    lda #$03
    sta wic64_response_header_size

    +wic64_set_zeropage_pointer_from wic64_request

    ; read protocol byte (first byte)
    ldy #$00
    lda (wic64_zeropage_pointer),y
    sta .protocol

    cmp #"E"
    bne +

    ; extended protocol
    lda #$06
    sta wic64_request_header_size
    lda #$05
    sta wic64_response_header_size

    ; read payload size (third and fourth byte)
+   ldy #$02
    lda (wic64_zeropage_pointer),y
    sta wic64_transfer_size

    iny
    lda (wic64_zeropage_pointer),y
    sta wic64_transfer_size+1

.send_header:
    ldy #$00
-   lda (wic64_zeropage_pointer),y
    sta $dd01
    +wic64_wait_for_handshake
    iny
    cpy wic64_request_header_size
    bne -

.advance_pointer_beyond_header:
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

    ; ask esp to switch to output by pulling PA2 low
    lda $dd00
    and #!$04
    sta $dd00

    ; esp now sends a handshake to confirm change of direction
    +wic64_wait_for_handshake

    ; esp now expects a handshake (accessing $dd01 asserts PC2 line)
    lda $dd01

    ; receive response header (3 bytes: <status> <size-low> <size-high>)
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

    clc
    lda wic64_status
    rts

;---------------------------------------------------------

wic64_receive: ; EXPORT
    +wic64_set_zeropage_pointer_from wic64_response

.wic64_receive_critical_begin:

.receive_pages:
    ldx wic64_bytes_to_transfer+1
    beq .receive_remaining_bytes
    ldy #$00

-   +wic64_wait_for_handshake
    lda $dd01
    sta (wic64_zeropage_pointer),y
    iny
    bne -

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

.wic64_receive_critical_end:

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

    ; reset to user timeout
    lda wic64_configured_timeout
    sta wic64_timeout

    ; restore user interrupt flag and rts
    lda .user_irq_flag
    beq +

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
; wic64_detect
;---------------------------------------------------------

wic64_detect: !zone wic64_detect { ; EXPORT

    ; Detects whether a Wic64 is present at all and also tests if the firmware
    ; is of version 2.0.0 or greater.

    ; If no wic is present, the carry flag will be set
    ; If it is a legacy version, the zero flag will be cleared

    ; Both current and legacy firmware implement get_version_string ($00) and
    ; both support the legacy command format ("W"). Even though this library
    ; does no longer support the legacy format by design, it does not check the
    ; magic byte before sending a command either. Since the library expects the
    ; payload size to be specified in the third and fourth byte (as opposed to
    ; the second and third byte in the legacy format), it is still able to
    ; correctly send this legacy command ("W", 4, 0, 0) with a zero payload
    ; size.
    ;
    ; The last few legacy firmware versions send the version as "WIC64FMV:nnnn",
    ; so the response size is always 13 bytes. Legacy versions that don't yet
    ; support this command send "Command error." instead, which is 14 bytes
    ; ($0e).
    ;
    ; For stable versions, the new firmware sends a string that is at least 6
    ; bytes long, but never no longer than 12 bytes in size, even if we we're to
    ; use something like "123.234.345\0". For unstable versions, the response is
    ; always 17 bytes or longer, e.g. the shortest possible string is something
    ; like "2.0.0-3-12345678\0".
    ;
    ; Thus if the reponse is either 13 or 14 bytes long, we can safely assume
    ; that it is a legacy firmware that send the response.
    ;
    ; For commands in legacy format, both fimware generations send the response
    ; size in big-endian byte order. Although This library always expects
    ; little-endian, it also receives the header to .response_header, where the
    ; first byte is the wic64_status and the second byte is the low byte of
    ; wic64_response_size, so the high byte will end up in wic64_status and the
    ; low byte will still end up in wic64_response_size. For this command,
    ; wic64_response_header_size will be adjusted in order to receive only two
    ; header bytes.

    ; first make sure wic64_response_size is not #$0d or $0e by accident
    lda #$55
    sta wic64_response_size

    +wic64_initialize

    +wic64_send_header .request
    bcs .return

    +wic64_send
    bcs .return

    ; receive only two header bytes this time
    dec wic64_response_header_size
    +wic64_receive_header
    inc wic64_response_header_size

    bcs .return

    lda wic64_response_size

    cmp #$0d
    beq .legacy_firmware ; has send "WIC64FWV:nnnn" (13 bytes)

    cmp #$0e
    beq .legacy_firmware ; has send "Command error." (14 bytes)

.new_firmware:
    ; We still need to complete the transfer session to make sure the firmware
    ; is in a valid state again and can accept the next request. We'll simply
    ; send the appropriate amount of handshakes and ignore the response data, as
    ; this avoids having to reserve memory to store the response. Since the
    ; reponse size never exceeds 30 bytes, the loop can be kept simple. A slight
    ; delay between handshakes is required, though.

    ldy wic64_response_size
--  lda $dd01
    ldx #$00
-   dex
    bne -
    dey
    bne --

    lda #$00
    sta wic64_status

    +wic64_finalize ; zero flag set => new firmware
    clc             ; carry clear => device present

.return:
    rts

.legacy_firmware:
    lda #$01
    sta wic64_status

    +wic64_finalize ; zero flag clear => legacy firmware
    clc             ; carry clear => device present
    rts

.request: !byte "W", $04, $00, $00
}

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

.check_server_error:
    beq .ready_to_receive

.server_error:
    ; adhere to protocol and finish the transfer
    ; by receiving the response to the tape buffer
    +wic64_set_zeropage_pointer_to .tapebuffer

    jsr wic64_receive
    ; we don't care if this times out or not

    clc               ; no timeout occurred in wic64_receive_header
    lda wic64_status  ; return status to user as usual
+   rts

.ready_to_receive:
    ; manually receive and discard the load address
    +wic64_wait_for_handshake
    lda $dd01

    +wic64_wait_for_handshake
    lda $dd01

    ; default to loading to $0801 instead (equivalent to LOAD"PRG",8,0)
    +wic64_set_zeropage_pointer_to $0801

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
    sta (wic64_zeropage_pointer),y
    iny
    bne -

    inc wic64_zeropage_pointer+1
    dex
    bne -

    ; transfer remaining bytes
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

    ; reset stack pointer
    ldx #$ff
    txs

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
; wic64_return_to_portal
;---------------------------------------------------------

!if (wic64_include_return_to_portal != 0) {

wic64_return_to_portal: ; EXPORT
    +wic64_load_and_run .portal_request
    rts

} ; end of !if wic64_include_return_to_portal != 0

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

wic64_configured_timeout !byte $02
wic64_user_timeout_handler: !word $0000
wic64_counters: !byte $00, $00, $00

;---------------------------------------------------------
; Locals
;---------------------------------------------------------

.protocol: !byte $00
.user_irq_flag: !byte $00
.timeout_handler: !word $0000

!if (wic64_include_return_to_portal != 0) {

.portal_request:
!text "R", $01, <.portal_url_size, >.portal_url_size
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

        !warn "wic64_send: critical: ", .wic64_send_critical_begin, " - ", .wic64_send_critical_end
        !if (>.wic64_send_critical_begin != >.wic64_send_critical_end) {
            !warn "!! wic64_send: critical section crosses page boundary !!"
        }

        !warn "wic64_receive: critical: ", .wic64_receive_critical_begin, " - ", .wic64_receive_critical_end
        !if (>.wic64_receive_critical_begin != >.wic64_receive_critical_end) {
            !warn "!! wic64_receive: critical section crosses page boundary !!"
        }

        !warn "wic64_zeropage_pointer = ", wic64_zeropage_pointer
        !warn "wic64_include_load_and_run = ", wic64_include_load_and_run
        !warn "wic64_include_return_to_portal = ", wic64_include_return_to_portal
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