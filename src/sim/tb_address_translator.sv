`timescale 1ns/1ps
module tb_address_translator;
    logic [31:0] address_i;
    logic write_enable_i;
    wire ram_we, uart_we, gpio_we, display_we, led_we, buzzer_we, vga_we;
    wire [2:0] mux_sel;
    wire [31:0] rdata_o;
    integer checks = 0;
    address_translator dut (.*);
    mux_lectura mux (
        .mux_sel(mux_sel), .ram_dout(32'h11111111),
        .uart_dout(32'h22222222), .gpio_dout(32'h33333333),
        .display_dout(32'h44444444), .led_dout(32'h55555555),
        .buzzer_dout(32'h66666666), .vga_dout(32'h77777777),
        .rdata_o(rdata_o)
    );
    // Modelo independiente: rangos numericos, no cortes de bits del DUT.
    task automatic check(input logic [31:0] a, input logic w);
        integer target;
        logic [6:0] expected_we;
        logic [31:0] expected_data;
        begin
            target = 7;
            if (a % 4 == 0) begin
                if (a >= 32'h2000 && a <= 32'h2ffc) target = 0;
                if (a == 32'h10040 || a == 32'h10044 || a == 32'h10048) target = 1;
                if (a == 32'h10120) target = 2;
                if (a == 32'h10130) target = 3;
                if (a == 32'h10138) target = 4;
                if (a == 32'h10140) target = 5;
                if (a >= 32'h11000 && a <= 32'h117fc) target = 6;
            end
            expected_we = 0;
            if (w && target != 7 && target != 2) expected_we[target] = 1'b1;
            case (target)
                0: expected_data = 32'h11111111;
                1: expected_data = 32'h22222222;
                2: expected_data = 32'h33333333;
                3: expected_data = 32'h44444444;
                4: expected_data = 32'h55555555;
                5: expected_data = 32'h66666666;
                6: expected_data = 32'h77777777;
                default: expected_data = 0;
            endcase
            address_i = a; write_enable_i = w; #1;
            if (mux_sel !== target[2:0] ||
                {vga_we,buzzer_we,led_we,display_we,gpio_we,uart_we,ram_we} !== expected_we ||
                rdata_o !== expected_data)
                $fatal(1,"FAIL a=%h we=%b mux=%b data=%h", a,w,mux_sel,rdata_o);
            checks++;
        end
    endtask
    initial begin
        // Incluye ROM, RAM, MMIO, todos los huecos y accesos desalineados.
        for (integer a = 0; a < 32'h20000; a++) begin
            check(a, 0); check(a, 1);
        end
        // Bits altos: ninguna ventana puede tener alias fuera de su direccion.
        for (integer n = 0; n < 2000; n++) begin
            check($urandom, 0); check($urandom, 1);
        end
        check(32'h80002000,1); check(32'h80010040,1);
        check(32'h80011000,1); check(32'hffffffff,1);
        $display("PASS AT + MUX: %0d checks", checks);
        $finish;
    end
endmodule
