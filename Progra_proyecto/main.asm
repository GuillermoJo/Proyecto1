;========================================================
; Reloj + Fecha + Alarma
; ATmega328P - AVR Assembler
;========================================================

.include "m328pdef.inc"

;========================================================
; Constantes
;========================================================
.equ MODE_NORMAL    = 0
.equ MODE_SET_HOUR  = 1
.equ MODE_SET_MIN   = 2
.equ MODE_SET_DAY   = 3
.equ MODE_SET_MON   = 4
.equ MODE_SET_AH    = 5
.equ MODE_SET_AM    = 6

.equ VIEW_TIME      = 0
.equ VIEW_DATE      = 1
.equ VIEW_ALARM     = 2

.equ BTN_VIEW_BIT   = 0
.equ BTN_UP_BIT     = 1
.equ BTN_DOWN_BIT   = 2
.equ BTN_MODE_BIT   = 3

.equ BLANK_CODE     = 10

;========================================================
; SRAM
;========================================================
.dseg
hour:               .byte 1
minute:             .byte 1
second:             .byte 1
day:                .byte 1
month:              .byte 1

alarm_hour:         .byte 1
alarm_min:          .byte 1

current_view:       .byte 1
edit_mode:          .byte 1

blink_flag:         .byte 1
ms_count_l:         .byte 1
ms_count_h:         .byte 1
halfsec_l:          .byte 1
halfsec_h:          .byte 1

scan_idx:           .byte 1

disp0:              .byte 1
disp1:              .byte 1
disp2:              .byte 1
disp3:              .byte 1

btn_locks:          .byte 1
btn_events:         .byte 1

alarm_ringing:      .byte 1
alarm_latched:      .byte 1

colon_on:           .byte 1
aux_led:            .byte 1

.cseg

;========================================================
; Vectores de interrupción
;========================================================
.org 0x0000
    rjmp RESET

.org 0x0002
    reti
.org 0x0004
    reti
.org 0x0006
    reti
.org 0x0008
    rjmp ISR_PCINT1
.org 0x000A
    reti
.org 0x000C
    reti
.org 0x000E
    reti
.org 0x0010
    reti
.org 0x0012
    reti
.org 0x0014
    reti
.org 0x0016
    reti
.org 0x0018
    reti
.org 0x001A
    reti
.org 0x001C
    rjmp ISR_TIMER0_COMPA
.org 0x001E
    reti
.org 0x0020
    reti
.org 0x0022
    reti
.org 0x0024
    reti
.org 0x0026
    reti
.org 0x0028
    reti
.org 0x002A
    reti
.org 0x002C
    reti
.org 0x002E
    reti
.org 0x0030
    reti
.org 0x0032
    reti

;========================================================
; Tabla 7 segmentos
; bit6..bit0 = A B C D E F G
;========================================================
SEG_TABLE:
    .db 0b1111110, 0b0110000, 0b1101101, 0b1111001, 0b0110011, 0b1011011, 0b1011111, 0b1110000, 0b1111111, 0b1111011, 0b0000000, 0b0000000 ; padding

;========================================================
; RESET
;========================================================
RESET:
    ldi r16, high(RAMEND)
    out SPH, r16
    ldi r16, low(RAMEND)
    out SPL, r16

    clr r1

    ; Valores iniciales
    ldi r16, 12
    sts hour, r16

    clr r16
    sts minute, r16
    sts second, r16

    ldi r16, 1
    sts day, r16
    sts month, r16

    ldi r16, 6
    sts alarm_hour, r16

    clr r16
    sts alarm_min, r16
    sts current_view, r16
    sts edit_mode, r16
    sts blink_flag, r16
    sts ms_count_l, r16
    sts ms_count_h, r16
    sts halfsec_l, r16
    sts halfsec_h, r16
    sts scan_idx, r16
    sts btn_locks, r16
    sts btn_events, r16
    sts alarm_ringing, r16
    sts alarm_latched, r16
    sts colon_on, r16
    sts aux_led, r16
    sts disp0, r16
    sts disp1, r16
    sts disp2, r16
    sts disp3, r16

    ; PORTB:
    ; PB5 = ":"
    ; PB4..PB0 = segmentos A..E
    ldi r16, 0b00111111
    out DDRB, r16

    ; PORTD:
    ; PD7..PD6 = segmentos F,G
    ; PD5..PD2 = multiplexado
    ; PD1..PD0 libres
    ldi r16, 0b11111100
    out DDRD, r16
    clr r16
    out PORTD, r16

    ; PORTC:
    ; PC0..PC3 = botones entrada
    ; PC4 = LED salida
    ; PC5 = buzzer salida
    ldi r16, 0b00110000
    out DDRC, r16

    ; pull-up en PC0..PC3
    ldi r16, 0b00001111
    out PORTC, r16

    ; Pin Change Interrupt solo en PORTC
    ldi r16, (1<<PCIE1)
    sts PCICR, r16

    ldi r16, (1<<PCINT8)|(1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)
    sts PCMSK1, r16

    ; Timer0 CTC cada 1 ms
    ldi r16, (1<<WGM01)
    out TCCR0A, r16

    ldi r16, (1<<CS01)|(1<<CS00)
    out TCCR0B, r16

    ldi r16, 249
    out OCR0A, r16

    ldi r16, (1<<OCIE0A)
    sts TIMSK0, r16

    sei

MAIN_LOOP:
    rcall PROCESS_BUTTON_EVENTS
    rcall UPDATE_UI_STATE
    rcall BUILD_DISPLAY_BUFFER
    rjmp MAIN_LOOP

;========================================================
; ISR TIMER0 COMPA - cada 1 ms
;========================================================
ISR_TIMER0_COMPA:
    push r16
    in   r16, SREG
    push r16
    push r17
    push r18
    push r19
    push r20
    push r21
    push r22
    push r23
    push r24
    push r25
    push r30
    push r31

    ; contador de 500 ms
    lds r24, halfsec_l
    lds r25, halfsec_h
    adiw r24, 1
    sts halfsec_l, r24
    sts halfsec_h, r25

    ldi r16, low(500)
    ldi r17, high(500)
    cp  r24, r16
    cpc r25, r17
    brne T0_SKIP_500

    clr r16
    sts halfsec_l, r16
    sts halfsec_h, r16

    lds r16, blink_flag
    ldi r17, 1
    eor r16, r17
    sts blink_flag, r16

T0_SKIP_500:
    ; contador de 1000 ms
    lds r24, ms_count_l
    lds r25, ms_count_h
    adiw r24, 1
    sts ms_count_l, r24
    sts ms_count_h, r25

    ldi r16, low(1000)
    ldi r17, high(1000)
    cp  r24, r16
    cpc r25, r17
    brne T0_SKIP_1S

    clr r16
    sts ms_count_l, r16
    sts ms_count_h, r16

    rcall CLOCK_TICK_1S

T0_SKIP_1S:
    rcall MUX_REFRESH

    pop r31
    pop r30
    pop r25
    pop r24
    pop r23
    pop r22
    pop r21
    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

;========================================================
; ISR PCINT1 para A0..A3
; Genera evento al soltar el botón
;========================================================
ISR_PCINT1:
    push r16
    in   r16, SREG
    push r16
    push r17
    push r18

    in  r16, PINC
    lds r17, btn_locks
    lds r18, btn_events

    ; PC0 VIEW
    sbrs r16, 0
    rjmp PC0_PRESSED
PC0_RELEASED:
    sbrs r17, BTN_VIEW_BIT
    rjmp CHECK_PC1
    cbr r17, (1<<BTN_VIEW_BIT)
    sbr r18, (1<<BTN_VIEW_BIT)
    rjmp CHECK_PC1
PC0_PRESSED:
    sbr r17, (1<<BTN_VIEW_BIT)

CHECK_PC1:
    ; PC1 UP
    sbrs r16, 1
    rjmp PC1_PRESSED
PC1_RELEASED:
    sbrs r17, BTN_UP_BIT
    rjmp CHECK_PC2
    cbr r17, (1<<BTN_UP_BIT)
    sbr r18, (1<<BTN_UP_BIT)
    rjmp CHECK_PC2
PC1_PRESSED:
    sbr r17, (1<<BTN_UP_BIT)

CHECK_PC2:
    ; PC2 DOWN
    sbrs r16, 2
    rjmp PC2_PRESSED
PC2_RELEASED:
    sbrs r17, BTN_DOWN_BIT
    rjmp CHECK_PC3
    cbr r17, (1<<BTN_DOWN_BIT)
    sbr r18, (1<<BTN_DOWN_BIT)
    rjmp CHECK_PC3
PC2_PRESSED:
    sbr r17, (1<<BTN_DOWN_BIT)

CHECK_PC3:
    ; PC3 MODE
    sbrs r16, 3
    rjmp PC3_PRESSED
PC3_RELEASED:
    sbrs r17, BTN_MODE_BIT
    rjmp ISR_PC1_END
    cbr r17, (1<<BTN_MODE_BIT)
    sbr r18, (1<<BTN_MODE_BIT)
    rjmp ISR_PC1_END
PC3_PRESSED:
    sbr r17, (1<<BTN_MODE_BIT)

ISR_PC1_END:
    sts btn_locks, r17
    sts btn_events, r18

    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

;========================================================
; Procesar eventos de botones
;========================================================
PROCESS_BUTTON_EVENTS:
    push r16
    push r17

    lds r16, btn_events
    tst r16
    breq PBE_EXIT

    ; MODE
    sbrs r16, BTN_MODE_BIT
    rjmp PBE_CHECK_VIEW
    cbr r16, (1<<BTN_MODE_BIT)
    sts btn_events, r16
    rcall HANDLE_MODE_EVENT
    rjmp PBE_EXIT

PBE_CHECK_VIEW:
    lds r16, btn_events
    sbrs r16, BTN_VIEW_BIT
    rjmp PBE_CHECK_UP
    cbr r16, (1<<BTN_VIEW_BIT)
    sts btn_events, r16
    rcall HANDLE_VIEW_EVENT
    rjmp PBE_EXIT

PBE_CHECK_UP:
    lds r16, btn_events
    sbrs r16, BTN_UP_BIT
    rjmp PBE_CHECK_DOWN
    cbr r16, (1<<BTN_UP_BIT)
    sts btn_events, r16
    rcall INCREMENT_ACTIVE_FIELD
    rjmp PBE_EXIT

PBE_CHECK_DOWN:
    lds r16, btn_events
    sbrs r16, BTN_DOWN_BIT
    rjmp PBE_EXIT
    cbr r16, (1<<BTN_DOWN_BIT)
    sts btn_events, r16
    rcall DECREMENT_ACTIVE_FIELD

PBE_EXIT:
    pop r17
    pop r16
    ret

;========================================================
; Manejo botón MODE
;========================================================
HANDLE_MODE_EVENT:
    push r16
    push r17

    ; si la alarma está sonando, MODE la silencia
    lds r16, alarm_ringing
    tst r16
    breq HME_NEXT_MODE
    clr r16
    sts alarm_ringing, r16
    rjmp HME_END

HME_NEXT_MODE:
    lds r16, edit_mode
    inc r16
    cpi r16, 7
    brlo HME_STORE
    clr r16

HME_STORE:
    sts edit_mode, r16

    cpi r16, MODE_SET_HOUR
    brne HME_CHK1
    ldi r17, VIEW_TIME
    sts current_view, r17
    rjmp HME_END

HME_CHK1:
    cpi r16, MODE_SET_MIN
    brne HME_CHK2
    ldi r17, VIEW_TIME
    sts current_view, r17
    rjmp HME_END

HME_CHK2:
    cpi r16, MODE_SET_DAY
    brne HME_CHK3
    ldi r17, VIEW_DATE
    sts current_view, r17
    rjmp HME_END

HME_CHK3:
    cpi r16, MODE_SET_MON
    brne HME_CHK4
    ldi r17, VIEW_DATE
    sts current_view, r17
    rjmp HME_END

HME_CHK4:
    cpi r16, MODE_SET_AH
    brne HME_CHK5
    ldi r17, VIEW_ALARM
    sts current_view, r17
    rjmp HME_END

HME_CHK5:
    cpi r16, MODE_SET_AM
    brne HME_END
    ldi r17, VIEW_ALARM
    sts current_view, r17

HME_END:
    pop r17
    pop r16
    ret

;========================================================
; Manejo botón VIEW
;========================================================
HANDLE_VIEW_EVENT:
    push r16

    ; solo cambia vista en modo normal
    lds r16, edit_mode
    tst r16
    brne HVE_END

    lds r16, current_view
    inc r16
    cpi r16, 3
    brlo HVE_STORE
    clr r16

HVE_STORE:
    sts current_view, r16

HVE_END:
    pop r16
    ret

;========================================================
; Actualizar LEDs
;========================================================
UPDATE_UI_STATE:
    push r16
    push r17

    ; ":" en D13
    lds r16, current_view
    cpi r16, VIEW_DATE
    brne UIS_NOT_DATE
    ldi r17, 1
    sts colon_on, r17
    rjmp UIS_AUX

UIS_NOT_DATE:
    lds r17, blink_flag
    sts colon_on, r17

UIS_AUX:
    ; A4 encendido en vista alarma o config alarma
    clr r17

    lds r16, current_view
    cpi r16, VIEW_ALARM
    breq UIS_AUX_ON

    lds r16, edit_mode
    cpi r16, MODE_SET_AH
    breq UIS_AUX_ON
    cpi r16, MODE_SET_AM
    breq UIS_AUX_ON
    rjmp UIS_STORE

UIS_AUX_ON:
    ldi r17, 1

UIS_STORE:
    sts aux_led, r17

    pop r17
    pop r16
    ret

;========================================================
; Construir buffer de display
;========================================================
BUILD_DISPLAY_BUFFER:
    push r16
    push r17
    push r18
    push r19
    push r20
    push r21
    push r24
    push r25
    push r30
    push r31

    ; r16 = valor izquierdo
    ; r17 = valor derecho
    lds r16, current_view
    cpi r16, VIEW_TIME
    brne BDB_CHECK_DATE
    lds r16, hour
    lds r17, minute
    rjmp BDB_SPLIT_PAIR

BDB_CHECK_DATE:
    lds r18, current_view
    cpi r18, VIEW_DATE
    brne BDB_LOAD_ALARM
    lds r16, day
    lds r17, month
    rjmp BDB_SPLIT_PAIR

BDB_LOAD_ALARM:
    lds r16, alarm_hour
    lds r17, alarm_min

BDB_SPLIT_PAIR:
    mov r24, r16
    rcall SPLIT_DECIMAL
    mov r18, r24
    mov r19, r25

    mov r24, r17
    rcall SPLIT_DECIMAL
    mov r20, r24
    mov r21, r25

    ; Parpadeo del campo en edición
    lds r16, blink_flag
    tst r16
    brne BDB_CONVERT

    lds r16, edit_mode
    cpi r16, MODE_SET_HOUR
    breq BDB_BLANK_LEFT
    cpi r16, MODE_SET_DAY
    breq BDB_BLANK_LEFT
    cpi r16, MODE_SET_AH
    breq BDB_BLANK_LEFT
    cpi r16, MODE_SET_MIN
    breq BDB_BLANK_RIGHT
    cpi r16, MODE_SET_MON
    breq BDB_BLANK_RIGHT
    cpi r16, MODE_SET_AM
    breq BDB_BLANK_RIGHT
    rjmp BDB_CONVERT

BDB_BLANK_LEFT:
    ldi r18, BLANK_CODE
    ldi r19, BLANK_CODE
    rjmp BDB_CONVERT

BDB_BLANK_RIGHT:
    ldi r20, BLANK_CODE
    ldi r21, BLANK_CODE

BDB_CONVERT:
    mov r24, r18
    rcall DIGIT_TO_SEG
    sts disp0, r24

    mov r24, r19
    rcall DIGIT_TO_SEG
    sts disp1, r24

    mov r24, r20
    rcall DIGIT_TO_SEG
    sts disp2, r24

    mov r24, r21
    rcall DIGIT_TO_SEG
    sts disp3, r24

    pop r31
    pop r30
    pop r25
    pop r24
    pop r21
    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    ret

;========================================================
; Separar decimal
; Entrada: r24 = 0..99
; Salida:  r24 = decenas, r25 = unidades
;========================================================
SPLIT_DECIMAL:
    push r16
    clr r16
    clr r25

SPLIT_LOOP:
    cpi r24, 10
    brlo SPLIT_DONE
    subi r24, 10
    inc r16
    rjmp SPLIT_LOOP

SPLIT_DONE:
    mov r25, r24
    mov r24, r16
    pop r16
    ret

;========================================================
; Convertir dígito a segmentos
; Entrada: r24 = 0..10
; Salida:  r24 = patrón 7 segmentos
;========================================================
DIGIT_TO_SEG:
    push ZH
    push ZL
    ldi ZH, high(SEG_TABLE<<1)
    ldi ZL, low(SEG_TABLE<<1)
    add ZL, r24
    adc ZH, r1
    lpm r24, Z
    pop ZL
    pop ZH
    ret

;========================================================
; Multiplexado
; D5 = decenas horas/día
; D4 = unidades horas/día
; D3 = decenas minutos/mes
; D2 = unidades minutos/mes
;========================================================
MUX_REFRESH:
    push r16
    push r17
    push r18
    push r19
    push r20

    lds r16, scan_idx

    cpi r16, 0
    brne MUX_CHK1
    lds r17, disp0
    ldi r18, (1<<PD5)
    rjmp MUX_OUTPUT

MUX_CHK1:
    cpi r16, 1
    brne MUX_CHK2
    lds r17, disp1
    ldi r18, (1<<PD4)
    rjmp MUX_OUTPUT

MUX_CHK2:
    cpi r16, 2
    brne MUX_CHK3
    lds r17, disp2
    ldi r18, (1<<PD3)
    rjmp MUX_OUTPUT

MUX_CHK3:
    lds r17, disp3
    ldi r18, (1<<PD2)

MUX_OUTPUT:
    ; PORTB = ":" + segmentos A..E
    mov r19, r17
    lsr r19
    lsr r19
    andi r19, 0b00011111

    lds r20, colon_on
    tst r20
    breq MUX_NO_COLON
    ori r19, (1<<PB5)

MUX_NO_COLON:
    out PORTB, r19

    ; PORTD = segmentos F/G + dígito activo
    clr r19
    sbrc r17, 1
    ori r19, (1<<PD7)
    sbrc r17, 0
    ori r19, (1<<PD6)
    or  r19, r18
    out PORTD, r19

    ; PORTC = pull-ups PC0..PC3 + LED A4 + buzzer A5
    ldi r19, 0b00001111

    lds r20, aux_led
    tst r20
    breq MUX_NO_AUX
    ori r19, (1<<PC4)

MUX_NO_AUX:
    lds r20, alarm_ringing
    tst r20
    breq MUX_NO_BUZZ
    ori r19, (1<<PC5)

MUX_NO_BUZZ:
    out PORTC, r19

    lds r16, scan_idx
    inc r16
    cpi r16, 4
    brlo MUX_STORE
    clr r16

MUX_STORE:
    sts scan_idx, r16

    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    ret

;========================================================
; Tick de 1 segundo
;========================================================
CLOCK_TICK_1S:
    push r16
    push r17

    lds r16, second
    inc r16
    cpi r16, 60
    brlo CTS_STORE_SEC

    clr r16
    sts second, r16

    lds r16, minute
    inc r16
    cpi r16, 60
    brlo CTS_STORE_MIN

    clr r16
    sts minute, r16

    lds r16, hour
    inc r16
    cpi r16, 24
    brlo CTS_STORE_HOUR

    clr r16
    sts hour, r16
    rcall INCREMENT_DAY_ROLLOVER
    rjmp CTS_ALARM_CHECK

CTS_STORE_HOUR:
    sts hour, r16
    rjmp CTS_ALARM_CHECK

CTS_STORE_MIN:
    sts minute, r16
    rjmp CTS_ALARM_CHECK

CTS_STORE_SEC:
    sts second, r16

CTS_ALARM_CHECK:
    ; activar solo al inicio del minuto exacto
    lds r16, second
    tst r16
    brne CTS_CLEAR_IF_NEEDED

    lds r16, hour
    lds r17, alarm_hour
    cp  r16, r17
    brne CTS_CLEAR_IF_NEEDED

    lds r16, minute
    lds r17, alarm_min
    cp  r16, r17
    brne CTS_CLEAR_IF_NEEDED

    lds r16, alarm_latched
    tst r16
    brne CTS_END

    ldi r16, 1
    sts alarm_ringing, r16
    sts alarm_latched, r16
    rjmp CTS_END

CTS_CLEAR_IF_NEEDED:
    lds r16, hour
    lds r17, alarm_hour
    cp  r16, r17
    brne CTS_CLEAR_LATCH

    lds r16, minute
    lds r17, alarm_min
    cp  r16, r17
    brne CTS_CLEAR_LATCH

    rjmp CTS_END

CTS_CLEAR_LATCH:
    clr r16
    sts alarm_latched, r16

CTS_END:
    pop r17
    pop r16
    ret

;========================================================
; Incrementar campo activo
;========================================================
INCREMENT_ACTIVE_FIELD:
    push r16
    push r17
    push r18

    lds r16, edit_mode

    cpi r16, MODE_SET_HOUR
    brne IAF_CHK_MIN
    lds r17, hour
    inc r17
    cpi r17, 24
    brlo IAF_STORE_HOUR
    clr r17
IAF_STORE_HOUR:
    sts hour, r17
    rjmp IAF_END

IAF_CHK_MIN:
    cpi r16, MODE_SET_MIN
    brne IAF_CHK_DAY
    lds r17, minute
    inc r17
    cpi r17, 60
    brlo IAF_STORE_MIN
    clr r17
IAF_STORE_MIN:
    sts minute, r17
    clr r17
    sts second, r17
    rjmp IAF_END

IAF_CHK_DAY:
    cpi r16, MODE_SET_DAY
    brne IAF_CHK_MON
    lds r17, day
    inc r17
    rcall GET_MONTH_MAXDAY
    cp r17, r18
    brlo IAF_STORE_DAY
    breq IAF_STORE_DAY
    ldi r17, 1
IAF_STORE_DAY:
    sts day, r17
    rjmp IAF_END

IAF_CHK_MON:
    cpi r16, MODE_SET_MON
    brne IAF_CHK_AH
    lds r17, month
    inc r17
    cpi r17, 13
    brlo IAF_STORE_MON
    ldi r17, 1
IAF_STORE_MON:
    sts month, r17
    lds r17, day
    rcall GET_MONTH_MAXDAY
    cp r17, r18
    brlo IAF_END
    breq IAF_END
    sts day, r18
    rjmp IAF_END

IAF_CHK_AH:
    cpi r16, MODE_SET_AH
    brne IAF_CHK_AM
    lds r17, alarm_hour
    inc r17
    cpi r17, 24
    brlo IAF_STORE_AH
    clr r17
IAF_STORE_AH:
    sts alarm_hour, r17
    rjmp IAF_END

IAF_CHK_AM:
    cpi r16, MODE_SET_AM
    brne IAF_END
    lds r17, alarm_min
    inc r17
    cpi r17, 60
    brlo IAF_STORE_AM
    clr r17
IAF_STORE_AM:
    sts alarm_min, r17

IAF_END:
    pop r18
    pop r17
    pop r16
    ret

;========================================================
; Decrementar campo activo
;========================================================
DECREMENT_ACTIVE_FIELD:
    push r16
    push r17
    push r18

    lds r16, edit_mode

    cpi r16, MODE_SET_HOUR
    brne DAF_CHK_MIN
    lds r17, hour
    tst r17
    brne DAF_DEC_HOUR
    ldi r17, 23
    rjmp DAF_STORE_HOUR
DAF_DEC_HOUR:
    dec r17
DAF_STORE_HOUR:
    sts hour, r17
    rjmp DAF_END

DAF_CHK_MIN:
    cpi r16, MODE_SET_MIN
    brne DAF_CHK_DAY
    lds r17, minute
    tst r17
    brne DAF_DEC_MIN
    ldi r17, 59
    rjmp DAF_STORE_MIN
DAF_DEC_MIN:
    dec r17
DAF_STORE_MIN:
    sts minute, r17
    clr r17
    sts second, r17
    rjmp DAF_END

DAF_CHK_DAY:
    cpi r16, MODE_SET_DAY
    brne DAF_CHK_MON
    lds r17, day
    cpi r17, 1
    brne DAF_DEC_DAY
    rcall GET_MONTH_MAXDAY
    mov r17, r18
    rjmp DAF_STORE_DAY
DAF_DEC_DAY:
    dec r17
DAF_STORE_DAY:
    sts day, r17
    rjmp DAF_END

DAF_CHK_MON:
    cpi r16, MODE_SET_MON
    brne DAF_CHK_AH
    lds r17, month
    cpi r17, 1
    brne DAF_DEC_MON
    ldi r17, 12
    rjmp DAF_STORE_MON
DAF_DEC_MON:
    dec r17
DAF_STORE_MON:
    sts month, r17
    lds r17, day
    rcall GET_MONTH_MAXDAY
    cp r17, r18
    brlo DAF_END
    breq DAF_END
    sts day, r18
    rjmp DAF_END

DAF_CHK_AH:
    cpi r16, MODE_SET_AH
    brne DAF_CHK_AM
    lds r17, alarm_hour
    tst r17
    brne DAF_DEC_AH
    ldi r17, 23
    rjmp DAF_STORE_AH
DAF_DEC_AH:
    dec r17
DAF_STORE_AH:
    sts alarm_hour, r17
    rjmp DAF_END

DAF_CHK_AM:
    cpi r16, MODE_SET_AM
    brne DAF_END
    lds r17, alarm_min
    tst r17
    brne DAF_DEC_AM
    ldi r17, 59
    rjmp DAF_STORE_AM
DAF_DEC_AM:
    dec r17
DAF_STORE_AM:
    sts alarm_min, r17

DAF_END:
    pop r18
    pop r17
    pop r16
    ret

;========================================================
; Avance natural del día
;========================================================
INCREMENT_DAY_ROLLOVER:
    push r16
    push r17
    push r18

    lds r16, day
    inc r16

    rcall GET_MONTH_MAXDAY
    cp r16, r18
    brlo IDR_STORE_DAY
    breq IDR_STORE_DAY

    ldi r16, 1
    sts day, r16

    lds r17, month
    inc r17
    cpi r17, 13
    brlo IDR_STORE_MONTH
    ldi r17, 1

IDR_STORE_MONTH:
    sts month, r17
    rjmp IDR_END

IDR_STORE_DAY:
    sts day, r16

IDR_END:
    pop r18
    pop r17
    pop r16
    ret

;========================================================
; r18 = máximo día del mes actual
;========================================================
GET_MONTH_MAXDAY:
    push r16

    lds r16, month
    cpi r16, 2
    breq GMD_FEB

    cpi r16, 4
    breq GMD_30
    cpi r16, 6
    breq GMD_30
    cpi r16, 9
    breq GMD_30
    cpi r16, 11
    breq GMD_30

    ldi r18, 31
    rjmp GMD_END

GMD_FEB:
    ldi r18, 28
    rjmp GMD_END

GMD_30:
    ldi r18, 30

GMD_END:
    pop r16
    ret