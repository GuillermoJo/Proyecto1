.include "m328pdef.inc"

; modos de operacion del reloj
.equ MODO_NORMAL   = 0
.equ MODO_HORA     = 1
.equ MODO_MINUTO   = 2
.equ MODO_DIA      = 3
.equ MODO_MES      = 4
.equ MODO_ALARM_H  = 5
.equ MODO_ALARM_M  = 6

; vistas disponibles en pantalla
.equ VISTA_HORA    = 0
.equ VISTA_FECHA   = 1
.equ VISTA_ALARMA  = 2

; posiciones de bit de cada boton en los registros de estado
.equ BIT_BTN_VER   = 0
.equ BIT_BTN_SUB   = 1
.equ BIT_BTN_BAJ   = 2
.equ BIT_BTN_MOD   = 3

; codigo especial para apagar todos los segmentos de un digito
.equ COD_VACIO     = 10

; registros de trabajo temporales
.def tmp0  = r16
.def tmp1  = r17
.def tmp2  = r18
.def tmp3  = r19
.def tmp4  = r20

.dseg

; variables del reloj
horas:         .byte 1
minutos:       .byte 1
segundos:      .byte 1
dia:           .byte 1
mes:           .byte 1

; configuracion de la alarma
alar_hora:     .byte 1
alar_min:      .byte 1

; estado general de la interfaz
vista_actual:  .byte 1
modo_edicion:  .byte 1

; variables de temporizacion y parpadeo
flag_parpadeo: .byte 1
cnt_ms_l:      .byte 1
cnt_ms_h:      .byte 1
cnt_500_l:     .byte 1
cnt_500_h:     .byte 1

; indice del digito que se refresca en el multiplex
indice_mux:    .byte 1

; patrones de segmento para cada digito del display
seg_d0:        .byte 1
seg_d1:        .byte 1
seg_d2:        .byte 1
seg_d3:        .byte 1

; registros de eventos y bloqueos de botones
bloqueos:      .byte 1
eventos:       .byte 1

; estado de la alarma
alarma_sonando:  .byte 1
alarma_usada:    .byte 1

; control del LED de dos puntos y del LED indicador
puntos_on:     .byte 1
led_alarma:    .byte 1

.cseg

; solo se usan los vectores de PCINT1 y TIMER0 COMPA
.org 0x0000
    rjmp INICIO

.org 0x0008
    rjmp ISR_BOTONES

.org 0x001C
    rjmp ISR_TICK_MS

; tabla de patrones para display de 7 segmentos
; el bit 6 corresponde al segmento A y el bit 0 al segmento G
TABLA_SEG:
    .db 0b1111110, 0b0110000, 0b1101101, 0b1111001, 0b0110011, 0b1011011, 0b1011111, 0b1110000, 0b1111111, 0b1111011, 0b0000000, 0b0000000

; rutina de inicializacion del sistema
INICIO:
    ldi tmp0, high(RAMEND)
    out SPH, tmp0
    ldi tmp0, low(RAMEND)
    out SPL, tmp0
    clr r1

    ; hora inicial al encender
    ldi tmp0, 12
    sts horas, tmp0
    clr tmp0
    sts minutos, tmp0
    sts segundos, tmp0

    ; fecha inicial al encender
    ldi tmp0, 1
    sts dia, tmp0
    sts mes, tmp0

    ; alarma predeterminada a las seis de la manana
    ldi tmp0, 6
    sts alar_hora, tmp0
    clr tmp0
    sts alar_min, tmp0

    ; poner en cero todas las variables de control
    clr tmp0
    sts vista_actual, tmp0
    sts modo_edicion, tmp0
    sts flag_parpadeo, tmp0
    sts cnt_ms_l, tmp0
    sts cnt_ms_h, tmp0
    sts cnt_500_l, tmp0
    sts cnt_500_h, tmp0
    sts indice_mux, tmp0
    sts bloqueos, tmp0
    sts eventos, tmp0
    sts alarma_sonando, tmp0
    sts alarma_usada, tmp0
    sts puntos_on, tmp0
    sts led_alarma, tmp0
    sts seg_d0, tmp0
    sts seg_d1, tmp0
    sts seg_d2, tmp0
    sts seg_d3, tmp0

    ; PB0 a PB5 como salidas para los segmentos y el LED de dos puntos
    ldi tmp0, 0b00111111
    out DDRB, tmp0

    ; PD2 a PD7 como salidas para seleccion de digito y segmentos F G
    ldi tmp0, 0b11111100
    out DDRD, tmp0
    clr tmp0
    out PORTD, tmp0

    ; PC0 a PC3 entradas para botones PC4 salida LED PC5 salida buzzer
    ldi tmp0, 0b00110000
    out DDRC, tmp0

    ; activar resistencias de pull up internas en los pines de botones
    ldi tmp0, 0b00001111
    out PORTC, tmp0

    ; habilitar interrupcion por cambio de pin solo en el grupo de PORTC
    ldi tmp0, (1<<PCIE1)
    sts PCICR, tmp0

    ; seleccionar solo los pines PC0 a PC3 dentro del grupo PORTC
    ldi tmp0, (1<<PCINT8)|(1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)
    sts PCMSK1, tmp0

    ; configurar Timer0 en modo CTC con interrupcion cada un milisegundo
    ldi tmp0, (1<<WGM01)
    out TCCR0A, tmp0
    ldi tmp0, (1<<CS01)|(1<<CS00)
    out TCCR0B, tmp0
    ldi tmp0, 249
    out OCR0A, tmp0
    ldi tmp0, (1<<OCIE0A)
    sts TIMSK0, tmp0

    sei

CICLO_PRINCIPAL:
    rcall PROCESAR_BOTONES
    rcall ACTUALIZAR_SALIDAS
    rcall CONSTRUIR_BUFFER
    rjmp CICLO_PRINCIPAL


; interrupcion del Timer0 que se ejecuta cada milisegundo
ISR_TICK_MS:
    push r16
    in   r16, SREG
    push r16
    push r17
    push r18
    push r19
    push r20
    push r24
    push r25
    push r30
    push r31

    ; contar hasta 500 milisegundos para controlar el parpadeo
    lds r24, cnt_500_l
    lds r25, cnt_500_h
    adiw r24, 1
    sts cnt_500_l, r24
    sts cnt_500_h, r25

    ldi r16, low(500)
    ldi r17, high(500)
    cp  r24, r16
    cpc r25, r17
    brne TICK_SALTAR_500

    ; al llegar a 500 ms resetear el contador e invertir el flag de parpadeo
    clr r16
    sts cnt_500_l, r16
    sts cnt_500_h, r16
    lds r16, flag_parpadeo
    ldi r17, 1
    eor r16, r17
    sts flag_parpadeo, r16

TICK_SALTAR_500:
    ; contar hasta 1000 milisegundos para el tick de segundos
    lds r24, cnt_ms_l
    lds r25, cnt_ms_h
    adiw r24, 1
    sts cnt_ms_l, r24
    sts cnt_ms_h, r25

    ldi r16, low(1000)
    ldi r17, high(1000)
    cp  r24, r16
    cpc r25, r17
    brne TICK_SALTAR_1S

    ; al completar el segundo resetear y avanzar el reloj
    clr r16
    sts cnt_ms_l, r16
    sts cnt_ms_h, r16
    rcall AVANZAR_SEGUNDO

TICK_SALTAR_1S:
    rcall REFRESCAR_DISPLAY

    pop r31
    pop r30
    pop r25
    pop r24
    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti


; interrupcion que detecta cambios en los pines de botones PC0 a PC3
ISR_BOTONES:
    push r16
    in   r16, SREG
    push r16
    push r17
    push r18

    ; leer el estado actual de los pines de botones
    in  r16, PINC
    lds r17, bloqueos
    lds r18, eventos

    ; verificar boton VER en PC0
    sbrs r16, 0
    rjmp BTN0_PRESIONADO
BTN0_SOLTADO:
    sbrs r17, BIT_BTN_VER
    rjmp VER_PC1
    cbr r17, (1<<BIT_BTN_VER)
    sbr r18, (1<<BIT_BTN_VER)
    rjmp VER_PC1
BTN0_PRESIONADO:
    sbr r17, (1<<BIT_BTN_VER)

VER_PC1:
    ; verificar boton SUBIR en PC1
    sbrs r16, 1
    rjmp BTN1_PRESIONADO
BTN1_SOLTADO:
    sbrs r17, BIT_BTN_SUB
    rjmp VER_PC2
    cbr r17, (1<<BIT_BTN_SUB)
    sbr r18, (1<<BIT_BTN_SUB)
    rjmp VER_PC2
BTN1_PRESIONADO:
    sbr r17, (1<<BIT_BTN_SUB)

VER_PC2:
    ; verificar boton BAJAR en PC2
    sbrs r16, 2
    rjmp BTN2_PRESIONADO
BTN2_SOLTADO:
    sbrs r17, BIT_BTN_BAJ
    rjmp VER_PC3
    cbr r17, (1<<BIT_BTN_BAJ)
    sbr r18, (1<<BIT_BTN_BAJ)
    rjmp VER_PC3
BTN2_PRESIONADO:
    sbr r17, (1<<BIT_BTN_BAJ)

VER_PC3:
    ; verificar boton MODO en PC3
    sbrs r16, 3
    rjmp BTN3_PRESIONADO
BTN3_SOLTADO:
    sbrs r17, BIT_BTN_MOD
    rjmp FIN_ISR_BTN
    cbr r17, (1<<BIT_BTN_MOD)
    sbr r18, (1<<BIT_BTN_MOD)
    rjmp FIN_ISR_BTN
BTN3_PRESIONADO:
    sbr r17, (1<<BIT_BTN_MOD)

FIN_ISR_BTN:
    sts bloqueos, r17
    sts eventos, r18

    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti


; lee los eventos pendientes y ejecuta la accion correspondiente
PROCESAR_BOTONES:
    push r16
    push r17

    lds r16, eventos
    tst r16
    breq PB_SALIR

    ; el boton MODO tiene prioridad sobre los demas
    sbrs r16, BIT_BTN_MOD
    rjmp PB_VER_VISTA
    cbr r16, (1<<BIT_BTN_MOD)
    sts eventos, r16
    rcall ACCION_MODO
    rjmp PB_SALIR

PB_VER_VISTA:
    lds r16, eventos
    sbrs r16, BIT_BTN_VER
    rjmp PB_VER_SUBIR
    cbr r16, (1<<BIT_BTN_VER)
    sts eventos, r16
    rcall ACCION_VISTA
    rjmp PB_SALIR

PB_VER_SUBIR:
    lds r16, eventos
    sbrs r16, BIT_BTN_SUB
    rjmp PB_VER_BAJAR
    cbr r16, (1<<BIT_BTN_SUB)
    sts eventos, r16
    rcall INCREMENTAR_CAMPO
    rjmp PB_SALIR

PB_VER_BAJAR:
    lds r16, eventos
    sbrs r16, BIT_BTN_BAJ
    rjmp PB_SALIR
    cbr r16, (1<<BIT_BTN_BAJ)
    sts eventos, r16
    rcall DECREMENTAR_CAMPO

PB_SALIR:
    pop r17
    pop r16
    ret


; maneja la pulsacion del boton MODO
ACCION_MODO:
    push r16
    push r17

    ; si la alarma esta sonando este boton la silencia
    lds r16, alarma_sonando
    tst r16
    breq AM_AVANZAR_MODO
    clr r16
    sts alarma_sonando, r16
    rjmp AM_FIN

AM_AVANZAR_MODO:
    ; avanzar al siguiente modo de edicion con vuelta al inicio en 7
    lds r16, modo_edicion
    inc r16
    cpi r16, 7
    brlo AM_GUARDAR
    clr r16

AM_GUARDAR:
    sts modo_edicion, r16

    ; forzar la vista correspondiente al modo recien activado
    cpi r16, MODO_HORA
    brne AM_C1
    ldi r17, VISTA_HORA
    sts vista_actual, r17
    rjmp AM_FIN

AM_C1:
    cpi r16, MODO_MINUTO
    brne AM_C2
    ldi r17, VISTA_HORA
    sts vista_actual, r17
    rjmp AM_FIN

AM_C2:
    cpi r16, MODO_DIA
    brne AM_C3
    ldi r17, VISTA_FECHA
    sts vista_actual, r17
    rjmp AM_FIN

AM_C3:
    cpi r16, MODO_MES
    brne AM_C4
    ldi r17, VISTA_FECHA
    sts vista_actual, r17
    rjmp AM_FIN

AM_C4:
    cpi r16, MODO_ALARM_H
    brne AM_C5
    ldi r17, VISTA_ALARMA
    sts vista_actual, r17
    rjmp AM_FIN

AM_C5:
    cpi r16, MODO_ALARM_M
    brne AM_FIN
    ldi r17, VISTA_ALARMA
    sts vista_actual, r17

AM_FIN:
    pop r17
    pop r16
    ret


; maneja la pulsacion del boton VER cambiando la vista activa
ACCION_VISTA:
    push r16

    ; la vista solo cambia cuando no hay ningun campo en edicion
    lds r16, modo_edicion
    tst r16
    brne AV_FIN

    lds r16, vista_actual
    inc r16
    cpi r16, 3
    brlo AV_GUARDAR
    clr r16

AV_GUARDAR:
    sts vista_actual, r16

AV_FIN:
    pop r16
    ret


; actualiza el estado del LED de dos puntos y del LED indicador de alarma
ACTUALIZAR_SALIDAS:
    push r16
    push r17

    ; en vista fecha los dos puntos permanecen fijos encendidos
    lds r16, vista_actual
    cpi r16, VISTA_FECHA
    brne AS_NO_FECHA
    ldi r17, 1
    sts puntos_on, r17
    rjmp AS_LED_ALARMA

AS_NO_FECHA:
    ; en otras vistas los dos puntos parpadean siguiendo el flag de parpadeo
    lds r17, flag_parpadeo
    sts puntos_on, r17

AS_LED_ALARMA:
    ; el LED indicador se enciende al ver o editar la alarma
    clr r17
    lds r16, vista_actual
    cpi r16, VISTA_ALARMA
    breq AS_LED_ON
    lds r16, modo_edicion
    cpi r16, MODO_ALARM_H
    breq AS_LED_ON
    cpi r16, MODO_ALARM_M
    breq AS_LED_ON
    rjmp AS_GUARDAR_LED

AS_LED_ON:
    ldi r17, 1

AS_GUARDAR_LED:
    sts led_alarma, r17

    pop r17
    pop r16
    ret


; arma el contenido del buffer de display segun la vista y el modo activos
CONSTRUIR_BUFFER:
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

    ; seleccionar los dos valores a mostrar segun la vista activa
    lds r16, vista_actual
    cpi r16, VISTA_HORA
    brne CB_VER_FECHA
    lds r16, horas
    lds r17, minutos
    rjmp CB_SEPARAR

CB_VER_FECHA:
    lds r18, vista_actual
    cpi r18, VISTA_FECHA
    brne CB_CARGAR_ALARMA
    lds r16, dia
    lds r17, mes
    rjmp CB_SEPARAR

CB_CARGAR_ALARMA:
    lds r16, alar_hora
    lds r17, alar_min

CB_SEPARAR:
    ; separar el valor izquierdo en decenas y unidades
    mov r24, r16
    rcall SEPARAR_DECIMAL
    mov r18, r24
    mov r19, r25

    ; separar el valor derecho en decenas y unidades
    mov r24, r17
    rcall SEPARAR_DECIMAL
    mov r20, r24
    mov r21, r25

    ; cuando el flag de parpadeo esta en cero blanquear el campo en edicion
    lds r16, flag_parpadeo
    tst r16
    brne CB_CONVERTIR

    lds r16, modo_edicion
    cpi r16, MODO_HORA
    breq CB_BLANQUEAR_IZQ
    cpi r16, MODO_DIA
    breq CB_BLANQUEAR_IZQ
    cpi r16, MODO_ALARM_H
    breq CB_BLANQUEAR_IZQ
    cpi r16, MODO_MINUTO
    breq CB_BLANQUEAR_DER
    cpi r16, MODO_MES
    breq CB_BLANQUEAR_DER
    cpi r16, MODO_ALARM_M
    breq CB_BLANQUEAR_DER
    rjmp CB_CONVERTIR

CB_BLANQUEAR_IZQ:
    ldi r18, COD_VACIO
    ldi r19, COD_VACIO
    rjmp CB_CONVERTIR

CB_BLANQUEAR_DER:
    ldi r20, COD_VACIO
    ldi r21, COD_VACIO

CB_CONVERTIR:
    ; convertir cada digito a su patron de segmentos y guardarlo en el buffer
    mov r24, r18
    rcall DIGITO_A_SEG
    sts seg_d0, r24

    mov r24, r19
    rcall DIGITO_A_SEG
    sts seg_d1, r24

    mov r24, r20
    rcall DIGITO_A_SEG
    sts seg_d2, r24

    mov r24, r21
    rcall DIGITO_A_SEG
    sts seg_d3, r24

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


; separa un numero de dos cifras en su decena y su unidad
; recibe el valor en r24 y devuelve decenas en r24 y unidades en r25
SEPARAR_DECIMAL:
    push r16
    clr r16
    clr r25

SD_BUCLE:
    cpi r24, 10
    brlo SD_FIN
    subi r24, 10
    inc r16
    rjmp SD_BUCLE

SD_FIN:
    mov r25, r24
    mov r24, r16
    pop r16
    ret


; consulta la tabla en flash y devuelve el patron de segmentos para el digito dado
; recibe el indice en r24 y devuelve el patron en r24
DIGITO_A_SEG:
    push ZH
    push ZL
    ldi ZH, high(TABLA_SEG<<1)
    ldi ZL, low(TABLA_SEG<<1)
    add ZL, r24
    adc ZH, r1
    lpm r24, Z
    pop ZL
    pop ZH
    ret


; enciende un digito del display por vez ciclando entre los cuatro disponibles
REFRESCAR_DISPLAY:
    push r16
    push r17
    push r18
    push r19
    push r20

    lds r16, indice_mux

    cpi r16, 0
    brne RD_CHK1
    lds r17, seg_d0
    ldi r18, (1<<PD5)
    rjmp RD_SALIDA

RD_CHK1:
    cpi r16, 1
    brne RD_CHK2
    lds r17, seg_d1
    ldi r18, (1<<PD4)
    rjmp RD_SALIDA

RD_CHK2:
    cpi r16, 2
    brne RD_CHK3
    lds r17, seg_d2
    ldi r18, (1<<PD3)
    rjmp RD_SALIDA

RD_CHK3:
    lds r17, seg_d3
    ldi r18, (1<<PD2)

RD_SALIDA:
    ; escribir segmentos A a E en PORTB y el LED de dos puntos en PB5
    mov r19, r17
    lsr r19
    lsr r19
    andi r19, 0b00011111

    lds r20, puntos_on
    tst r20
    breq RD_SIN_PUNTOS
    ori r19, (1<<PB5)

RD_SIN_PUNTOS:
    out PORTB, r19

    ; escribir segmentos F y G en PORTD junto con la linea de seleccion del digito
    clr r19
    sbrc r17, 1
    ori r19, (1<<PD7)
    sbrc r17, 0
    ori r19, (1<<PD6)
    or  r19, r18
    out PORTD, r19

    ; escribir en PORTC manteniendo los pull ups y activando LED y buzzer si corresponde
    ldi r19, 0b00001111

    lds r20, led_alarma
    tst r20
    breq RD_SIN_LED
    ori r19, (1<<PC4)

RD_SIN_LED:
    lds r20, alarma_sonando
    tst r20
    breq RD_SIN_BUZZER
    ori r19, (1<<PC5)

RD_SIN_BUZZER:
    out PORTC, r19

    ; avanzar al siguiente digito y volver a cero al llegar a cuatro
    lds r16, indice_mux
    inc r16
    cpi r16, 4
    brlo RD_GUARDAR
    clr r16

RD_GUARDAR:
    sts indice_mux, r16

    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    ret


; incrementa segundos minutos horas y delega el avance de fecha cuando corresponde
AVANZAR_SEGUNDO:
    push r16
    push r17

    lds r16, segundos
    inc r16
    cpi r16, 60
    brlo AVS_GUARDAR_SEG

    clr r16
    sts segundos, r16

    lds r16, minutos
    inc r16
    cpi r16, 60
    brlo AVS_GUARDAR_MIN

    clr r16
    sts minutos, r16

    lds r16, horas
    inc r16
    cpi r16, 24
    brlo AVS_GUARDAR_HORA

    clr r16
    sts horas, r16
    rcall AVANZAR_DIA
    rjmp AVS_VER_ALARMA

AVS_GUARDAR_HORA:
    sts horas, r16
    rjmp AVS_VER_ALARMA

AVS_GUARDAR_MIN:
    sts minutos, r16
    rjmp AVS_VER_ALARMA

AVS_GUARDAR_SEG:
    sts segundos, r16

AVS_VER_ALARMA:
    ; la alarma solo se activa en el segundo cero del minuto coincidente
    lds r16, segundos
    tst r16
    brne AVS_LIMPIAR_SI_TOCA

    lds r16, horas
    lds r17, alar_hora
    cp  r16, r17
    brne AVS_LIMPIAR_SI_TOCA

    lds r16, minutos
    lds r17, alar_min
    cp  r16, r17
    brne AVS_LIMPIAR_SI_TOCA

    ; verificar que no se haya activado ya en este mismo minuto
    lds r16, alarma_usada
    tst r16
    brne AVS_FIN

    ldi r16, 1
    sts alarma_sonando, r16
    sts alarma_usada, r16
    rjmp AVS_FIN

AVS_LIMPIAR_SI_TOCA:
    ; si la hora y el minuto ya no coinciden liberar el seguro para la proxima vez
    lds r16, horas
    lds r17, alar_hora
    cp  r16, r17
    brne AVS_LIBERAR_SEGURO

    lds r16, minutos
    lds r17, alar_min
    cp  r16, r17
    brne AVS_LIBERAR_SEGURO

    rjmp AVS_FIN

AVS_LIBERAR_SEGURO:
    clr r16
    sts alarma_usada, r16

AVS_FIN:
    pop r17
    pop r16
    ret


; incrementa el campo que esta siendo editado segun el modo activo
INCREMENTAR_CAMPO:
    push r16
    push r17
    push r18

    lds r16, modo_edicion

    cpi r16, MODO_HORA
    brne IC_MIN
    lds r17, horas
    inc r17
    cpi r17, 24
    brlo IC_GUARDAR_HORA
    clr r17
IC_GUARDAR_HORA:
    sts horas, r17
    rjmp IC_FIN

IC_MIN:
    cpi r16, MODO_MINUTO
    brne IC_DIA
    lds r17, minutos
    inc r17
    cpi r17, 60
    brlo IC_GUARDAR_MIN
    clr r17
IC_GUARDAR_MIN:
    sts minutos, r17
    clr r17
    sts segundos, r17
    rjmp IC_FIN

IC_DIA:
    cpi r16, MODO_DIA
    brne IC_MES
    lds r17, dia
    inc r17
    rcall MAX_DIAS_MES
    cp r17, r18
    brlo IC_GUARDAR_DIA
    breq IC_GUARDAR_DIA
    ldi r17, 1
IC_GUARDAR_DIA:
    sts dia, r17
    rjmp IC_FIN

IC_MES:
    cpi r16, MODO_MES
    brne IC_ALAR_H
    lds r17, mes
    inc r17
    cpi r17, 13
    brlo IC_GUARDAR_MES
    ldi r17, 1
IC_GUARDAR_MES:
    sts mes, r17
    lds r17, dia
    rcall MAX_DIAS_MES
    cp r17, r18
    brlo IC_FIN
    breq IC_FIN
    sts dia, r18
    rjmp IC_FIN

IC_ALAR_H:
    cpi r16, MODO_ALARM_H
    brne IC_ALAR_M
    lds r17, alar_hora
    inc r17
    cpi r17, 24
    brlo IC_GUARDAR_AH
    clr r17
IC_GUARDAR_AH:
    sts alar_hora, r17
    rjmp IC_FIN

IC_ALAR_M:
    cpi r16, MODO_ALARM_M
    brne IC_FIN
    lds r17, alar_min
    inc r17
    cpi r17, 60
    brlo IC_GUARDAR_AM
    clr r17
IC_GUARDAR_AM:
    sts alar_min, r17

IC_FIN:
    pop r18
    pop r17
    pop r16
    ret


; decrementa el campo que esta siendo editado segun el modo activo
DECREMENTAR_CAMPO:
    push r16
    push r17
    push r18

    lds r16, modo_edicion

    cpi r16, MODO_HORA
    brne DC_MIN
    lds r17, horas
    tst r17
    brne DC_DEC_HORA
    ldi r17, 23
    rjmp DC_GUARDAR_HORA
DC_DEC_HORA:
    dec r17
DC_GUARDAR_HORA:
    sts horas, r17
    rjmp DC_FIN

DC_MIN:
    cpi r16, MODO_MINUTO
    brne DC_DIA
    lds r17, minutos
    tst r17
    brne DC_DEC_MIN
    ldi r17, 59
    rjmp DC_GUARDAR_MIN
DC_DEC_MIN:
    dec r17
DC_GUARDAR_MIN:
    sts minutos, r17
    clr r17
    sts segundos, r17
    rjmp DC_FIN

DC_DIA:
    cpi r16, MODO_DIA
    brne DC_MES
    lds r17, dia
    cpi r17, 1
    brne DC_DEC_DIA
    rcall MAX_DIAS_MES
    mov r17, r18
    rjmp DC_GUARDAR_DIA
DC_DEC_DIA:
    dec r17
DC_GUARDAR_DIA:
    sts dia, r17
    rjmp DC_FIN

DC_MES:
    cpi r16, MODO_MES
    brne DC_ALAR_H
    lds r17, mes
    cpi r17, 1
    brne DC_DEC_MES
    ldi r17, 12
    rjmp DC_GUARDAR_MES
DC_DEC_MES:
    dec r17
DC_GUARDAR_MES:
    sts mes, r17
    lds r17, dia
    rcall MAX_DIAS_MES
    cp r17, r18
    brlo DC_FIN
    breq DC_FIN
    sts dia, r18
    rjmp DC_FIN

DC_ALAR_H:
    cpi r16, MODO_ALARM_H
    brne DC_ALAR_M
    lds r17, alar_hora
    tst r17
    brne DC_DEC_AH
    ldi r17, 23
    rjmp DC_GUARDAR_AH
DC_DEC_AH:
    dec r17
DC_GUARDAR_AH:
    sts alar_hora, r17
    rjmp DC_FIN

DC_ALAR_M:
    cpi r16, MODO_ALARM_M
    brne DC_FIN
    lds r17, alar_min
    tst r17
    brne DC_DEC_AM
    ldi r17, 59
    rjmp DC_GUARDAR_AM
DC_DEC_AM:
    dec r17
DC_GUARDAR_AM:
    sts alar_min, r17

DC_FIN:
    pop r18
    pop r17
    pop r16
    ret


; avanza el dia del calendario al llegar a medianoche
AVANZAR_DIA:
    push r16
    push r17
    push r18

    lds r16, dia
    inc r16

    rcall MAX_DIAS_MES
    cp r16, r18
    brlo ADR_GUARDAR_DIA
    breq ADR_GUARDAR_DIA

    ; si se supero el maximo del mes pasar al dia uno del mes siguiente
    ldi r16, 1
    sts dia, r16

    lds r17, mes
    inc r17
    cpi r17, 13
    brlo ADR_GUARDAR_MES
    ldi r17, 1

ADR_GUARDAR_MES:
    sts mes, r17
    rjmp ADR_FIN

ADR_GUARDAR_DIA:
    sts dia, r16

ADR_FIN:
    pop r18
    pop r17
    pop r16
    ret


; devuelve en r18 la cantidad de dias del mes almacenado en la variable mes
; febrero siempre se trata con 28 dias sin considerar años bisiestos
MAX_DIAS_MES:
    push r16

    lds r16, mes

    cpi r16, 2
    breq MDM_FEB

    cpi r16, 4
    breq MDM_30
    cpi r16, 6
    breq MDM_30
    cpi r16, 9
    breq MDM_30
    cpi r16, 11
    breq MDM_30

    ldi r18, 31
    rjmp MDM_FIN

MDM_FEB:
    ldi r18, 28
    rjmp MDM_FIN

MDM_30:
    ldi r18, 30

MDM_FIN:
    pop r16
    ret