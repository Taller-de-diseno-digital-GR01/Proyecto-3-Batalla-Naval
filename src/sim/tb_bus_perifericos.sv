`timescale 1ns/1ps
// Compilar junto al RTL real de feature/uart, button, 7seg, led_estado, buzzer.
// RAM y VGA NO estan implementadas aqui: se usan datos constantes solo en el MUX.
module tb_bus_perifericos;
    logic clk_i = 0;
    always #5 clk_i = ~clk_i;
    logic rst_i = 1;
    logic [31:0] address_i = 0, wdata_i = 0;
    logic write_enable_i = 0;
    logic [6:0] botones_i = 0;
    wire ram_we, uart_we, gpio_we, display_we, led_we, buzzer_we, vga_we;
    wire [2:0] mux_sel;
    wire [31:0] uart_dout, gpio_dout, display_dout, led_dout, buzzer_dout, rdata_o;
    wire tx_o, dp_o, buzzer_o;
    wire [6:0] seg_o;
    wire [3:0] an_o;
    wire [2:0] leds_o;

    address_translator at (.*);
    mux_lectura mux (
        .mux_sel(mux_sel), .ram_dout(32'hDEAD0001), .vga_dout(32'hDEAD0002),
        .uart_dout(uart_dout), .gpio_dout(gpio_dout), .display_dout(display_dout),
        .led_dout(led_dout), .buzzer_dout(buzzer_dout), .rdata_o(rdata_o)
    );
    periferico_uart uart (
        .clk_i(clk_i), .rst_i(rst_i), .write_enable_i(uart_we),
        .addr_i(address_i[3:2]), .wdata_i(wdata_i), .rdata_o(uart_dout),
        .rx_i(1'b1), .tx_o(tx_o)
    );
    periferico_entradas gpio (
        .clk_i(clk_i), .rst_i(rst_i), .write_enable_i(gpio_we),
        .addr_i(2'b00), .wdata_i(wdata_i), .rdata_o(gpio_dout), .botones_i(botones_i)
    );
    periferico_7seg display (
        .clk_i(clk_i), .rst_i(rst_i), .write_enable_i(display_we),
        .addr_i(2'b00), .wdata_i(wdata_i), .rdata_o(display_dout),
        .seg_o(seg_o), .an_o(an_o), .dp_o(dp_o)
    );
    periferico_led led (
        .clk_i(clk_i), .rst_i(rst_i), .write_enable_i(led_we),
        .addr_i(2'b00), .wdata_i(wdata_i), .rdata_o(led_dout), .leds_o(leds_o)
    );
    periferico_buzzer buzzer (
        .clk_i(clk_i), .rst_i(rst_i), .write_enable_i(buzzer_we),
        .addr_i(2'b00), .wdata_i(wdata_i), .rdata_o(buzzer_dout), .buzzer_o(buzzer_o)
    );

    task automatic write_word(input logic [31:0] a, input logic [31:0] d);
        @(negedge clk_i);
        address_i = a; wdata_i = d; write_enable_i = 1;
        @(posedge clk_i); #1;
        @(negedge clk_i); write_enable_i = 0;
    endtask
    task automatic read_check(input logic [31:0] a, input logic [31:0] expected);
        address_i = a; #1;
        if (rdata_o !== expected)
            $fatal(1,"FAIL read %h: got %h expected %h",a,rdata_o,expected);
    endtask
    initial begin
        repeat (3) @(negedge clk_i);
        rst_i = 0;
        write_word(32'h10138,32'h4);
        read_check(32'h10138,32'h4); // LED: addr local debe ser 00, no [3:2]=10.
        if (leds_o !== 3'b100) $fatal(1,"FAIL leds");
        write_word(32'h10130,32'h00051234);
        read_check(32'h10130,32'h00051234);
        write_word(32'h10044,32'hdeadbea5);
        read_check(32'h10044,32'ha5); // TX = registro local 01, dato de 8 bits.
        read_check(32'h10040,0);
        write_word(32'h10048,32'h5a);
        read_check(32'h10048,32'h5a); // Preserva semantica RW del RX actual.
        write_word(32'h1004c,32'hffffffff);
        read_check(32'h1004c,0);
        read_check(32'h10044,32'ha5);
        read_check(32'h10048,32'h5a);
        @(negedge clk_i); botones_i = 7'b1010101;
        @(posedge clk_i); #1;
        read_check(32'h10120,32'h55);
        write_word(32'h10120,32'hffffffff);
        read_check(32'h10120,32'h55);
        write_word(32'h10140,32'h3);
        read_check(32'h10140,32'h3);
        write_word(32'h10139,32'h0); // No alineada: no debe apagar LED.
        read_check(32'h10138,32'h4);
        read_check(32'h0,0); // ROM no participa en el bus de datos.
        read_check(32'h10124,0);
        $display("PASS bus con 5 perifericos reales: direcciones, escritura, lectura y aislamiento");
        $finish;
    end
endmodule
