# raw inputs
# Leer https://docs.python.org/3/library/termios.html
# Leer https://docs.python.org/3/library/contextlib.html
import os
import sys
import termios
import tty
from contextlib import contextmanager

ESCAPE = "\x1b"
FIN_DE_ARCHIVO = "\x04"  # Ctrl-D

# Las flechas llegan como ESC [ letra, o ESC O letra si la terminal está en modo aplicación
FLECHAS = {"A": (-1, 0), "B": (1, 0), "C": (0, 1), "D": (0, -1)}
VIM = {"k": (-1, 0), "j": (1, 0), "l": (0, 1), "h": (0, -1)}


@contextmanager
def modo_crudo(flujo=sys.stdin):
    """Deja el teclado sin buffer de línea y sin eco, y lo devuelve como estaba al salir."""
    if not flujo.isatty():  # con la entrada redirigida no hay nada que configurar
        yield
        return
    guardado = termios.tcgetattr(flujo)
    try:
        tty.setcbreak(flujo.fileno())  # Ctrl-C
        yield
    finally:
        termios.tcsetattr(flujo, termios.TCSADRAIN, guardado)


def leer_tecla(flujo=sys.stdin):
    # os.read y no flujo.read, el buffer de Python se quedaría con el resto de la flecha y el select ya no lo vería
    return os.read(flujo.fileno(), 8).decode(errors="ignore")


def flecha(tecla):
    """(dfila, dcolumna) si la tecla es una flecha o hjkl, si no None."""
    if len(tecla) == 3 and tecla[0] == ESCAPE and tecla[1] in "[O":
        return FLECHAS.get(tecla[2])
    return VIM.get(tecla.lower())
