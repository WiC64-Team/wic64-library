!macro print .string {
    print = $ab1e
    lda #<.string
    ldy #>.string
    jsr print
}

!macro screen_on {
    lda $d011
    ora #$10
    sta $d011
}

!macro screen_off {
    lda $d011
    and #!$10
    sta $d011
}