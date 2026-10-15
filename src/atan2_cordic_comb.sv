/*
 * atan2_cordic_comb.sv
 *
 * Combinational CORDIC atan2(y, x) accelerator.
 * Bit-accurate to Python reference model (10-atan2_cordic.py).
 * Format:
 *   Inputs:  x_bi, y_bi (32-bit signed integers, Q16.16)
 *   Output:  angle_bo (32-bit signed, Q3.29 format, radians in [-pi, pi])
 */

`timescale 1ns / 1ps

module atan2_cordic_comb (
    input  logic signed [31:0] y_bi,
    input  logic signed [31:0] x_bi,
    output logic signed [31:0] angle_bo
);

    // ============================================================
    // CORDIC Constants (Q3.29 format: 3 integer bits, 29 frac bits)
    // ============================================================
    localparam int ITERATIONS = 32;

    localparam logic signed [63:0] PI     = 64'sh000000006487ed51; // round(pi * 2^29)
    localparam logic signed [63:0] TWO_PI = 64'sh00000000c90fdaa2; // round(2*pi * 2^29)

    // Precomputed atan(2^-i) table in Q3.29 format
    localparam logic signed [63:0] ATAN_TABLE [0:31] = '{
        64'sh1921fb54, 64'sh0ed63383, 64'sh07d6dd7e, 64'sh03fab753,
        64'sh01ff55bb, 64'sh00ffeaae, 64'sh007ffd55, 64'sh003fffab,
        64'sh001ffff5, 64'sh000fffff, 64'sh00080000, 64'sh00040000,
        64'sh00020000, 64'sh00010000, 64'sh00008000, 64'sh00004000,
        64'sh00002000, 64'sh00001000, 64'sh00000800, 64'sh00000400,
        64'sh00000200, 64'sh00000100, 64'sh00000080, 64'sh00000040,
        64'sh00000020, 64'sh00000010, 64'sh00000008, 64'sh00000004,
        64'sh00000002, 64'sh00000001, 64'sh00000000, 64'sh00000000
    };

    // ============================================================
    // Combinational CORDIC core
    // ============================================================
    always_comb begin : cordic_combinational
        logic signed [63:0] x, y;
        logic signed [63:0] x_old, y_old;
        logic signed [63:0] angle;

        // Undefined for (0, 0)
        if (x_bi == 32'sd0 && y_bi == 32'sd0) begin
            angle_bo = 32'sd0;
        end else begin
            // Move vector into right half-plane (x >= 0)
            // atan2(y, x) = atan2(-y, -x) +/- pi
            if (x_bi < 32'sd0) begin
                x = -{{32{x_bi[31]}}, x_bi};
                y = -{{32{y_bi[31]}}, y_bi};
                angle = PI;
            end else begin
                x = {{32{x_bi[31]}}, x_bi};
                y = {{32{y_bi[31]}}, y_bi};
                angle = 64'sd0;
            end

            // 32 unrolled combinational CORDIC vectoring stages
            for (int i = 0; i < ITERATIONS; i++) begin
                x_old = x;
                y_old = y;

                if (y > 64'sd0) begin
                    x = x_old + (y_old >>> i);
                    y = y_old - (x_old >>> i);
                    angle = angle + ATAN_TABLE[i];
                end else begin
                    x = x_old - (y_old >>> i);
                    y = y_old + (x_old >>> i);
                    angle = angle - ATAN_TABLE[i];
                end
            end

            // Normalize angle to [-PI, PI]
            if (angle > PI) begin
                angle = angle - TWO_PI;
            end else if (angle < -PI) begin
                angle = angle + TWO_PI;
            end

            angle_bo = angle[31:0];
        end
    end

endmodule
