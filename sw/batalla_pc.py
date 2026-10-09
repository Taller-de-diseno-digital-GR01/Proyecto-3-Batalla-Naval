#!/usr/bin/env python3
import argparse
import select
import shutil
import sys
import time

import enlace
import partida
import protocolo
import terminal
import vista

# Cada cuánto se despierta el lazo sin teclas ni bytes, solo para vencer la espera de una respuesta
VUELTA = 0.2


def opciones():
    cli = argparse.ArgumentParser(description="Terminal remota del Jugador 2 de la batalla naval de la Basys 3")
    cli.add_argument("-p", "--puerto", help="puerto serial, si no se da se busca la tarjeta sola")
    cli.add_argument("-b", "--baudios", type=int, default=enlace.BAUDIOS)
    cli.add_argument("-l", "--lista", action="store_true", help="lista los puertos de la tarjeta y sale")
    return cli.parse_args()


def listar():
    puertos = enlace.puertos_de_la_tarjeta()
    if not puertos:
        print("No se detecta ninguna Basys 3.")
        return
    for puerto in puertos:
        print("%s  %s" % (puerto.device, puerto.description))


def jugar(puerto):
    decodificador = protocolo.Decodificador()
    juego = partida.Partida()
    with terminal.modo_crudo():
        vista.dibujar(juego)
        tamano = shutil.get_terminal_size()
        while True:
            listos, _, _ = select.select([sys.stdin, puerto], [], [], VUELTA)
            cambio = False
            if sys.stdin in listos:
                if not tecla(puerto, juego):
                    return
                cambio = True
            if puerto in listos:
                for evento in decodificador.alimentar(puerto.read(64)):
                    juego.aplicar(evento)
                    cambio = True
            # Si se agranda la ventana el tablero se vuelve a escalar sin esperar a una tecla
            if shutil.get_terminal_size() != tamano:
                tamano = shutil.get_terminal_size()
                cambio = True
            if juego.revisar_espera(time.monotonic()) or cambio:
                vista.dibujar(juego)


def tecla(puerto, juego):
    """Atiende una tecla, y devuelve False cuando el jugador quiere salir."""
    pulsada = terminal.leer_tecla()
    if pulsada in ("", terminal.ESCAPE, terminal.FIN_DE_ARCHIVO):
        return False
    paso = terminal.flecha(pulsada)
    if paso is not None:
        juego.mover(*paso)
    elif pulsada.lower() == "r":
        juego.rotar()
    elif pulsada in ("\n", "\r"):
        trama = juego.confirmar(time.monotonic())
        if trama is not None:
            enlace.mandar(puerto, trama)
    return True


def main():
    args = opciones()
    if args.lista:
        listar()
        return 0
    try:
        puerto = enlace.abrir(args.puerto, args.baudios)
    except enlace.ErrorEnlace as error:
        print("Error, %s" % error, file=sys.stderr)
        return 1
    try:
        jugar(puerto)
    except KeyboardInterrupt:
        pass
    finally:
        puerto.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
