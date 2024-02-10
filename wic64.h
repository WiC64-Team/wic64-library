!zone wic64 {
;---------------------------------------------------------
; Command constants
;---------------------------------------------------------

WIC64_GET_VERSION_STRING  = $00
WIC64_GET_VERSION_NUMBERS = $26

WIC64_SCAN_WIFI_NETWORKS       = $0c
WIC64_CONNECT_WITH_SSID_STRING = $02
WIC64_CONNECT_WITH_SSID_INDEX  = $0d
WIC64_IS_CONFIGURED            = $2f
WIC64_IS_CONNECTED             = $2c

WIC64_GET_MAC  = $14
WIC64_GET_SSID = $10
WIC64_GET_RSSI = $11
WIC64_GET_IP   = $06

WIC64_HTTP_GET         = $01
WIC64_HTTP_GET_ENCODED = $0f
WIC64_HTTP_POST_URL    = $28
WIC64_HTTP_POST_DATA   = $2b

WIC64_TCP_OPEN      = $21
WIC64_TCP_AVAILABLE = $30
WIC64_TCP_READ      = $22
WIC64_TCP_WRITE     = $23
WIC64_TCP_CLOSE     = $2e

WIC64_GET_SERVER = $12
WIC64_SET_SERVER = $08

WIC64_GET_TIMEZONE   = $17
WIC64_SET_TIMEZONE   = $16
WIC64_GET_LOCAL_TIME = $15

WIC64_UPDATE_FIRMWARE = $27

WIC64_REBOOT = $29
WIC64_GET_STATUS_MESSAGE = $2a
WIC64_SET_TRANSFER_TIMEOUT = $2d
WIC64_SET_REMOTE_TIMEOUT = $32
WIC64_IS_HARDWARE = $31

WIC64_FORCE_TIMEOUT = $fc
WIC64_FORCE_ERROR = $fd
WIC64_ECHO = $fe

WIC64_SUCCESS          = $00
WIC64_INTERNAL_ERROR   = $01
WIC64_CLIENT_ERROR     = $02
WIC64_CONNECTION_ERROR = $03
WIC64_NETWORK_ERROR    = $04
WIC64_SERVER_ERROR     = $05

;---------------------------------------------------------
; Opcode constants
;---------------------------------------------------------

wic64_lda_abs = $ad
wic64_sta_abs_y = $99
wic64_lda_abs_y = $b9
wic64_inc_abs = $ee
wic64_nop = $ea

;---------------------------------------------------------
; Assembly time options
;---------------------------------------------------------

!ifndef wic64_optimize_for_size {
    wic64_optimize_for_size = 0
}

!ifndef wic64_include_enter_portal {
    wic64_include_enter_portal = 0
}

!ifndef wic64_include_load_and_run {
    !if (wic64_include_enter_portal != 0) {
        wic64_include_load_and_run = 1
    } else {
        wic64_include_load_and_run = 0
    }
}

;---------------------------------------------------------
; Runtime options
;---------------------------------------------------------

!macro wic64_set_timeout .timeout {
    lda #.timeout
    sta wic64_timeout
    sta wic64_configured_timeout
}

;---------------------------------------------------------

!macro wic64_dont_disable_irqs {
    lda #$01
    sta wic64_dont_disable_irqs
}

!macro wic64_disable_irqs {
    lda #$00
    sta wic64_dont_disable_irqs
}

;---------------------------------------------------------

!macro wic64_set_timeout_handler .addr {
    lda #<.addr
    sta wic64_timeout_handler
    lda #>.addr
    sta wic64_timeout_handler+1
    tsx
    stx wic64_timeout_handler_stackpointer
}

!macro wic64_unset_timeout_handler {
    lda #$00
    sta wic64_timeout_handler
    sta wic64_timeout_handler+1
}

;---------------------------------------------------------

!macro wic64_set_error_handler .addr {
    lda #<.addr
    sta wic64_error_handler
    lda #>.addr
    sta wic64_error_handler+1
    tsx
    stx wic64_error_handler_stackpointer
}

!macro wic64_unset_error_handler {
    lda #$00
    sta wic64_error_handler
    sta wic64_error_handler+1
}

;---------------------------------------------------------

!macro wic64_set_store_instruction .addr {
    ldy #$02
-   lda .addr,y
    sta wic64_store_instruction_pages,y
    sta wic64_store_instruction_bytes,y
    dey
    bpl -

    lda #wic64_lda_abs
    sta wic64_destination_pointer_highbyte_inc
}

!macro wic64_reset_store_instruction {
    jsr wic64_reset_store_instruction
}

;---------------------------------------------------------

!macro wic64_set_fetch_instruction .addr {
    ldy #$02
-   lda .addr,y
    sta wic64_fetch_instruction_pages,y
    sta wic64_fetch_instruction_bytes,y
    dey
    bpl -

    lda #wic64_lda_abs
    sta wic64_source_pointer_highbyte_inc
}

!macro wic64_reset_fetch_instruction {
    jsr wic64_reset_fetch_instruction
}

;---------------------------------------------------------
; Transfer functions
;---------------------------------------------------------

!macro wic64_initialize {
    jsr wic64_initialize
}

;---------------------------------------------------------

!macro wic64_set_request .request {
    lda #<.request
    sta wic64_request
    lda #>.request
    sta wic64_request+1
}

;---------------------------------------------------------

!macro wic64_send_header {
    jsr wic64_send_header
}

!macro wic64_send_header .request {
    +wic64_set_request .request
    jsr wic64_send_header
}

;---------------------------------------------------------

!macro wic64_send {
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_send
}

!macro wic64_send .source {
    +wic64_set_request .source
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_send
}

!macro wic64_send .source, .size {
    +wic64_set_request .source

    lda #<.size
    sta wic64_bytes_to_transfer
    lda #>.size
    sta wic64_bytes_to_transfer+1

    jsr wic64_send
}

!macro wic64_send .source, ~.size {
    +wic64_set_request .source

    lda .size
    sta wic64_bytes_to_transfer
    lda .size+1
    sta wic64_bytes_to_transfer+1

    jsr wic64_send
}

;---------------------------------------------------------

!macro wic64_receive_header {
    jsr wic64_receive_header
}

;---------------------------------------------------------

!macro wic64_set_response .response {
    lda #<.response
    sta wic64_response
    lda #>.response
    sta wic64_response+1
}

;---------------------------------------------------------

!macro wic64_receive {
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_receive
}

!macro wic64_receive .destination {
    +wic64_set_response .destination
    +wic64_prepare_transfer_of_remaining_bytes
    jsr wic64_receive
}

!macro wic64_receive .destination, .size {
    +wic64_set_response .destination

    lda #<.size
    sta wic64_bytes_to_transfer
    lda #>.size
    sta wic64_bytes_to_transfer+1

    jsr wic64_receive
}

!macro wic64_receive .destination, ~.size {
    +wic64_set_response .destination

    lda .size
    sta wic64_bytes_to_transfer
    lda .size+1
    sta wic64_bytes_to_transfer+1

    jsr wic64_receive
}

;---------------------------------------------------------

!macro wic64_finalize {
    jsr wic64_finalize
}

;---------------------------------------------------------

!macro wic64_execute .request {
    +wic64_set_request .request

    lda wic64_store_instruction_pages
    cmp #wic64_sta_abs_y
    bne +

    lda #$00
    sta wic64_auto_discard_response

+   jsr wic64_execute
}

!macro wic64_execute .request, .response {
    +wic64_set_request .request
    +wic64_set_response .response

    jsr wic64_execute
}

!macro wic64_execute .request, .response, .timeout {
    lda wic64_timeout
    sta wic64_configured_timeout

    lda #.timeout
    sta wic64_timeout

    +wic64_execute .request, .response
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

    lda wic64_timeout
    sta wic64_configured_timeout

    lda #.timeout
    sta wic64_timeout

    jsr wic64_load_and_run
}

!if (wic64_include_enter_portal != 0) {

!macro wic64_enter_portal {
    jsr wic64_enter_portal
}

}

;---------------------------------------------------------
; Internal macros
;---------------------------------------------------------

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
+   lda wic64_timeout
    sta wic64_counters+2
    cmp #$01
    bne +
    lda #$48
+   sta wic64_counters+1

   ; keep testing for FLAG2 until all counters are down to zero
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

;---------------------------------------------------------
; set the source pointer to read request data from
; in wic64_send (self-modifying code)

!macro wic64_set_source_pointer_from .addr {
    ; only set the pointer if no custom fetch
    ; operation has been installed
    lda wic64_fetch_instruction_pages
    cmp #wic64_lda_abs_y
    bne .done

    lda .addr
    sta wic64_source_pointer_pages
    lda .addr+1
    sta wic64_source_pointer_pages+1
.done
}

;---------------------------------------------------------
; set the destination pointer to write response data to
; in wic64_receive (self-modifying code)

!macro wic64_set_destination_pointer_from .addr {
    ; only set the pointer if no custom store
    ; operation has been installed
    lda wic64_store_instruction_pages
    cmp #wic64_sta_abs_y
    bne .done

    lda .addr
    sta wic64_destination_pointer_pages
    lda .addr+1
    sta wic64_destination_pointer_pages+1
.done
}

;---------------------------------------------------------
; Make sure the next call to wic64_send or wic64_receive
; will transfer all bytes not sent or received so far.

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

}