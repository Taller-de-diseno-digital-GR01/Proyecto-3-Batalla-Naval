// ROM de caracteres del periferico VGA, una fuente de 5 x 7 para ASCII de 0x20 a 0x5F.
// codigo_i = ASCII - 32, asi el programa escribe el codigo con la misma cuenta que el ensamblador
// ('A' - 32 = 33). Solo trae espacio, digitos, letras mayusculas y ! - :, el resto sale en blanco.
// Combinacional. El periferico la lee en el dominio de clk_pix_i con el codigo ya registrado.
//
// Cada glifo esta escrito fila por fila, el bit 4 es la columna izquierda. Para agregar un caracter basta
// con sumar sus 7 filas con su codigo.
module fuente_caracteres (
  input  logic [5:0] codigo_i, // ASCII - 32
  input  logic [2:0] fila_i,   // 0 arriba a 6 abajo, la 7 siempre en blanco
  output logic [4:0] bits_o    // [4] columna izquierda, [0] derecha
  );

  always_comb begin
    case ({codigo_i, fila_i})
      // '!', codigo 1
      {6'd1, 3'd0}: bits_o = 5'b00100;
      {6'd1, 3'd1}: bits_o = 5'b00100;
      {6'd1, 3'd2}: bits_o = 5'b00100;
      {6'd1, 3'd3}: bits_o = 5'b00100;
      {6'd1, 3'd4}: bits_o = 5'b00100;
      {6'd1, 3'd5}: bits_o = 5'b00000;
      {6'd1, 3'd6}: bits_o = 5'b00100;
      // '-', codigo 13
      {6'd13, 3'd0}: bits_o = 5'b00000;
      {6'd13, 3'd1}: bits_o = 5'b00000;
      {6'd13, 3'd2}: bits_o = 5'b00000;
      {6'd13, 3'd3}: bits_o = 5'b11111;
      {6'd13, 3'd4}: bits_o = 5'b00000;
      {6'd13, 3'd5}: bits_o = 5'b00000;
      {6'd13, 3'd6}: bits_o = 5'b00000;
      // '0', codigo 16
      {6'd16, 3'd0}: bits_o = 5'b01110;
      {6'd16, 3'd1}: bits_o = 5'b10001;
      {6'd16, 3'd2}: bits_o = 5'b10011;
      {6'd16, 3'd3}: bits_o = 5'b10101;
      {6'd16, 3'd4}: bits_o = 5'b11001;
      {6'd16, 3'd5}: bits_o = 5'b10001;
      {6'd16, 3'd6}: bits_o = 5'b01110;
      // '1', codigo 17
      {6'd17, 3'd0}: bits_o = 5'b00100;
      {6'd17, 3'd1}: bits_o = 5'b01100;
      {6'd17, 3'd2}: bits_o = 5'b00100;
      {6'd17, 3'd3}: bits_o = 5'b00100;
      {6'd17, 3'd4}: bits_o = 5'b00100;
      {6'd17, 3'd5}: bits_o = 5'b00100;
      {6'd17, 3'd6}: bits_o = 5'b01110;
      // '2', codigo 18
      {6'd18, 3'd0}: bits_o = 5'b01110;
      {6'd18, 3'd1}: bits_o = 5'b10001;
      {6'd18, 3'd2}: bits_o = 5'b00001;
      {6'd18, 3'd3}: bits_o = 5'b00010;
      {6'd18, 3'd4}: bits_o = 5'b00100;
      {6'd18, 3'd5}: bits_o = 5'b01000;
      {6'd18, 3'd6}: bits_o = 5'b11111;
      // '3', codigo 19
      {6'd19, 3'd0}: bits_o = 5'b11111;
      {6'd19, 3'd1}: bits_o = 5'b00010;
      {6'd19, 3'd2}: bits_o = 5'b00100;
      {6'd19, 3'd3}: bits_o = 5'b00010;
      {6'd19, 3'd4}: bits_o = 5'b00001;
      {6'd19, 3'd5}: bits_o = 5'b10001;
      {6'd19, 3'd6}: bits_o = 5'b01110;
      // '4', codigo 20
      {6'd20, 3'd0}: bits_o = 5'b00010;
      {6'd20, 3'd1}: bits_o = 5'b00110;
      {6'd20, 3'd2}: bits_o = 5'b01010;
      {6'd20, 3'd3}: bits_o = 5'b10010;
      {6'd20, 3'd4}: bits_o = 5'b11111;
      {6'd20, 3'd5}: bits_o = 5'b00010;
      {6'd20, 3'd6}: bits_o = 5'b00010;
      // '5', codigo 21
      {6'd21, 3'd0}: bits_o = 5'b11111;
      {6'd21, 3'd1}: bits_o = 5'b10000;
      {6'd21, 3'd2}: bits_o = 5'b11110;
      {6'd21, 3'd3}: bits_o = 5'b00001;
      {6'd21, 3'd4}: bits_o = 5'b00001;
      {6'd21, 3'd5}: bits_o = 5'b10001;
      {6'd21, 3'd6}: bits_o = 5'b01110;
      // '6', codigo 22
      {6'd22, 3'd0}: bits_o = 5'b00110;
      {6'd22, 3'd1}: bits_o = 5'b01000;
      {6'd22, 3'd2}: bits_o = 5'b10000;
      {6'd22, 3'd3}: bits_o = 5'b11110;
      {6'd22, 3'd4}: bits_o = 5'b10001;
      {6'd22, 3'd5}: bits_o = 5'b10001;
      {6'd22, 3'd6}: bits_o = 5'b01110;
      // '7', codigo 23
      {6'd23, 3'd0}: bits_o = 5'b11111;
      {6'd23, 3'd1}: bits_o = 5'b00001;
      {6'd23, 3'd2}: bits_o = 5'b00010;
      {6'd23, 3'd3}: bits_o = 5'b00100;
      {6'd23, 3'd4}: bits_o = 5'b01000;
      {6'd23, 3'd5}: bits_o = 5'b01000;
      {6'd23, 3'd6}: bits_o = 5'b01000;
      // '8', codigo 24
      {6'd24, 3'd0}: bits_o = 5'b01110;
      {6'd24, 3'd1}: bits_o = 5'b10001;
      {6'd24, 3'd2}: bits_o = 5'b10001;
      {6'd24, 3'd3}: bits_o = 5'b01110;
      {6'd24, 3'd4}: bits_o = 5'b10001;
      {6'd24, 3'd5}: bits_o = 5'b10001;
      {6'd24, 3'd6}: bits_o = 5'b01110;
      // '9', codigo 25
      {6'd25, 3'd0}: bits_o = 5'b01110;
      {6'd25, 3'd1}: bits_o = 5'b10001;
      {6'd25, 3'd2}: bits_o = 5'b10001;
      {6'd25, 3'd3}: bits_o = 5'b01111;
      {6'd25, 3'd4}: bits_o = 5'b00001;
      {6'd25, 3'd5}: bits_o = 5'b00010;
      {6'd25, 3'd6}: bits_o = 5'b01100;
      // ':', codigo 26
      {6'd26, 3'd0}: bits_o = 5'b00000;
      {6'd26, 3'd1}: bits_o = 5'b01100;
      {6'd26, 3'd2}: bits_o = 5'b01100;
      {6'd26, 3'd3}: bits_o = 5'b00000;
      {6'd26, 3'd4}: bits_o = 5'b01100;
      {6'd26, 3'd5}: bits_o = 5'b01100;
      {6'd26, 3'd6}: bits_o = 5'b00000;
      // 'A', codigo 33
      {6'd33, 3'd0}: bits_o = 5'b01110;
      {6'd33, 3'd1}: bits_o = 5'b10001;
      {6'd33, 3'd2}: bits_o = 5'b10001;
      {6'd33, 3'd3}: bits_o = 5'b10001;
      {6'd33, 3'd4}: bits_o = 5'b11111;
      {6'd33, 3'd5}: bits_o = 5'b10001;
      {6'd33, 3'd6}: bits_o = 5'b10001;
      // 'B', codigo 34
      {6'd34, 3'd0}: bits_o = 5'b11110;
      {6'd34, 3'd1}: bits_o = 5'b10001;
      {6'd34, 3'd2}: bits_o = 5'b10001;
      {6'd34, 3'd3}: bits_o = 5'b11110;
      {6'd34, 3'd4}: bits_o = 5'b10001;
      {6'd34, 3'd5}: bits_o = 5'b10001;
      {6'd34, 3'd6}: bits_o = 5'b11110;
      // 'C', codigo 35
      {6'd35, 3'd0}: bits_o = 5'b01110;
      {6'd35, 3'd1}: bits_o = 5'b10001;
      {6'd35, 3'd2}: bits_o = 5'b10000;
      {6'd35, 3'd3}: bits_o = 5'b10000;
      {6'd35, 3'd4}: bits_o = 5'b10000;
      {6'd35, 3'd5}: bits_o = 5'b10001;
      {6'd35, 3'd6}: bits_o = 5'b01110;
      // 'D', codigo 36
      {6'd36, 3'd0}: bits_o = 5'b11100;
      {6'd36, 3'd1}: bits_o = 5'b10010;
      {6'd36, 3'd2}: bits_o = 5'b10001;
      {6'd36, 3'd3}: bits_o = 5'b10001;
      {6'd36, 3'd4}: bits_o = 5'b10001;
      {6'd36, 3'd5}: bits_o = 5'b10010;
      {6'd36, 3'd6}: bits_o = 5'b11100;
      // 'E', codigo 37
      {6'd37, 3'd0}: bits_o = 5'b11111;
      {6'd37, 3'd1}: bits_o = 5'b10000;
      {6'd37, 3'd2}: bits_o = 5'b10000;
      {6'd37, 3'd3}: bits_o = 5'b11110;
      {6'd37, 3'd4}: bits_o = 5'b10000;
      {6'd37, 3'd5}: bits_o = 5'b10000;
      {6'd37, 3'd6}: bits_o = 5'b11111;
      // 'F', codigo 38
      {6'd38, 3'd0}: bits_o = 5'b11111;
      {6'd38, 3'd1}: bits_o = 5'b10000;
      {6'd38, 3'd2}: bits_o = 5'b10000;
      {6'd38, 3'd3}: bits_o = 5'b11110;
      {6'd38, 3'd4}: bits_o = 5'b10000;
      {6'd38, 3'd5}: bits_o = 5'b10000;
      {6'd38, 3'd6}: bits_o = 5'b10000;
      // 'G', codigo 39
      {6'd39, 3'd0}: bits_o = 5'b01110;
      {6'd39, 3'd1}: bits_o = 5'b10001;
      {6'd39, 3'd2}: bits_o = 5'b10000;
      {6'd39, 3'd3}: bits_o = 5'b10111;
      {6'd39, 3'd4}: bits_o = 5'b10001;
      {6'd39, 3'd5}: bits_o = 5'b10001;
      {6'd39, 3'd6}: bits_o = 5'b01111;
      // 'H', codigo 40
      {6'd40, 3'd0}: bits_o = 5'b10001;
      {6'd40, 3'd1}: bits_o = 5'b10001;
      {6'd40, 3'd2}: bits_o = 5'b10001;
      {6'd40, 3'd3}: bits_o = 5'b11111;
      {6'd40, 3'd4}: bits_o = 5'b10001;
      {6'd40, 3'd5}: bits_o = 5'b10001;
      {6'd40, 3'd6}: bits_o = 5'b10001;
      // 'I', codigo 41
      {6'd41, 3'd0}: bits_o = 5'b01110;
      {6'd41, 3'd1}: bits_o = 5'b00100;
      {6'd41, 3'd2}: bits_o = 5'b00100;
      {6'd41, 3'd3}: bits_o = 5'b00100;
      {6'd41, 3'd4}: bits_o = 5'b00100;
      {6'd41, 3'd5}: bits_o = 5'b00100;
      {6'd41, 3'd6}: bits_o = 5'b01110;
      // 'J', codigo 42
      {6'd42, 3'd0}: bits_o = 5'b00111;
      {6'd42, 3'd1}: bits_o = 5'b00010;
      {6'd42, 3'd2}: bits_o = 5'b00010;
      {6'd42, 3'd3}: bits_o = 5'b00010;
      {6'd42, 3'd4}: bits_o = 5'b00010;
      {6'd42, 3'd5}: bits_o = 5'b10010;
      {6'd42, 3'd6}: bits_o = 5'b01100;
      // 'K', codigo 43
      {6'd43, 3'd0}: bits_o = 5'b10001;
      {6'd43, 3'd1}: bits_o = 5'b10010;
      {6'd43, 3'd2}: bits_o = 5'b10100;
      {6'd43, 3'd3}: bits_o = 5'b11000;
      {6'd43, 3'd4}: bits_o = 5'b10100;
      {6'd43, 3'd5}: bits_o = 5'b10010;
      {6'd43, 3'd6}: bits_o = 5'b10001;
      // 'L', codigo 44
      {6'd44, 3'd0}: bits_o = 5'b10000;
      {6'd44, 3'd1}: bits_o = 5'b10000;
      {6'd44, 3'd2}: bits_o = 5'b10000;
      {6'd44, 3'd3}: bits_o = 5'b10000;
      {6'd44, 3'd4}: bits_o = 5'b10000;
      {6'd44, 3'd5}: bits_o = 5'b10000;
      {6'd44, 3'd6}: bits_o = 5'b11111;
      // 'M', codigo 45
      {6'd45, 3'd0}: bits_o = 5'b10001;
      {6'd45, 3'd1}: bits_o = 5'b11011;
      {6'd45, 3'd2}: bits_o = 5'b10101;
      {6'd45, 3'd3}: bits_o = 5'b10101;
      {6'd45, 3'd4}: bits_o = 5'b10001;
      {6'd45, 3'd5}: bits_o = 5'b10001;
      {6'd45, 3'd6}: bits_o = 5'b10001;
      // 'N', codigo 46
      {6'd46, 3'd0}: bits_o = 5'b10001;
      {6'd46, 3'd1}: bits_o = 5'b10001;
      {6'd46, 3'd2}: bits_o = 5'b11001;
      {6'd46, 3'd3}: bits_o = 5'b10101;
      {6'd46, 3'd4}: bits_o = 5'b10011;
      {6'd46, 3'd5}: bits_o = 5'b10001;
      {6'd46, 3'd6}: bits_o = 5'b10001;
      // 'O', codigo 47
      {6'd47, 3'd0}: bits_o = 5'b01110;
      {6'd47, 3'd1}: bits_o = 5'b10001;
      {6'd47, 3'd2}: bits_o = 5'b10001;
      {6'd47, 3'd3}: bits_o = 5'b10001;
      {6'd47, 3'd4}: bits_o = 5'b10001;
      {6'd47, 3'd5}: bits_o = 5'b10001;
      {6'd47, 3'd6}: bits_o = 5'b01110;
      // 'P', codigo 48
      {6'd48, 3'd0}: bits_o = 5'b11110;
      {6'd48, 3'd1}: bits_o = 5'b10001;
      {6'd48, 3'd2}: bits_o = 5'b10001;
      {6'd48, 3'd3}: bits_o = 5'b11110;
      {6'd48, 3'd4}: bits_o = 5'b10000;
      {6'd48, 3'd5}: bits_o = 5'b10000;
      {6'd48, 3'd6}: bits_o = 5'b10000;
      // 'Q', codigo 49
      {6'd49, 3'd0}: bits_o = 5'b01110;
      {6'd49, 3'd1}: bits_o = 5'b10001;
      {6'd49, 3'd2}: bits_o = 5'b10001;
      {6'd49, 3'd3}: bits_o = 5'b10001;
      {6'd49, 3'd4}: bits_o = 5'b10101;
      {6'd49, 3'd5}: bits_o = 5'b10010;
      {6'd49, 3'd6}: bits_o = 5'b01101;
      // 'R', codigo 50
      {6'd50, 3'd0}: bits_o = 5'b11110;
      {6'd50, 3'd1}: bits_o = 5'b10001;
      {6'd50, 3'd2}: bits_o = 5'b10001;
      {6'd50, 3'd3}: bits_o = 5'b11110;
      {6'd50, 3'd4}: bits_o = 5'b10100;
      {6'd50, 3'd5}: bits_o = 5'b10010;
      {6'd50, 3'd6}: bits_o = 5'b10001;
      // 'S', codigo 51
      {6'd51, 3'd0}: bits_o = 5'b01111;
      {6'd51, 3'd1}: bits_o = 5'b10000;
      {6'd51, 3'd2}: bits_o = 5'b10000;
      {6'd51, 3'd3}: bits_o = 5'b01110;
      {6'd51, 3'd4}: bits_o = 5'b00001;
      {6'd51, 3'd5}: bits_o = 5'b00001;
      {6'd51, 3'd6}: bits_o = 5'b11110;
      // 'T', codigo 52
      {6'd52, 3'd0}: bits_o = 5'b11111;
      {6'd52, 3'd1}: bits_o = 5'b00100;
      {6'd52, 3'd2}: bits_o = 5'b00100;
      {6'd52, 3'd3}: bits_o = 5'b00100;
      {6'd52, 3'd4}: bits_o = 5'b00100;
      {6'd52, 3'd5}: bits_o = 5'b00100;
      {6'd52, 3'd6}: bits_o = 5'b00100;
      // 'U', codigo 53
      {6'd53, 3'd0}: bits_o = 5'b10001;
      {6'd53, 3'd1}: bits_o = 5'b10001;
      {6'd53, 3'd2}: bits_o = 5'b10001;
      {6'd53, 3'd3}: bits_o = 5'b10001;
      {6'd53, 3'd4}: bits_o = 5'b10001;
      {6'd53, 3'd5}: bits_o = 5'b10001;
      {6'd53, 3'd6}: bits_o = 5'b01110;
      // 'V', codigo 54
      {6'd54, 3'd0}: bits_o = 5'b10001;
      {6'd54, 3'd1}: bits_o = 5'b10001;
      {6'd54, 3'd2}: bits_o = 5'b10001;
      {6'd54, 3'd3}: bits_o = 5'b10001;
      {6'd54, 3'd4}: bits_o = 5'b10001;
      {6'd54, 3'd5}: bits_o = 5'b01010;
      {6'd54, 3'd6}: bits_o = 5'b00100;
      // 'W', codigo 55
      {6'd55, 3'd0}: bits_o = 5'b10001;
      {6'd55, 3'd1}: bits_o = 5'b10001;
      {6'd55, 3'd2}: bits_o = 5'b10001;
      {6'd55, 3'd3}: bits_o = 5'b10101;
      {6'd55, 3'd4}: bits_o = 5'b10101;
      {6'd55, 3'd5}: bits_o = 5'b10101;
      {6'd55, 3'd6}: bits_o = 5'b01010;
      // 'X', codigo 56
      {6'd56, 3'd0}: bits_o = 5'b10001;
      {6'd56, 3'd1}: bits_o = 5'b10001;
      {6'd56, 3'd2}: bits_o = 5'b01010;
      {6'd56, 3'd3}: bits_o = 5'b00100;
      {6'd56, 3'd4}: bits_o = 5'b01010;
      {6'd56, 3'd5}: bits_o = 5'b10001;
      {6'd56, 3'd6}: bits_o = 5'b10001;
      // 'Y', codigo 57
      {6'd57, 3'd0}: bits_o = 5'b10001;
      {6'd57, 3'd1}: bits_o = 5'b10001;
      {6'd57, 3'd2}: bits_o = 5'b10001;
      {6'd57, 3'd3}: bits_o = 5'b01010;
      {6'd57, 3'd4}: bits_o = 5'b00100;
      {6'd57, 3'd5}: bits_o = 5'b00100;
      {6'd57, 3'd6}: bits_o = 5'b00100;
      // 'Z', codigo 58
      {6'd58, 3'd0}: bits_o = 5'b11111;
      {6'd58, 3'd1}: bits_o = 5'b00001;
      {6'd58, 3'd2}: bits_o = 5'b00010;
      {6'd58, 3'd3}: bits_o = 5'b00100;
      {6'd58, 3'd4}: bits_o = 5'b01000;
      {6'd58, 3'd5}: bits_o = 5'b10000;
      {6'd58, 3'd6}: bits_o = 5'b11111;
      default: bits_o = 5'b00000;
    endcase
  end

endmodule
