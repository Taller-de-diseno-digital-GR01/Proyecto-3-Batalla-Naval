// PLL que saca los dos relojes del sistema del oscilador de 100 MHz de la Basys 3 (pin W5).
// clk_sys_o va al procesador, las memorias y los perifericos, clk_pix_o al barrido del VGA.
// Los dos salen del mismo VCO, asi que quedan relacionados en fase.
//
// clk_sys_o es de 33,33 MHz y no de 50: con el sistema integrado nextpnr-xilinx da entre 39 y 43 MHz
// de maximo para clk_sys, segun la colocacion. 1000 / 30 deja margen, y la UART queda con 0,47 % de
// error en RX (a 40 MHz serian 1,4 % y sin margen de timing).
//
// yosys define SYNTHESIS al leer el RTL e iverilog no. En sintesis va la primitiva PLLE2_BASE de la
// Artix-7, en simulacion un divisor con contadores que da las mismas frecuencias, porque iverilog no
// conoce las primitivas de Xilinx.
module generador_relojes (
  input  logic clk_i,     // 100 MHz, pin W5
  output logic clk_sys_o, // 33,33 MHz
  output logic clk_pix_o, // 25 MHz
  output logic locked_o   // en alto cuando los dos relojes ya son estables
  );

`ifdef SYNTHESIS

  // VCO = 100 MHz * 10 / 1 = 1000 MHz, dentro de los 800-1600 MHz del PLLE2 en la -1.
  // 1000 / 30 = 33,33 MHz y 1000 / 40 = 25 MHz
  logic clk_fb;
  logic clk_sys_pll;
  logic clk_pix_pll;

  PLLE2_BASE #(
    .CLKIN1_PERIOD  (10.0),
    .DIVCLK_DIVIDE  (1),
    .CLKFBOUT_MULT  (10),
    .CLKOUT0_DIVIDE (30),
    .CLKOUT1_DIVIDE (40)
  ) u_pll (
    .CLKIN1   (clk_i),
    .CLKFBIN  (clk_fb),
    .CLKFBOUT (clk_fb),
    .CLKOUT0  (clk_sys_pll),
    .CLKOUT1  (clk_pix_pll),
    .CLKOUT2  (),
    .CLKOUT3  (),
    .CLKOUT4  (),
    .CLKOUT5  (),
    .LOCKED   (locked_o),
    // Sin conectar a proposito, no en 1'b0. Con una constante, nextpnr-xilinx rutea el pin y escribe
    // mal su bit de inversion (ZINV_RST), y el PLL queda en reinicio para siempre: sin locked y sin
    // ninguna salida, probado en la tarjeta. Sin conectar es como lo usa LiteX con este mismo flujo,
    // y Vivado deja los pines sin conectar en cero
    .PWRDWN   (),
    .RST      ()
  );

  // Cada salida a la red global de reloj
  BUFG u_bufg_sys (.I(clk_sys_pll), .O(clk_sys_o));
  BUFG u_bufg_pix (.I(clk_pix_pll), .O(clk_pix_o));

`else

  // Modelo de simulacion. clk_sys_o dura 3 ciclos de clk_i (30 ns) y clk_pix_o 4 (40 ns). El ciclo
  // de trabajo de clk_sys_o no es 50 %, pero todo el diseno usa solo el flanco de subida. Los dos
  // suben juntos cada 12 ciclos, igual que con el PLL. locked sube despues de 16 ciclos de entrada
  logic [1:0] cuenta_sys = '0;
  logic [1:0] cuenta_pix = '0;
  logic [3:0] espera_lock = '0;

  always_ff @(posedge clk_i) begin
    cuenta_sys <= (cuenta_sys == 2'd2) ? 2'd0 : cuenta_sys + 2'd1;
    cuenta_pix <= cuenta_pix + 2'd1;
    if (espera_lock != '1) espera_lock <= espera_lock + 4'd1;
  end

  assign clk_sys_o = (cuenta_sys == 2'd0);
  assign clk_pix_o = ~cuenta_pix[1];
  assign locked_o = (espera_lock == '1);

`endif

endmodule
