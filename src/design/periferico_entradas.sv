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

  localparam logic [1:0] ADDR_ESTADO = 2'b00;
  localparam int NUM_BOTONES = 7;

  logic [NUM_BOTONES-1:0] estado;

  // Un solo flip-flop por bit, esta para cortar el camino combinacional del pin hasta DataIn_i y no como sincronizador
  always_ff @(posedge clk_i) begin
    if (rst_i) estado <= '0;
    else estado <= botones_i;
  end

  always_comb begin
    case (addr_i)
      ADDR_ESTADO: rdata_o = {{(WIDTH-NUM_BOTONES){1'b0}}, estado};
      default: rdata_o = '0;
    endcase
  end

endmodule
