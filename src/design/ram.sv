module ram (
  input  logic        clk_i,
  input  logic        write_enable_i, // ram_we del Address Translator
  input  logic [31:0] addr_i,         // DataAddress_o, direccion en bytes
  input  logic [31:0] wdata_i,        // DataOut_o
  output logic [31:0] rdata_o         // ram_dout, hacia MUX_LECTURA
  );

  localparam PALABRAS = 1024; // 4 KB, 0x0000_2000 a 0x0000_2FFF

  logic [31:0] mem [0:PALABRAS-1];

  // Sin reset ni contenido inicial: el programa limpia lo que usa.
  // addr_i[1:0] siempre es 00 y addr_i[31:12] ya lo reviso el AT
  always_ff @(posedge clk_i)
    if (write_enable_i) mem[addr_i[11:2]] <= wdata_i;

  // Lectura asincrona: el dato sale en el mismo ciclo, para que el lw termine en uno
  assign rdata_o = mem[addr_i[11:2]];

endmodule
