`timescale 1ns / 1ps

// 2×2 Output Stationary（输出驻留）Systolic Array（脉动阵列）。
// Activation从左向右传播，Weight驻留在PE内，每个PE保存一个输出Partial Sum（部分和）。
module SystolicArray (
    input                clk,
    input                rst,
    input                clear,
    input                step,
    input         [1:0]  phase,
    input                weight_load,
    input                weight_switch,
    input        [31:0]  weight_matrix,
    input  signed [7:0] a_left_row0,
    input  signed [7:0] a_left_row1,
    output signed [31:0] sum00,
    output signed [31:0] sum01,
    output signed [31:0] sum10,
    output signed [31:0] sum11
);
    wire signed [7:0] weight_00;
    wire signed [7:0] weight_01;
    wire signed [7:0] weight_10;
    wire signed [7:0] weight_11;

    assign weight_00 = weight_matrix[7:0];
    assign weight_01 = weight_matrix[15:8];
    assign weight_10 = weight_matrix[23:16];
    assign weight_11 = weight_matrix[31:24];

    // 阵列右边界的Activation传播输出按设计无需继续使用。
    /* verilator lint_off PINCONNECTEMPTY */
    wire signed [7:0] a00_to_01;
    wire signed [7:0] a10_to_11;

    MacPE pe00 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .weight_load(weight_load),
        .weight_switch(weight_switch),
        .weight_select(phase == 2'd1),
        .shadow_weight_0_in(weight_00),
        .shadow_weight_1_in(weight_10),
        .activation_in(a_left_row0),
        .activation_out(a00_to_01),
        .accumulator(sum00)
    );

    MacPE pe01 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .weight_load(weight_load),
        .weight_switch(weight_switch),
        .weight_select(phase == 2'd2),
        .shadow_weight_0_in(weight_01),
        .shadow_weight_1_in(weight_11),
        .activation_in(a00_to_01),
        .activation_out(),
        .accumulator(sum01)
    );

    MacPE pe10 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .weight_load(weight_load),
        .weight_switch(weight_switch),
        .weight_select(phase == 2'd2),
        .shadow_weight_0_in(weight_00),
        .shadow_weight_1_in(weight_10),
        .activation_in(a_left_row1),
        .activation_out(a10_to_11),
        .accumulator(sum10)
    );

    MacPE pe11 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .weight_load(weight_load),
        .weight_switch(weight_switch),
        .weight_select(phase == 2'd3),
        .shadow_weight_0_in(weight_01),
        .shadow_weight_1_in(weight_11),
        .activation_in(a10_to_11),
        .activation_out(),
        .accumulator(sum11)
    );
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
