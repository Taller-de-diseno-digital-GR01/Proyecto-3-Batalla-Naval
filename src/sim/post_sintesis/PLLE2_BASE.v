`timescale 1ns/1ps

// Modelo de comportamiento de la primitiva PLLE2_BASE, solo para simular el netlist de sintesis. La
// biblioteca de yosys (cells_xtra.v) la trae como caja negra, sin funcionamiento, y Vivado no esta en
// el flujo, asi que no hay un modelo UNISIM a mano.
//
// Mide el periodo de CLKIN1 y genera CLKOUT0 y CLKOUT1 con periodo
// T_in * DIVCLK_DIVIDE * CLKOUTn_DIVIDE / CLKFBOUT_MULT, en fase con la entrada como en el PLL real.
// LOCKED sube despues de 16 ciclos de entrada, igual que el modelo de generador_relojes.sv. No modela
// jitter, tiempo de enganche real, desfase ni el lazo de realimentacion: CLKFBOUT sigue a CLKIN1.
module PLLE2_BASE #(
  parameter BANDWIDTH = "OPTIMIZED",
  parameter CLKIN1_PERIOD = 0,
  parameter integer CLKFBOUT_MULT = 5,
  parameter integer DIVCLK_DIVIDE = 1,
  parameter integer CLKOUT0_DIVIDE = 1,
  parameter integer CLKOUT1_DIVIDE = 1,
  parameter integer CLKOUT2_DIVIDE = 1,
  parameter integer CLKOUT3_DIVIDE = 1,
  parameter integer CLKOUT4_DIVIDE = 1,
  parameter integer CLKOUT5_DIVIDE = 1
) (
  output reg  CLKFBOUT,
  output reg  CLKOUT0,
  output reg  CLKOUT1,
  output wire CLKOUT2,
  output wire CLKOUT3,
  output wire CLKOUT4,
  output wire CLKOUT5,
  output reg  LOCKED,
  input  wire CLKFBIN,
  input  wire CLKIN1,
  input  wire PWRDWN,
  input  wire RST
);

  assign CLKOUT2 = 1'b0;
  assign CLKOUT3 = 1'b0;
  assign CLKOUT4 = 1'b0;
  assign CLKOUT5 = 1'b0;

  realtime t_anterior = 0;
  realtime t_in = 0;
  integer flancos = 0;

  initial begin
    CLKFBOUT = 1'b0;
    CLKOUT0 = 1'b0;
    CLKOUT1 = 1'b0;
    LOCKED = 1'b0;
  end

  always @(CLKIN1) CLKFBOUT = CLKIN1;

  always @(posedge CLKIN1) begin
    if (flancos > 0) t_in = $realtime - t_anterior;
    t_anterior = $realtime;
    flancos = flancos + 1;
    if (flancos == 16) LOCKED = 1'b1;
  end

  // Cada salida arranca en el flanco 2 de la entrada, con el periodo ya medido
  initial begin
    realtime medio;
    wait (flancos == 2);
    medio = t_in * DIVCLK_DIVIDE * CLKOUT0_DIVIDE / CLKFBOUT_MULT / 2.0;
    forever begin
      CLKOUT0 = 1'b1;
      #(medio);
      CLKOUT0 = 1'b0;
      #(medio);
    end
  end

  initial begin
    realtime medio;
    wait (flancos == 2);
    medio = t_in * DIVCLK_DIVIDE * CLKOUT1_DIVIDE / CLKFBOUT_MULT / 2.0;
    forever begin
      CLKOUT1 = 1'b1;
      #(medio);
      CLKOUT1 = 1'b0;
      #(medio);
    end
  end

endmodule
