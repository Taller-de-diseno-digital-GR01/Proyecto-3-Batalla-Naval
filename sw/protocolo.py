# Tramas de nivel03.md, "Mensajes UART que usa el flujo". Los valores son los mismos de programa.s
from collections import namedtuple

TRAMA_INICIO = 0xAA
LARGO_TRAMA = 5

MSG_COLOCAR = 0x10
MSG_DISPARO = 0x11
MSG_ESTADO = 0x20
MSG_RES_COLOCACION = 0x21
MSG_DISPARO_DADO = 0x22
MSG_DISPARO_RECIBIDO = 0x23
MSG_RESUMEN_DISPAROS = 0x24
MSG_RESUMEN_HUNDIDOS = 0x25

EST_COLOCACION = 0
EST_BATALLA = 1
EST_TURNO = 2
EST_FIN = 3

COL_VALIDA = 0
COL_TRASLAPE = 1
COL_FUERA = 2
COL_REPETIDO = 3

D_IMPACTO = 0
D_FALLO = 1
D_HUNDIDO = 2
D_REPETIDO = 3

J1 = 0
J2 = 1

# El largo de cada barco por id, igual que en la ROM
LARGOS = (4, 3, 2)

Estado = namedtuple("Estado", "que dato")
ResColocacion = namedtuple("ResColocacion", "barco codigo")
DisparoDado = namedtuple("DisparoDado", "fila columna resultado")
DisparoRecibido = namedtuple("DisparoRecibido", "fila columna resultado")
ResumenDisparos = namedtuple("ResumenDisparos", "j1 j2")
ResumenHundidos = namedtuple("ResumenHundidos", "j1 j2")


def armar(tipo, d1, d2):
    return bytes([TRAMA_INICIO, tipo, d1, d2, tipo ^ d1 ^ d2])


def casilla(fila, columna):
    return fila << 4 | columna


def codificar_colocar(barco, vertical, fila, columna):
    return armar(MSG_COLOCAR, barco | (0x80 if vertical else 0), casilla(fila, columna))


def codificar_disparo(fila, columna):
    return armar(MSG_DISPARO, casilla(fila, columna), 0)


def _evento(tipo, d1, d2):
    if tipo == MSG_ESTADO:
        return Estado(que=d1, dato=d2)
    if tipo == MSG_RES_COLOCACION:
        return ResColocacion(barco=d1, codigo=d2)
    if tipo in (MSG_DISPARO_DADO, MSG_DISPARO_RECIBIDO):
        if d1 & 0x88:  # fila o columna mayor que 7, la vista se saldría del tablero
            return None
        clase = DisparoDado if tipo == MSG_DISPARO_DADO else DisparoRecibido
        return clase(fila=d1 >> 4, columna=d1 & 0xF, resultado=d2)
    if tipo == MSG_RESUMEN_DISPAROS:
        return ResumenDisparos(j1=d1, j2=d2)
    if tipo == MSG_RESUMEN_HUNDIDOS:
        return ResumenHundidos(j1=d1, j2=d2)
    return None


class Decodificador:
    """El mismo lector que UART_ATENDER en la ROM, un 0xAA siempre arranca una trama nueva."""

    def __init__(self):
        self.descartados = 0
        self._trama = bytearray()

    def alimentar(self, datos):
        """Come los bytes que hayan llegado y devuelve los mensajes completos que salieron."""
        eventos = []
        for byte in datos:
            evento = self._comer(byte)
            if evento is not None:
                eventos.append(evento)
        return eventos

    def _comer(self, byte):
        if byte == TRAMA_INICIO:
            if self._trama:  # la que venía a medias se pierde
                self.descartados += 1
            self._trama = bytearray([byte])
            return None
        if not self._trama:
            self.descartados += 1
            return None
        self._trama.append(byte)
        if len(self._trama) < LARGO_TRAMA:
            return None
        _, tipo, d1, d2, verificacion = self._trama
        self._trama = bytearray()
        evento = _evento(tipo, d1, d2) if tipo ^ d1 ^ d2 == verificacion else None
        if evento is None:
            self.descartados += 1
        return evento
