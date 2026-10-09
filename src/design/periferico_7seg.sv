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

  localparam logic [1:0] ADDR_DIGITOS = 2'b00;
  // 16 bits de digitos BCD y 4 de puntos, J1 en los dos nibbles altos
  localparam int ANCHO_DIGITOS = 20;

  logic [ANCHO_DIGITOS-1:0] reg_digitos;
  logic escribir_digitos;

  marcador #(.REFRESH_BITS(REFRESH_BITS)) u_marcador (
    .clk(clk_i),
    .rst(rst_i),
    .i_digitos(reg_digitos[15:0]),
    .i_puntos(reg_digitos[19:16]),
    .o_seg(seg_o),
    .o_an(an_o),
    .o_dp(dp_o)
  );

  assign escribir_digitos = write_enable_i && addr_i == ADDR_DIGITOS;

  // Solo rst_i lo borra, BTN_RST lo atiende el programa y las ganadas se conservan
  always_ff @(posedge clk_i) begin
    if (rst_i) reg_digitos <= '0;
    else if (escribir_digitos) reg_digitos <= wdata_i[ANCHO_DIGITOS-1:0];
  end

  always_comb begin
    case (addr_i)
      ADDR_DIGITOS: rdata_o = {{(WIDTH-ANCHO_DIGITOS){1'b0}}, reg_digitos};
      default: rdata_o = '0;
    endcase
  end

endmodule
