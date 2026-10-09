#!/usr/bin/env python3
"""Recorta un VCD a la ventana [desde, hasta] (en unidades del timescale).

Los cambios anteriores a 'desde' se condensan en un bloque $dumpvars al inicio de
la ventana, así cada señal arranca con el valor que tenía en ese instante. Los
tiempos se corren para que la ventana empiece en 0, porque vecdump siempre dibuja
el eje desde 0.

Uso: recortar_vcd.py entrada.vcd salida.vcd desde hasta
"""
import sys


def volcar_inicio(o, estado):
    o.write('#0\n$dumpvars\n')
    for ident, v in estado.items():
        o.write(f'{v}{ident}\n' if len(v) == 1 else f'{v} {ident}\n')
    o.write('$end\n')


def recortar(entrada, salida, desde, hasta):
    estado = {}
    t = 0
    en_cabecera = True
    dentro = False
    with open(entrada) as f, open(salida, 'w') as o:
        for linea in f:
            if en_cabecera:
                o.write(linea)
                en_cabecera = '$enddefinitions' not in linea
                continue
            s = linea.strip()
            if not s or s.startswith('$'):
                continue
            if s[0] == '#':
                t = int(s[1:])
                if t > hasta:
                    break
                if t > desde and not dentro:
                    volcar_inicio(o, estado)
                    dentro = True
                if dentro:
                    o.write(f'#{t - desde}\n')
                continue
            if dentro:
                o.write(linea)
            else:
                v, ident = s.split() if s[0] in 'bBrR' else (s[0], s[1:])
                estado[ident] = v
        if not dentro:
            volcar_inicio(o, estado)
        o.write(f'#{hasta - desde}\n')


if __name__ == '__main__':
    if len(sys.argv) != 5:
        sys.exit('uso: recortar_vcd.py entrada.vcd salida.vcd desde hasta')
    recortar(sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
