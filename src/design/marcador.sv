// Port del marcador del P2, los cuatro digitos llegan en BCD y el modulo no sabe que representan
module marcador #(parameter REFRESH_BITS = 18) (
  input logic clk,
  input logic rst,
  input logic [15:0] i_digitos, // [3:0] va a AN0 y [15:12] a AN3
  input logic [3:0] i_puntos, // un bit por digito, en alto enciende el punto

  output logic [6:0] o_seg, // gfedcba, activos en bajo
  output logic [3:0] o_an, // activos en bajo
  output logic o_dp // activo en bajo
  );

endmodule
