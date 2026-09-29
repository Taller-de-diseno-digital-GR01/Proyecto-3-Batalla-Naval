// Los puertos del bus llevan sufijo _i/_o porque la seccion 4.5.5 del enunciado los define asi, igual que en periferico_uart
module periferico_buzzer #(parameter WIDTH = 32, parameter CLK_FREQ_HZ = 100_000_000, parameter UNIDAD_MS = 50) (
  input logic clk_i,
  input logic rst_i,
  input logic write_enable_i,
  input logic [1:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  output logic buzzer_o // pin M18, JC2
  );

endmodule
