# prueba_ripes.s
# Programa de prueba para comprobar que Ripes sirve para el proyecto.
# Usa solo instrucciones de la lista base del instructivo (sin lui ni auipc).
#
# Resultado esperado al terminar:
#   s0 = 0x00010000   base de los perifericos
#   s2 = 0x00002000   base de la RAM
#   t0 = 0x00001234   valor de prueba
#   t1 = 0x00001234   lo que se lee de vuelta de la RAM
#   memoria 0x00002000 = 0x00001234   (RAM)
#   memoria 0x00010130 = 0x00001234   (DISPLAYS)

.equ DISPLAYS, 0x130        # desplazamiento de los displays desde s0
.equ VAR_PRUEBA, 0x000      # desplazamiento de una palabra de RAM desde s2

.globl INICIO
.text
INICIO:
    # s0 = 0x0001_0000. No cabe en los 12 bits de addi, asi que se arma
    # con un 1 corrido 16 posiciones a la izquierda.
    addi s0, zero, 1
    slli s0, s0, 16

    # s2 = 0x0000_2000, un 1 corrido 13 posiciones.
    addi s2, zero, 1
    slli s2, s2, 13

    # t0 = 0x1234. Tampoco cabe en addi (maximo 2047 = 0x7FF), se arma en dos partes:
    # 0x123 corrido 4 bits da 0x1230, y se le suma 0x4.
    addi t0, zero, 0x123
    slli t0, t0, 4
    addi t0, t0, 0x4

    # Escribe en la RAM y lo lee de vuelta.
    sw t0, VAR_PRUEBA(s2)
    lw t1, VAR_PRUEBA(s2)

    # Escribe el mismo valor en el registro de los displays.
    sw t1, DISPLAYS(s0)

FIN:
    # Lazo infinito, igual que el programa real, que nunca termina.
    jal zero, FIN
