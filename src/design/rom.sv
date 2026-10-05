module rom #(
  parameter ARCHIVO_HEX = "sw/programa.hex" // relativo a la raiz del repo, desde donde corre yosys
  ) (
  input  logic [31:0] addr_i,  // ProgAddress_o, direccion en bytes (el PC)
  output logic [31:0] instr_o  // ProgIn_i
  );

  localparam PALABRAS = 2048; // 8 KB, 0x0000_0000 a 0x0000_1FFF

  logic [31:0] mem [0:PALABRAS-1];

  // Las palabras que el archivo no trae quedan sin valor, y en simulacion se leen como X
  initial $readmemh(ARCHIVO_HEX, mem);

  // Lectura asincrona: la instruccion sale en el mismo ciclo que el PC.
  // addr_i[1:0] siempre es 00 y addr_i[31:13] se ignora, fuera de rango la ROM se repite
  assign instr_o = mem[addr_i[12:2]];

endmodule
