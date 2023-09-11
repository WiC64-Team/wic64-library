!zone wic64 {

;*********************************************************
; Assembly time options
;
; Define the symbols in the following section before
; including this file to change the defaults.
;*********************************************************

!ifndef wic64_request_pointer {
    wic64_request_pointer = $22
}

!ifndef wic64_response_pointer {
    wic64_response_pointer = $24
}

!ifndef wic64_optimize_for_size {
    wic64_optimize_for_size = 0
}

!ifndef wic64_include_return_to_portal {
    wic64_include_return_to_portal = 0
}

!ifndef wic64_include_load_and_run {
    !if (wic64_include_return_to_portal != 0) {
        wic64_include_load_and_run = 1
    }
}

!ifndef wic64_include_load_and_run {
    wic64_include_load_and_run = 0
}

!ifndef wic64_optimize_for_size {
    wic64_optimize_for_size = 0
}

;*********************************************************
; Runtime options
;
; Set the following memory locations to control runtime
; behaviour.
;*********************************************************

; wic64_timeout
;
; This value defines the time to wait for a handshake.
;
; Note that this includes waiting for the WiC64 to process
; the request before sending a response, so this value
; may need to be adjusted, e.g. when a HTTP request is sent
; to a server that is slow to respond.
;
; The enforced minimum value is $01, which corresponds to
; a timeout of approximately one second.
;
; If a timeout occurs, the carry flag will be set to signal
; a timeout to the calling routine.
;
; Higher values will increase the timeout in a non-linear
; fashion.

wic64_timeout !byte $02

; wic64_dont_disable_irqs
;
; Set to a nonzero value to prevent disabling of
; interrupts during transfers.
;
; Note that the interrupt flag will always be reset
; to its previous state after a transfer has completed.
;
; This option merely prevents setting the interrupt
; flag *during* transfers.
;
; The default is to disable irqs during transfer.
;
wic64_dont_disable_irqs !byte $00

; ********************************************************
; Globals
; ********************************************************
wic64_transfer_size !word $0000

; these label should be local, but unfortunately acmes
; limited scoping requires these labels to be global
wic64_counters !byte $00, $00, $00
wic64_user_timeout_handler !word $0000

; ********************************************************
; Locals
; ********************************************************
.user_irq_flag: !byte $00

; ********************************************************
; Define macro .wait_for_handshake
; ********************************************************
;
; If wic64_optimize_for_size is set to a nonzero value,
; a subroutine will be defined using the code defined
; in wic64_wait_for_handshake_code and the macro will
; be defined to simply call this subroutine.
;
; Otherwise the macro will contain the code directly.
;
; Note that optimizing for size will significantly decrease
; transfer speed by about 30% due to the jsr/rts overhead
; added for every byte transferred.

!macro wic64_wait_for_handshake_code {
    ; wait until a handshake has been received from the ESP,
    ; e.g. the FLAG2 line on the userport has been asserted,
    ; with sets bit 4 of $dd0d. Set the carry flag to indicate
    ; a timeout if the timeout length specified in wic64_timeout
    ; has been exceeded.

    ; do a first cheap test for FLAG2 before wasting cycles
    ; setting up the counters.
    lda #$10
    bit $dd0d
    !if (wic64_optimize_for_size == 0) {
        bne .success
    } else {
        beq +
        rts
    }

    ; no fast response, setup timeout delay loop
+   lda #$00
    sta wic64_counters+0
    lda wic64_timeout
    sta wic64_counters+1
    sta wic64_counters+2
    cmp #$01
    bne +
    lda #$48
    sta wic64_counters+1

+   ; keep testing for FLAG2 until all counters are zero
    lda #$10
.wait
    bit $dd0d
    !if (wic64_optimize_for_size == 0) {
        bne .success
    } else {
        beq +
        rts
    }

+   dec wic64_counters+0
    bne .wait

    dec wic64_counters+1
    bne .wait

    dec wic64_counters+2
    bne .wait

.timeout
    jmp wic64_handle_timeout

.success
}

; ********************************************************

!if (wic64_optimize_for_size == 0) {
    !macro .wait_for_handshake {
        +wic64_wait_for_handshake_code
    }
} else {
    wic64_wait_for_handshake_routine !zone {
        +wic64_wait_for_handshake_code
        ; rts is done from macro code
    }

    !macro .wait_for_handshake {
        jsr wic64_wait_for_handshake_routine
    }
}

; ********************************************************

!macro wic64_branch_on_timeout .addr {
    lda #<.addr
    sta wic64_user_timeout_handler
    lda #>.addr
    sta wic64_user_timeout_handler+1
}

; ********************************************************

!macro wic64_prepare_transfer_of_remaining_bytes {
    jsr wic64_prepare_transfer_of_remaining_bytes
}

wic64_prepare_transfer_of_remaining_bytes:
    lda wic64_transfer_size
    sta wic64_bytes_to_transfer
    lda wic64_transfer_size+1
    sta wic64_bytes_to_transfer+1
    rts

!macro wic64_update_transfer_size_after_transfer {
    jsr wic64_update_transfer_size_after_transfer
}

wic64_update_transfer_size_after_transfer: !zone {
    lda wic64_transfer_size
    sec
    sbc wic64_bytes_to_transfer
    sta wic64_transfer_size

    lda wic64_transfer_size+1
    sbc wic64_bytes_to_transfer+1
    sta wic64_transfer_size+1
    bcs .done

    lda #$00
    sta wic64_transfer_size
    sta wic64_transfer_size+1
.done
    clc
    rts
}

; ********************************************************

!macro wic64_initialize {
    jsr wic64_initialize
}

wic64_initialize
    ; always start with a cleared FLAG2 bit in $dd0d
    lda $dd0d

    ; make sure timeout is at least $02
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

+   ; set pa2 to output
    lda $dd02
	ora #$04
	sta $dd02

    clc ; carry will be set if transfer times out
    rts

; ********************************************************

!macro wic64_send_header {
    ; request must be set beforehand
    jsr wic64_send_header
}

!macro wic64_send_header .request {
    +wic64_set_request .request
    jsr wic64_send_header
}

wic64_send_header
    ; ask esp to switch to input
    lda $dd00
    ora #$04
    sta $dd00

    ; switch userport to output
    lda #$ff
    sta $dd03

    ; get request size, which is the size of the complete
    ; request, including the request header

    ldy #$01
    lda (wic64_request_pointer),y
    sta wic64_transfer_size

    iny
    lda (wic64_request_pointer),y
    sta wic64_transfer_size+1

    ; transfer header only
    lda #$04
    sta wic64_bytes_to_transfer
    lda #$00
    sta wic64_bytes_to_transfer+1

    jsr wic64_send

    ; advance request pointer beyond header
    lda wic64_request_pointer
    clc
    adc #$04
    sta wic64_request_pointer
    lda wic64_request_pointer+1
    adc #$00
    sta wic64_request_pointer+1
    clc

    rts

; ********************************************************

!macro wic64_send {
    ; request must be set beforehand
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_send
}

!macro wic64_send .request {
    +wic64_set_request .request
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_send
}

!macro wic64_send .request, .size {
    +wic64_set_request .request

    lda #<.size
    sta wic64_bytes_to_transfer
    lda #>.size+1
    sta wic64_bytes_to_transfer+1

    jsr wic64_send
}

wic64_send
    ldx wic64_bytes_to_transfer+1
    beq .send_remaining_bytes

.send_pages
    ldy #$00
-   lda (wic64_request_pointer),y
    sta $dd01
    +.wait_for_handshake

    iny
    bne -

    inc wic64_request_pointer+1
    dex
    bne -

.send_remaining_bytes
    ldx wic64_bytes_to_transfer
    beq .send_done

    ldy #$00
-   lda (wic64_request_pointer),y
    sta $dd01
    +.wait_for_handshake

    iny
    dex
    bne -

.send_done
    +wic64_update_transfer_size_after_transfer
    rts

; ********************************************************

!macro wic64_receive_header {
    jsr wic64_receive_header
}

wic64_receive_header:
    ; switch userport to input
    lda #$00
    sta $dd03

    ; ask esp to switch to output by pulling PA2 low
    lda $dd00
    and #!$04
    sta $dd00

    ; esp now sends a handshake to confirm change of direction
    +.wait_for_handshake

    ; esp now expects a handshake (accessing $dd01 asserts PC2 line)
    lda $dd01

    ; response size is sent in big-endian for unknown reasons
    +.wait_for_handshake
    lda $dd01
    sta wic64_transfer_size+1
    sta wic64_bytes_to_transfer+1

    +.wait_for_handshake
    lda $dd01
    sta wic64_transfer_size
    sta wic64_bytes_to_transfer

    rts

; ********************************************************

!macro wic64_receive {
    ; response must be set beforehand
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_receive
}

!macro wic64_receive .response {
    +wic64_set_response .response
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_receive
}

!macro wic64_receive .response, .size {
    +wic64_set_response .response

    lda #<.size
    sta wic64_bytes_to_transfer
    lda #>.size+1
    sta wic64_bytes_to_transfer+1

    jsr wic64_receive
}

wic64_receive
    ldx wic64_bytes_to_transfer+1
    beq .receive_remaining_bytes

.receive_pages
    ldy #$00

-   +.wait_for_handshake
    lda $dd01
    sta (wic64_response_pointer),y
    iny
    bne -

    inc wic64_response_pointer+1
    dex
    bne -

.receive_remaining_bytes
    ldx wic64_bytes_to_transfer
    beq .receive_done

    ldy #$00
-   +.wait_for_handshake
    lda $dd01
    sta (wic64_response_pointer),y

    iny
    dex
    bne -

.receive_done
    +wic64_update_transfer_size_after_transfer
    rts

wic64_bytes_to_transfer !word $0000

; ********************************************************

!macro wic64_finalize {
    jsr wic64_finalize
}

wic64_finalize
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

; ********************************************************

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

.timeout_handler !word $0000

; ********************************************************
; wic64_execute
; ********************************************************

!macro wic64_set_request .request {
    lda #<.request
    sta wic64_request_pointer
    lda #>.request
    sta wic64_request_pointer+1
}

!macro wic64_set_response .response {
    lda #<.response
    sta wic64_response_pointer
    lda #>.response
    sta wic64_response_pointer+1
}

!macro wic64_execute .request, .response {
    +wic64_execute .request, .response, $02
}

!macro wic64_execute .request, .response, .timeout {
    +wic64_set_request .request
    +wic64_set_response .response

    lda #.timeout
    sta wic64_timeout

    jsr wic64_execute
}

wic64_execute
    +wic64_initialize
    +wic64_branch_on_timeout +
    +wic64_send_header
    +wic64_send
    +wic64_receive_header
    +wic64_receive
    +wic64_finalize
+   rts

; ********************************************************
; wic64_load_and_run
; ********************************************************

!if (wic64_include_load_and_run != 0) {

!macro wic64_load_and_run .request {
    +wic64_load_and_run .request, $02
}

!macro wic64_load_and_run .request, .timeout {
    +wic64_set_request .request

    lda #.timeout
    sta wic64_timeout

    jsr wic64_load_and_run
}

wic64_load_and_run:
    sei

    lda #$00
    sta wic64_dont_disable_irqs

    +wic64_initialize
    +wic64_branch_on_timeout +
    +wic64_send_header
    +wic64_send
    +wic64_receive_header
    jmp .check_response_size

.check_response_size
    ; if the response size is 2 bytes or less,
    ; we can assume that an error has occured,
    ; e.g. a 404, server was busy, or the
    ; requested command did not return data, etc.
    lda wic64_transfer_size+1
    bne .ready_to_receive

    lda #$02
    cmp wic64_transfer_size
    bcc .ready_to_receive

.server_error
    ; we still adhere to protocol and finish the transfer
    ; by receiving the response to the tape buffer
    lda #<.tapebuffer
    sta wic64_response_pointer
    lda #>.tapebuffer
    sta wic64_response_pointer+1

    jsr wic64_receive

   sec ; indicate error to caller
+  rts

.ready_to_receive
    ; receive and discard load address...
    +.wait_for_handshake
    lda $dd01

    +.wait_for_handshake
    lda $dd01

    ; now it would be correct to subtract two bytes
    ; from the response size reported by the firmware,
    ; since we have already read the two load address
    ; bytes. unfortunately, the original firmware contains
    ; a hack that already substracts two from the reported
    ; response size if a url ends in ".prg"...

    ; always load to $0801
    +wic64_set_response $0801

    ; copy receive-and-run-routine to tape buffer
    ldx #$00
-   lda .receive_and_run,x
    sta .tapebuffer,x
    inx
    cpx #.receive_and_run_size
    bne -

    ; transfer response size to tapebuffer location
    lda wic64_transfer_size
    sta .response_size
    lda wic64_transfer_size+1
    sta .response_size+1

    jmp .tapebuffer

; ********************************************************

.tapebuffer = $0334
.basic_end_pointer = $2d
.basic_reset_program_pointer = $a68e
.kernal_init_io = $fda3
.kernal_reset_vectors = $ff8a
.basic_perform_run = $a7ae

.receive_and_run
!pseudopc .tapebuffer {
    ldx .response_size+1
    beq ++

    ldy #$00
-   lda $dd0d
    and #$10
    beq -
    lda $dd01
    sta (wic64_response_pointer),y
    iny
    bne -

    inc wic64_response_pointer+1
    dex
    bne -

++  ldx .response_size
    beq ++

    ldy #$00
-   lda $dd0d
    and #$10
    beq -
    lda $dd01
    sta (wic64_response_pointer),y

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

; ********************************************************
; wic64_return_to_portal
; ********************************************************

!if (wic64_include_return_to_portal != 0) {

!macro wic64_return_to_portal {
    jsr wic64_return_to_portal
}

wic64_return_to_portal: !zone wic64_return_to_portal {
    ; if the portal loads sucessfully, this routine
    ; never returns. This if it returns, something went
    ; wrong (e.g. no network, server busy, etc)

    ; retry at most 16 times
    lda #$10
    sta .retries

-   +wic64_load_and_run .portal

    ; failed to load portal, keep trying...
    dec .retries
    bne -

    ; max number of retries reached, return and let
    ; the caller handle this further
    rts

    .retries: !byte $00

    .portal:
    !text "W", .portal_url_end - .portal_url + 4, $00, $01
    .portal_url:
    !text "http://x.wic64.net/menue.prg"
    .portal_url_end:
}

} ; end of !if wic64_include_return_to_portal != 0

; ********************************************************

} ; end of !if wic64_include_load_and_run != 0

; ********************************************************

!ifdef wic64_debug {
    !if (wic64_debug != 0) {
        !warn "wic64_request_pointer = ", wic64_request_pointer
        !warn "wic64_response_pointer = ", wic64_response_pointer
        !warn "wic64_include_load_and_run = ", wic64_include_load_and_run
        !warn "wic64_include_return_to_portal = ", wic64_include_return_to_portal
        !warn "wic64_optimize_for_size = ", wic64_optimize_for_size
        !if (wic64_include_load_and_run != 0) {
            !warn "Tapebuffer code is ", .receive_and_run_size, " bytes"
        }
    }
}

} ; end of !zone WiC64