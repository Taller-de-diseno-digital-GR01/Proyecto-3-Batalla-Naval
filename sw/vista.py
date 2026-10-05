import dibujo
import partida
import protocolo

LIMPIAR = "\x1b[2J\x1b[H"
SEPARACION = " " * 8

CASILLAS = {
    partida.AGUA: ("·", "gris"),
    partida.BARCO: ("■", "fuerte"),
    partida.IMPACTO: ("✕", "rojo"),
    partida.FALLO: ("o", "azul"),
}


def dibujar(juego):
    print(LIMPIAR + "\n".join(_lineas(juego)))


def _lineas(juego):
    lineas = ["", dibujo.pintar("  B A T A L L A   N A V A L", "fuerte") + "   " + dibujo.pintar("Jugador 2", "azul"), ""]
    lineas.append("  %-19s%s%s" % ("TU FLOTA", SEPARACION, "FLOTA DEL JUGADOR 1"))
    lineas += _tableros(juego)
    lineas.append("")
    lineas += _estado(juego)
    if juego.aviso:
        texto, color = juego.aviso
        lineas.append("  " + dibujo.pintar(texto, color))
    lineas.append("")
    lineas.append(dibujo.pintar("  " + _ayuda(juego), "gris"))
    return lineas


def _tableros(juego):
    vista_previa = set()
    cursor_propio = juego.fase == partida.COLOCACION and juego.barco is not None
    if cursor_propio:
        vista_previa = set(partida.casillas_barco(juego.barco, juego.cursor[0], juego.cursor[1], juego.vertical))
    cursor_enemigo = juego.me_toca
    cabecera = "    " + " ".join("ABCDEFGH")
    lineas = ["  " + cabecera + SEPARACION + cabecera]
    for fila in range(partida.LADO):
        izquierda = [_casilla(juego.propio[fila][c], (fila, c) in vista_previa,
                              cursor_propio and [fila, c] == juego.cursor) for c in range(partida.LADO)]
        derecha = [_casilla(juego.enemigo[fila][c], False,
                            cursor_enemigo and [fila, c] == juego.cursor) for c in range(partida.LADO)]
        lineas.append("    %d %s%s  %d %s" % (fila + 1, " ".join(izquierda), SEPARACION, fila + 1, " ".join(derecha)))
    return lineas


def _casilla(estado, previa, cursor):
    simbolo, color = CASILLAS[estado]
    if previa:
        simbolo, color = "■", "amarillo"
    if cursor:
        color = "invertido"
    return dibujo.pintar(simbolo, color)


def _estado(juego):
    if juego.fase == partida.COLOCACION:
        if juego.barco is None:
            return ["  Flota lista, esperando a que el Jugador 1 termine de colocar."]
        sentido = "vertical" if juego.vertical else "horizontal"
        texto = "  Colocando el barco de %d casillas, %s." % (protocolo.LARGOS[juego.barco], sentido)
    elif juego.fase == partida.BATALLA:
        texto = "  " + dibujo.pintar("Tu turno, elegí dónde disparar.", "verde") if juego.me_toca else "  Turno del Jugador 1."
    else:
        return _final(juego)
    if juego.esperando:
        texto += dibujo.pintar("  esperando respuesta de la tarjeta...", "gris")
    return [texto]


def _final(juego):
    if juego.ganador == protocolo.J2:
        lineas = ["  " + dibujo.pintar("VICTORIA, hundiste toda la flota del Jugador 1", "verde")]
    else:
        lineas = ["  " + dibujo.pintar("DERROTA, el Jugador 1 hundió tu flota", "rojo")]
    if juego.disparos:
        lineas.append("  disparos   Jugador 1 %d, Jugador 2 %d" % juego.disparos)
    if juego.hundidos:
        lineas.append("  hundidos   Jugador 1 %d, Jugador 2 %d" % juego.hundidos)
    lineas.append(dibujo.pintar("  BTN_RST en la tarjeta para jugar otra", "gris"))
    return lineas


def _ayuda(juego):
    if juego.fase == partida.COLOCACION and juego.barco is not None:
        return "flechas mueven, r rota, Enter coloca, ESC sale"
    if juego.me_toca:
        return "flechas mueven, Enter dispara, ESC sale"
    return "ESC sale"
