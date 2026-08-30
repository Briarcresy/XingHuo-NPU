`timescale 1ns/1ps

// 教学用纯推理 Tiny TPU 顶层（Verilog-2001）。
// 计算：Y = ReLU(A x W + bias)，A/W/Y 均为 2x2，bias 按列广播。
//
// 顶层只连接各功能模块，不在这里实现具体算法：
// control -> feeder -> systolic array -> VPU。
module tiny_tpu (
    input  clk,
    input  rst,
    input  start,

    // 矩阵元素从低位到高位依次为 00、01、10、11。
    input  [63:0] activation_matrix,
    input  [63:0] weight_matrix,
    // 从低位到高位依次为 bias0、bias1。
    input  [31:0] bias_vector,

    output busy,
    output done,
    output [63:0] result_matrix
);
    // 控制通路信号。
    wire [1:0] phase;
    wire       array_clear;
    wire       array_step;
    wire       result_write_enable;

    // Feeder 到脉动阵列的四路边界数据。
    wire signed [15:0] a_left_row0;
    wire signed [15:0] a_left_row1;
    wire signed [15:0] w_top_col0;
    wire signed [15:0] w_top_col1;

    // 脉动阵列保存的四个 32 位输出部分和。
    wire signed [31:0] sum00;
    wire signed [31:0] sum01;
    wire signed [31:0] sum10;
    wire signed [31:0] sum11;

    control_unit control (
        .clk(clk),
        .rst(rst),
        .start(start),
        .busy(busy),
        .done(done),
        .phase(phase),
        .array_clear(array_clear),
        .array_step(array_step),
        .result_write_enable(result_write_enable)
    );

    matrix_feeder_2x2 feeder (
        .phase(phase),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .a_left_row0(a_left_row0),
        .a_left_row1(a_left_row1),
        .w_top_col0(w_top_col0),
        .w_top_col1(w_top_col1)
    );

    systolic_array_2x2 array (
        .clk(clk),
        .rst(rst),
        .clear(array_clear),
        .step(array_step),
        .a_left_row0(a_left_row0),
        .a_left_row1(a_left_row1),
        .w_top_col0(w_top_col0),
        .w_top_col1(w_top_col1),
        .sum00(sum00),
        .sum01(sum01),
        .sum10(sum10),
        .sum11(sum11)
    );

    vpu_2x2 vpu (
        .clk(clk),
        .rst(rst),
        .result_write_enable(result_write_enable),
        .bias_vector(bias_vector),
        .sum00(sum00),
        .sum01(sum01),
        .sum10(sum10),
        .sum11(sum11),
        .result_matrix(result_matrix)
    );
endmodule
