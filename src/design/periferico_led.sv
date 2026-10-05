module periferico_led #(parameter WIDTH = 32) (
  input logic clk_i,
  input logic rst_i,
  input logic write_enable_i,
  input logic [1:0] addr_i,
  input logic [WIDTH-1:0] wdata_i,
  output logic [WIDTH-1:0] rdata_o,

  output logic [2:0] leds_o // LD0 colocacion, LD1 batalla, LD2 resultado
  );

  localparam logic [1:0] ADDR_LEDS = 2'b00;
  localparam int NUM_LEDS = 3;

  logic [NUM_LEDS-1:0] reg_leds;
  logic escribir_leds;

  assign escribir_leds = write_enable_i && addr_i == ADDR_LEDS;

  // Sin decodificador, el programa escribe el one-hot directo y dos LEDs encendidos serian un bug suyo
  always_ff @(posedge clk_i) begin
    if (rst_i) reg_leds <= '0;
    else if (escribir_leds) reg_leds <= wdata_i[NUM_LEDS-1:0];
  end

  assign leds_o = reg_leds;

  always_comb begin
    case (addr_i)
      ADDR_LEDS: rdata_o = {{(WIDTH-NUM_LEDS){1'b0}}, reg_leds};
      default: rdata_o = '0;
    endcase
  end

endmodule
