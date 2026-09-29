module secuenciador_melodia #(parameter CLK_FREQ_HZ = 100_000_000, parameter UNIDAD_MS = 50) (
  input logic clk,
  input logic rst,
  input logic i_iniciar, // pulso de un ciclo con la escritura del programa
  input logic [2:0] i_sonido, // desde REG_SONIDO

  output logic [17:0] o_n, // medio periodo menos uno, hacia generador_tono
  output logic o_sonar,
  output logic o_fin // en alto mientras la melodia este terminada, limpia REG_SONIDO
  );

endmodule
