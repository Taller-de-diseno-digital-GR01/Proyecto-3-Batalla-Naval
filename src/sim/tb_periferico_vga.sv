`timescale 1ns/1ps

module tb_periferico_vga;

  // Los dos relojes van a su frecuencia real, el barrido no se puede reescalar sin cambiar la temporizacion
  localparam int H_TOTAL = 800;
  localparam int V_TOTAL = 525;
  localparam int H_VISIBLE = 640;
  localparam int V_VISIBLE = 480;
  localparam int PIX_CUADRO = H_TOTAL * V_TOTAL;
  localparam int COLUMNAS = 20;
  localparam int FILAS = 15;
  localparam int CASILLAS = COLUMNAS * FILAS;
  localparam int LATENCIA = 2; // lectura del puerto B + registro de salida

  logic clk_tb;
  logic clk_pix_tb;
  logic rst_tb;
  logic we_tb;
  logic [8:0] addr_tb;
  logic [31:0] wdata_tb;
  logic [31:0] rdata_tb;
  logic hsync_tb;
  logic vsync_tb;
  logic [3:0] r_tb;
  logic [3:0] g_tb;
  logic [3:0] b_tb;

  int pruebas = 0;
  int errores = 0;

  // Lo que deberia haber en cada casilla, el testbench lo lleva aparte para no comparar el DUT contra si mismo
  // [2:0] color y [3] borde, el resto de la palabra el barrido no lo usa
  logic [3:0] modelo [0:CASILLAS-1];

  // Lo que devuelve revisar_cuadro
  int malos_color;
  int malos_sync;
  int bajos_h;
  int bajos_v;
  int n_buscado;
  int h_min, h_max, v_min, v_max;
  string primer_error;

  periferico_vga dut (
    .clk_i(clk_tb),
    .rst_i(rst_tb),
    .write_enable_i(we_tb),
    .addr_i(addr_tb),
    .wdata_i(wdata_tb),
    .rdata_o(rdata_tb),
    .clk_pix_i(clk_pix_tb),
    .vga_hsync_o(hsync_tb),
    .vga_vsync_o(vsync_tb),
    .vga_r_o(r_tb),
    .vga_g_o(g_tb),
    .vga_b_o(b_tb)
  );

  always #5 clk_tb = ~clk_tb; // 100 MHz
  always #20 clk_pix_tb = ~clk_pix_tb; // 25 MHz

  // La paleta escrita de nuevo a mano, si alguien cambia la del DUT esta prueba lo nota
  function automatic logic [11:0] paleta(input logic [2:0] c);
    case (c)
      3'b000: paleta = 12'h04A;
      3'b001: paleta = 12'h888;
      3'b010: paleta = 12'hF00;
      3'b011: paleta = 12'hFFF;
      3'b100: paleta = 12'hFF0;
      3'b101: paleta = 12'h000;
      3'b110: paleta = 12'h0F0;
      3'b111: paleta = 12'hF0F;
      default: paleta = 12'hxxx;
    endcase
  endfunction

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

  // ---------------------------------------------------------------- lado del CPU

  task automatic ciclo();
    @(posedge clk_tb);
    #1;
  endtask

  task automatic escribir(input logic [8:0] a, input logic [31:0] d);
    addr_tb = a;
    wdata_tb = d;
    we_tb = 1'b1;
    ciclo();
    we_tb = 1'b0;
    wdata_tb = 32'b0;
    if (a < CASILLAS) modelo[a] = d[3:0];
  endtask

  task automatic pintar(input int fila, input int col, input logic [2:0] c);
    escribir(fila * COLUMNAS + col, {29'b0, c});
  endtask

  // Sin reloj de por medio, si el dato tarda un ciclo esto lo agarra
  task automatic chequear_lectura(input string nombre, input logic [8:0] a, input logic [31:0] esperado);
    addr_tb = a;
    #1;
    anotar(nombre, rdata_tb === esperado,
           $sformatf("addr %0d esperaba %08h y dio %08h", a, esperado, rdata_tb));
  endtask

  // ---------------------------------------------------------------- lado del monitor

  task automatic ciclo_pix();
    @(posedge clk_pix_tb);
    #1;
  endtask

  // Con rst_pix arriba los contadores se quedan en (0, 0) varios ciclos, ese no es el inicio de un cuadro
  task automatic esperar_inicio_cuadro();
    do ciclo_pix(); while (!(dut.h_count == 0 && dut.v_count == 0 && !dut.rst_pix));
  endtask

  // Recorre un cuadro entero y compara cada pixel contra el modelo. El pixel (h, v) sale LATENCIA ciclos despues
  // de que los contadores pasan por el, asi que la muestra k del cuadro corresponde a la posicion k - LATENCIA
  task automatic revisar_cuadro(input logic [11:0] buscado);
    int h, v;
    bit visible;
    bit contorno;
    logic [3:0] casilla;
    logic [11:0] esperado;
    logic [11:0] visto;
    logic hs_esperado;
    logic vs_esperado;

    malos_color = 0;
    malos_sync = 0;
    bajos_h = 0;
    bajos_v = 0;
    n_buscado = 0;
    h_min = H_TOTAL;
    h_max = -1;
    v_min = V_TOTAL;
    v_max = -1;
    primer_error = "";

    esperar_inicio_cuadro();
    repeat (LATENCIA) ciclo_pix();

    for (int p = 0; p < PIX_CUADRO; p++) begin
      h = p % H_TOTAL;
      v = p / H_TOTAL;
      visible = (h < H_VISIBLE) && (v < V_VISIBLE);
      casilla = modelo[(v / 32) * COLUMNAS + h / 32];
      // Una casilla con borde lleva negro en su primer y ultimo pixel de cada eje
      contorno = (h % 32 == 0) || (h % 32 == 31) || (v % 32 == 0) || (v % 32 == 31);
      if (!visible) esperado = 12'h000;
      else if (casilla[3] && contorno) esperado = 12'h000;
      else esperado = paleta(casilla[2:0]);
      hs_esperado = !(h >= 656 && h <= 751);
      vs_esperado = !(v >= 490 && v <= 491);
      visto = {r_tb, g_tb, b_tb};

      if (visto !== esperado) begin
        if (malos_color == 0)
          primer_error = $sformatf("pixel h=%0d v=%0d esperaba %03h y dio %03h", h, v, esperado, visto);
        malos_color++;
      end

      if (hsync_tb !== hs_esperado || vsync_tb !== vs_esperado) begin
        if (malos_sync == 0 && malos_color == 0)
          primer_error = $sformatf("pixel h=%0d v=%0d esperaba hsync=%b vsync=%b y dio %b %b",
                                   h, v, hs_esperado, vs_esperado, hsync_tb, vsync_tb);
        malos_sync++;
      end

      if (hsync_tb === 1'b0) bajos_h++;
      if (vsync_tb === 1'b0) bajos_v++;

      if (visible && visto === buscado) begin
        n_buscado++;
        if (h < h_min) h_min = h;
        if (h > h_max) h_max = h;
        if (v < v_min) v_min = v;
        if (v > v_max) v_max = v;
      end

      ciclo_pix();
    end
  endtask

  task automatic anotar_cuadro(input string nombre);
    anotar({nombre, ", colores"}, malos_color == 0,
           $sformatf("%0d pixeles malos, el primero %s", malos_color, primer_error));
    anotar({nombre, ", sincronismos"}, malos_sync == 0,
           $sformatf("%0d pixeles malos, el primero %s", malos_sync, primer_error));
  endtask

  // Ancho y periodo de hsync contados en ciclos de pixel, sin mirar los contadores del DUT
  task automatic medir_hsync();
    logic antes;
    int periodo;
    int bajo;

    do begin antes = hsync_tb; ciclo_pix(); end while (!(antes === 1'b1 && hsync_tb === 1'b0));
    anotar("hsync baja LATENCIA ciclos despues del pixel 656", dut.h_count == 656 + LATENCIA,
           $sformatf("bajo con h_count=%0d", dut.h_count));

    bajo = 0;
    periodo = 0;
    while (hsync_tb === 1'b0) begin ciclo_pix(); bajo++; periodo++; end
    anotar("hsync dura 96 pixeles abajo", bajo == 96, $sformatf("duro %0d", bajo));

    do begin antes = hsync_tb; ciclo_pix(); periodo++; end while (!(antes === 1'b1 && hsync_tb === 1'b0));
    anotar("una linea dura 800 pixeles", periodo == H_TOTAL, $sformatf("duro %0d", periodo));
  endtask

  // ---------------------------------------------------------------- pruebas

  // Solo las primeras lineas, un cuadro completo en VCD pesa cientos de MB
  initial begin
    $dumpfile("tb_periferico_vga.vcd");
    $dumpvars(0, tb_periferico_vga);
    #100us;
    $dumpoff;
  end

  initial begin
    logic [31:0] palabra;

    clk_tb = 1'b0;
    clk_pix_tb = 1'b0;
    rst_tb = 1'b1;
    we_tb = 1'b0;
    addr_tb = '0;
    wdata_tb = '0;
    for (int i = 0; i < CASILLAS; i++) modelo[i] = 4'b0000;

    repeat (20) ciclo();
    anotar("con reset los contadores estan en 0", dut.h_count == 0 && dut.v_count == 0,
           $sformatf("h_count=%0d v_count=%0d", dut.h_count, dut.v_count));
    anotar("y las salidas en reposo, sincronismos arriba y negro",
           hsync_tb === 1'b1 && vsync_tb === 1'b1 && {r_tb, g_tb, b_tb} === 12'h000,
           $sformatf("hsync=%b vsync=%b rgb=%03h", hsync_tb, vsync_tb, {r_tb, g_tb, b_tb}));

    chequear_lectura("la memoria arranca en ceros, casilla 0", 9'd0, 32'h0);
    chequear_lectura("y en la ultima casilla visible", 9'd299, 32'h0);
    chequear_lectura("y en la ultima palabra del rango", 9'd511, 32'h0);

    rst_tb = 1'b0;

    medir_hsync();

    // ------------------------------------------------ puerto del CPU

    escribir(9'd5, 32'hDEADBEA5);
    chequear_lectura("una escritura se lee de vuelta con los bits reservados", 9'd5, 32'hDEADBEA5);

    escribir(9'd6, 32'h0000_0003);
    chequear_lectura("cambiar addr_i sin reloj cambia rdata_o, la lectura es combinacional", 9'd6, 32'h0000_0003);
    chequear_lectura("y volver a la anterior tambien", 9'd5, 32'hDEADBEA5);

    addr_tb = 9'd5;
    wdata_tb = 32'h1234_5678;
    we_tb = 1'b0;
    repeat (3) ciclo();
    chequear_lectura("sin write_enable_i la memoria no cambia", 9'd5, 32'hDEADBEA5);

    escribir(9'd511, 32'hCAFE_0007);
    chequear_lectura("las palabras de 300 a 511 tambien guardan", 9'd511, 32'hCAFE_0007);

    // ------------------------------------------------ una casilla sola

    // Borrar la pantalla es un lazo de software, el testbench hace lo mismo que hara el programa
    for (int i = 0; i < CASILLAS; i++) escribir(i, 32'h0);
    pintar(3, 5, 3'b010);

    revisar_cuadro(12'hF00);
    anotar_cuadro("cuadro de agua con un impacto en (3, 5)");
    anotar("el impacto ocupa h=160..191 y v=96..127 y nada mas",
           n_buscado == 32 * 32 && h_min == 160 && h_max == 191 && v_min == 96 && v_max == 127,
           $sformatf("%0d pixeles en h=%0d..%0d v=%0d..%0d", n_buscado, h_min, h_max, v_min, v_max));
    anotar("hsync pasa 96 pixeles abajo en cada una de las 525 lineas", bajos_h == 96 * V_TOTAL,
           $sformatf("estuvo abajo %0d pixeles", bajos_h));
    anotar("vsync pasa 2 lineas abajo por cuadro", bajos_v == 2 * H_TOTAL,
           $sformatf("estuvo abajo %0d pixeles", bajos_v));

    // ------------------------------------------------ los 8 colores

    // idx % 8 con 20 columnas reparte los 8 codigos por toda la pantalla. La basura arriba prende el bit de
    // borde en mas o menos la mitad de las casillas y prueba que el barrido ignora [31:4]
    for (int i = 0; i < CASILLAS; i++) begin
      palabra = $urandom;
      escribir(i, {palabra[31:3], 3'(i % 8)});
    end

    revisar_cuadro(paleta(3'b111));
    anotar_cuadro("cuadro con los 8 codigos y basura en los bits reservados");

    // ------------------------------------------------ escritura a media pantalla

    repeat (PIX_CUADRO / 2) ciclo_pix();
    pintar(14, 19, 3'b001);
    pintar(0, 0, 3'b100);

    revisar_cuadro(paleta(3'b100));
    anotar_cuadro("casillas escritas a mitad de cuadro salen completas en el siguiente");

    // ------------------------------------------------ reset a media partida

    rst_tb = 1'b1;
    repeat (20) ciclo();
    anotar("un reset a media partida vuelve los contadores a 0", dut.h_count == 0 && dut.v_count == 0,
           $sformatf("h_count=%0d v_count=%0d", dut.h_count, dut.v_count));
    // La 299 es la casilla (14, 19), que se pinto arriba con 001
    chequear_lectura("pero no borra la memoria de video", 9'd299, 32'h0000_0001);
    rst_tb = 1'b0;

    revisar_cuadro(paleta(3'b100));
    anotar_cuadro("despues del reset la imagen sigue igual");

    $display("%0d pruebas, %0d fallos", pruebas, errores);
    if (errores != 0) $fatal(1, "tb_periferico_vga termino con fallos");
    $finish;
  end

endmodule
