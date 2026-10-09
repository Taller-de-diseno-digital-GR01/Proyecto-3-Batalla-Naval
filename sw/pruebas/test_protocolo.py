# Pruebas del decodificador, corren sin tarjeta porque protocolo.py es puro
# Correr con: make test-app

import unittest

import protocolo


class CodificarTest(unittest.TestCase):

    def test_colocar_lleva_orientacion_en_el_bit_7(self):
        self.assertEqual(protocolo.codificar_colocar(1, True, 2, 3),
                         bytes([0xAA, 0x10, 0x81, 0x23, 0x10 ^ 0x81 ^ 0x23]))

    def test_disparo_con_d2_en_cero(self):
        self.assertEqual(protocolo.codificar_disparo(7, 7), bytes([0xAA, 0x11, 0x77, 0x00, 0x11 ^ 0x77]))


class DecodificadorTest(unittest.TestCase):

    def setUp(self):
        self.decodificador = protocolo.Decodificador()

    def test_estado(self):
        eventos = self.decodificador.alimentar(protocolo.armar(protocolo.MSG_ESTADO, protocolo.EST_TURNO, 1))
        self.assertEqual(eventos, [protocolo.Estado(que=protocolo.EST_TURNO, dato=1)])

    def test_disparo_dado_parte_la_casilla(self):
        eventos = self.decodificador.alimentar(protocolo.armar(protocolo.MSG_DISPARO_DADO, 0x52, protocolo.D_HUNDIDO))
        self.assertEqual(eventos, [protocolo.DisparoDado(fila=5, columna=2, resultado=protocolo.D_HUNDIDO)])

    def test_tramas_seguidas_en_una_sola_lectura(self):
        datos = (protocolo.armar(protocolo.MSG_ESTADO, protocolo.EST_FIN, 0)
                 + protocolo.armar(protocolo.MSG_RESUMEN_DISPAROS, 10, 12)
                 + protocolo.armar(protocolo.MSG_RESUMEN_HUNDIDOS, 3, 1))
        self.assertEqual(len(self.decodificador.alimentar(datos)), 3)

    def test_trama_partida_en_dos_lecturas(self):
        trama = protocolo.armar(protocolo.MSG_RES_COLOCACION, 2, protocolo.COL_TRASLAPE)
        self.assertEqual(self.decodificador.alimentar(trama[:2]), [])
        self.assertEqual(self.decodificador.alimentar(trama[2:]), [protocolo.ResColocacion(barco=2, codigo=1)])

    def test_bytes_sueltos_se_descartan(self):
        trama = protocolo.armar(protocolo.MSG_ESTADO, protocolo.EST_BATALLA, 0)
        self.assertEqual(len(self.decodificador.alimentar(b"\x13\x37" + trama)), 1)
        self.assertEqual(self.decodificador.descartados, 2)

    def test_un_aa_a_media_trama_resincroniza(self):
        trama = protocolo.armar(protocolo.MSG_ESTADO, protocolo.EST_BATALLA, 0)
        self.assertEqual(len(self.decodificador.alimentar(trama[:3] + trama)), 1)

    def test_verificacion_mala_se_descarta(self):
        trama = bytearray(protocolo.armar(protocolo.MSG_ESTADO, protocolo.EST_BATALLA, 0))
        trama[4] ^= 1
        self.assertEqual(self.decodificador.alimentar(trama), [])

    def test_tipo_de_la_pc_no_se_acepta_de_vuelta(self):
        self.assertEqual(self.decodificador.alimentar(protocolo.codificar_disparo(1, 1)), [])

    def test_casilla_fuera_de_rango_se_descarta(self):
        self.assertEqual(self.decodificador.alimentar(protocolo.armar(protocolo.MSG_DISPARO_RECIBIDO, 0x08, 0)), [])


if __name__ == "__main__":
    unittest.main()
