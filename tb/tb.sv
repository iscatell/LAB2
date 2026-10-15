/*
 * tb.v
 *
 *  Created on: 17.10.2019
 *      Author: Alexander Antonov <antonov.alex.alex@gmail.com>
 *     License: See LICENSE file for details
 */


`timescale 1ns / 1ps

`define HALF_PERIOD			5						//external 100 MHZ
`define DIVIDER_115200		32'd8680
`define DIVIDER_19200		32'd52083
`define DIVIDER_9600		32'd104166
`define DIVIDER_4800		32'd208333
`define DIVIDER_2400		32'd416666


module tb ();
//
logic CLK_100MHZ, RST, rx;
logic [15:0] SW;
logic [15:0] LED;

always #`HALF_PERIOD CLK_100MHZ = ~CLK_100MHZ;

always #1000 SW = SW + 8'h1;
	
NEXYS4_DDR
#(
	.SIM("YES")
) DUT (
	.CLK100MHZ(CLK_100MHZ)
    , .CPU_RESETN(!RST)
    
    , .SW(SW)
    , .LED(LED)

    , .UART_TXD_IN(rx)
    , .UART_RXD_OUT()
);

////reset all////
task RESET_ALL ();
    begin
    CLK_100MHZ = 1'b0;
    RST = 1'b1;
    rx = 1'b1;
    #(`HALF_PERIOD/2);
    RST = 1;
    #(`HALF_PERIOD*6);
    RST = 0;
    while (DUT.srst) WAIT(10);
    end
endtask

////wait////
task WAIT
    (
     input logic [15:0] periods
     );
    begin
    integer i;
    for (i=0; i<periods; i=i+1)
        begin
        #(`HALF_PERIOD*2);
        end
    end
endtask

`define UDM_RX_SIGNAL rx
`define UDM_BLOCK DUT.udm
`include "udm.svh"
udm_driver udm = new();

/////////////////////////
// main test procedure //
localparam CSR_LED_ADDR         = 32'h00000000;
localparam CSR_SW_ADDR          = 32'h00000004;
localparam CSR_Y_ADDR           = 32'h10000000;
localparam CSR_X_ADDR           = 32'h10000004;
localparam CSR_ANGLE_ADDR       = 32'h20000000;
localparam TESTMEM_ADDR         = 32'h80000000;

initial
    begin
    logic [31:0] wrdata [];
    integer ARRSIZE=10;
    
	$display ("### SIMULATION STARTED ###");
	
	SW = 8'h30;
	RESET_ALL();
	WAIT(100);

	udm.cfg(`DIVIDER_115200, 2'b00);
	udm.check();
	udm.hreset();
	WAIT(100);
	
	// ============================================================
	// CORDIC atan2 verification tests across all 4 quadrants
	// ============================================================

	// Test 1: Quadrant I (y = 100, x = 100) -> Expected: 0x191c9ac2
	$display ("Testing Quadrant I: y = 100, x = 100");
	udm.wr32(CSR_Y_ADDR, 32'd100);
	udm.wr32(CSR_X_ADDR, 32'd100);
	udm.rd32(CSR_ANGLE_ADDR);

	// Test 2: Quadrant II (y = 100, x = -100) -> Expected: 0x4b60916b
	$display ("Testing Quadrant II: y = 100, x = -100");
	udm.wr32(CSR_Y_ADDR, 32'd100);
	udm.wr32(CSR_X_ADDR, -32'd100);
	udm.rd32(CSR_ANGLE_ADDR);

	// Test 3: Quadrant III (y = -100, x = -100) -> Expected: 0xb494ad71
	$display ("Testing Quadrant III: y = -100, x = -100");
	udm.wr32(CSR_Y_ADDR, -32'd100);
	udm.wr32(CSR_X_ADDR, -32'd100);
	udm.rd32(CSR_ANGLE_ADDR);

	// Test 4: Quadrant IV (y = -100, x = 100) -> Expected: 0xe6d8a41a
	$display ("Testing Quadrant IV: y = -100, x = 100");
	udm.wr32(CSR_Y_ADDR, -32'd100);
	udm.wr32(CSR_X_ADDR, 32'd100);
	udm.rd32(CSR_ANGLE_ADDR);

	// Test 5: Positive Y-axis (y = 100, x = 0) -> Expected: 0x324a5b8e
	$display ("Testing +Y axis: y = 100, x = 0");
	udm.wr32(CSR_Y_ADDR, 32'd100);
	udm.wr32(CSR_X_ADDR, 32'd0);
	udm.rd32(CSR_ANGLE_ADDR);

	// Test 6: Zero point (y = 0, x = 0) -> Expected: 0x00000000
	$display ("Testing (0, 0): y = 0, x = 0");
	udm.wr32(CSR_Y_ADDR, 32'd0);
	udm.wr32(CSR_X_ADDR, 32'd0);
	udm.rd32(CSR_ANGLE_ADDR);
	
	WAIT(1000);

	$display ("### TEST PROCEDURE FINISHED ###");
	$stop;
    end


endmodule
