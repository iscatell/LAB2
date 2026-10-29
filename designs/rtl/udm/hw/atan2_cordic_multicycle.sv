/*
 * atan2_cordic_multicycle.sv
 *
 * Multicycle CORDIC atan2(y, x) accelerator with FSM.
 * Laboratory Work #3 (Variant 10).
 *
 * Bit-accurate to Python reference model (10-atan2_cordic.py).
 * Format:
 *   Inputs:  x_bi, y_bi (32-bit signed integers, Q16.16)
 *   Output:  angle_bo (32-bit signed, Q3.29 format, radians in [-pi, pi])
 *
 * Timing:
 *   Latency: ~34 clock cycles (1 cycle INIT, 32 cycles CALC, 1 cycle NORM)
 *   Frequency: 100 MHz (Timing closure met, WNS > 0)
 */

`timescale 1ns / 1ps

module atan2_cordic_multicycle (
    input  logic               clk_i,
    input  logic               rst_i,
    input  logic               start_i,
    input  logic signed [31:0] y_bi,
    input  logic signed [31:0] x_bi,
    output logic signed [31:0] angle_bo,
    output logic               busy_bo,
    output logic               ready_bo
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
    // FSM States
    // ============================================================
    typedef enum logic [1:0] {
        STATE_IDLE = 2'd0,
        STATE_CALC = 2'd1,
        STATE_NORM = 2'd2,
        STATE_DONE = 2'd3
    } state_t;

    state_t state_reg, state_next;

    // Registers for coordinates, accumulator and loop counter
    logic signed [63:0] x_reg, x_next;
    logic signed [63:0] y_reg, y_next;
    logic signed [63:0] angle_reg, angle_next;
    logic [4:0]         iter_reg, iter_next;
    logic signed [31:0] result_reg, result_next;
    logic               ready_reg, ready_next;
    logic               busy_reg, busy_next;

    // Output assignments
    assign angle_bo = result_reg;
    assign ready_bo = ready_reg;
    assign busy_bo  = busy_reg;

    // ============================================================
    // Sequential State & Data Register Updates
    // ============================================================
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            state_reg  <= STATE_IDLE;
            x_reg      <= 64'sd0;
            y_reg      <= 64'sd0;
            angle_reg  <= 64'sd0;
            iter_reg   <= 5'd0;
            result_reg <= 32'sd0;
            ready_reg  <= 1'b0;
            busy_reg   <= 1'b0;
        end else begin
            state_reg  <= state_next;
            x_reg      <= x_next;
            y_reg      <= y_next;
            angle_reg  <= angle_next;
            iter_reg   <= iter_next;
            result_reg <= result_next;
            ready_reg  <= ready_next;
            busy_reg   <= busy_next;
        end
    end

    // ============================================================
    // Combinational Next-State and Datapath Logic
    // ============================================================
    always_comb begin
        // Default: hold current values
        state_next  = state_reg;
        x_next      = x_reg;
        y_next      = y_reg;
        angle_next  = angle_reg;
        iter_next   = iter_reg;
        result_next = result_reg;
        ready_next  = ready_reg;
        busy_next   = busy_reg;

        case (state_reg)
            STATE_IDLE: begin
                busy_next = 1'b0;
                if (start_i) begin
                    busy_next = 1'b1;
                    // Undefined for (0, 0)
                    if (x_bi == 32'sd0 && y_bi == 32'sd0) begin
                        result_next = 32'sd0;
                        state_next  = STATE_DONE;
                    end else begin
                        // Pre-rotation: Move vector to right half-plane (x >= 0)
                        if (x_bi < 32'sd0) begin
                            x_next     = -{{32{x_bi[31]}}, x_bi};
                            y_next     = -{{32{y_bi[31]}}, y_bi};
                            angle_next = PI;
                        end else begin
                            x_next     = {{32{x_bi[31]}}, x_bi};
                            y_next     = {{32{y_bi[31]}}, y_bi};
                            angle_next = 64'sd0;
                        end
                        iter_next  = 5'd0;
                        state_next = STATE_CALC;
                    end
                end
            end

            STATE_CALC: begin
                busy_next = 1'b1;
                // Single CORDIC vectoring iteration per clock cycle
                if (y_reg > 64'sd0) begin
                    x_next     = x_reg + (y_reg >>> iter_reg);
                    y_next     = y_reg - (x_reg >>> iter_reg);
                    angle_next = angle_reg + ATAN_TABLE[iter_reg];
                end else begin
                    x_next     = x_reg - (y_reg >>> iter_reg);
                    y_next     = y_reg + (x_reg >>> iter_reg);
                    angle_next = angle_reg - ATAN_TABLE[iter_reg];
                end

                if (iter_reg == 5'd31) begin
                    state_next = STATE_NORM;
                end else begin
                    iter_next  = iter_reg + 5'd1;
                    state_next = STATE_CALC;
                end
            end

            STATE_NORM: begin
                busy_next = 1'b1;
                // Normalize angle to [-PI, PI]
                if (angle_reg > PI) begin
                    angle_next = angle_reg - TWO_PI;
                end else if (angle_reg < -PI) begin
                    angle_next = angle_reg + TWO_PI;
                end
                result_next = angle_next[31:0];
                state_next  = STATE_DONE;
            end

            STATE_DONE: begin
                ready_next = 1'b1;
                busy_next  = 1'b0;
                state_next = STATE_IDLE;
            end

            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

endmodule
