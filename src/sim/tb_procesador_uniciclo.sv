`timescale 1ns / 1ps

// Testbench autoverificable de procesador_uniciclo.sv, ver docs/diseño/modulos/PROCESADOR_UNICICLO.md
// inciso h). Corre las pruebas oficiales rv32ui de src/sim/riscv-tests/ con la ROM y la RAM del
// proyecto. Cada prueba termina escribiendo en 0xFFFF_FFF0: 1 si pasó, 0 si falló, y el número del
// caso que falló queda en x28.

module tb_procesador_uniciclo;

  localparam logic [31:0] DIR_RESULTADO = 32'hFFFF_FFF0;
  localparam int MAX_CICLOS = 20000;
  localparam string CARPETA = "../sim/riscv-tests/"; // make sim corre desde src/build

  logic        clk = 0;
  logic        rst = 1;
  logic [31:0] prog_address, prog_in;
  logic [31:0] data_address, data_out, data_in;
  logic        we;

  always #10 clk = ~clk; // 50 MHz

  procesador_uniciclo dut (
    .clk_i        (clk),
    .rst_i        (rst),
    .ProgAddress_o(prog_address),
    .ProgIn_i     (prog_in),
    .DataAddress_o(data_address),
    .DataOut_o    (data_out),
    .DataIn_i     (data_in),
    .we_o         (we)
  );

  rom #(.ARCHIVO_HEX({CARPETA, "simple.text.hex"})) u_rom (
    .addr_i (prog_address),
    .instr_o(prog_in)
  );

  // Hace de Address Translator: la RAM solo escribe en su ventana, 0x0000_2000 a 0x0000_2FFF.
  // La escritura del resultado en 0xFFFF_FFF0 no llega a ningún lado
  ram u_ram (
    .clk_i         (clk),
    .write_enable_i(we && data_address[31:12] == 20'h00002),
    .addr_i        (data_address),
    .wdata_i       (data_out),
    .rdata_o       (data_in)
  );

  string pruebas[] = '{"lw", "sw", "lui", "add", "addi", "and", "andi", "or", "ori", "xor", "xori",
                       "sub", "sll", "slli", "srl", "srli", "sra", "srai", "slt", "slti", "sltu",
                       "sltiu", "beq", "bne", "blt", "bge", "jal", "jalr", "simple"};

  int fallidas = 0;
  int i, ciclo, f, c;
  logic terminada;

  // true si el archivo existe y tiene al menos un carácter. Las pruebas sin datos no tienen .data.hex
  function automatic bit tiene_contenido(input string archivo);
    int fd, ch;
    fd = $fopen(archivo, "r");
    if (fd == 0) return 0;
    ch = $fgetc(fd);
    $fclose(fd);
    return ch != -1;
  endfunction

  task automatic correr(input string nombre);
    // Memorias limpias, para que no quede nada de la prueba anterior
    for (c = 0; c < 2048; c++) u_rom.mem[c] = 'x;
    for (c = 0; c < 1024; c++) u_ram.mem[c] = 'x;
    $readmemh({CARPETA, nombre, ".text.hex"}, u_rom.mem);
    if (tiene_contenido({CARPETA, nombre, ".data.hex"}))
      $readmemh({CARPETA, nombre, ".data.hex"}, u_ram.mem);

    // Reset: dos flancos con rst en alto, y el PC tiene que quedar en el vector de reset
    rst = 1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    if (prog_address !== 32'h0000_0000) begin
      fallidas++;
      $display("FALLA %-6s: despues de rst_i el PC vale 0x%08h, esperado 0x00000000", nombre, prog_address);
      terminada = 1; // no se corre la prueba
    end
    else
      terminada = 0;
    rst = 0;

    // Correr hasta la escritura del resultado. Se mira en el flanco de bajada, con el bus estable
    for (ciclo = 0; ciclo < MAX_CICLOS && !terminada; ciclo++) begin
      @(negedge clk);
      if (we && data_address == DIR_RESULTADO) begin
        terminada = 1;
        if (data_out === 32'd1)
          $display("PASS %-6s (%0d ciclos)", nombre, ciclo);
        else begin
          fallidas++;
          $display("FALLA %-6s: fallo el caso %0d (x28)", nombre,
                   dut.nucleo.singlecycle_datapath.regfile.register[28]);
        end
      end
    end
    if (!terminada && ciclo == MAX_CICLOS) begin
      fallidas++;
      $display("FALLA %-6s: no termino en %0d ciclos, PC = 0x%08h", nombre, MAX_CICLOS, prog_address);
    end
  endtask

  initial begin
    foreach (pruebas[i]) correr(pruebas[i]);

    if (fallidas == 0)
      $display("PASS tb_procesador_uniciclo: %0d pruebas rv32ui", pruebas.size());
    else
      $display("FAIL tb_procesador_uniciclo: %0d de %0d pruebas fallaron", fallidas, pruebas.size());
    $finish;
  end

endmodule
