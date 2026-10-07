import shutil

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


def tamano_casilla():
    """(ancho, alto) en caracteres de cada casilla, lo más grande que deje la terminal."""
    columnas, filas = shutil.get_terminal_size()
    # 14 líneas se van en título, estado y ayuda y 7 en los huecos entre filas, y cada tablero lleva 4 de rótulo y 7 huecos a lo ancho
    alto = max(1, (filas - 21) // partida.LADO)
    ancho = max(1, (columnas - 2 * 11 - len(SEPARACION) - 2) // (2 * partida.LADO))
    # Un caracter de terminal es más o menos el doble de alto que de ancho
    ancho = min(ancho, 2 * alto + 1)
    alto = min(alto, ancho // 2 or 1)
    return ancho, alto


def _lineas(juego):
    ancho, alto = tamano_casilla()
    lineas = ["", dibujo.pintar("  B A T A L L A   N A V A L", "fuerte") + "   " + dibujo.pintar("Jugador 2", "azul"), ""]
    lineas.append("    %s%s    %s" % ("TU FLOTA".ljust(8 * ancho + 7), SEPARACION, "FLOTA DEL JUGADOR 1"))
    lineas += _tableros(juego, ancho, alto)
    lineas.append("")
    lineas += _estado(juego)
    if juego.aviso:
        texto, color = juego.aviso
        lineas.append("  " + dibujo.pintar(texto, color))
    lineas.append("")
    lineas.append(dibujo.pintar("  " + _ayuda(juego), "gris"))
    return lineas


def _tableros(juego, ancho, alto):
    vista_previa = set()
    cursor_propio = juego.fase == partida.COLOCACION and juego.barco is not None
    if cursor_propio:
        vista_previa = set(partida.casillas_barco(juego.barco, juego.cursor[0], juego.cursor[1], juego.vertical))
    cursor_enemigo = juego.me_toca
    cabecera = "    " + " ".join(letra.center(ancho) for letra in "ABCDEFGH")
    lineas = [cabecera + SEPARACION + cabecera]
    for fila in range(partida.LADO):
        for subfila in range(alto):
            centro = subfila == alto // 2
            rotulo = "  %d " % (fila + 1) if centro else "    "
            izquierda = [_casilla(juego.propio[fila][c], (fila, c) in vista_previa,
                                  cursor_propio and [fila, c] == juego.cursor, ancho, centro) for c in range(partida.LADO)]
            derecha = [_casilla(juego.enemigo[fila][c], False,
                                cursor_enemigo and [fila, c] == juego.cursor, ancho, centro) for c in range(partida.LADO)]
            lineas.append(rotulo + " ".join(izquierda) + SEPARACION + rotulo + " ".join(derecha))
        if alto > 1 and fila < partida.LADO - 1:
            lineas.append("")
    return lineas


def _casilla(estado, previa, cursor, ancho, centro):
    simbolo, color = CASILLAS[estado]
    if previa:
        simbolo, color = "■", "amarillo"
    if cursor:
        color = "invertido"
    # Los barcos llenan toda la casilla para que se lean como un bloque, el resto solo marca el centro
    if simbolo == "■":
        texto = ("▒" if cursor else "█") * ancho
    else:
        texto = (simbolo if centro else " ").center(ancho)
    return dibujo.pintar(texto, color)


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
        return "hjkl o flechas mueven, r rota, Enter coloca, ESC sale"
    if juego.me_toca:
        return "hjkl o flechas mueven, Enter dispara, ESC sale"
    return "ESC sale"
