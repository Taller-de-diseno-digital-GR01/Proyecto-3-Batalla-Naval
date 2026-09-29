// Port del generador_tono del P2, lo que decidia que sonar y cuanto tiempo paso a secuenciador_melodia
module generador_tono #(parameter ANCHO_N = 18) ( // 18 bits alcanzan para A3, la nota mas grave de ROM_NOTAS
  input logic clk,
  input logic rst,
  input logic [ANCHO_N-1:0] i_n, // medio periodo menos uno, en ciclos
  input logic i_sonar,

  output logic o_sound // onda cuadrada hacia el pin del buzzer
  );

  logic apagado;
  logic fin_medio_periodo;
  logic [ANCHO_N-1:0] cont_divisor;
  logic reg_onda;

  assign apagado = rst | ~i_sonar;

  // Contador y comparador como submodulos para que el esquematico conserve los bloques de la tabla del doc
  contador_limpiable #(.ANCHO(ANCHO_N)) u_cont (
    .clk(clk),
    .i_limpiar(apagado | fin_medio_periodo),
    .o_cuenta(cont_divisor)
  );

  // >= y no == porque la nota cambia sin pasar por silencio y el contador puede quedar arriba del N nuevo
  comparador_mayor_igual #(.ANCHO(ANCHO_N)) u_cmp (
    .i_a(cont_divisor),
    .i_b(i_n),
    .o_mayor_igual(fin_medio_periodo)
  );

  always_ff @(posedge clk) begin
    if (apagado) reg_onda <= 1'b0;
    else reg_onda <= reg_onda ^ fin_medio_periodo;
  end

  // La AND baja el buzzer en el mismo ciclo en que se apaga i_sonar, reg_onda llegaria uno despues
  assign o_sound = reg_onda & i_sonar;

endmodule


module contador_limpiable #(parameter ANCHO = 18) (
  input logic clk,
  input logic i_limpiar,
  output logic [ANCHO-1:0] o_cuenta
  );

  always_ff @(posedge clk) begin
    if (i_limpiar) o_cuenta <= '0;
    else o_cuenta <= o_cuenta + 1'b1;
  end

endmodule


module comparador_mayor_igual #(parameter ANCHO = 18) (
  input logic [ANCHO-1:0] i_a,
  input logic [ANCHO-1:0] i_b,
  output logic o_mayor_igual
  );

  assign o_mayor_igual = i_a >= i_b;

endmodule
