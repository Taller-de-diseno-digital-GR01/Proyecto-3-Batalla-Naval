module marcador #(parameter REFRESH_BITS = 18) (
  input logic clk,
  input logic rst,
  input logic [15:0] i_digitos, // [3:0] va a AN0 y [15:12] a AN3
  input logic [3:0] i_puntos, // un bit por digito, en alto enciende el punto

  output logic [6:0] o_seg, // gfedcba, activos en bajo
  output logic [3:0] o_an, // activos en bajo
  output logic o_dp // activo en bajo
  );

  logic [REFRESH_BITS-1:0] contador;
  logic [1:0] selector;
  logic [3:0] digito_bcd;
  logic punto;

  always_ff @(posedge clk) begin
    if (rst) contador <= '0;
    else contador <= contador + 1'b1;
  end

  assign selector = contador[REFRESH_BITS-1 -: 2];

  always_comb begin
    case (selector)
      2'b00: begin
        digito_bcd = i_digitos[3:0];
        punto = i_puntos[0];
        o_an = 4'b1110;
      end
      2'b01: begin
        digito_bcd = i_digitos[7:4];
        punto = i_puntos[1];
        o_an = 4'b1101;
      end
      2'b10: begin
        digito_bcd = i_digitos[11:8];
        punto = i_puntos[2];
        o_an = 4'b1011;
      end
      default: begin
        digito_bcd = i_digitos[15:12];
        punto = i_puntos[3];
        o_an = 4'b0111;
      end
    endcase
  end

  assign o_dp = ~punto;

  always_comb begin
    case (digito_bcd)
      4'd0: o_seg = 7'b1000000;
      4'd1: o_seg = 7'b1111001;
      4'd2: o_seg = 7'b0100100;
      4'd3: o_seg = 7'b0110000;
      4'd4: o_seg = 7'b0011001;
      4'd5: o_seg = 7'b0010010;
      4'd6: o_seg = 7'b0000010;
      4'd7: o_seg = 7'b1111000;
      4'd8: o_seg = 7'b0000000;
      4'd9: o_seg = 7'b0010000;
      default: o_seg = 7'b1111111; // 10 a 15 apaga el digito, el programa lo usa para borrar
    endcase
  end

endmodule
