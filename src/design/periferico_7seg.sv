// Los puertos del bus llevan sufijo _i/_o porque la seccion 4.5.5 del enunciado los define asi, igual que en periferico_uart
module periferico_7seg #(parameter WIDTH = 32, parameter REFRESH_BITS = 18) (
  input logic clk_i,
  input logic rst_i,
  input logic write_enable_i,
  input logic [1:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  output logic [6:0] seg_o,
  output logic [3:0] an_o,
  output logic dp_o
  );

endmodule
