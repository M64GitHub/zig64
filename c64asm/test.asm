; 6510 Test Program (No BASIC Stub)
; Target: Commodore 64, starts at $C000

.segment "CODE"
.org $C000              ; Start at $C000 in RAM
.export LOADADDR = *

start:
    SEI                ; Disable interrupts (we’re taking control!)
    LDA #$00           ; Load 0 into Accumulator
    STA $01            ; Disable BASIC/KERNAL ROMs (full RAM mode)
    LDX #$FF           ; Load X with 255 (stack pointer init)
    TXS                ; Set Stack Pointer to $FF
    LDY #$00           ; Load Y with 0 (our counter)

    ; Fill screen memory ($0400-$07FF) with a pattern
screen_fill:
    LDA #$41           ; ASCII 'A'
    STA $0400, Y       ; Write to screen memory (first page)
    LDA #$01           ; Color white
    STA $D800, Y       ; Write to color RAM
    INY                ; Increment Y
    CPY #$FF           ; Compare Y with 255
    BNE screen_fill    ; Loop until Y = 255

    ; Do some math with Accumulator and X
    LDA #$05           ; Start with 5 in A
    LDX #$03           ; X = 3
math_loop:
    CLC                ; Clear Carry
    ADC #$02           ; Add 2 to A (5, 7, 9...)
    DEX                ; Decrement X
    BNE math_loop      ; Loop until X = 0 (runs 3 times)
    STA $D020          ; Store final A (should be 11, $0B) in border color

    ; Check Zero and Negative flags
    LDA #$00           ; Load 0 into A
    CMP #$01           ; Compare with 1 (sets Negative flag)
    BEQ skip           ; Shouldn’t branch (A != 1)
    BMI negative_set   ; Should branch (Negative flag set)
skip:
    JMP done           ; Skip if something’s off
negative_set:
    LDA #$FF           ; Load 255 (test Negative flag)
    STA $D021          ; Store in background color

done:
    LDA #$37           ; Restore $01 to default (00110111)
    STA $01            ; Back to normal memory config
    CLI                ; Re-enable interrupts
    RTS                ; Return (or halt in emulator)

; End of program
