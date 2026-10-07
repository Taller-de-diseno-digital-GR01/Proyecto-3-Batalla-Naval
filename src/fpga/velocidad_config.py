#!/usr/bin/env python3
# velocidad_config.py
# Sube la frecuencia con que la FPGA lee su configuracion de la flash SPI.
#
# Uso: python3 src/fpga/velocidad_config.py src/build/top.bit
#
# xc7frames2bit deja COR0 en 0x02003FE5, el valor por defecto de Vivado, con CCLK a ~3 MHz.
# Leer los ~17,5 Mbit del bitstream de la flash toma asi ~6 s, y despues de PROG la tarjeta
# queda todo ese tiempo sin VGA ni 7 segmentos. Con COR0 = 0x02423FE5 (lo que pone Vivado con
# BITSTREAM.CONFIG.CONFIGRATE 33, sacado de un .bit suyo) carga en ~0,5 s. Solo cambia el
# campo OSCFSEL (COR0[22:17]), el resto queda igual. El bitstream de openXC7 no lleva CRC, asi
# que no hay que recalcular nada. Por JTAG (make program) no se nota, ahi el reloj es TCK.

import sys

SINCRONIA    = bytes.fromhex("aa995566")
ESCRIBE_COR0 = bytes.fromhex("30012001")  # paquete tipo 1, escritura de una palabra en COR0
COR0_3MHZ    = bytes.fromhex("02003fe5")
COR0_33MHZ   = bytes.fromhex("02423fe5")

if len(sys.argv) != 2:
    sys.exit("Uso: python3 src/fpga/velocidad_config.py <archivo.bit>")

ruta = sys.argv[1]
datos = bytearray(open(ruta, "rb").read())

inicio = datos.find(SINCRONIA)
if inicio < 0:
    sys.exit(f"ERROR: {ruta} no tiene la palabra de sincronia, no parece un bitstream")

# El COR0 va en el encabezado de configuracion, antes de los frames
pos = datos.find(ESCRIBE_COR0, inicio, inicio + 512)
if pos < 0 or pos % 4 != inicio % 4:
    sys.exit(f"ERROR: no se encontro la escritura de COR0 en {ruta}")

valor = datos[pos + 4:pos + 8]
if valor == COR0_33MHZ:
    print(f"{ruta}: COR0 ya estaba a 33 MHz")
    sys.exit(0)
if valor != COR0_3MHZ:
    sys.exit(f"ERROR: COR0 = 0x{valor.hex()} en {ruta}, se esperaba 0x{COR0_3MHZ.hex()}. "
             "Revisar antes de cambiarlo a ciegas")

datos[pos + 4:pos + 8] = COR0_33MHZ
open(ruta, "wb").write(datos)
print(f"{ruta}: COR0 0x{COR0_3MHZ.hex()} -> 0x{COR0_33MHZ.hex()}, CCLK a 33 MHz")
