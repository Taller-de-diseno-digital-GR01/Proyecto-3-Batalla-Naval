# Lo que la PC recuerda para dibujar. Las reglas viven en la ROM, acá solo se anota lo que la FPGA contesta
import protocolo

COLOCACION = "colocacion"
BATALLA = "batalla"
FIN = "fin"

AGUA = 0
BARCO = 1
IMPACTO = 2
FALLO = 3

LADO = 8

# La FPGA descarta sin responder, así que una trama sin respuesta en este tiempo se da por perdida
LIMITE_RESPUESTA = 2.0

MOTIVOS = {
    protocolo.COL_TRASLAPE: "se traslapa con otro barco",
    protocolo.COL_FUERA: "se sale del tablero",
}


def nombre_casilla(fila, columna):
    return "%s%d" % ("ABCDEFGH"[columna], fila + 1)


def casillas_barco(barco, fila, columna, vertical):
    """Todas las casillas que ocuparía el barco, aunque alguna caiga fuera del tablero."""
    largo = protocolo.LARGOS[barco]
    if vertical:
        return [(fila + i, columna) for i in range(largo)]
    return [(fila, columna + i) for i in range(largo)]


def _tablero():
    return [[AGUA] * LADO for _ in range(LADO)]


class Partida:

    def __init__(self):
        self.fase = COLOCACION
        self.propio = _tablero()
        self.enemigo = _tablero()
        self.colocados = set()
        self.vertical = False
        self.cursor = [0, 0]
        self.turno = None
        self.ganador = None
        self.disparos = None
        self.hundidos = None
        self.aviso = None
        # Trama mandada que todavía no tiene respuesta, (tipo, datos, instante)
        self.pendiente = None

    @property
    def barco(self):
        """El próximo barco por colocar, o None si la flota ya está."""
        for barco in range(len(protocolo.LARGOS)):
            if barco not in self.colocados:
                return barco
        return None

    @property
    def esperando(self):
        return self.pendiente is not None

    @property
    def me_toca(self):
        return self.fase == BATALLA and self.turno == protocolo.J2

    def mover(self, dfila, dcolumna):
        self.cursor[0] = min(max(self.cursor[0] + dfila, 0), LADO - 1)
        self.cursor[1] = min(max(self.cursor[1] + dcolumna, 0), LADO - 1)

    def rotar(self):
        if self.fase == COLOCACION:
            self.vertical = not self.vertical

    def confirmar(self, ahora):
        """La trama que hay que mandar por la jugada en el cursor, o None si no toca mandar nada."""
        # Regla de conversación de nivel03, no se transmite de nuevo hasta tener la respuesta
        if self.esperando:
            return None
        fila, columna = self.cursor
        if self.fase == COLOCACION and self.barco is not None:
            self.pendiente = (protocolo.MSG_COLOCAR, (self.barco, fila, columna, self.vertical), ahora)
            return protocolo.codificar_colocar(self.barco, self.vertical, fila, columna)
        if self.me_toca:
            self.pendiente = (protocolo.MSG_DISPARO, (fila, columna), ahora)
            return protocolo.codificar_disparo(fila, columna)
        return None

    def revisar_espera(self, ahora):
        """True si la respuesta pendiente se venció, para que la vista avise."""
        if not self.esperando or ahora - self.pendiente[2] < LIMITE_RESPUESTA:
            return False
        self.pendiente = None
        self.aviso = ("la tarjeta no respondió, probá de nuevo", "amarillo")
        return True

    def aplicar(self, evento):
        if isinstance(evento, protocolo.Estado):
            self._estado(evento)
        elif isinstance(evento, protocolo.ResColocacion):
            self._colocacion(evento)
        elif isinstance(evento, protocolo.DisparoDado):
            self._disparo_dado(evento)
        elif isinstance(evento, protocolo.DisparoRecibido):
            self._disparo_recibido(evento)
        elif isinstance(evento, protocolo.ResumenDisparos):
            self.disparos = evento
        elif isinstance(evento, protocolo.ResumenHundidos):
            self.hundidos = evento

    def _estado(self, evento):
        if evento.que == protocolo.EST_COLOCACION:
            # Llega al arrancar y con cada BTN_RST, en cualquier punto de la partida
            self.__init__()
            self.aviso = ("partida nueva", "azul")
        elif evento.que == protocolo.EST_BATALLA:
            self.fase = BATALLA
            self.cursor = [0, 0]
            self.aviso = ("arranca la batalla", "azul")
        elif evento.que == protocolo.EST_TURNO:
            self.fase = BATALLA
            self.turno = evento.dato
            if self.turno == protocolo.J1:
                # Si el Disparo dado se perdió, este Estado avisa que el disparo sí contó
                self.pendiente = None
        elif evento.que == protocolo.EST_FIN:
            self.fase = FIN
            self.ganador = evento.dato
            self.pendiente = None

    def _colocacion(self, evento):
        if not self.esperando or self.pendiente[0] != protocolo.MSG_COLOCAR:
            return
        barco, fila, columna, vertical = self.pendiente[1]
        if evento.barco != barco:
            return
        self.pendiente = None
        # Repetido sale cuando se reenvió una colocación que sí había entrado, cuenta como aceptada
        if evento.codigo in (protocolo.COL_VALIDA, protocolo.COL_REPETIDO):
            for f, c in casillas_barco(barco, fila, columna, vertical):
                self.propio[f][c] = BARCO
            self.colocados.add(barco)
            self.aviso = ("barco de %d en %s" % (protocolo.LARGOS[barco], nombre_casilla(fila, columna)), "verde")
        else:
            self.aviso = ("rechazado, %s" % MOTIVOS.get(evento.codigo, "motivo desconocido"), "rojo")

    def _disparo_dado(self, evento):
        if self.esperando and self.pendiente[0] == protocolo.MSG_DISPARO:
            self.pendiente = None
        donde = nombre_casilla(evento.fila, evento.columna)
        if evento.resultado == protocolo.D_REPETIDO:
            self.aviso = ("ya habías disparado a %s, elegí otra" % donde, "amarillo")
            return
        if evento.resultado == protocolo.D_FALLO:
            self.enemigo[evento.fila][evento.columna] = FALLO
            self.aviso = ("%s, agua" % donde, "gris")
            return
        self.enemigo[evento.fila][evento.columna] = IMPACTO
        if evento.resultado == protocolo.D_HUNDIDO:
            self.aviso = ("%s, ¡hundido!" % donde, "verde")
        else:
            self.aviso = ("%s, impacto" % donde, "verde")

    def _disparo_recibido(self, evento):
        donde = nombre_casilla(evento.fila, evento.columna)
        if evento.resultado == protocolo.D_FALLO:
            self.propio[evento.fila][evento.columna] = FALLO
            self.aviso = ("el Jugador 1 tiró a %s y falló" % donde, "gris")
            return
        self.propio[evento.fila][evento.columna] = IMPACTO
        if evento.resultado == protocolo.D_HUNDIDO:
            self.aviso = ("el Jugador 1 te hundió un barco en %s" % donde, "rojo")
        else:
            self.aviso = ("el Jugador 1 te pegó en %s" % donde, "rojo")
