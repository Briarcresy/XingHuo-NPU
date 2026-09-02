`timescale 1ns / 1ps

// 2×2 True Weight Stationary Systolic Array（真正的权重固定脉动阵列）。
// 行对应输出列j，列对应归约维度k：
//   PE00=W00，PE01=W10 -> 输出C[i][0]
//   PE10=W01，PE11=W11 -> 输出C[i][1]
module SystolicArray (
    input clk,
    input rst,
    input clear,
    input step,
    input weight_load,
    input weight_switch,
    input [31:0] weight_matrix,
    input signed [7:0] activation_top_col0,
    input signed [7:0] activation_top_col1,
    input activation_valid_col0,
    input activation_valid_col1,
    output signed [31:0] result_col0_stream,
    output result_col0_valid,
    output signed [31:0] result_col1_stream,
    output result_col1_valid
);
    wire signed [7:0] weight_00;
    wire signed [7:0] weight_01;
    wire signed [7:0] weight_10;
    wire signed [7:0] weight_11;
    wire signed [7:0] activation_00_to_10;
    wire signed [7:0] activation_01_to_11;
    wire activation_00_to_10_valid;
    wire activation_01_to_11_valid;
    wire signed [31:0] partial_sum_00_to_01;
    wire signed [31:0] partial_sum_10_to_11;
    wire partial_sum_00_to_01_valid;
    wire partial_sum_10_to_11_valid;

    assign weight_00 = weight_matrix[7:0];
    assign weight_01 = weight_matrix[15:8];
    assign weight_10 = weight_matrix[23:16];
    assign weight_11 = weight_matrix[31:24];

    /* verilator lint_off PINCONNECTEMPTY */
    MacPE pe00 (
        .clk(clk), .rst(rst), .clear(clear), .enable(step),
        .weight_load(weight_load), .weight_switch(weight_switch),
        .shadow_weight_in(weight_00),
        .activation_in(activation_top_col0),
        .activation_valid_in(activation_valid_col0),
        .activation_out(activation_00_to_10),
        .activation_valid_out(activation_00_to_10_valid),
        .partial_sum_in(32'sd0),
        .partial_sum_valid_in(activation_valid_col0),
        .partial_sum_out(partial_sum_00_to_01),
        .partial_sum_valid_out(partial_sum_00_to_01_valid)
    );

    MacPE pe01 (
        .clk(clk), .rst(rst), .clear(clear), .enable(step),
        .weight_load(weight_load), .weight_switch(weight_switch),
        .shadow_weight_in(weight_10),
        .activation_in(activation_top_col1),
        .activation_valid_in(activation_valid_col1),
        .activation_out(activation_01_to_11),
        .activation_valid_out(activation_01_to_11_valid),
        .partial_sum_in(partial_sum_00_to_01),
        .partial_sum_valid_in(partial_sum_00_to_01_valid),
        .partial_sum_out(result_col0_stream),
        .partial_sum_valid_out(result_col0_valid)
    );

    MacPE pe10 (
        .clk(clk), .rst(rst), .clear(clear), .enable(step),
        .weight_load(weight_load), .weight_switch(weight_switch),
        .shadow_weight_in(weight_01),
        .activation_in(activation_00_to_10),
        .activation_valid_in(activation_00_to_10_valid),
        .activation_out(), .activation_valid_out(),
        .partial_sum_in(32'sd0),
        .partial_sum_valid_in(activation_00_to_10_valid),
        .partial_sum_out(partial_sum_10_to_11),
        .partial_sum_valid_out(partial_sum_10_to_11_valid)
    );

    MacPE pe11 (
        .clk(clk), .rst(rst), .clear(clear), .enable(step),
        .weight_load(weight_load), .weight_switch(weight_switch),
        .shadow_weight_in(weight_11),
        .activation_in(activation_01_to_11),
        .activation_valid_in(activation_01_to_11_valid),
        .activation_out(), .activation_valid_out(),
        .partial_sum_in(partial_sum_10_to_11),
        .partial_sum_valid_in(partial_sum_10_to_11_valid),
        .partial_sum_out(result_col1_stream),
        .partial_sum_valid_out(result_col1_valid)
    );
    /* verilator lint_on PINCONNECTEMPTY */
endmodule
