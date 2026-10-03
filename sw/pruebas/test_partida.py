# Pruebas de lo que la PC anota con cada respuesta de la FPGA, sin tarjeta
# Correr con: make test-app

import unittest

import partida
import protocolo


class PartidaTest(unittest.TestCase):

    def setUp(self):
        self.juego = partida.Partida()

    def colocar(self, codigo):
        trama = self.juego.confirmar(0)
        self.juego.aplicar(protocolo.ResColocacion(barco=trama[2] & 3, codigo=codigo))
        return trama

    def test_colocacion_aceptada_marca_el_barco(self):
        self.juego.rotar()
        self.juego.mover(1, 2)
        self.assertEqual(self.colocar(protocolo.COL_VALIDA), protocolo.codificar_colocar(0, True, 1, 2))
        self.assertEqual([self.juego.propio[f][2] for f in range(1, 5)], [partida.BARCO] * 4)
        self.assertEqual(self.juego.barco, 1)

    def test_colocacion_rechazada_no_avanza(self):
        self.colocar(protocolo.COL_TRASLAPE)
        self.assertEqual(self.juego.barco, 0)
        self.assertEqual(self.juego.aviso[1], "rojo")

    def test_no_manda_otra_sin_respuesta(self):
        self.assertIsNotNone(self.juego.confirmar(0))
        self.assertIsNone(self.juego.confirmar(0.5))

    def test_la_espera_vence(self):
        self.juego.confirmar(0)
        self.assertFalse(self.juego.revisar_espera(1))
        self.assertTrue(self.juego.revisar_espera(partida.LIMITE_RESPUESTA + 0.1))
        self.assertIsNotNone(self.juego.confirmar(3))

    def test_solo_dispara_en_su_turno(self):
        self.juego.aplicar(protocolo.Estado(protocolo.EST_BATALLA, 0))
        self.juego.aplicar(protocolo.Estado(protocolo.EST_TURNO, protocolo.J1))
        self.assertIsNone(self.juego.confirmar(0))
        self.juego.aplicar(protocolo.Estado(protocolo.EST_TURNO, protocolo.J2))
        self.assertEqual(self.juego.confirmar(0), protocolo.codificar_disparo(0, 0))

    def test_disparo_dado_y_recibido(self):
        self.juego.aplicar(protocolo.DisparoDado(3, 4, protocolo.D_FALLO))
        self.juego.aplicar(protocolo.DisparoRecibido(6, 1, protocolo.D_HUNDIDO))
        self.assertEqual(self.juego.enemigo[3][4], partida.FALLO)
        self.assertEqual(self.juego.propio[6][1], partida.IMPACTO)

    def test_estado_colocacion_reinicia_todo(self):
        self.colocar(protocolo.COL_VALIDA)
        self.juego.aplicar(protocolo.Estado(protocolo.EST_FIN, protocolo.J1))
        self.juego.aplicar(protocolo.Estado(protocolo.EST_COLOCACION, 0))
        self.assertEqual(self.juego.fase, partida.COLOCACION)
        self.assertEqual(self.juego.barco, 0)
        self.assertEqual(self.juego.propio, partida.Partida().propio)


if __name__ == "__main__":
    unittest.main()
