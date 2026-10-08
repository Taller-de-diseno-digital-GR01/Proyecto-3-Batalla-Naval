# programa.s
# Batalla Naval, Proyecto 3 de EL3313 Taller de Diseño Digital.
# Programa rv32i que corre en el núcleo uniciclo desde la ROM (0x0000_0000).
#
# Diseño: docs/diseño/diagramas/nivel03.md (sección "Programa en ensamblador") y
# docs/diseño/modulos/PROGRAMA.md (nivel 4). Las secciones de este archivo siguen ese orden.
#
# Instrucciones: lista base del instructivo más lui. Las subrutinas se llaman con
# "jal ra, NOMBRE" (no con "call", que usa auipc). Pseudoinstrucciones usadas: li, mv, j,
# ret, beqz, bnez, que se expanden en instrucciones de la lista.
#
# Ensamblado: bash sw/ensamblar.sh sw/programa.s

# ==============================================================================
# 1. Nombres simbólicos
# ==============================================================================

# --- Registros de periféricos, desplazamientos desde s0 = 0x0001_0000 ---
.equ UART_CTRL,             0x040   # [0] send, [1] new_rx
.equ UART_TX,               0x044
.equ UART_RX,               0x048
.equ BOTONES,               0x120
.equ DISPLAYS,              0x130
.equ LED,                   0x138
.equ BUZZER,                0x140

# --- Variables en RAM, desplazamientos desde s2 = 0x0000_2000 ---
.equ TABLERO_J1,            0x000   # 64 palabras, índice fila * 8 + columna
.equ TABLERO_J2,            0x100
.equ FASE,                  0x200
.equ TURNO,                 0x204
.equ COLOCADOS_J1,          0x208   # cantidad, de 0 a 3
.equ COLOCADOS_J2,          0x20C   # máscara, un bit por id
.equ CURSOR_FILA,           0x210
.equ CURSOR_COL,            0x214
.equ ORIENTACION,           0x218
.equ BOTONES_PREV,          0x21C
.equ IMPACTOS_J1,           0x220   # 3 palabras, una por id
.equ IMPACTOS_J2,           0x22C
.equ DISPAROS_J1,           0x238
.equ DISPAROS_J2,           0x23C
.equ HUNDIDOS_POR_J1,       0x240
.equ HUNDIDOS_POR_J2,       0x244
.equ GANADAS_BCD,           0x248   # [15:8] Jugador 1, [7:0] Jugador 2
.equ RX_INDICE,             0x24C
.equ RX_TRAMA,              0x250   # 5 palabras
.equ FIN_VARIABLES,         0x264

# --- Bits del registro de botones ---
.equ BTN_ARRIBA,            0x01
.equ BTN_ABAJO,             0x02
.equ BTN_IZQ,               0x04
.equ BTN_DER,               0x08
.equ BTN_SEL,               0x10
.equ BTN_OK,                0x20
.equ BTN_RST,               0x40
.equ BTN_FLECHAS,           0x0F

# --- Colores del VGA ---
.equ C_AGUA,                0
.equ C_BARCO,               1
.equ C_IMPACTO,             2
.equ C_FALLO,               3
.equ C_CURSOR,              4
.equ C_FONDO,               5
.equ C_J1,                  6
.equ C_J2,                  7
.equ BORDE,                 8       # bit 3 de la palabra de video: contorno negro (periferico_vga.sv)

# --- Estado de una casilla en RAM, bits [1:0]. Los bits [3:2] son el id del barco ---
.equ E_AGUA,                0
.equ E_BARCO,               1
.equ E_IMPACTO,             2
.equ E_FALLO,               3

# --- Melodías del buzzer ---
.equ SND_SILENCIO,          0
.equ SND_IMPACTO,           1
.equ SND_FALLO,             2
.equ SND_HUNDIDO,           3
.equ SND_INVALIDA,          4
.equ SND_VICTORIA,          5

# --- LED de estado ---
.equ LED_COLOCACION,        0x1
.equ LED_BATALLA,           0x2
.equ LED_RESULTADO,         0x4

# --- Fase ---
.equ F_COLOCACION,          0
.equ F_BATALLA,             1
.equ F_RESULTADO,           2

# --- Resultado de colocación (igual al D2 de la trama Resultado de colocación) ---
.equ COL_VALIDA,            0
.equ COL_TRASLAPE,          1
.equ COL_FUERA,             2
.equ COL_REPETIDO,          3

# --- Resultado de disparo (igual al D2 de las tramas de disparo) ---
.equ D_IMPACTO,             0
.equ D_FALLO,               1
.equ D_HUNDIDO,             2
.equ D_REPETIDO,            3

# --- Tramas UART ---
.equ TRAMA_INICIO,          0xAA
.equ MSG_COLOCAR,           0x10
.equ MSG_DISPARO,           0x11
.equ MSG_ESTADO,            0x20
.equ MSG_RES_COLOCACION,    0x21
.equ MSG_DISPARO_DADO,      0x22
.equ MSG_DISPARO_RECIBIDO,  0x23
.equ MSG_RESUMEN_DISPAROS,  0x24
.equ MSG_RESUMEN_HUNDIDOS,  0x25
.equ TRAMA_LARGO,           5

# --- D1 de la trama Estado ---
.equ EST_COLOCACION,        0
.equ EST_BATALLA,           1
.equ EST_TURNO,             2
.equ EST_FIN,               3

# --- Pantalla: cuadrícula de 20 x 15 casillas, una palabra por casilla ---
.equ VGA_BYTES,             1200    # 300 casillas * 4 bytes
.equ TAB_FILA0,             4       # fila de pantalla de la fila 0 de los tableros
.equ TAB_COL0,              1       # columna de pantalla de la columna 0 del tablero J1
# Las filas 0 y 14 quedan vacías: muchos monitores esconden unos píxeles del borde de la imagen
.equ HUD_FILA_TITULOS,      1       # JUGADOR 1 y JUGADOR 2 encima de cada tablero
.equ HUD_FILA_ESTADO,       2       # barras de colocación, turno, o el ganador al final
.equ HUD_FILA_LETRAS,       3       # A a H encima de cada tablero
.equ HUD_FILA_MENSAJE,      12      # mensaje de traspaso, o cómo empezar otra partida al final
.equ HUD_FILA_GANADAS,      13      # PARTIDAS GANADAS J1 00 J2 00
.equ HUD_COL_GANADAS_J1,    13      # casilla con los dos dígitos de las ganadas del Jugador 1
.equ HUD_COL_GANADAS_J2,    17
.equ ULTIMA_COL,            19

# --- Texto en la palabra de video, en ASCII - 32 (periferico_vga.sv) ---
# Dos caracteres por casilla: [9:4] la mitad izquierda y [15:10] la derecha. Con CENTRADO se
# dibuja solo el de [9:4], en el centro de la casilla.
.equ CAR_DESPL,             4
.equ CAR2_DESPL,            10
.equ CENTRADO,              0x10000 # bit 16
.equ CH__,                  0       # espacio, en TEXTO se escribe _
.equ CH_0,                  16
.equ CH_1,                  17
.equ CH_2,                  18
.equ CH_3,                  19
.equ CH_4,                  20
.equ CH_5,                  21
.equ CH_6,                  22
.equ CH_7,                  23
.equ CH_8,                  24
.equ CH_9,                  25
.equ CH_A,                  33
.equ CH_B,                  34
.equ CH_C,                  35
.equ CH_D,                  36
.equ CH_E,                  37
.equ CH_F,                  38
.equ CH_G,                  39
.equ CH_H,                  40
.equ CH_I,                  41
.equ CH_J,                  42
.equ CH_K,                  43
.equ CH_L,                  44
.equ CH_M,                  45
.equ CH_N,                  46
.equ CH_O,                  47
.equ CH_P,                  48
.equ CH_Q,                  49
.equ CH_R,                  50
.equ CH_S,                  51
.equ CH_T,                  52
.equ CH_U,                  53
.equ CH_V,                  54
.equ CH_W,                  55
.equ CH_X,                  56
.equ CH_Y,                  57
.equ CH_Z,                  58

# ==============================================================================
# Inicio de cada vuelta de los tres lazos (PROGRAMA.md, sección 5)
#   s3 = flancos de los botones
#   s4 = TIPO de la trama completa y válida, o 0 si no llegó ninguna
#   s5, s6 = D1 y D2 de esa trama
# BTN_RST vuelve a PARTIDA desde cualquier fase.
# ==============================================================================
.macro VUELTA
    jal  ra, LEER_BOTONES
    mv   s3, a0
    jal  ra, UART_ATENDER
    mv   s4, a0
    mv   s5, a1
    mv   s6, a2
    andi t0, s3, BTN_RST
    bnez t0, PARTIDA
.endm

# ==============================================================================
# TEXTO fila, columna, color, FRASE: escribe FRASE en la pantalla desde la casilla (fila, columna)
# sobre el color dado, dos letras por casilla. Solo letras, dígitos y _ para los espacios. Si la
# frase tiene un número impar de letras, la última casilla lleva una sola. Para empezar en la mitad
# derecha de una casilla, la frase arranca con _. Cada casilla cuesta 3 instrucciones (lui, addi y
# sw), o 2 si la palabra cabe en el inmediato. Ensucia t0.
# ==============================================================================
.macro TEXTO fila, col, color, frase
    .set texto_col, \col
    .set texto_par, 0
    .irpc c, \frase
    .if texto_par == 0
    .set texto_izq, CH_\c
    .set texto_par, 1
    .else
    li   t0, (CH_\c << CAR2_DESPL) | (texto_izq << CAR_DESPL) | \color
    sw   t0, ((\fila * 20 + texto_col) * 4)(s1)
    .set texto_col, texto_col + 1
    .set texto_par, 0
    .endif
    .endr
    .if texto_par == 1
    li   t0, (texto_izq << CAR_DESPL) | \color
    sw   t0, ((\fila * 20 + texto_col) * 4)(s1)
    .endif
.endm

.globl INICIO
.text

# ==============================================================================
# 2. Arranque por rst_i y partida nueva
# ==============================================================================
INICIO:
    lui  s0, 0x10                       # s0 = 0x0001_0000, periféricos
    lui  s1, 0x11                       # s1 = 0x0001_1000, memoria de video
    lui  s2, 0x2                        # s2 = 0x0000_2000, variables en RAM
    sw   zero, GANADAS_BCD(s2)          # las ganadas solo se borran acá
    sw   zero, DISPLAYS(s0)             # displays en 00 00
    sw   zero, UART_CTRL(s0)            # descarta un byte recibido antes del arranque

PARTIDA:                                # también es el destino de BTN_RST
    lui  sp, 0x3                        # sp = 0x0000_3000, pila vacía
    jal  ra, NUEVA_PARTIDA
    li   t0, F_COLOCACION
    sw   t0, FASE(s2)
    li   t0, LED_COLOCACION
    sw   t0, LED(s0)
    jal  ra, HUD_COLOCACION
    TEXTO HUD_FILA_MENSAJE, 0, C_FONDO, _J1_COLOCA_CON_BOTONES_Y_J2_DESDE_LA_PC
    li   a0, 0                          # vista previa del barco 0: largo 4, horizontal
    li   a1, 4
    li   a2, 0
    jal  ra, DIBUJAR_CURSOR
    li   a0, MSG_ESTADO
    li   a1, EST_COLOCACION
    li   a2, 0
    jal  ra, UART_ENVIAR_TRAMA

# ==============================================================================
# 3. Fase de colocación
#   s7 = id, s8 = fila, s9 = columna y s10 = orientación del barco del Jugador 2
#   s11 = indicador de repintado (Jugador 1) o código de colocación (Jugador 2)
# ==============================================================================
LAZO_COLOCACION:
    VUELTA

    # --- Jugador 1, botones ---
    lw   t0, COLOCADOS_J1(s2)
    li   t1, 3
    beq  t0, t1, COL_J2                 # flota completa, se salta su parte

    li   s11, 0                         # s11 = 1 si hay que repintar la vista previa
    andi t0, s3, BTN_FLECHAS
    beqz t0, COL_J1_SEL
    mv   a0, s3
    jal  ra, MOVER_CURSOR
    li   s11, 1
COL_J1_SEL:
    andi t0, s3, BTN_SEL
    beqz t0, COL_J1_PREVIA
    lw   t0, ORIENTACION(s2)
    xori t0, t0, 1
    sw   t0, ORIENTACION(s2)
    li   s11, 1
COL_J1_PREVIA:
    beqz s11, COL_J1_OK
    li   a0, 0
    jal  ra, REPINTAR_TABLERO
    li   a0, 0                          # DIBUJAR_CURSOR(0, 4 - colocados, orientación)
    lw   t0, COLOCADOS_J1(s2)
    li   a1, 4
    sub  a1, a1, t0
    lw   a2, ORIENTACION(s2)
    jal  ra, DIBUJAR_CURSOR
COL_J1_OK:
    andi t0, s3, BTN_OK
    beqz t0, COL_J2
    li   a0, 0
    lw   a1, COLOCADOS_J1(s2)           # el Jugador 1 coloca en orden: id = colocados
    lw   a2, CURSOR_FILA(s2)
    lw   a3, CURSOR_COL(s2)
    lw   a4, ORIENTACION(s2)
    jal  ra, VALIDAR_COLOCACION
    beqz a0, COL_J1_VALIDA              # COL_VALIDA = 0
    li   t0, SND_INVALIDA
    sw   t0, BUZZER(s0)
    j    COL_J2
COL_J1_VALIDA:
    li   a0, 0
    lw   a1, COLOCADOS_J1(s2)
    lw   a2, CURSOR_FILA(s2)
    lw   a3, CURSOR_COL(s2)
    lw   a4, ORIENTACION(s2)
    jal  ra, COLOCAR_BARCO
    lw   t0, COLOCADOS_J1(s2)
    addi t0, t0, 1
    sw   t0, COLOCADOS_J1(s2)
    li   a0, 0
    jal  ra, REPINTAR_TABLERO           # muestra el barco recién colocado
    lw   t0, COLOCADOS_J1(s2)
    li   t1, 3
    beq  t0, t1, COL_J1_HUD             # con la flota completa no hay vista previa
    li   a0, 0
    li   a1, 4
    sub  a1, a1, t0
    lw   a2, ORIENTACION(s2)
    jal  ra, DIBUJAR_CURSOR
COL_J1_HUD:
    jal  ra, HUD_COLOCACION

    # --- Jugador 2, trama Colocar barco ---
COL_J2:
    li   t0, MSG_COLOCAR
    bne  s4, t0, COL_FIN_VUELTA         # cualquier otra trama se descarta
    andi s7, s5, 3                      # id
    srli s10, s5, 7                     # orientación, bit 7 de D1
    srli s8, s6, 4                      # fila
    andi s9, s6, 0xF                    # columna
    lw   t0, COLOCADOS_J2(s2)
    li   t1, 1
    sll  t1, t1, s7                     # 1 << id
    and  t0, t0, t1
    li   s11, COL_REPETIDO
    bnez t0, COL_J2_RESPONDER
    li   a0, 1
    mv   a1, s7
    mv   a2, s8
    mv   a3, s9
    mv   a4, s10
    jal  ra, VALIDAR_COLOCACION
    mv   s11, a0
    bnez s11, COL_J2_RESPONDER
    li   a0, 1
    mv   a1, s7
    mv   a2, s8
    mv   a3, s9
    mv   a4, s10
    jal  ra, COLOCAR_BARCO              # se guarda en RAM, no se pinta
    lw   t0, COLOCADOS_J2(s2)
    li   t1, 1
    sll  t1, t1, s7
    or   t0, t0, t1
    sw   t0, COLOCADOS_J2(s2)
    jal  ra, HUD_COLOCACION
COL_J2_RESPONDER:
    li   a0, MSG_RES_COLOCACION
    mv   a1, s7
    mv   a2, s11
    jal  ra, UART_ENVIAR_TRAMA

    # --- ¿Terminaron los dos? ---
COL_FIN_VUELTA:
    lw   t0, COLOCADOS_J1(s2)
    li   t1, 3
    bne  t0, t1, LAZO_COLOCACION
    lw   t0, COLOCADOS_J2(s2)
    li   t1, 7
    bne  t0, t1, LAZO_COLOCACION

# ==============================================================================
# 4. Fase de batalla
#   s7 = jugador dueño del tablero atacado, s8 = fila, s9 = columna
#   s10 = resultado del disparo, s11 = casilla en formato de trama (fila << 4 | columna)
# ==============================================================================
INICIO_BATALLA:
    li   t0, F_BATALLA
    sw   t0, FASE(s2)
    li   t0, LED_BATALLA
    sw   t0, LED(s0)
    sw   zero, TURNO(s2)
    sw   zero, CURSOR_FILA(s2)
    sw   zero, CURSOR_COL(s2)
    li   a0, 0
    jal  ra, REPINTAR_TABLERO           # borra la última vista previa
    jal  ra, HUD_TURNO
    li   a0, 1                          # cursor sobre el tablero del Jugador 2
    li   a1, 1
    li   a2, 0
    jal  ra, DIBUJAR_CURSOR
    li   a0, MSG_ESTADO
    li   a1, EST_BATALLA
    li   a2, 0
    jal  ra, UART_ENVIAR_TRAMA
    li   a0, MSG_ESTADO
    li   a1, EST_TURNO
    li   a2, 0
    jal  ra, UART_ENVIAR_TRAMA

LAZO_BATALLA:
    VUELTA
    lw   t0, TURNO(s2)
    bnez t0, TURNO_J2

TURNO_J1:
    andi t0, s3, BTN_FLECHAS
    beqz t0, TURNO_J1_OK
    mv   a0, s3
    jal  ra, MOVER_CURSOR
    li   a0, 1
    jal  ra, REPINTAR_TABLERO
    li   a0, 1
    li   a1, 1
    li   a2, 0
    jal  ra, DIBUJAR_CURSOR
TURNO_J1_OK:
    andi t0, s3, BTN_OK
    beqz t0, LAZO_BATALLA
    li   s7, 1                          # el Jugador 1 ataca el tablero del Jugador 2
    lw   s8, CURSOR_FILA(s2)
    lw   s9, CURSOR_COL(s2)
    j    DISPARO

TURNO_J2:
    li   t0, MSG_DISPARO
    bne  s4, t0, LAZO_BATALLA           # cualquier otra trama se descarta
    li   s7, 0                          # el Jugador 2 ataca el tablero del Jugador 1
    srli s8, s5, 4
    andi s9, s5, 0xF

DISPARO:
    mv   a0, s7
    mv   a1, s8
    mv   a2, s9
    jal  ra, PROCESAR_DISPARO
    mv   s10, a0
    slli s11, s8, 4
    or   s11, s11, s9
    li   t0, D_REPETIDO
    bne  s10, t0, DISPARO_VALIDO
    lw   t0, TURNO(s2)
    beqz t0, LAZO_BATALLA               # repetido del Jugador 1: se ignora
    li   a0, MSG_DISPARO_DADO           # repetido del Jugador 2: la PC pide otra casilla
    mv   a1, s11
    li   a2, D_REPETIDO
    jal  ra, UART_ENVIAR_TRAMA
    j    LAZO_BATALLA                   # el turno no cambia

DISPARO_VALIDO:
    lw   t0, TURNO(s2)                  # disparos del tirador + 1
    slli t0, t0, 2
    add  t0, t0, s2
    lw   t1, DISPAROS_J1(t0)
    addi t1, t1, 1
    sw   t1, DISPAROS_J1(t0)
    mv   a0, s7
    mv   a1, s8
    mv   a2, s9
    jal  ra, PINTAR_CASILLA
    lw   t0, TURNO(s2)
    li   a0, MSG_DISPARO_RECIBIDO       # tiró el Jugador 1
    beqz t0, DISPARO_TRAMA
    li   a0, MSG_DISPARO_DADO           # tiró el Jugador 2
DISPARO_TRAMA:
    mv   a1, s11
    mv   a2, s10
    jal  ra, UART_ENVIAR_TRAMA
    li   t0, D_HUNDIDO
    bne  s10, t0, DISPARO_SONIDO
    lw   t0, TURNO(s2)                  # hundidos del tirador + 1
    slli t0, t0, 2
    add  t0, t0, s2
    lw   t1, HUNDIDOS_POR_J1(t0)
    addi t1, t1, 1
    sw   t1, HUNDIDOS_POR_J1(t0)
    li   t2, 3
    beq  t1, t2, FIN_PARTIDA            # la victoria reemplaza a la melodía de hundido
DISPARO_SONIDO:
    addi t0, s10, 1                     # impacto 1, fallo 2, hundido 3
    sw   t0, BUZZER(s0)
    lw   t0, TURNO(s2)
    xori t0, t0, 1
    sw   t0, TURNO(s2)
    jal  ra, HUD_TURNO
    li   a0, MSG_ESTADO
    li   a1, EST_TURNO
    lw   a2, TURNO(s2)
    jal  ra, UART_ENVIAR_TRAMA
    lw   t0, TURNO(s2)
    bnez t0, LAZO_BATALLA
    li   a0, 1                          # vuelve el turno del Jugador 1: cursor
    li   a1, 1
    li   a2, 0
    jal  ra, DIBUJAR_CURSOR
    j    LAZO_BATALLA

# ==============================================================================
# 5. Fin de partida. El ganador es el jugador que tiene el turno.
# ==============================================================================
FIN_PARTIDA:
    li   t0, F_RESULTADO
    sw   t0, FASE(s2)
    li   t0, LED_RESULTADO
    sw   t0, LED(s0)
    li   t0, SND_VICTORIA
    sw   t0, BUZZER(s0)
    lw   a0, TURNO(s2)
    jal  ra, HUD_RESULTADO
    lw   a0, TURNO(s2)
    jal  ra, SUMAR_GANADA
    jal  ra, HUD_GANADAS
    li   a0, MSG_ESTADO
    li   a1, EST_FIN
    lw   a2, TURNO(s2)
    jal  ra, UART_ENVIAR_TRAMA
    li   a0, MSG_RESUMEN_DISPAROS
    lw   a1, DISPAROS_J1(s2)
    lw   a2, DISPAROS_J2(s2)
    jal  ra, UART_ENVIAR_TRAMA
    li   a0, MSG_RESUMEN_HUNDIDOS
    lw   a1, HUNDIDOS_POR_J1(s2)
    lw   a2, HUNDIDOS_POR_J2(s2)
    jal  ra, UART_ENVIAR_TRAMA

LAZO_FIN:
    VUELTA                                  # la única salida es BTN_RST
    j    LAZO_FIN

# ==============================================================================
# 6. Subrutinas
# Convención (PROGRAMA.md, sección 3): argumentos en a0 a a4, resultado en a0 
# (a0 a a2 en UART_ATENDER y VALIDAR_TRAMA). 
#Los t* y a* quedan sucios. Los s3 a s11 que usa una
# subrutina se guardan en su marco. s0, s1 y s2 no se escriben nunca.
# ==============================================================================

# ------------------------------------------------------------------------------
# DIR_TABLERO: a0 jugador, a1 fila, a2 columna -> a0 dirección de la casilla en RAM.
# Hoja.
# ------------------------------------------------------------------------------
DIR_TABLERO:
    slli t0, a1, 3                      # fila * 8
    add  t0, t0, a2                     # fila * 8 + columna
    slli t0, t0, 2                      # desplazamiento en bytes
    slli t1, a0, 8                      # jugador * 0x100
    add  t0, t0, t1
    add  a0, s2, t0
    ret

# ------------------------------------------------------------------------------
# DIR_VGA_TABLERO: a0 jugador, a1 fila, a2 columna -> a0 dirección en video.
# s1 + 4 * (fp * 20 + cp), con fp = TAB_FILA0 + fila y cp = 1 + 10 * jugador + columna. Hoja.
# ------------------------------------------------------------------------------
DIR_VGA_TABLERO:
    addi t0, a1, TAB_FILA0              # fp
    slli t1, t0, 4
    slli t0, t0, 2
    add  t0, t0, t1                     # fp * 20
    slli t1, a0, 3
    slli t2, a0, 1
    add  t1, t1, t2                     # 10 * jugador
    add  t0, t0, t1
    add  t0, t0, a2
    addi t0, t0, TAB_COL0               # fp * 20 + cp
    slli t0, t0, 2
    add  a0, s1, t0
    ret

# ------------------------------------------------------------------------------
# LEER_BOTONES: -> a0 flancos = actual & ~BOTONES_PREV. Hoja.
# ------------------------------------------------------------------------------
LEER_BOTONES:
    lw   t0, BOTONES(s0)
    lw   t1, BOTONES_PREV(s2)
    sw   t0, BOTONES_PREV(s2)
    xori t1, t1, -1                     # ~anterior
    and  a0, t0, t1
    ret

# ------------------------------------------------------------------------------
# MOVER_CURSOR: a0 flancos. Mueve el cursor una casilla por flecha, sin salir de 0 a 7.
# Hoja.
# ------------------------------------------------------------------------------
MOVER_CURSOR:
    lw   t0, CURSOR_FILA(s2)
    lw   t1, CURSOR_COL(s2)
    li   t3, 7
    andi t2, a0, BTN_ARRIBA
    beqz t2, MC_ABAJO
    beqz t0, MC_ABAJO                   # ya está en la fila 0
    addi t0, t0, -1
MC_ABAJO:
    andi t2, a0, BTN_ABAJO
    beqz t2, MC_IZQ
    beq  t0, t3, MC_IZQ                 # ya está en la fila 7
    addi t0, t0, 1
MC_IZQ:
    andi t2, a0, BTN_IZQ
    beqz t2, MC_DER
    beqz t1, MC_DER                     # ya está en la columna 0
    addi t1, t1, -1
MC_DER:
    andi t2, a0, BTN_DER
    beqz t2, MC_GUARDAR
    beq  t1, t3, MC_GUARDAR             # ya está en la columna 7
    addi t1, t1, 1
MC_GUARDAR:
    sw   t0, CURSOR_FILA(s2)
    sw   t1, CURSOR_COL(s2)
    ret

# ------------------------------------------------------------------------------
# UART_ENVIAR_BYTE: a0 byte. Espera send en 0, escribe el byte y arranca el envío
# conservando new_rx. Es la única espera del programa. Hoja.
# ------------------------------------------------------------------------------
UART_ENVIAR_BYTE:
    lw   t0, UART_CTRL(s0)
    andi t0, t0, 1                      # send
    bnez t0, UART_ENVIAR_BYTE
    sw   a0, UART_TX(s0)
    lw   t0, UART_CTRL(s0)
    ori  t0, t0, 1                      # send = 1, new_rx sin cambios
    sw   t0, UART_CTRL(s0)
    ret

# ------------------------------------------------------------------------------
# UART_ENVIAR_TRAMA: a0 TIPO, a1 D1, a2 D2. Manda 0xAA, TIPO, D1, D2 y la verificación.
# Marco de 16 bytes: ra, s3, s4, s5.
# ------------------------------------------------------------------------------
UART_ENVIAR_TRAMA:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s3, 8(sp)
    sw   s4, 4(sp)
    sw   s5, 0(sp)
    mv   s3, a0
    mv   s4, a1
    mv   s5, a2
    li   a0, TRAMA_INICIO
    jal  ra, UART_ENVIAR_BYTE
    mv   a0, s3
    jal  ra, UART_ENVIAR_BYTE
    mv   a0, s4
    jal  ra, UART_ENVIAR_BYTE
    mv   a0, s5
    jal  ra, UART_ENVIAR_BYTE
    xor  a0, s3, s4
    xor  a0, a0, s5
    jal  ra, UART_ENVIAR_BYTE
    lw   s5, 0(sp)
    lw   s4, 4(sp)
    lw   s3, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# ------------------------------------------------------------------------------
# UART_ATENDER: atiende como máximo un byte recibido.
# -> a0 TIPO de una trama completa y válida, o 0. a1 D1 y a2 D2 de esa trama.
# Arma el marco (4 bytes, ra) solo cuando llama a VALIDAR_TRAMA.
# ------------------------------------------------------------------------------
UART_ATENDER:
    lw   t0, UART_CTRL(s0)
    andi t0, t0, 2                      # new_rx
    bnez t0, UA_HAY_BYTE
    li   a0, 0
    ret
UA_HAY_BYTE:
    lw   t1, UART_RX(s0)
    sw   zero, UART_CTRL(s0)            # baja new_rx, send no cambia
    andi t1, t1, 0xFF
    li   t2, TRAMA_INICIO
    bne  t1, t2, UA_NO_INICIO
    sw   t1, RX_TRAMA(s2)               # un 0xAA siempre empieza una trama nueva
    li   t2, 1
    sw   t2, RX_INDICE(s2)
    li   a0, 0
    ret
UA_NO_INICIO:
    lw   t2, RX_INDICE(s2)
    bnez t2, UA_GUARDAR
    li   a0, 0                          # byte suelto, se descarta
    ret
UA_GUARDAR:
    slli t3, t2, 2
    add  t3, t3, s2
    sw   t1, RX_TRAMA(t3)               # RX_TRAMA[RX_INDICE] = byte
    addi t2, t2, 1
    li   t4, TRAMA_LARGO
    beq  t2, t4, UA_COMPLETA
    sw   t2, RX_INDICE(s2)
    li   a0, 0
    ret
UA_COMPLETA:
    sw   zero, RX_INDICE(s2)
    addi sp, sp, -4
    sw   ra, 0(sp)
    jal  ra, VALIDAR_TRAMA
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# ------------------------------------------------------------------------------
# VALIDAR_TRAMA: revisa RX_TRAMA[1] a RX_TRAMA[4].
# -> a0 TIPO si pasa todos los chequeos, o 0. a1 D1, a2 D2. Hoja.
# ------------------------------------------------------------------------------
VALIDAR_TRAMA:
    lw   a0, RX_TRAMA+4(s2)             # TIPO
    lw   a1, RX_TRAMA+8(s2)             # D1
    lw   a2, RX_TRAMA+12(s2)            # D2
    lw   t0, RX_TRAMA+16(s2)            # verificación
    xor  t1, a0, a1
    xor  t1, t1, a2
    bne  t1, t0, VT_DESCARTAR
    li   t2, MSG_COLOCAR
    beq  a0, t2, VT_COLOCAR
    li   t2, MSG_DISPARO
    beq  a0, t2, VT_DISPARO
    j    VT_DESCARTAR                   # la PC solo manda Colocar barco y Disparo
VT_COLOCAR:
    andi t1, a1, 0x7C                   # bits 6 a 2 de D1 en cero
    bnez t1, VT_DESCARTAR
    andi t1, a1, 3
    li   t2, 3
    beq  t1, t2, VT_DESCARTAR           # no existe el id 3
    andi t1, a2, 0x88                   # fila y columna de 0 a 7
    bnez t1, VT_DESCARTAR
    ret
VT_DISPARO:
    andi t1, a1, 0x88
    bnez t1, VT_DESCARTAR
    bnez a2, VT_DESCARTAR
    ret
VT_DESCARTAR:
    li   a0, 0
    ret

# ------------------------------------------------------------------------------
# VALIDAR_COLOCACION: a0 jugador, a1 id, a2 fila, a3 columna, a4 orientación.
# -> a0 COL_VALIDA, COL_TRASLAPE o COL_FUERA. "Fuera" se revisa antes que "traslape".
# Marco de 12 bytes: ra, s3 (casillas que faltan), s4 (orientación).
# ------------------------------------------------------------------------------
VALIDAR_COLOCACION:
    addi sp, sp, -12
    sw   ra, 8(sp)
    sw   s3, 4(sp)
    sw   s4, 0(sp)
    li   t0, 4
    sub  s3, t0, a1                     # largo = 4 - id
    mv   s4, a4
    mv   t1, a3                         # horizontal: avanza la columna
    beqz a4, VC_BORDE
    mv   t1, a2                         # vertical: avanza la fila
VC_BORDE:
    add  t1, t1, s3
    addi t1, t1, -1                     # coordenada de la última casilla
    li   t2, 7
    blt  t2, t1, VC_FUERA
    mv   a1, a2                         # DIR_TABLERO(jugador, fila, columna)
    mv   a2, a3
    jal  ra, DIR_TABLERO
    li   t1, 4                          # paso horizontal: una palabra
    beqz s4, VC_RECORRER
    li   t1, 32                         # paso vertical: una fila de 8 palabras
VC_RECORRER:
    lw   t0, 0(a0)
    andi t0, t0, 3
    bnez t0, VC_TRASLAPE                # E_AGUA = 0
    add  a0, a0, t1
    addi s3, s3, -1
    bnez s3, VC_RECORRER
    li   a0, COL_VALIDA
    j    VC_SALIR
VC_FUERA:
    li   a0, COL_FUERA
    j    VC_SALIR
VC_TRASLAPE:
    li   a0, COL_TRASLAPE
VC_SALIR:
    lw   s4, 0(sp)
    lw   s3, 4(sp)
    lw   ra, 8(sp)
    addi sp, sp, 12
    ret

# ------------------------------------------------------------------------------
# COLOCAR_BARCO: mismos argumentos que VALIDAR_COLOCACION, que ya tiene que haber dado
# COL_VALIDA. Escribe (id << 2) | E_BARCO en cada casilla del barco.
# Marco de 16 bytes: ra, s3 (casillas que faltan), s4 (orientación), s5 (valor).
# ------------------------------------------------------------------------------
COLOCAR_BARCO:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s3, 8(sp)
    sw   s4, 4(sp)
    sw   s5, 0(sp)
    li   t0, 4
    sub  s3, t0, a1                     # largo = 4 - id
    mv   s4, a4
    slli s5, a1, 2
    ori  s5, s5, E_BARCO
    mv   a1, a2
    mv   a2, a3
    jal  ra, DIR_TABLERO
    li   t1, 4
    beqz s4, CB_RECORRER
    li   t1, 32
CB_RECORRER:
    sw   s5, 0(a0)
    add  a0, a0, t1
    addi s3, s3, -1
    bnez s3, CB_RECORRER
    lw   s5, 0(sp)
    lw   s4, 4(sp)
    lw   s3, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# ------------------------------------------------------------------------------
# PROCESAR_DISPARO: a0 jugador dueño del tablero, a1 fila, a2 columna.
# -> a0 D_IMPACTO, D_FALLO, D_HUNDIDO o D_REPETIDO. Solo cambia la casilla y el
# contador de impactos del barco. Marco de 8 bytes: ra, s3 (jugador).
# ------------------------------------------------------------------------------
PROCESAR_DISPARO:
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   s3, 0(sp)
    mv   s3, a0
    jal  ra, DIR_TABLERO
    lw   t0, 0(a0)
    andi t1, t0, 2                      # bit 1 en uno: ya se disparó
    bnez t1, PD_REPETIDO
    andi t1, t0, 3
    bnez t1, PD_BARCO                   # E_BARCO
    ori  t0, t0, E_FALLO                # agua: 00 pasa a 11
    sw   t0, 0(a0)
    li   a0, D_FALLO
    j    PD_SALIR
PD_BARCO:
    xori t0, t0, 3                      # 01 pasa a 10 (E_IMPACTO), el id no cambia
    sw   t0, 0(a0)
    srli t2, t0, 2
    andi t2, t2, 3                      # id
    slli t3, s3, 3
    slli t4, s3, 2
    add  t3, t3, t4                     # 12 * jugador
    slli t4, t2, 2
    add  t3, t3, t4                     # + 4 * id
    add  t3, t3, s2
    lw   t4, IMPACTOS_J1(t3)
    addi t4, t4, 1
    sw   t4, IMPACTOS_J1(t3)
    li   t5, 4
    sub  t5, t5, t2                     # largo = 4 - id
    li   a0, D_IMPACTO
    bne  t4, t5, PD_SALIR
    li   a0, D_HUNDIDO
    j    PD_SALIR
PD_REPETIDO:
    li   a0, D_REPETIDO
PD_SALIR:
    lw   s3, 0(sp)
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

# ------------------------------------------------------------------------------
# SUMAR_GANADA: a0 ganador. Suma 1 en BCD a sus dos dígitos de GANADAS_BCD
# ([15:8] Jugador 1, [7:0] Jugador 2), de 99 vuelve a 00, y escribe los displays. Hoja.
# ------------------------------------------------------------------------------
SUMAR_GANADA:
    lw   t0, GANADAS_BCD(s2)
    li   t1, 1
    sub  t1, t1, a0
    slli t1, t1, 3                      # desplazamiento: 8 para J1, 0 para J2
    srl  t2, t0, t1
    andi t2, t2, 0xFF                   # dígitos del ganador
    li   t3, 0xFF
    sll  t3, t3, t1
    xori t3, t3, -1
    and  t0, t0, t3                     # borra esos dígitos de la palabra
    addi t2, t2, 1
    andi t4, t2, 0xF
    li   t5, 10
    bne  t4, t5, SG_GUARDAR
    addi t2, t2, 6                      # unidades de 10 a 0 y una decena más (0x0A + 6 = 0x10)
    srli t4, t2, 4
    bne  t4, t5, SG_GUARDAR
    li   t2, 0                          # 99 + 1 = 00
SG_GUARDAR:
    sll  t2, t2, t1
    or   t0, t0, t2
    sw   t0, GANADAS_BCD(s2)
    sw   t0, DISPLAYS(s0)
    ret

# ------------------------------------------------------------------------------
# PINTAR_CASILLA: a0 jugador, a1 fila, a2 columna. Copia el estado de la casilla de RAM
# a la pantalla. PRIVACIDAD: es la única rutina que copia un tablero a la pantalla, y un
# barco sin disparar del Jugador 2 se pinta como agua.
# Marco de 20 bytes: ra, s3 a s6.
# ------------------------------------------------------------------------------
PINTAR_CASILLA:
    addi sp, sp, -20
    sw   ra, 16(sp)
    sw   s3, 12(sp)
    sw   s4, 8(sp)
    sw   s5, 4(sp)
    sw   s6, 0(sp)
    mv   s3, a0
    mv   s4, a1
    mv   s5, a2
    jal  ra, DIR_TABLERO
    lw   s6, 0(a0)
    andi s6, s6, 3                      # solo el estado: el bit 2 es parte del id
    beqz s3, PC_ESCRIBIR                # tablero propio del Jugador 1: tal cual
    li   t0, E_BARCO
    bne  s6, t0, PC_ESCRIBIR
    li   s6, C_AGUA                     # barco del Jugador 2 sin disparar
PC_ESCRIBIR:
    mv   a0, s3
    mv   a1, s4
    mv   a2, s5
    jal  ra, DIR_VGA_TABLERO
    ori  s6, s6, BORDE                  # las casillas de tablero llevan la línea del grid
    sw   s6, 0(a0)                      # los estados coinciden con C_AGUA a C_FALLO
    lw   s6, 0(sp)
    lw   s5, 4(sp)
    lw   s4, 8(sp)
    lw   s3, 12(sp)
    lw   ra, 16(sp)
    addi sp, sp, 20
    ret

# ------------------------------------------------------------------------------
# REPINTAR_TABLERO: a0 jugador. Pinta las 64 casillas desde la RAM.
# Marco de 16 bytes: ra, s3 (jugador), s4 (fila), s5 (columna).
# ------------------------------------------------------------------------------
REPINTAR_TABLERO:
    addi sp, sp, -16
    sw   ra, 12(sp)
    sw   s3, 8(sp)
    sw   s4, 4(sp)
    sw   s5, 0(sp)
    mv   s3, a0
    li   s4, 0
RT_FILA:
    li   s5, 0
RT_COLUMNA:
    mv   a0, s3
    mv   a1, s4
    mv   a2, s5
    jal  ra, PINTAR_CASILLA
    addi s5, s5, 1
    li   t0, 8
    blt  s5, t0, RT_COLUMNA
    addi s4, s4, 1
    blt  s4, t0, RT_FILA
    lw   s5, 0(sp)
    lw   s4, 4(sp)
    lw   s3, 8(sp)
    lw   ra, 12(sp)
    addi sp, sp, 16
    ret

# ------------------------------------------------------------------------------
# DIBUJAR_CURSOR: a0 jugador, a1 largo (1 o más), a2 orientación.
# Pinta con C_CURSOR desde (CURSOR_FILA, CURSOR_COL) hacia la derecha o hacia abajo, y
# se detiene en la primera casilla fuera del tablero.
# Marco de 24 bytes: ra, s3 (jugador), s4 (largo), s5 (orientación), s6 (fila), s7 (col).
# ------------------------------------------------------------------------------
DIBUJAR_CURSOR:
    addi sp, sp, -24
    sw   ra, 20(sp)
    sw   s3, 16(sp)
    sw   s4, 12(sp)
    sw   s5, 8(sp)
    sw   s6, 4(sp)
    sw   s7, 0(sp)
    mv   s3, a0
    mv   s4, a1
    mv   s5, a2
    lw   s6, CURSOR_FILA(s2)
    lw   s7, CURSOR_COL(s2)
DC_CASILLA:
    li   t0, 7
    blt  t0, s6, DC_SALIR               # fuera del tablero
    blt  t0, s7, DC_SALIR
    mv   a0, s3
    mv   a1, s6
    mv   a2, s7
    jal  ra, DIR_VGA_TABLERO
    li   t0, C_CURSOR + BORDE
    sw   t0, 0(a0)
    beqz s5, DC_HORIZONTAL
    addi s6, s6, 1
    j    DC_SIGUIENTE
DC_HORIZONTAL:
    addi s7, s7, 1
DC_SIGUIENTE:
    addi s4, s4, -1
    bnez s4, DC_CASILLA
DC_SALIR:
    lw   s7, 0(sp)
    lw   s6, 4(sp)
    lw   s5, 8(sp)
    lw   s4, 12(sp)
    lw   s3, 16(sp)
    lw   ra, 20(sp)
    addi sp, sp, 24
    ret

# ------------------------------------------------------------------------------
# VGA_LIMPIAR: escribe C_FONDO en las 300 casillas de la pantalla. Hoja.
# ------------------------------------------------------------------------------
VGA_LIMPIAR:
    mv   t0, s1
    addi t1, s1, VGA_BYTES
    li   t2, C_FONDO
VL_LAZO:
    sw   t2, 0(t0)
    addi t0, t0, 4
    bne  t0, t1, VL_LAZO
    ret

# ------------------------------------------------------------------------------
# VGA_RELLENAR_FILA: a0 fila, a1 columna inicial, a2 columna final (incluida), a3 color.
# Hoja.
# ------------------------------------------------------------------------------
VGA_RELLENAR_FILA:
    slli t0, a0, 4
    slli t1, a0, 2
    add  t0, t0, t1                     # fila * 20
    add  t1, t0, a1
    add  t2, t0, a2
    slli t1, t1, 2
    add  t1, t1, s1                     # dirección de la primera casilla
    slli t2, t2, 2
    add  t2, t2, s1                     # dirección de la última casilla
VR_LAZO:
    sw   a3, 0(t1)
    addi t1, t1, 4
    bge  t2, t1, VR_LAZO
    ret

# ------------------------------------------------------------------------------
# HUD_COLOCACION: barra de cada jugador en la fila 1 mientras no complete su flota.
# Marco de 4 bytes: ra.
# ------------------------------------------------------------------------------
HUD_COLOCACION:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   a0, HUD_FILA_ESTADO
    li   a1, 1                          # columnas del tablero J1
    li   a2, 8
    lw   t0, COLOCADOS_J1(s2)
    li   t1, 3
    beq  t0, t1, HC_J1_LISTO
    li   a3, C_J1
    jal  ra, VGA_RELLENAR_FILA
    TEXTO HUD_FILA_ESTADO, 2, C_J1, _COLOCANDO
    j    HC_J2
HC_J1_LISTO:                            # el Jugador 1 terminó
    li   a3, C_FONDO
    jal  ra, VGA_RELLENAR_FILA
    TEXTO HUD_FILA_ESTADO, 3, C_FONDO, _LISTO
HC_J2:
    li   a0, HUD_FILA_ESTADO
    li   a1, 11                         # columnas del tablero J2
    li   a2, 18
    lw   t0, COLOCADOS_J2(s2)
    li   t1, 7
    beq  t0, t1, HC_J2_LISTO
    li   a3, C_J2
    jal  ra, VGA_RELLENAR_FILA
    TEXTO HUD_FILA_ESTADO, 12, C_J2, _COLOCANDO
    j    HC_SALIR
HC_J2_LISTO:                            # el Jugador 2 terminó
    li   a3, C_FONDO
    jal  ra, VGA_RELLENAR_FILA
    TEXTO HUD_FILA_ESTADO, 13, C_FONDO, _LISTO
HC_SALIR:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# ------------------------------------------------------------------------------
# HUD_TURNO: fila 1 completa en el color del jugador con el turno, con TURNO JUGADOR n, y el
# mensaje de traspaso: qué tiene que hacer el Jugador 1, o que se espera a la PC.
# Marco de 4 bytes: ra.
# ------------------------------------------------------------------------------
HUD_TURNO:
    addi sp, sp, -4
    sw   ra, 0(sp)
    li   a0, HUD_FILA_ESTADO
    li   a1, 0
    li   a2, ULTIMA_COL
    lw   t0, TURNO(s2)
    addi a3, t0, C_J1                   # C_J1 + jugador
    jal  ra, VGA_RELLENAR_FILA
    li   a0, HUD_FILA_MENSAJE
    li   a1, 0
    li   a2, ULTIMA_COL
    li   a3, C_FONDO
    jal  ra, VGA_RELLENAR_FILA          # borra el mensaje anterior
    lw   t0, TURNO(s2)
    bnez t0, HT_J2
    TEXTO HUD_FILA_ESTADO, 5, C_J1, _TURNO_DEL_JUGADOR_1
    TEXTO HUD_FILA_MENSAJE, 1, C_FONDO, APUNTE_CON_FLECHAS_Y_DISPARE_CON_SW0
    j    HT_SALIR
HT_J2:
    TEXTO HUD_FILA_ESTADO, 5, C_J2, _TURNO_DEL_JUGADOR_2
    TEXTO HUD_FILA_MENSAJE, 1, C_FONDO, _ESPERANDO_EL_DISPARO_DEL_JUGADOR_2
HT_SALIR:
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret

# ------------------------------------------------------------------------------
# HUD_RESULTADO: a0 ganador. Pinta la fila de estado y la del mensaje en su color, con
# GANA EL JUGADOR n y cómo empezar otra partida. Las ganadas siguen a la vista.
# Marco de 8 bytes: ra, s3 (color del ganador).
# ------------------------------------------------------------------------------
HUD_RESULTADO:
    addi sp, sp, -8
    sw   ra, 4(sp)
    sw   s3, 0(sp)
    addi s3, a0, C_J1
    li   a0, HUD_FILA_ESTADO
    li   a1, 0
    li   a2, ULTIMA_COL
    mv   a3, s3
    jal  ra, VGA_RELLENAR_FILA
    li   a0, HUD_FILA_MENSAJE
    li   a1, 0
    li   a2, ULTIMA_COL
    mv   a3, s3
    jal  ra, VGA_RELLENAR_FILA
    li   t1, C_J1
    bne  s3, t1, HR_J2
    TEXTO HUD_FILA_ESTADO, 5, C_J1, _GANA_EL_JUGADOR_1
    TEXTO HUD_FILA_MENSAJE, 1, C_J1, _SUBA_Y_BAJE_SW15_PARA_OTRA_PARTIDA
    j    HR_SALIR
HR_J2:
    TEXTO HUD_FILA_ESTADO, 5, C_J2, _GANA_EL_JUGADOR_2
    TEXTO HUD_FILA_MENSAJE, 1, C_J2, _SUBA_Y_BAJE_SW15_PARA_OTRA_PARTIDA
HR_SALIR:
    lw   s3, 0(sp)
    lw   ra, 4(sp)
    addi sp, sp, 8
    ret

# ------------------------------------------------------------------------------
# HUD_FIJO: lo que no cambia en toda la partida. Títulos, letras A a H y números 1 a 8 de los
# tableros, y el texto de la fila de ganadas. Hoja.
# ------------------------------------------------------------------------------
HUD_FIJO:
    TEXTO HUD_FILA_TITULOS, 2, C_FONDO, _JUGADOR_1
    TEXTO HUD_FILA_TITULOS, 12, C_FONDO, _JUGADOR_2
    TEXTO HUD_FILA_GANADAS, 2, C_FONDO, PARTIDAS_GANADAS___J1_
    TEXTO HUD_FILA_GANADAS, 14, C_FONDO, ___J2_
    # Letras de columna, una centrada por casilla encima de cada tablero. El código de una letra
    # es el de la anterior más uno, que en la palabra es sumar 1 << CAR_DESPL
    li   t0, CENTRADO | (CH_A << CAR_DESPL) | C_FONDO
    addi t1, s1, (HUD_FILA_LETRAS * 20 + TAB_COL0) * 4
    li   t2, 8
HF_LETRAS:
    sw   t0, 0(t1)                      # tablero J1
    sw   t0, 40(t1)                     # tablero J2, 10 columnas a la derecha
    addi t0, t0, 1 << CAR_DESPL
    addi t1, t1, 4                      # columna siguiente
    addi t2, t2, -1
    bnez t2, HF_LETRAS
    # Números de fila a la izquierda de cada tablero, columnas 0 y 10
    li   t0, CENTRADO | (CH_1 << CAR_DESPL) | C_FONDO
    addi t1, s1, TAB_FILA0 * 20 * 4
    li   t2, 8
HF_NUMEROS:
    sw   t0, 0(t1)                      # columna 0, Jugador 1
    sw   t0, 40(t1)                     # columna 10, Jugador 2
    addi t0, t0, 1 << CAR_DESPL
    addi t1, t1, 80                     # fila siguiente
    addi t2, t2, -1
    bnez t2, HF_NUMEROS
    ret

# ------------------------------------------------------------------------------
# HUD_GANADAS: los dígitos de GANADAS_BCD en la fila de ganadas, los dos de cada jugador en
# una casilla. Hoja.
# ------------------------------------------------------------------------------
.macro DIGITOS_GANADAS desplazamiento, col
    srli t1, t0, \desplazamiento + 4     # decena, mitad izquierda
    andi t1, t1, 0xF
    addi t1, t1, CH_0
    slli t1, t1, CAR_DESPL
    srli t2, t0, \desplazamiento         # unidad, mitad derecha
    andi t2, t2, 0xF
    addi t2, t2, CH_0
    slli t2, t2, CAR2_DESPL
    or   t1, t1, t2
    ori  t1, t1, C_FONDO
    sw   t1, ((HUD_FILA_GANADAS * 20 + \col) * 4)(s1)
.endm

HUD_GANADAS:
    lw   t0, GANADAS_BCD(s2)
    DIGITOS_GANADAS 8, HUD_COL_GANADAS_J1
    DIGITOS_GANADAS 0, HUD_COL_GANADAS_J2
    ret

# ------------------------------------------------------------------------------
# NUEVA_PARTIDA: deja todo como al empezar una partida, salvo las ganadas.
# Marco de 4 bytes: ra.
# ------------------------------------------------------------------------------
NUEVA_PARTIDA:
    addi sp, sp, -4
    sw   ra, 0(sp)
    lw   t2, GANADAS_BCD(s2)            # se conserva
    mv   t0, s2
    addi t1, s2, FIN_VARIABLES
NP_LIMPIAR:                             # tableros y variables en cero
    sw   zero, 0(t0)
    addi t0, t0, 4
    bne  t0, t1, NP_LIMPIAR
    sw   t2, GANADAS_BCD(s2)
    lw   t0, BOTONES(s0)                # un BTN_RST sostenido no vuelve a dar flanco
    sw   t0, BOTONES_PREV(s2)
    li   t0, SND_SILENCIO
    sw   t0, BUZZER(s0)
    jal  ra, VGA_LIMPIAR
    li   a0, 0
    jal  ra, REPINTAR_TABLERO
    li   a0, 1
    jal  ra, REPINTAR_TABLERO
    jal  ra, HUD_FIJO
    jal  ra, HUD_GANADAS
    lw   ra, 0(sp)
    addi sp, sp, 4
    ret
