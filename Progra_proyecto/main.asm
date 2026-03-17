;Guillermo Jo 
;24616
;Proyecto 1

.include "m328pdef.inc"

; Constantes con nombre para los modos de edición
.equ MODE_NORMAL    = 0     ; Sin campo en edición
.equ MODE_SET_HOUR  = 1     ; Editando horas del reloj
.equ MODE_SET_MIN   = 2     ; Editando minutos del reloj
.equ MODE_SET_DAY   = 3     ; Editando día del calendario
.equ MODE_SET_MON   = 4     ; Editando mes del calendario
.equ MODE_SET_AH    = 5     ; Editando hora de alarma
.equ MODE_SET_AM    = 6     ; Editando minuto de alarma

; Constantes con nombre para las vistas del display
.equ VIEW_TIME      = 0     ; Muestra HH:MM
.equ VIEW_DATE      = 1     ; Muestra DD:MM
.equ VIEW_ALARM     = 2     ; Muestra alarma HH:MM

; Posiciones de bit en los registros de estado de botones
.equ BTN_VIEW_BIT   = 0
.equ BTN_UP_BIT     = 1
.equ BTN_DOWN_BIT   = 2
.equ BTN_MODE_BIT   = 3

; Código de dígito, mapea a "todos los segmentos apagados" en SEG_TABLE
.equ BLANK_CODE     = 10

; REGISTROS
; Todos los temporales
.def rA   = r16
.def rB   = r17     
.def rC   = r18     
.def rD   = r19     
.def rE   = r20     
.def rF   = r21     
.def rG   = r22     
.def rH   = r23     

;SEGMENTO DE DATOS EN SRAM
.dseg

;Campos del reloj en tiempo real
hour:           .byte 1     ; 0..23
minute:         .byte 1     ; 0..59
second:         .byte 1     ; 0..59

;Campos del calendario
day:            .byte 1     ; 1..31
month:          .byte 1     ; 1..12

;Configuración de alarma
alarm_hour:     .byte 1     ; 0..23
alarm_min:      .byte 1     ; 0..59

;Estado
current_view:   .byte 1     ; VIEW_TIME / VIEW_DATE / VIEW_ALARM
edit_mode:      .byte 1     ; MODE_NORMAL .. MODE_SET_AM

;Auxiliares
blink_flag:     .byte 1     ; Se invierte cada 500 ms; controla parpadeo y colon
ms_count_l:     .byte 1     ; Byte bajo del contador 0-999 ms
ms_count_h:     .byte 1     ; Byte alto del contador 0-999 ms
halfsec_l:      .byte 1     ; Byte bajo del contador 0-499 ms
halfsec_h:      .byte 1     ; Byte alto del contador 0-499 ms

;Driver del display
scan_idx:       .byte 1     ; Posición del dígito que se está manejando (0..3)
disp0:          .byte 1     ; Patrón de segmentos para dígito 0 (más a la izquierda)
disp1:          .byte 1     ; Patrón de segmentos para dígito 1
disp2:          .byte 1     ; Patrón de segmentos para dígito 2
disp3:          .byte 1     ; Patrón de segmentos para dígito 3 (más a la derecha)

; Flags de control por evento de presionar y soltar
; btn_locks : bit activo mientras el botón está presionado (evita eventos repetidos)
; btn_events: bit activo en flanco de soltar; limpiado por PROCESS_BUTTON_EVENTS
btn_locks:      .byte 1
btn_events:     .byte 1

; Estado de la alarma
; alarm_ringing : 1 mientras el buzzer debe sonar; se limpia con el botón MODE
; alarm_latched : evita re-activación dentro del mismo minuto de alarma
alarm_ringing:  .byte 1
alarm_latched:  .byte 1

; Control de salidas
colon_on:   .byte 1     ; 1 = LED de dos puntos habilitado en este ciclo MUX
aux_led:    .byte 1     ; 1 = LED indicador de alarma habilitado

; SEGMENTO DE CÓDIGO
.cseg


; Tabla de interrupciones
; Solo se usan dos vectores
.org 0x0000
    rjmp RESET              ; Encendido / reset externo

.org 0x0002
    reti
.org 0x0004
    reti
.org 0x0006
    reti
.org 0x0008
    rjmp ISR_PCINT1         ; PCINT1 (pines PORTC) -> manejador de botones
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
    rjmp ISR_TIMER0_COMPA   ; TIMER0 COMPA -> tick de 1 ms
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

; TABLA DE LOOKUP 7 SEGMENTOS
SEG_TABLE:
    .db 0b1111110, 0b0110000, 0b1101101, 0b1111001, 0b0110011, 0b1011011, 0b1011111, 0b1110000, 0b1111111, 0b1111011, 0b0000000, 0b0000000


; Se ejecuta una vez al encender o tras cualquier fuente de reset.
RESET:
    ;Configuración del puntero
    ldi rA, high(RAMEND)
    out SPH, rA
    ldi rA, low(RAMEND)
    out SPL, rA
    clr r1                  ; r1 se mantiene en 0

    ;Valores iniciales del reloj
    ldi rA, 12
    sts hour, rA            ; Arranca en 12:00:00
    clr rA
    sts minute, rA
    sts second, rA

    ;Valores iniciales del calendario
    ldi rA, 1
    sts day, rA             ; 1 de enero
    sts month, rA

    ;Valores iniciales de la alarma
    ldi rA, 6
    sts alarm_hour, rA      ; Alarma por defecto a las 06:00
    clr rA
    sts alarm_min, rA

    ;Poner en cero todas las variables de UI y control
    clr rA
    sts current_view, rA
    sts edit_mode, rA
    sts blink_flag, rA
    sts ms_count_l, rA
    sts ms_count_h, rA
    sts halfsec_l, rA
    sts halfsec_h, rA
    sts scan_idx, rA
    sts btn_locks, rA
    sts btn_events, rA
    sts alarm_ringing, rA
    sts alarm_latched, rA
    sts colon_on, rA
    sts aux_led, rA
    sts disp0, rA
    sts disp1, rA
    sts disp2, rA
    sts disp3, rA

    ;Registros de dirección de GPIO
    ; PORTB: PB0-PB5 todas salidas
    ldi rA, 0b00111111
    out DDRB, rA

    ; PORTD: PD2-PD7 salidas
    ldi rA, 0b11111100
    out DDRD, rA

    ; PORTD valor inicial
    clr rA
    out PORTD, rA

    ; PORTC: PC0-PC3 entradas, PC4 salida, PC5 salida
    ldi rA, 0b00110000
    out DDRC, rA

    ; Activar pull-ups internos en los pines de botones PC0-PC3
    ; El botón lee 0 cuando está presionado y 1 cuando está suelto
    ldi rA, 0b00001111
    out PORTC, rA

    ;Configuración de interrupción por cambio de pin
    ; Habilitar PCIE1 para monitorear PORTC
    ldi rA, (1<<PCIE1)
    sts PCICR, rA

    ; Desenmascarar solo PC0-PC3 dentro del grupo PORTC
    ldi rA, (1<<PCINT8)|(1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)
    sts PCMSK1, rA

    ;Configuración Timer0: CTC
    ; f_tick = 16.000.000 / (64 * (249+1)) = 1000 Hz  => período = 1 ms
    ldi rA, (1<<WGM01)          ; Modo CTC
    out TCCR0A, rA
    ldi rA, (1<<CS01)|(1<<CS00) ; Prescaler = 64
    out TCCR0B, rA
    ldi rA, 249                 ; OCR0A = 249 -> comparación cada 1 ms
    out OCR0A, rA
    ldi rA, (1<<OCIE0A)         ; Habilitar interrupción Output Compare A
    sts TIMSK0, rA
    sei                         ; Habilitar interrupciones globales

; BUCLE PRINCIPAL
MAIN_LOOP:
    rcall PROCESS_BUTTON_EVENTS ; Procesar eventos pendientes de botones soltados
    rcall UPDATE_UI_STATE       
    rcall BUILD_DISPLAY_BUFFER  
    rjmp  MAIN_LOOP

; ISR_TIMER0_COMPA  - Se dispara cada 1 ms
ISR_TIMER0_COMPA:
    push r16
    in   r16, SREG              ; Guardar registro de estado
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

    ;Contador de 500 ms
    lds r24, halfsec_l
    lds r25, halfsec_h
    adiw r24, 1                 ; Incremento de 16 bits
    sts halfsec_l, r24
    sts halfsec_h, r25

    ldi rA, low(500)
    ldi rB, high(500)
    cp  r24, rA
    cpc r25, rB
    brne T0_SKIP_500            ; Aún no llegó a 500 -> saltar el toggle

    ; Resetear contador e invertir blink_flag
    clr rA
    sts halfsec_l, rA
    sts halfsec_h, rA

    lds rA, blink_flag
    ldi rB, 1
    eor rA, rB                  ; Invertir bit 0
    sts blink_flag, rA

T0_SKIP_500:
    ;Contador de 1000 ms 
    lds r24, ms_count_l
    lds r25, ms_count_h
    adiw r24, 1
    sts ms_count_l, r24
    sts ms_count_h, r25

    ldi rA, low(1000)
    ldi rB, high(1000)
    cp  r24, rA
    cpc r25, rB
    brne T0_SKIP_1S             ; Aún no llegó a 1000 -> saltar tick del reloj

    ; Resetear contador y avanzar el reloj
    clr rA
    sts ms_count_l, rA
    sts ms_count_h, rA

    rcall CLOCK_TICK_1S         ; Incrementar segundos y verificar alarma

T0_SKIP_1S:
    rcall MUX_REFRESH           ; Refrescar un dígito

    ; Restaurar todos los registros en orden inverso
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

; ISR_PCINT1  - Interrupción por cambio de pin en PORTC
ISR_PCINT1:
    push r16
    in   r16, SREG
    push r16
    push r17
    push r18

    in  rA, PINC            ; Leer estado actual de botones (0 = presionado)
    lds rB, btn_locks       ; Sombra: qué botones estaban presionados antes
    lds rC, btn_events      ; Eventos pendientes aún no consumidos por el bucle principal

    ;PC0 -> botón VIEW
    sbrs rA, 0              ; Si bit 0 = 1, el pin está en HIGH - botón suelto
    rjmp PC0_PRESSED
PC0_RELEASED:
    sbrs rB, BTN_VIEW_BIT   ; ¿Estaba bloqueado? (¿se registró la presión?)
    rjmp CHECK_PC1
    cbr rB, (1<<BTN_VIEW_BIT)      ; Limpiar bloqueo
    sbr rC, (1<<BTN_VIEW_BIT)      ; Registrar evento de soltar
    rjmp CHECK_PC1
PC0_PRESSED:
    sbr rB, (1<<BTN_VIEW_BIT)      ; Marcar como mantenido presionado

CHECK_PC1:
    ;PC1 - botón UP
    sbrs rA, 1
    rjmp PC1_PRESSED
PC1_RELEASED:
    sbrs rB, BTN_UP_BIT
    rjmp CHECK_PC2
    cbr rB, (1<<BTN_UP_BIT)
    sbr rC, (1<<BTN_UP_BIT)
    rjmp CHECK_PC2
PC1_PRESSED:
    sbr rB, (1<<BTN_UP_BIT)

CHECK_PC2:
    ;PC2 - botón DOWN
    sbrs rA, 2
    rjmp PC2_PRESSED
PC2_RELEASED:
    sbrs rB, BTN_DOWN_BIT
    rjmp CHECK_PC3
    cbr rB, (1<<BTN_DOWN_BIT)
    sbr rC, (1<<BTN_DOWN_BIT)
    rjmp CHECK_PC3
PC2_PRESSED:
    sbr rB, (1<<BTN_DOWN_BIT)

CHECK_PC3:
    ;PC3 - botón MODE
    sbrs rA, 3
    rjmp PC3_PRESSED
PC3_RELEASED:
    sbrs rB, BTN_MODE_BIT
    rjmp ISR_PC1_END
    cbr rB, (1<<BTN_MODE_BIT)
    sbr rC, (1<<BTN_MODE_BIT)
    rjmp ISR_PC1_END
PC3_PRESSED:
    sbr rB, (1<<BTN_MODE_BIT)

ISR_PC1_END:
    sts btn_locks,  rB      ; Persistir estado de bloqueos actualizado
    sts btn_events, rC      ; Persistir flags de eventos actualizados

    pop r18
    pop r17
    pop r16
    out SREG, r16
    pop r16
    reti

; PROCESS_BUTTON_EVENTS
; Cada evento manejado se limpia antes del despacho para que una ISR re-entrante no pierda el siguiente flanco.
PROCESS_BUTTON_EVENTS:
    push r16
    push r17
    push r18

    lds rA, btn_events
    tst rA
    brne PBE_GO
    rjmp PBE_END            ;Sin eventos pendientes - retorno rápido
PBE_GO:

    ; ---- Evento botón MODE --------------------------------------------------
    sbrs rA, BTN_MODE_BIT
    rjmp PBE_CHECK_VIEW

    cbr rA, (1<<BTN_MODE_BIT)
    sts btn_events, rA      ; Limpiar evento inmediatamente

    ; Si la alarma está sonando, MODE la silencia
    lds rB, alarm_ringing
    tst rB
    breq PBE_MODE_NEXT
    clr rB
    sts alarm_ringing, rB
    rjmp PBE_END

PBE_MODE_NEXT:
    ; Avanzar edit_mode, con vuelta de 6 -> 0
    lds rB, edit_mode
    inc rB
    cpi rB, 7
    brlo PBE_MODE_OK
    clr rB
PBE_MODE_OK:
    sts edit_mode, rB

    ;Forzar la vista que corresponde al nuevo modo de edición
    cpi rB, MODE_SET_HOUR
    brne PBE_MODE_CHK1
    ldi rC, VIEW_TIME
    sts current_view, rC
    rjmp PBE_END

PBE_MODE_CHK1:
    cpi rB, MODE_SET_MIN
    brne PBE_MODE_CHK2
    ldi rC, VIEW_TIME
    sts current_view, rC
    rjmp PBE_END

PBE_MODE_CHK2:
    cpi rB, MODE_SET_DAY
    brne PBE_MODE_CHK3
    ldi rC, VIEW_DATE
    sts current_view, rC
    rjmp PBE_END

PBE_MODE_CHK3:
    cpi rB, MODE_SET_MON
    brne PBE_MODE_CHK4
    ldi rC, VIEW_DATE
    sts current_view, rC
    rjmp PBE_END

PBE_MODE_CHK4:
    cpi rB, MODE_SET_AH
    brne PBE_MODE_CHK5
    ldi rC, VIEW_ALARM
    sts current_view, rC
    rjmp PBE_END

PBE_MODE_CHK5:
    cpi rB, MODE_SET_AM
    brne PBE_END
    ldi rC, VIEW_ALARM
    sts current_view, rC
    rjmp PBE_END

    ;Evento botón VIEW
    ;Solo funciona en modo normal
PBE_CHECK_VIEW:
    lds rA, btn_events
    sbrs rA, BTN_VIEW_BIT
    rjmp PBE_CHECK_UP

    cbr rA, (1<<BTN_VIEW_BIT)
    sts btn_events, rA

    lds rB, edit_mode
    tst rB
    brne PBE_END            ;Ignorar VIEW mientras se está en modo edición

    lds rB, current_view
    inc rB
    cpi rB, 3
    brlo PBE_VIEW_OK
    clr rB                  ;Vuelta de VIEW_ALARM - VIEW_TIME
PBE_VIEW_OK:
    sts current_view, rB
    rjmp PBE_END

    ;Evento botón UP
PBE_CHECK_UP:
    lds rA, btn_events
    sbrs rA, BTN_UP_BIT
    rjmp PBE_CHECK_DOWN

    cbr rA, (1<<BTN_UP_BIT)
    sts btn_events, rA
    rcall INCREMENT_ACTIVE_FIELD
    rjmp PBE_END

    ;Evento botón DOWN
PBE_CHECK_DOWN:
    lds rA, btn_events
    sbrs rA, BTN_DOWN_BIT
    rjmp PBE_END

    cbr rA, (1<<BTN_DOWN_BIT)
    sts btn_events, rA
    rcall DECREMENT_ACTIVE_FIELD

PBE_END:
    pop r18
    pop r17
    pop r16
    ret

; UPDATE_UI_STATE
; Calcula los flags colon_on y aux_led que usa MUX_REFRESH
UPDATE_UI_STATE:
    push r16
    push r17

    ; Determinar estado del colon
    lds rA, current_view
    cpi rA, VIEW_DATE
    brne UI_NOT_DATE
    ldi rB, 1               ; Vista fecha: colon permanentemente encendido
    sts colon_on, rB
    rjmp UI_AUX

UI_NOT_DATE:
    lds rB, blink_flag      ; Otras vistas: colon parpadea a 1 Hz
    sts colon_on, rB

UI_AUX:
    ; Determinar estado del LED indicador de alarma
    clr rB

    lds rA, current_view
    cpi rA, VIEW_ALARM
    breq UI_AUX_ON          ; Viendo alarma - LED encendido

    ; También encendido al configurar los campos de alarma
    lds rA, edit_mode
    cpi rA, MODE_SET_AH
    breq UI_AUX_ON
    cpi rA, MODE_SET_AM
    breq UI_AUX_ON
    rjmp UI_AUX_STORE

UI_AUX_ON:
    ldi rB, 1

UI_AUX_STORE:
    sts aux_led, rB

    pop r17
    pop r16
    ret

; BUILD_DISPLAY_BUFFER
; Determina qué par de dígitos mostrar según current_view, separa cada valor en decenas/unidades, aplica el blanco de parpadeo para el campo en edición, y convierte cada dígito a su patrón de segmento.
BUILD_DISPLAY_BUFFER:
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

    ;Seleccionar fuente de datos según la vista
    lds rA, current_view
    cpi rA, VIEW_TIME
    brne BDB_CHK_DATE
    lds rB, hour            ; Mostrar HH:MM
    lds rC, minute
    rjmp BDB_SPLIT_PAIR

BDB_CHK_DATE:
    cpi rA, VIEW_DATE
    brne BDB_ALARM
    lds rB, day             ; Mostrar DD:MM
    lds rC, month
    rjmp BDB_SPLIT_PAIR

BDB_ALARM:
    lds rB, alarm_hour      ; Mostrar alarma HH:MM
    lds rC, alarm_min

BDB_SPLIT_PAIR:
    ; Separar valor izquierdo en decenas (r18) y unidades (r19)
    mov r24, rB
    rcall SPLIT_DECIMAL
    mov r18, r24            ; Dígito de decenas
    mov r19, r25            ; Dígito de unidades

    ; Separar valor derecho en decenas (r20) y unidades (r21)
    mov r24, rC
    rcall SPLIT_DECIMAL
    mov r20, r24            ; Dígito de decenas
    mov r21, r25            ; Dígito de unidades

    ; Lógica de parpadeo
    ; Cuando blink_flag == 0, blanquear el campo en edición.
    lds rA, blink_flag
    tst rA
    brne BDB_CONVERT        ; mostrar todos los dígitos normalmente

    lds rA, edit_mode
    cpi rA, MODE_SET_HOUR
    breq BDB_BLANK_LEFT
    cpi rA, MODE_SET_DAY
    breq BDB_BLANK_LEFT
    cpi rA, MODE_SET_AH
    breq BDB_BLANK_LEFT
    cpi rA, MODE_SET_MIN
    breq BDB_BLANK_RIGHT
    cpi rA, MODE_SET_MON
    breq BDB_BLANK_RIGHT
    cpi rA, MODE_SET_AM
    breq BDB_BLANK_RIGHT
    rjmp BDB_CONVERT        ; MODE_NORMAL

BDB_BLANK_LEFT:
    ; Reemplazar dígitos del par izquierdo con BLANK_CODE
    ldi r18, BLANK_CODE
    ldi r19, BLANK_CODE
    rjmp BDB_CONVERT

BDB_BLANK_RIGHT:
    ldi r20, BLANK_CODE
    ldi r21, BLANK_CODE

BDB_CONVERT:
    ; Convertir cada índice de dígito al patrón de segmento de hardware
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
    pop r23
    pop r22
    pop r21
    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    ret

; SPLIT_DECIMAL

; Algoritmo: resta repetida de 10.
SPLIT_DECIMAL:
    clr r25
    clr rA              ; Acumula el conteo de decenas
SPLIT_LOOP:
    cpi r24, 10
    brlo SPLIT_DONE     ; r24 < 10 - el residuo es el dígito de unidades
    subi r24, 10
    inc rA
    rjmp SPLIT_LOOP
SPLIT_DONE:
    mov r25, r24        ; Residuo - unidades
    mov r24, rA         ; Conteo  - decenas
    ret

; DIGIT_TO_SEG
; Usa el registro Z (ZH:ZL) como puntero a memoria de programa.
DIGIT_TO_SEG:
    push ZH
    push ZL
    ldi ZH, high(SEG_TABLE<<1)
    ldi ZL, low(SEG_TABLE<<1)
    add ZL, r24             ; Desplazamiento al dígito solicitado
    adc ZH, r1              ; Acarreo al byte alto
    lpm r24, Z              ; Cargar byte desde la flash
    pop ZL
    pop ZH
    ret

; MUX_REFRESH
; Llamado cada 1 ms desde ISR_TIMER0_COMPA.
; Maneja un dígito por llamada, ciclando scan_idx 0->1->2->3->0...
MUX_REFRESH:
    push r16
    push r17
    push r18
    push r19
    push r20

    lds rA, scan_idx

    ; Seleccionar datos de segmento y pin de selección para la ranura actual
    cpi rA, 0
    brne MUX_CHK1
    lds rB, disp0
    ldi rC, (1<<PD5)        ; Dígito 0 en PD5
    rjmp MUX_OUTPUT

MUX_CHK1:
    cpi rA, 1
    brne MUX_CHK2
    lds rB, disp1
    ldi rC, (1<<PD4)        ; Dígito 1 en PD4
    rjmp MUX_OUTPUT

MUX_CHK2:
    cpi rA, 2
    brne MUX_CHK3
    lds rB, disp2
    ldi rC, (1<<PD3)        ; Dígito 2 en PD3
    rjmp MUX_OUTPUT

MUX_CHK3:
    lds rB, disp3
    ldi rC, (1<<PD2)        ; Dígito 3 en PD2

MUX_OUTPUT:
    mov rD, rB
    lsr rD
    lsr rD
    andi rD, 0b00011111

    lds rE, colon_on
    tst rE
    breq MUX_NO_COLON
    ori rD, (1<<PB5)        ; Activar bit del LED colon
MUX_NO_COLON:
    out PORTB, rD

    ; PORTD: segmentos F y G  + selección de dígito 
    clr rD
    sbrc rB, 1              ; Bit 1 del byte de segmento = seg F
    ori rD, (1<<PD7)
    sbrc rB, 0              ; Bit 0 del byte de segmento = seg G
    ori rD, (1<<PD6)
    or   rD, rC             ; OR con el bit de selección de dígito
    out PORTD, rD

    ; PORTC: mantener pull-ups, manejar LED y buzzer
    ldi rD, 0b00001111      ; Base: pull-ups en PC0-PC3, salidas en bajo

    lds rE, aux_led
    tst rE
    breq MUX_NO_AUX
    ori rD, (1<<PC4)        ; Encender LED indicador de alarma
MUX_NO_AUX:

    lds rE, alarm_ringing
    tst rE
    breq MUX_NO_BUZZ
    ori rD, (1<<PC5)        ; Activar buzzer
MUX_NO_BUZZ:
    out PORTC, rD

    ; Avanzar índice de escaneo, vuelta en 4 
    lds rA, scan_idx
    inc rA
    cpi rA, 4
    brlo MUX_STORE
    clr rA
MUX_STORE:
    sts scan_idx, rA

    pop r20
    pop r19
    pop r18
    pop r17
    pop r16
    ret

; CLOCK_TICK_1S
; Llamado una vez por segundo desde ISR_TIMER0_COMPA.
CLOCK_TICK_1S:
    push r16
    push r17
    push r18

    ; Segundos: 0..59 
    lds rA, second
    inc rA
    cpi rA, 60
    brlo CT_STORE_SEC       ; Aún no es 60: guardar y saltar a verificación de alarma

    ; Segundo desbordado - incrementar minutos
    clr rA
    sts second, rA

    lds rA, minute
    inc rA
    cpi rA, 60
    brlo CT_STORE_MIN

    ; Minuto desbordado - incrementar horas
    clr rA
    sts minute, rA

    lds rA, hour
    inc rA
    cpi rA, 24
    brlo CT_STORE_HOUR

    ; Hora desbordada - incrementar día
    clr rA
    sts hour, rA
    rcall INCREMENT_DAY_ROLLOVER
    rjmp CT_ALARM_CHECK

CT_STORE_HOUR:
    sts hour, rA
    rjmp CT_ALARM_CHECK

CT_STORE_MIN:
    sts minute, rA
    rjmp CT_ALARM_CHECK

CT_STORE_SEC:
    sts second, rA

CT_ALARM_CHECK:
    ; Evaluar solo en el segundo 0
    lds rA, second
    tst rA
    brne CT_CLEAR_IF_NEEDED ; No es segundo 0: verificar si hay que limpiar el latch

    ; Verificar coincidencia de hora
    lds rA, hour
    lds rB, alarm_hour
    cp  rA, rB
    brne CT_CLEAR_IF_NEEDED ; Hora no coincide: limpiar latch si está lejos de la alarma

    ; Verificar coincidencia de minuto
    lds rA, minute
    lds rB, alarm_min
    cp  rA, rB
    brne CT_CLEAR_IF_NEEDED

    ; Hora y minuto coinciden en segundo 0: activar alarma si no está latcheada
    lds rA, alarm_latched
    tst rA
    brne CT_END             ; Ya se activó este minuto: no hacer nada

    ldi rA, 1
    sts alarm_ringing, rA   ; Comenzar a sonar
    sts alarm_latched, rA   ; Activar latch para evitar re-activación
    rjmp CT_END

CT_CLEAR_IF_NEEDED:
    ; Se llega aquí cuando la hora no coincide con alarm_hour:alarm_min. Antes de limpiar el latch, confirmar que realmente estamos lejos del match
    lds rA, hour
    lds rB, alarm_hour
    cp  rA, rB
    brne CT_CLEAR_LATCH     ; Hora diferente - definitivamente lejos de la alarma

    lds rA, minute
    lds rB, alarm_min
    cp  rA, rB
    brne CT_CLEAR_LATCH     ; Minuto diferente - definitivamente lejos de la alarma

    rjmp CT_END             ; Mismo HH:MM pero second!=0 dejar el latch intacto

CT_CLEAR_LATCH:
    clr rA
    sts alarm_latched, rA   ; Dejar que la alarma se active en la próxima coincidencia

CT_END:
    pop r18
    pop r17
    pop r16
    ret

; INCREMENT_ACTIVE_FIELD
; Incrementa el campo de reloj/calendario/alarma que corresponde al edit_mode actual. Envuelve cada campo dentro de su rango válido.
INCREMENT_ACTIVE_FIELD:
    push r16
    push r17

    lds rA, edit_mode

    ; Incrementar hora
    cpi rA, MODE_SET_HOUR
    brne IAF_CHK_MIN
    lds rB, hour
    inc rB
    cpi rB, 24
    brlo IAF_H_OK
    clr rB                  ; Vuelta de 24 - 0
IAF_H_OK:
    sts hour, rB
    rjmp IAF_END

    ; Incrementar minuto
IAF_CHK_MIN:
    cpi rA, MODE_SET_MIN
    brne IAF_CHK_DAY
    lds rB, minute
    inc rB
    cpi rB, 60
    brlo IAF_M_OK
    clr rB
IAF_M_OK:
    sts minute, rB
    clr rB
    sts second, rB          ; Resetear segundos para ajuste limpio de hora
    rjmp IAF_END

    ; Incrementar día
IAF_CHK_DAY:
    cpi rA, MODE_SET_DAY
    brne IAF_CHK_MON
    lds rB, day
    inc rB
    rcall GET_MONTH_MAXDAY  ; Devuelve máximo de días en rC
    cp  rB, rC
    brlo IAF_D_OK
    breq IAF_D_OK           ; Permitir día == máximo
    ldi rB, 1               ; Vuelta al superar el máximo - día 1
IAF_D_OK:
    sts day, rB
    rjmp IAF_END

    ; Incrementar mes (1..12) y ajustar día si es necesario
IAF_CHK_MON:
    cpi rA, MODE_SET_MON
    brne IAF_CHK_AH
    lds rB, month
    inc rB
    cpi rB, 13
    brlo IAF_MON_OK
    ldi rB, 1               ; Vuelta de diciembre - enero
IAF_MON_OK:
    sts month, rB
    lds rB, day
    rcall GET_MONTH_MAXDAY
    cp  rB, rC
    brlo IAF_END
    breq IAF_END
    sts day, rC             ; Limitar día al máximo del nuevo mes
    rjmp IAF_END

    ; Incrementar hora de alarma
IAF_CHK_AH:
    cpi rA, MODE_SET_AH
    brne IAF_CHK_AM
    lds rB, alarm_hour
    inc rB
    cpi rB, 24
    brlo IAF_AH_OK
    clr rB
IAF_AH_OK:
    sts alarm_hour, rB
    rjmp IAF_END

    ; Incrementar minuto de alarma
IAF_CHK_AM:
    cpi rA, MODE_SET_AM
    brne IAF_END
    lds rB, alarm_min
    inc rB
    cpi rB, 60
    brlo IAF_AM_OK
    clr rB
IAF_AM_OK:
    sts alarm_min, rB

IAF_END:
    pop r17
    pop r16
    ret

; DECREMENT_ACTIVE_FIELD
; Espejo de INCREMENT_ACTIVE_FIELD, decrementando cada campo con vuelta circular, los valores por debajo del mínimo vuelven al máximo del campo.
DECREMENT_ACTIVE_FIELD:
    push r16
    push r17

    lds rA, edit_mode

    ; Decrementar hora
    cpi rA, MODE_SET_HOUR
    brne DAF_CHK_MIN
    lds rB, hour
    tst rB
    brne DAF_H_DEC
    ldi rB, 23              ; Vuelta de 0 - 23
    rjmp DAF_H_STORE
DAF_H_DEC:
    dec rB
DAF_H_STORE:
    sts hour, rB
    rjmp DAF_END

    ; Decrementar minuto
DAF_CHK_MIN:
    cpi rA, MODE_SET_MIN
    brne DAF_CHK_DAY
    lds rB, minute
    tst rB
    brne DAF_M_DEC
    ldi rB, 59
    rjmp DAF_M_STORE
DAF_M_DEC:
    dec rB
DAF_M_STORE:
    sts minute, rB
    clr rB
    sts second, rB          ; Resetear segundos al cambiar el minuto
    rjmp DAF_END

    ; Decrementar día, vuelta al último día del mes actual
DAF_CHK_DAY:
    cpi rA, MODE_SET_DAY
    brne DAF_CHK_MON
    lds rB, day
    cpi rB, 1
    brne DAF_D_DEC
    rcall GET_MONTH_MAXDAY  ; Vuelta de 1 - último día del mes
    mov rB, rC
    rjmp DAF_D_STORE
DAF_D_DEC:
    dec rB
DAF_D_STORE:
    sts day, rB
    rjmp DAF_END

    ; Decrementar mes (1..12), ajustar día si es necesario
DAF_CHK_MON:
    cpi rA, MODE_SET_MON
    brne DAF_CHK_AH
    lds rB, month
    cpi rB, 1
    brne DAF_MON_DEC
    ldi rB, 12              ; Vuelta de enero - diciembre
    rjmp DAF_MON_STORE
DAF_MON_DEC:
    dec rB
DAF_MON_STORE:
    sts month, rB
    lds rB, day
    rcall GET_MONTH_MAXDAY
    cp  rB, rC
    brlo DAF_END
    breq DAF_END
    sts day, rC             ; Limitar día al máximo del nuevo mes
    rjmp DAF_END

    ; Decrementar hora de alarma
DAF_CHK_AH:
    cpi rA, MODE_SET_AH
    brne DAF_CHK_AM
    lds rB, alarm_hour
    tst rB
    brne DAF_AH_DEC
    ldi rB, 23
    rjmp DAF_AH_STORE
DAF_AH_DEC:
    dec rB
DAF_AH_STORE:
    sts alarm_hour, rB
    rjmp DAF_END

    ; Decrementar minuto de alarma
DAF_CHK_AM:
    cpi rA, MODE_SET_AM
    brne DAF_END
    lds rB, alarm_min
    tst rB
    brne DAF_AM_DEC
    ldi rB, 59
    rjmp DAF_AM_STORE
DAF_AM_DEC:
    dec rB
DAF_AM_STORE:
    sts alarm_min, rB

DAF_END:
    pop r17
    pop r16
    ret

; INCREMENT_DAY_ROLLOVER
; Llamado por CLOCK_TICK_1S al desbordarse la medianoche.
; Avanza el día del calendario, pasando al día 1 del mes siguiente
INCREMENT_DAY_ROLLOVER:
    push r16
    push r17

    lds rA, day
    inc rA

    rcall GET_MONTH_MAXDAY  ; Devuelve máximo de días en rC
    cp  rA, rC
    brlo IDR_STORE
    breq IDR_STORE          ; día == máximo sigue siendo válido

    ; El día superó el máximo del mes: pasar al día 1 del mes siguiente
    ldi rA, 1
    sts day, rA

    lds rB, month
    inc rB
    cpi rB, 13
    brlo IDR_MON_OK
    ldi rB, 1               ; Diciembre - Enero
IDR_MON_OK:
    sts month, rB
    rjmp IDR_END

IDR_STORE:
    sts day, rA

IDR_END:
    pop r17
    pop r16
    ret

; GET_MONTH_MAXDAY
; Devuelve la cantidad de días del mes actual en el registro rC. Lee la variable 'month' de la SRAM directamente.
GET_MONTH_MAXDAY:
    push r16

    lds rA, month

    cpi rA, 2
    breq GMD_FEB            ; Febrero - 28 días

    ; Meses con 30 días
    cpi rA, 4
    breq GMD_30
    cpi rA, 6
    breq GMD_30
    cpi rA, 9
    breq GMD_30
    cpi rA, 11
    breq GMD_30

    ; Todos los meses restantes - 31 días
    ldi rC, 31
    rjmp GMD_END

GMD_FEB:
    ldi rC, 28
    rjmp GMD_END

GMD_30:
    ldi rC, 30

GMD_END:
    pop r16
    ret