// Los puertos del bus llevan sufijo _i/_o porque la seccion 4.5.5 del enunciado los define asi, igual que en periferico_uart
module periferico_entradas #(parameter WIDTH = 32) (
  input logic clk_i,
  input logic rst_i,
  input logic write_enable_i, // gpio_we, el AT lo deja en cero porque el registro es de solo lectura
  input logic [1:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  input logic [6:0] botones_i // [0] BTN_ARRIBA hasta [6] BTN_RST, directo de los pines
  );

endmodule
