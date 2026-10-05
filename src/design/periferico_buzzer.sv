module periferico_buzzer #(parameter WIDTH = 32, parameter CLK_FREQ_HZ = 100_000_000, parameter UNIDAD_MS = 50) (
  input logic clk_i,
  input logic rst_i,
  input logic write_enable_i,
  input logic [1:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  output logic buzzer_o // pin M18, JC2
  );

  localparam logic [1:0] ADDR_SONIDO = 2'b00;
  localparam int ANCHO_SONIDO = 3;

  logic [ANCHO_SONIDO-1:0] reg_sonido;
  logic escribir_sonido;
  logic fin_melodia;
  logic [17:0] n_nota;
  logic sonar;

  assign escribir_sonido = write_enable_i && addr_i == ADDR_SONIDO;

  secuenciador_melodia #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .UNIDAD_MS(UNIDAD_MS)) u_secuenciador (
    .clk(clk_i),
    .rst(rst_i),
    .i_iniciar(escribir_sonido),
    .i_sonido(reg_sonido),
    .o_n(n_nota),
    .o_sonar(sonar),
    .o_fin(fin_melodia)
  );

  generador_tono #(.ANCHO_N(18)) u_generador (
    .clk(clk_i),
    .rst(rst_i),
    .i_n(n_nota),
    .i_sonar(sonar),
    .o_sound(buzzer_o)
  );

  // La escritura le gana a fin_melodia porque en reposo el secuenciador tiene o_fin siempre en alto
  always_ff @(posedge clk_i) begin
    if (rst_i) reg_sonido <= '0;
    else if (escribir_sonido) reg_sonido <= wdata_i[ANCHO_SONIDO-1:0];
    else if (fin_melodia) reg_sonido <= '0;
  end

  always_comb begin
    case (addr_i)
      ADDR_SONIDO: rdata_o = {{(WIDTH-ANCHO_SONIDO){1'b0}}, reg_sonido};
      default: rdata_o = '0;
    endcase
  end

endmodule
