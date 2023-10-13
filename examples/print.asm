!macro print .string {
    print = $ab1e
    lda #<.string
    ldy #>.string
    jsr print
}
