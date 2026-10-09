`timescale 1ns/1ps

// Prueba corta del sistema completo para la simulacion post-implementacion temporizada (make sim-post):
// el arranque del programa, la colocacion de las dos flotas y un disparo de cada jugador. Con
// make sim corre igual sobre el RTL, que sirve de referencia.
//
// La UART va a 694444 baudios y no a 115200, en el RTL y en el netlist (vivado_timesim.tcl lo
// implementa con BAUDIOS=694444). xsim avanza menos de 1 us de simulacion por segundo con los
// retardos, y a 115200 la partida no cabe en una corrida razonable. El resto del diseno es el de
// la tarjeta.
//
// Despues de implementar, Vivado deja el diseno en primitivas y la jerarquia interna cambia: no hay
// dut.u_ram.mem ni la memoria de video que revisa tb_top. Por eso esta prueba mira solo los pines
// y unos pocos cables de top que conservan el nombre en el netlist (rst, clk_sys, prog_address,
// prog_in, buzzer_dout, display_dout).
//
// Con POST_IMPL definido instancia el netlist de src/build/timesim/top_timesim.v, que no tiene
// parametros, y corre desde esa carpeta.
module tb_top_temporizado;

  // Con 33,33 MHz y 694444 baudios, TICKS_BIT = 48 ciclos de 30 ns. La cuenta es la de periferico_uart
  localparam int BAUDIOS = 694_444;
  localparam int TICKS_BIT = (33_333_333 + BAUDIOS / 2) / BAUDIOS;
  localparam int BIT_NS = TICKS_BIT * 30;

`ifdef POST_IMPL
  localparam string ARCHIVO_HEX = "../../../sw/programa.hex";
`else
  localparam string ARCHIVO_HEX = "../../sw/programa.hex";
`endif

  localparam logic [2:0] SND_IMPACTO = 3'd1;
  localparam logic [2:0] SND_FALLO = 3'd2;

  // Bits de botones en el mismo orden que el registro de estado del periferico de entradas
  localparam int BTN_ABAJO = 1;
  localparam int BTN_OK = 5;

  logic clk_tb = 1'b0;
  logic [6:0] botones = '0;
  logic rx_tb = 1'b1;
  logic tx_tb;
  logic [3:0] vga_r, vga_g, vga_b;
  logic vga_hsync, vga_vsync;
  logic [6:0] seg;
  logic [3:0] an;
  logic dp;
  logic [2:0] led;
  logic buzzer;

  int pruebas = 0;
  int errores = 0;

`ifdef POST_IMPL
  top dut (
`else
  top #(.ARCHIVO_HEX(ARCHIVO_HEX), .BAUDIOS(BAUDIOS)) dut (
`endif
    .clk         (clk_tb),
    .btn_arriba  (botones[0]),
    .btn_abajo   (botones[1]),
    .btn_izq     (botones[2]),
    .btn_der     (botones[3]),
    .btn_sel     (botones[4]),
    .btn_ok      (botones[5]),
    .btn_rst     (botones[6]),
    .rx_i        (rx_tb),
    .tx_o        (tx_tb),
    .vga_r_o     (vga_r),
    .vga_g_o     (vga_g),
    .vga_b_o     (vga_b),
    .vga_hsync_o (vga_hsync),
    .vga_vsync_o (vga_vsync),
    .seg         (seg),
    .an          (an),
    .dp          (dp),
    .led         (led),
    .buzzer      (buzzer)
  );

  always #5 clk_tb = ~clk_tb; // 100 MHz, como el oscilador de la Basys 3

  // ---------------------------------------------------------------- lado de la PC

  // Igual que en tb_top: receptor de la PC que guarda cada byte que sale por tx_o
  logic [7:0] bytes_pc [0:511];
  int recibidos = 0;

  initial begin
    logic [7:0] dato;
    forever begin
      @(negedge tx_tb);
      #(BIT_NS / 2);
      if (tx_tb === 1'b0) begin
        for (int i = 0; i < 8; i++) begin
          #(BIT_NS);
          dato[i] = tx_tb;
        end
        #(BIT_NS);
        if (recibidos < 512) bytes_pc[recibidos] = dato;
        recibidos++;
      end
    end
  end

  task automatic enviar_byte(input logic [7:0] dato);
    rx_tb = 1'b0;
    #(BIT_NS);
    for (int i = 0; i < 8; i++) begin
      rx_tb = dato[i];
      #(BIT_NS);
    end
    rx_tb = 1'b1;
    #(BIT_NS);
  endtask

  task automatic enviar_trama(input logic [7:0] tipo, input logic [7:0] d1, input logic [7:0] d2);
    logic [7:0] trama [0:4];
    trama[0] = 8'hAA;
    trama[1] = tipo;
    trama[2] = d1;
    trama[3] = d2;
    trama[4] = tipo ^ d1 ^ d2;
    for (int i = 0; i < 5; i++) begin
      enviar_byte(trama[i]);
      #5_000;
    end
  endtask

  task automatic chequear_trama(input string nombre, input int desde,
                                input logic [7:0] tipo, input logic [7:0] d1, input logic [7:0] d2);
    logic [39:0] esperada;
    logic [39:0] vista;
    int espera_us;
    espera_us = 0;
    while (recibidos < desde + 5 && espera_us < 3000) begin
      #1000;
      espera_us++;
    end
    esperada = {8'hAA, tipo, d1, d2, tipo ^ d1 ^ d2};
    vista = (recibidos >= desde + 5) ?
            {bytes_pc[desde], bytes_pc[desde+1], bytes_pc[desde+2], bytes_pc[desde+3], bytes_pc[desde+4]} : 'x;
    anotar(nombre, vista === esperada,
           $sformatf("esperaba %010h y llego %010h (%0d bytes en total)", esperada, vista, recibidos));
  endtask

  // ---------------------------------------------------------------- lado del Jugador 1

  // 150 us presionado y 150 us suelto, la mitad que en tb_top. Alcanza porque la vuelta mas larga del
  // lazo, un repintado del tablero, tarda unos 100 us
  task automatic presionar(input int boton);
    botones[boton] = 1'b1;
    #150_000;
    botones[boton] = 1'b0;
    #150_000;
  endtask

  // ---------------------------------------------------------------- utilidades

  task automatic anotar(input string nombre, input bit ok, input string detalle);
    pruebas++;
    if (ok) begin
      $display("ok %s", nombre);
    end
    else begin
      errores++;
      $display("fallo %s", nombre);
      $display("  %s", detalle);
    end
  endtask

  // ---------------------------------------------------------------- ejecucion del programa

  // Copia del programa para comparar lo que sale de la ROM del netlist
  logic [31:0] rom_ref [0:2047];
  initial $readmemh(ARCHIVO_HEX, rom_ref);

  // En cada flanco de clk_sys, antes de que los registros cambien, la instruccion en ProgIn tiene que
  // ser la del programa en la direccion del PC, y el PC siguiente tiene que salir de esa instruccion:
  // PC + 4, el destino de un jal, o una de las dos salidas de un branch. jalr no se revisa porque el
  // destino depende de un registro. Con los retardos del netlist esto confirma que la ROM y la logica
  // del PC se estabilizan dentro del ciclo.
  int instrucciones = 0;
  int errores_pc = 0;
  logic [12:0] pc_ant;
  logic [31:0] instr_ant;
  logic hay_ant = 1'b0;

  function automatic string revisar_salto(input logic [12:0] pc, input logic [31:0] i, input logic [12:0] pc_sig);
    logic [12:0] imm_j, imm_b;
    imm_j = {i[12], i[20], i[30:21], 1'b0};
    imm_b = {i[31], i[7], i[30:25], i[11:8], 1'b0};
    case (i[6:0])
      7'b1101111: return (pc_sig === 13'(pc + imm_j)) ? "" : $sformatf("jal a %04h", 13'(pc + imm_j));
      7'b1100011: return (pc_sig === 13'(pc + 4) || pc_sig === 13'(pc + imm_b)) ? "" :
                         $sformatf("branch a %04h o %04h", 13'(pc + 4), 13'(pc + imm_b));
      7'b1100111: return "";
      default:    return (pc_sig === 13'(pc + 4)) ? "" : $sformatf("%04h", 13'(pc + 4));
    endcase
  endfunction

  always @(posedge dut.clk_sys) begin
    if (dut.rst === 1'b0) begin
      logic [12:0] pc;
      logic [31:0] instr;
      string esperado;
      pc = {dut.prog_address[12:2], 2'b00};
      // Todas las instrucciones rv32i terminan en 11, asi que Vivado deja esos dos bits como constante
      // dentro de la ROM y prog_in[1:0] queda sin driver (Z) en el netlist. Se comparan los demas
      instr = {dut.prog_in[31:2], 2'b11};

      if (instr !== rom_ref[pc[12:2]]) begin
        errores_pc++;
        if (errores_pc <= 5)
          $display("  en %0d ns la ROM dio %08h en PC %04h y el programa tiene %08h",
                   $time, instr, pc, rom_ref[pc[12:2]]);
      end
      if (hay_ant) begin
        esperado = revisar_salto(pc_ant, instr_ant, pc);
        if (esperado != "") begin
          errores_pc++;
          if (errores_pc <= 5)
            $display("  en %0d ns el PC paso de %04h (%08h) a %04h, se esperaba %s",
                     $time, pc_ant, instr_ant, pc, esperado);
        end
      end
      if (instrucciones < 12)
        $display("  instruccion %2d: PC %04h  %08h", instrucciones, pc, instr);

      pc_ant = pc;
      instr_ant = instr;
      hay_ant = 1'b1;
      instrucciones++;
    end
  end

  // ---------------------------------------------------------------- prueba

  initial begin
    int marca;
    int antes;

    // Solo el arranque y el disparo del Jugador 1 van a la onda, el archivo queda manejable
    $dumpfile("tb_top_temporizado.vcd");
    $dumpvars(1, tb_top_temporizado);
    $dumpvars(0, dut.clk_sys, dut.rst, dut.prog_address, dut.prog_in, dut.buzzer_dout);

    #100;
    anotar("el sistema arranca en reinicio mientras el PLL no engancha", dut.rst === 1'b1,
           $sformatf("rst dio %0b", dut.rst));
    wait (dut.rst === 1'b0);
    $display("  el reinicio baja en %0d ns", $time);
    #1;
    anotar("la primera instruccion despues del reinicio es la de la direccion 0",
           dut.prog_address[12:2] === 11'd0 && dut.prog_in[31:2] === rom_ref[0][31:2],
           $sformatf("PC %04h e instruccion %08h", {dut.prog_address[12:2], 2'b00}, dut.prog_in));

    // Arranque: el programa limpia todo, avisa a la PC y queda en colocacion
    chequear_trama("la primera trama es Estado, fase de colocacion", 0, 8'h20, 8'h00, 8'h00);
    anotar("el LED marca la fase de colocacion", led === 3'b001, $sformatf("led dio %03b", led));
    anotar("el display muestra 00 00 de partidas ganadas",
           seg === 7'b1000000 && (an === 4'b1110 || an === 4'b1101 || an === 4'b1011 || an === 4'b0111),
           $sformatf("seg dio %07b y an %04b", seg, an));
    $dumpoff;

    // ------------------------------------------------ colocacion
    // Jugador 1 con los botones: barcos 0, 1 y 2 horizontales en las filas 0, 1 y 2 desde la columna 0
    presionar(BTN_OK);
    presionar(BTN_ABAJO);
    presionar(BTN_OK);
    presionar(BTN_ABAJO);
    presionar(BTN_OK);

    // Jugador 2 por la UART, en las filas 0, 2 y 4. Con el ultimo arranca la batalla
    marca = recibidos;
    enviar_trama(8'h10, 8'h00, 8'h00);
    chequear_trama("el barco 0 del Jugador 2 se acepta", marca, 8'h21, 8'h00, 8'h00);
    marca = recibidos;
    enviar_trama(8'h10, 8'h01, 8'h20);
    chequear_trama("el barco 1 del Jugador 2 se acepta", marca, 8'h21, 8'h01, 8'h00);
    marca = recibidos;
    enviar_trama(8'h10, 8'h02, 8'h40);
    chequear_trama("el barco 2 del Jugador 2 se acepta", marca, 8'h21, 8'h02, 8'h00);
    chequear_trama("arranca la batalla", marca + 5, 8'h20, 8'h01, 8'h00);
    chequear_trama("con el turno del Jugador 1", marca + 10, 8'h20, 8'h02, 8'h00);
    anotar("el LED pasa a batalla", led === 3'b010, $sformatf("led dio %03b", led));

    // ------------------------------------------------ disparos
    // Jugador 1: el cursor arranca en (0,0) del tablero del Jugador 2, donde esta su barco 0
    $dumpon;
    marca = recibidos;
    presionar(BTN_OK);
    chequear_trama("el disparo del Jugador 1 en (0,0) es impacto", marca, 8'h23, 8'h00, 8'h00);
    anotar("y suena el sonido de impacto", dut.buzzer_dout[2:0] === SND_IMPACTO,
           $sformatf("el registro del buzzer dio %0d", dut.buzzer_dout[2:0]));
    chequear_trama("y pasa el turno al Jugador 2", marca + 5, 8'h20, 8'h02, 8'h01);
    $dumpoff;

    // Jugador 2 por la UART en (5,5), donde el Jugador 1 no tiene barcos
    marca = recibidos;
    enviar_trama(8'h11, 8'h55, 8'h00);
    chequear_trama("el disparo del Jugador 2 en (5,5) es fallo", marca, 8'h22, 8'h55, 8'h01);
    anotar("y suena el sonido de fallo", dut.buzzer_dout[2:0] === SND_FALLO,
           $sformatf("el registro del buzzer dio %0d", dut.buzzer_dout[2:0]));
    chequear_trama("y vuelve el turno al Jugador 1", marca + 5, 8'h20, 8'h02, 8'h00);
    anotar("el LED sigue en batalla", led === 3'b010, $sformatf("led dio %03b", led));

    anotar($sformatf("las %0d instrucciones ejecutadas salen de la ROM y siguen el flujo del programa",
                     instrucciones),
           errores_pc == 0 && instrucciones > 0, $sformatf("%0d errores de PC o de instruccion", errores_pc));

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_top_temporizado termino con fallos");
    $finish;
  end

  // Por si el programa se queda trabado y nunca llega una trama
  initial begin
    #10_000_000;
    $fatal(1, "tb_top_temporizado no termino en 10 ms");
  end

endmodule
