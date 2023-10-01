!zone wic64 {
;---------------------------------------------------------
; Assembly time options
;---------------------------------------------------------
;
; Define the symbols in the following section before
; including this file to change the defaults.


;---------------------------------------------------------
; Specify the first of two consecutive zeropage locations
; that can be safely used by this library

!ifndef wic64_zeropage_pointer {
    wic64_zeropage_pointer = $a6 ; EXPORT
}

;---------------------------------------------------------
; Set to a non-zero value to enable size optimisations
; Optimizing for size will decrease performance

!ifndef wic64_optimize_for_size {
    wic64_optimize_for_size = 0
}

;---------------------------------------------------------
; Set to a non-zero value to include code to return to the
; WiC64 portal.
;
; Using this option implies wic64_include_load_run = 1

!ifndef wic64_include_return_to_portal {
    wic64_include_return_to_portal = 0
}

;---------------------------------------------------------
; Set to a non-zero value to include code to load and run
; programs.
;
; Will be set by default if wic64_include_return_to_portal
; is used

!ifndef wic64_include_load_and_run {
    !if (wic64_include_return_to_portal != 0) {
        wic64_include_load_and_run = 1
    } else {
        wic64_include_load_and_run = 0
    }
}

;---------------------------------------------------------
; Do not change - this option is only used during build

!ifndef wic64_use_unused_labels {
    wic64_use_unused_labels = 0
}

;---------------------------------------------------------
; Runtime options
;---------------------------------------------------------
;
; Set the following memory locations to control runtime
; behaviour.

;---------------------------------------------------------
; wic64_timeout
;
; This value defines the time to wait for a handshake.
;
; Note that this includes waiting for the WiC64 to process
; the request before sending a response, so this value
; may need to be adjusted, e.g. when a HTTP request is sent
; to a server that is slow to respond.
;
; The minimum value is $01, which corresponds to a timeout
; of approximately one second. Setting this value to zero
; sets the value to $01.
;
; If a timeout occurs, the carry flag will be set to signal
; a timeout to the calling routine.
;
; Higher values will increase the timeout in a non-linear
; fashion.

!macro wic64_set_timeout .timeout {
    lda #.timeout
    sta wic64_timeout
}

;---------------------------------------------------------
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

!macro wic64_do_disable_irqs {
    lda #$00
    sta wic64_dont_disable_irqs
}

!macro wic64_dont_disable_irqs {
    lda #$01
    sta wic64_dont_disable_irqs
}

;---------------------------------------------------------
; Setup an address to jump to in case a timeout
; occurs in any of the transfer routines that are called
; during command execution. This address needs to be set up
; before every new request, as it is reset in wic64_finalize.
;
; After a timeout occurs, the current stack level is reset
; to the level from which the transfer routine in which the
; timeout occurred was called, e.g. it will resemble a branch
; instruction.
;
; This is mainly useful if you're using the low level api
; calls, since it avoids having to check for a timeout after
; every single call. See the documentation for details.

!macro wic64_branch_on_timeout .addr {
    lda #<.addr
    sta wic64_user_timeout_handler
    lda #>.addr
    sta wic64_user_timeout_handler+1
}

;---------------------------------------------------------
; set zeropage pointer from specified address

!macro wic64_set_zeropage_pointer_from .addr {
    lda .addr
    sta wic64_zeropage_pointer
    lda .addr+1
    sta wic64_zeropage_pointer+1
}

;---------------------------------------------------------
; set zeropage pointer to the specified address

!macro wic64_set_zeropage_pointer_to .addr {
    lda #<.addr
    sta wic64_zeropage_pointer
    lda #>.addr
    sta wic64_zeropage_pointer+1
}

;---------------------------------------------------------
; Specify the start address of memory area containing the
; request to send to the WiC64

!macro wic64_set_request .request {
    lda #<.request
    sta wic64_request
    lda #>.request
    sta wic64_request+1
}

;---------------------------------------------------------
; Specify the start address of memory area where the
; response from the WiC64 should be stored to

!macro wic64_set_response .response {
    lda #<.response
    sta wic64_response
    lda #>.response
    sta wic64_response+1
}

;---------------------------------------------------------
; Make sure the next call to wic64_send or wic64_receive
; will transfer all bytes not sent or received so far

!macro wic64_prepare_transfer_of_remaining_bytes {
    jsr wic64_prepare_transfer_of_remaining_bytes
}

;---------------------------------------------------------
; Substract the number of bytes transferred in the previous
; call to wic64_send or wic64_receive from the number of
; bytes remaining to be transferred in the currend request
; or response

!macro wic64_update_transfer_size_after_transfer {
    jsr wic64_update_transfer_size_after_transfer
}

;---------------------------------------------------------

!macro wic64_initialize {
    jsr wic64_initialize
}

;---------------------------------------------------------

!macro wic64_send_header {
    ; request must be set beforehand
    jsr wic64_send_header
}

!macro wic64_send_header .request {
    +wic64_set_request .request
    jsr wic64_send_header
}

;---------------------------------------------------------

!macro wic64_send {
    ; request must be set beforehand
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_send
}

;---------------------------------------------------------

!macro wic64_send .request {
    +wic64_set_request .request
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_send
}

!macro wic64_send .request, .size {
    +wic64_set_request .request
    +wic64_set_zeropage_pointer_from wic64_request

    lda #<.size
    sta wic64_bytes_to_transfer
    lda #>.size+1
    sta wic64_bytes_to_transfer+1

    jsr wic64_send
}

;---------------------------------------------------------

!macro wic64_receive_header {
    jsr wic64_receive_header
}

;---------------------------------------------------------

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

;---------------------------------------------------------

!macro wic64_finalize {
    jsr wic64_finalize
}

;---------------------------------------------------------

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

;---------------------------------------------------------

!macro wic64_detect {
    jsr wic64_detect
}

;---------------------------------------------------------

!macro wic64_load_and_run .request {
    +wic64_load_and_run .request, $02
}

!macro wic64_load_and_run .request, .timeout {
    +wic64_set_request .request

    lda #.timeout
    sta wic64_timeout

    jsr wic64_load_and_run
}

!if (wic64_include_return_to_portal != 0) {

!macro wic64_return_to_portal {
    jsr wic64_return_to_portal
}

}

;---------------------------------------------------------
; Define macro wic64_wait_for_handshake
;---------------------------------------------------------
;
; If wic64_optimize_for_size is set to a nonzero value,
; a subroutine will be defined using the code defined
; in the macro wic64_wait_for_handshake_code and the
; macro will be defined to simply call this subroutine.
;
; Otherwise the macro will contain the code directly.
;
; Note that optimizing for size will significantly decrease
; transfer speed by about 30% due to the jsr/rts overhead
; added for every byte transferred.
;---------------------------------------------------------

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

+   ; keep testing for FLAG2 until all counters are down to zero
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

!if (wic64_optimize_for_size == 0) {
    !macro wic64_wait_for_handshake {
        +wic64_wait_for_handshake_code
    }
}

}