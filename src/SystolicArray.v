`timescale 1ns / 1ps

// 2×2 输出驻留脉动阵列。
// A 从左向右传播，W 从上向下传播，每个 PE 保存一个输出元素的部分和。
module SystolicArray (
    input                clk,
    input                rst,
    input                clear,
    input                step,
    input  signed [15:0] a_left_row0,
    input  signed [15:0] a_left_row1,
    input  signed [15:0] w_top_col0,
    input  signed [15:0] w_top_col1,
    output signed [31:0] sum00,
    output signed [31:0] sum01,
    output signed [31:0] sum10,
    output signed [31:0] sum11
);
    // 阵列右边界和下边界的传播输出按设计无需继续使用。
    /* verilator lint_off PINCONNECTEMPTY */
    wire signed [15:0] a00_to_01;
    wire signed [15:0] a10_to_11;
    wire signed [15:0] w00_to_10;
    wire signed [15:0] w01_to_11;

    MacPE pe00 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .activation_in(a_left_row0),
        .weight_in(w_top_col0),
        .activation_out(a00_to_01),
        .weight_out(w00_to_10),
        .accumulator(sum00)
    );

    MacPE pe01 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .activation_in(a00_to_01),
        .weight_in(w_top_col1),
        .activation_out(),
        .weight_out(w01_to_11),
        .accumulator(sum01)
    );

    MacPE pe10 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .activation_in(a_left_row1),
        .weight_in(w00_to_10),
        .activation_out(a10_to_11),
        .weight_out(),
        .accumulator(sum10)
    );

    MacPE pe11 (
        .clk(clk),
        .rst(rst),
        .clear(clear),
        .enable(step),
        .activation_in(a10_to_11),
        .weight_in(w01_to_11),
        .activation_out(),
        .weight_out(),
        .accumulator(sum11)
    );
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
