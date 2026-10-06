import os
import sys

COLORES = {
    "rojo": "\x1b[31m",
    "verde": "\x1b[32m",
    "amarillo": "\x1b[33m",
    "azul": "\x1b[34m",
    "gris": "\x1b[90m",
    "fuerte": "\x1b[1m",
    "invertido": "\x1b[7m",
}
NORMAL = "\x1b[0m"


def hay_color():
    return sys.stdout.isatty() and "NO_COLOR" not in os.environ


def pintar(texto, color):
    if not hay_color():
        return texto
    return "%s%s%s" % (COLORES[color], texto, NORMAL)
