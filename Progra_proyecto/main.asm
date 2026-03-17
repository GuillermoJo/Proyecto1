.include "m328pdef.inc"

.def zero      = r1
.def tmp       = r16
.def tmp2      = r17
.def tmp3      = r18
.def tmp4      = r19

.def msL       = r20
.def msH       = r21
.def mux_i     = r22

.def mode      = r23
.def flags     = r24
.def db_mode   = r25

; flags bits
.equ FLG_UP    = 0
.equ FLG_DN    = 1
.equ FLG_MD    = 2
.equ FLG_ALM_EN= 3
.equ FLG_ALM_ON= 4
.equ FLG_COLON = 5

; modos
.equ M_HORA    = 0
.equ M_FECHA   = 1
.equ M_SET_H   = 2
.equ M_SET_F   = 3
.equ M_SET_A   = 4
.equ M_ALM_OFF = 5

.dseg
hh:        .byte 1
mm:        .byte 1
ss:        .byte 1
day:       .byte 1
mon:       .byte 1

alm_hh:    .byte 1
alm_mm:    .byte 1

deb_ms:    .byte 1

.cseg

.org 0x0000
    rjmp RESET

.org PCINT1addr
    rjmp ISR_PCINT1

.org OC0Aaddr
    rjmp ISR_T0A

RESET:
    ldi tmp, low(RAMEND)
    out SPL, tmp
    ldi tmp, high(RAMEND)
    out SPH, tmp

    clr zero

    ; --- IO ---
    ; Segmentos a..g en PORTD bits0..6 (PD0..PD6)
    ldi tmp, 0b01111111
    out DDRD, tmp
    clr tmp
    out PORTD, tmp

    ; PB0 = DP, PB1..PB4 = enable digitos, PB5 = buzzer
    ldi tmp, 0b00111111
    out DDRB, tmp
    clr tmp
    out PORTB, tmp

    ; Botones en PC0, PC1, PC2 (MODE, UP, DOWN) con pull-up
    cbi DDRC, 0
    cbi DDRC, 1
    cbi DDRC, 2
    sbi PORTC, 0
    sbi PORTC, 1
    sbi PORTC, 2

    ; --- Variables iniciales ---
    ldi tmp, 12
    sts hh, tmp
    ldi tmp, 0
    sts mm, tmp
    sts ss, tmp
    ldi tmp, 1
    sts day, tmp
    ldi tmp, 1
    sts mon, tmp

    ldi tmp, 6
    sts alm_hh, tmp
    ldi tmp, 30
    sts alm_mm, tmp

    clr msL
    clr msH
    clr mux_i
    clr mode
    clr flags
    sbr flags, (1<<FLG_ALM_EN)

    ldi tmp, 0
    sts deb_ms, tmp

    ; --- Timer0 CTC 1ms ---
    ; 16MHz / 64 = 250kHz ; OCR0A=249 -> 1ms
    ldi tmp, (1<<WGM01)
    out TCCR0A, tmp
    ldi tmp, (1<<CS01) | (1<<CS00)
    out TCCR0B, tmp
    ldi tmp, 249
    out OCR0A, tmp
    ldi tmp, (1<<OCIE0A)
    sts TIMSK0, tmp

    ; --- PCINT para PORTC (PCINT8..14) ---
    ldi tmp, (1<<PCIE1)
    sts PCICR, tmp
    ldi tmp, (1<<PCINT8) | (1<<PCINT9) | (1<<PCINT10)
    sts PCMSK1, tmp

    sei

MAIN:
    rjmp MAIN

; ------------------------------------------------------------
; ISR Timer0 CompareA (1ms): multiplex + tiempo + debounce
; ------------------------------------------------------------
ISR_T0A:
    push tmp
    push tmp2
    push tmp3
    push tmp4
    push r30
    push r31

    ; debounce lockout countdown
    lds tmp, deb_ms
    tst tmp
    breq .db_done
    dec tmp
    sts deb_ms, tmp
.db_done:

    ; ms counter
    inc msL
    brne .no_msH
    inc msH
.no_msH:

    ; colon toggle cada 500ms
    ; 500ms = 500 ticks
    ; usamos msL/msH como 16-bit, comparamos contra 500
    ; cuando llega a 500, toggle y reset ms a 0
    ldi tmp, low(500)
    ldi tmp2, high(500)
    cp msL, tmp
    cpc msH, tmp2
    brne .no_500
    clr msL
    clr msH
    ldi tmp, (1<<FLG_COLON)
    eor flags, tmp
.no_500:

    ; segundo: contamos 1000ms con un contador aparte sencillo usando msH/msL
    ; acá: cuando colon hace toggle 2 veces -> 1s (porque toggle cada 500ms)
    ; para simplificar: si colon acaba de cambiar a 0, incrementamos 1 segundo
    sbrc flags, FLG_COLON
    rjmp .skip_1s

    ; si estamos en modo de configuración, no corre el reloj
    cpi mode, M_SET_H
    breq .skip_1s
    cpi mode, M_SET_F
    breq .skip_1s
    cpi mode, M_SET_A
    breq .skip_1s
    cpi mode, M_ALM_OFF
    breq .skip_1s

    ; ss++
    lds tmp, ss
    inc tmp
    cpi tmp, 60
    brlo .ss_ok
    clr tmp
    ; mm++
    lds tmp2, mm
    inc tmp2
    cpi tmp2, 60
    brlo .mm_ok
    clr tmp2
    ; hh++
    lds tmp3, hh
    inc tmp3
    cpi tmp3, 24
    brlo .hh_ok
    clr tmp3
    sts hh, tmp3
    ; fecha ++ (muy básico, sin bisiesto)
    rcall INC_DATE
    rjmp .store_time
.hh_ok:
    sts hh, tmp3
.mm_ok:
    sts mm, tmp2
.ss_ok:
    sts ss, tmp
.store_time:
.skip_1s:

    ; alarma: si habilitada y hh:mm coincide y ss==0 -> encender
    sbrs flags, FLG_ALM_EN
    rjmp .alm_check_done
    lds tmp, hh
    lds tmp2, alm_hh
    cp tmp, tmp2
    brne .alm_check_done
    lds tmp, mm
    lds tmp2, alm_mm
    cp tmp, tmp2
    brne .alm_check_done
    lds tmp, ss
    tst tmp
    brne .alm_check_done
    sbr flags, (1<<FLG_ALM_ON)
.alm_check_done:

    ; buzzer según FLG_ALM_ON
    sbrs flags, FLG_ALM_ON
    rjmp .buzz_off
    sbi PORTB, 5
    rjmp .buzz_done
.buzz_off:
    cbi PORTB, 5
.buzz_done:

    ; multiplex: apagar enables
    cbi PORTB, 1
    cbi PORTB, 2
    cbi PORTB, 3
    cbi PORTB, 4

    ; mux_i = (mux_i+1) mod 4
    inc mux_i
    cpi mux_i, 4
    brlo .mux_ok
    clr mux_i
.mux_ok:

    ; calcular digito a mostrar en tmp3 (0..15) y enable en PB1..PB4
    rcall GET_DIGIT_NIBBLE

    ; leer patron 7seg (a..g) en tmp4
    mov tmp2, tmp3
    rcall HEX_TO_7SEG

    ; cargar segmentos a..g en PORTD (bits0..6)
    out PORTD, tmp4

    ; DP (PB0) para colon en los dos dígitos centrales (mux 1 y mux 2)
    cbi PORTB, 0
    sbrc flags, FLG_COLON
    rjmp .dp_maybe
    rjmp .dp_done
.dp_maybe:
    cpi mux_i, 1
    breq .dp_on
    cpi mux_i, 2
    breq .dp_on
    rjmp .dp_done
.dp_on:
    sbi PORTB, 0
.dp_done:

    ; enable según mux_i
    cpi mux_i, 0
    breq .en_d1
    cpi mux_i, 1
    breq .en_d2
    cpi mux_i, 2
    breq .en_d3
    ; mux_i=3
    sbi PORTB, 4
    rjmp .isr_end
.en_d1:
    sbi PORTB, 1
    rjmp .isr_end
.en_d2:
    sbi PORTB, 2
    rjmp .isr_end
.en_d3:
    sbi PORTB, 3

.isr_end:
    pop r31
    pop r30
    pop tmp4
    pop tmp3
    pop tmp2
    pop tmp
    reti

; ------------------------------------------------------------
; ISR PCINT1: captura press (activo en 0) con lockout
; ------------------------------------------------------------
ISR_PCINT1:
    push tmp
    push tmp2

    lds tmp, deb_ms
    tst tmp
    brne .pcint_end

    in tmp, PINC

    ; MODE en PC0
    sbrs tmp, 0
    sbr flags, (1<<FLG_MD)

    ; UP en PC1
    sbrs tmp, 1
    sbr flags, (1<<FLG_UP)

    ; DOWN en PC2
    sbrs tmp, 2
    sbr flags, (1<<FLG_DN)

    ldi tmp2, 30
    sts deb_ms, tmp2

    rcall HANDLE_KEYS

.pcint_end:
    pop tmp2
    pop tmp
    reti

; ------------------------------------------------------------
; HANDLE_KEYS: usa flags y modo para actuar (presionar/soltar)
; ------------------------------------------------------------
HANDLE_KEYS:
    push tmp
    push tmp2
    push tmp3
    push tmp4

    ; MODE
    sbrs flags, FLG_MD
    rjmp .no_mode
    cbr flags, (1<<FLG_MD)

    inc mode
    cpi mode, 6
    brlo .mode_ok
    clr mode
.mode_ok:
.no_mode:

    ; si modo = apagar alarma, UP apaga
    cpi mode, M_ALM_OFF
    brne .not_off
    sbrs flags, FLG_UP
    rjmp .skip_off
    cbr flags, (1<<FLG_UP)
    cbr flags, (1<<FLG_ALM_ON)
    clr mode
.skip_off:
    rjmp .keys_end
.not_off:

    ; UP / DOWN segun modo
    sbrs flags, FLG_UP
    rjmp .no_up
    cbr flags, (1<<FLG_UP)
    rcall INC_FIELD
.no_up:

    sbrs flags, FLG_DN
    rjmp .no_dn
    cbr flags, (1<<FLG_DN)
    rcall DEC_FIELD
.no_dn:

.keys_end:
    pop tmp4
    pop tmp3
    pop tmp2
    pop tmp
    ret

; ------------------------------------------------------------
; INC_FIELD / DEC_FIELD: overflow/underflow
; ------------------------------------------------------------
INC_FIELD:
    push tmp
    push tmp2
    push tmp3

    cpi mode, M_SET_H
    breq .inc_time
    cpi mode, M_SET_F
    breq .inc_date
    cpi mode, M_SET_A
    breq .inc_alarm
    rjmp .inc_end

.inc_time:
    ; alterna entre minutos y horas usando mux_i(0..3) como “cursor” simple:
    ; si mux_i<2 -> horas, si mux_i>=2 -> minutos
    cpi mux_i, 2
    brlo .inc_hh
    rjmp .inc_mm
.inc_hh:
    lds tmp, hh
    inc tmp
    cpi tmp, 24
    brlo .hh_store
    clr tmp
.hh_store:
    sts hh, tmp
    rjmp .inc_end
.inc_mm:
    lds tmp, mm
    inc tmp
    cpi tmp, 60
    brlo .mm_store
    clr tmp
.mm_store:
    sts mm, tmp
    rjmp .inc_end

.inc_date:
    rcall INC_DATE
    rjmp .inc_end

.inc_alarm:
    cpi mux_i, 2
    brlo .inc_ah
    rjmp .inc_am
.inc_ah:
    lds tmp, alm_hh
    inc tmp
    cpi tmp, 24
    brlo .ah_store
    clr tmp
.ah_store:
    sts alm_hh, tmp
    rjmp .inc_end
.inc_am:
    lds tmp, alm_mm
    inc tmp
    cpi tmp, 60
    brlo .am_store
    clr tmp
.am_store:
    sts alm_mm, tmp

.inc_end:
    pop tmp3
    pop tmp2
    pop tmp
    ret

DEC_FIELD:
    push tmp
    push tmp2
    push tmp3

    cpi mode, M_SET_H
    breq .dec_time
    cpi mode, M_SET_F
    breq .dec_date
    cpi mode, M_SET_A
    breq .dec_alarm
    rjmp .dec_end

.dec_time:
    cpi mux_i, 2
    brlo .dec_hh
    rjmp .dec_mm
.dec_hh:
    lds tmp, hh
    tst tmp
    brne .hh_dec1
    ldi tmp, 24
.hh_dec1:
    dec tmp
    sts hh, tmp
    rjmp .dec_end
.dec_mm:
    lds tmp, mm
    tst tmp
    brne .mm_dec1
    ldi tmp, 60
.mm_dec1:
    dec tmp
    sts mm, tmp
    rjmp .dec_end

.dec_date:
    rcall DEC_DATE
    rjmp .dec_end

.dec_alarm:
    cpi mux_i, 2
    brlo .dec_ah
    rjmp .dec_am
.dec_ah:
    lds tmp, alm_hh
    tst tmp
    brne .ah_dec1
    ldi tmp, 24
.ah_dec1:
    dec tmp
    sts alm_hh, tmp
    rjmp .dec_end
.dec_am:
    lds tmp, alm_mm
    tst tmp
    brne .am_dec1
    ldi tmp, 60
.am_dec1:
    dec tmp
    sts alm_mm, tmp

.dec_end:
    pop tmp3
    pop tmp2
    pop tmp
    ret

; ------------------------------------------------------------
; GET_DIGIT_NIBBLE: devuelve en tmp3 el nibble del dígito a mostrar
; mux_i: 0 1 2 3
; Hora: HHMM (H1 H0 M1 M0)
; Fecha: DDMM (D1 D0 M1 M0)
; Config: muestra lo mismo que su campo
; ------------------------------------------------------------
GET_DIGIT_NIBBLE:
    push tmp
    push tmp2

    ; seleccionar fuente (hora o fecha o alarma)
    cpi mode, M_FECHA
    breq .use_date
    cpi mode, M_SET_F
    breq .use_date
    cpi mode, M_SET_A
    breq .use_alarm
    rjmp .use_time

.use_time:
    lds tmp, hh
    lds tmp2, mm
    rjmp .split

.use_date:
    lds tmp, day
    lds tmp2, mon
    rjmp .split

.use_alarm:
    lds tmp, alm_hh
    lds tmp2, alm_mm

.split:
    ; tmp=alto (0..59 o 0..23), tmp2=bajo (0..59)
    ; convertimos cada uno a BCD: decenas y unidades (0..9)
    ; digit order: [tmp tens][tmp units][tmp2 tens][tmp2 units]
    ; mux_i=0 -> tmp tens
    ; mux_i=1 -> tmp units
    ; mux_i=2 -> tmp2 tens
    ; mux_i=3 -> tmp2 units

    mov tmp3, tmp
    rcall BIN_TO_BCD
    ; devuelve tens en tmp3, units en tmp4
    cpi mux_i, 0
    breq .ret_tens_hi
    cpi mux_i, 1
    breq .ret_units_hi

    mov tmp3, tmp2
    rcall BIN_TO_BCD
    cpi mux_i, 2
    breq .ret_tens_lo
    ; mux_i=3
    mov tmp3, tmp4
    rjmp .gd_end

.ret_tens_hi:
    ; tmp3 ya es tens
    rjmp .gd_end
.ret_units_hi:
    mov tmp3, tmp4
    rjmp .gd_end
.ret_tens_lo:
    ; tmp3 ya es tens
.gd_end:
    pop tmp2
    pop tmp
    ret

; ------------------------------------------------------------
; BIN_TO_BCD: entrada tmp3 (0..99) -> tmp3=tens, tmp4=units
; ------------------------------------------------------------
BIN_TO_BCD:
    push tmp
    clr tmp4
    clr tmp
.bt_loop:
    cpi tmp3, 10
    brlo .bt_done
    subi tmp3, 10
    inc tmp
    rjmp .bt_loop
.bt_done:
    mov tmp4, tmp3
    mov tmp3, tmp
    pop tmp
    ret

; ------------------------------------------------------------
; HEX_TO_7SEG: entrada tmp2 (0..15) -> salida tmp4 patrón a..g (1=on)
; Tabla para cátodo común (si es ánodo común, invertí bits)
; ------------------------------------------------------------
HEX_TO_7SEG:
    push r30
    push r31
    ldi r30, low(seg_tab<<1)
    ldi r31, high(seg_tab<<1)
    add r30, tmp2
    adc r31, zero
    lpm tmp4, Z
    pop r31
    pop r30
    ret

; ------------------------------------------------------------
; Fecha: incremento/decremento simple (sin bisiesto)
; ------------------------------------------------------------
INC_DATE:
    push tmp
    push tmp2

    lds tmp, day
    inc tmp
    sts day, tmp
    rcall FIX_DATE_UP

    pop tmp2
    pop tmp
    ret

DEC_DATE:
    push tmp
    push tmp2

    lds tmp, day
    tst tmp
    brne .dd_ok
    ldi tmp, 1
.dd_ok:
    dec tmp
    sts day, tmp
    rcall FIX_DATE_DN

    pop tmp2
    pop tmp
    ret

FIX_DATE_UP:
    push tmp
    push tmp2
    ; si day > days_in_month -> day=1, mon++
    lds tmp, mon
    mov tmp2, tmp
    rcall DAYS_IN_MONTH
    ; tmp4 = dim
    lds tmp, day
    cp tmp, tmp4
    brlo .fdu_end
    breq .fdu_end
    ldi tmp, 1
    sts day, tmp
    lds tmp, mon
    inc tmp
    cpi tmp, 13
    brlo .mon_ok
    ldi tmp, 1
.mon_ok:
    sts mon, tmp
.fdu_end:
    pop tmp2
    pop tmp
    ret

FIX_DATE_DN:
    push tmp
    push tmp2
    ; si day == 0 -> mon--, day = days_in_month(mon)
    lds tmp, day
    tst tmp
    brne .fdd_end
    lds tmp, mon
    tst tmp
    brne .mon_dn1
    ldi tmp, 1
.mon_dn1:
    dec tmp
    cpi tmp, 0
    brne .mon_dn_ok
    ldi tmp, 12
.mon_dn_ok:
    sts mon, tmp
    mov tmp2, tmp
    rcall DAYS_IN_MONTH
    sts day, tmp4
.fdd_end:
    pop tmp2
    pop tmp
    ret

; DAYS_IN_MONTH: entrada tmp2 = mes (1..12) -> tmp4 = dias
DAYS_IN_MONTH:
    ; feb=28 fijo (asunción)
    cpi tmp2, 2
    breq .dim_28
    cpi tmp2, 4
    breq .dim_30
    cpi tmp2, 6
    breq .dim_30
    cpi tmp2, 9
    breq .dim_30
    cpi tmp2, 11
    breq .dim_30
    ldi tmp4, 31
    ret
.dim_30:
    ldi tmp4, 30
    ret
.dim_28:
    ldi tmp4, 28
    ret

; Tabla 7seg (catodo común): bit0=a..bit6=g
seg_tab:
    .db 0x3F,0x06,0x5B,0x4F,0x66,0x6D,0x7D,0x07, 0x7F,0x6F,0x77,0x7C,0x39,0x5E,0x79,0x71

;quiero que me hagas un código