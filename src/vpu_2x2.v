`timescale 1ns/1ps

// 教学版推理 VPU。
// 参考原 tiny-tpu 的 VPU/child 分层：本模块组织四路数据，标量运算由
// q8_8_bias_add 和 q8_8_relu 子模块完成，并在 result_write_enable 时锁存完整输出矩阵。
module vpu_2x2 (
    input  clk,
    input  rst,
    input  result_write_enable,
    input  [31:0]             bias_vector,
    input  signed [31:0]      sum00,
    input  signed [31:0]      sum01,
    input  signed [31:0]      sum10,
    input  signed [31:0]      sum11,
    output reg  [63:0]             result_matrix
);
    wire signed [15:0] bias_0;
    wire signed [15:0] bias_1;
    wire signed [31:0] biased_sum_00;
    wire signed [31:0] biased_sum_01;
    wire signed [31:0] biased_sum_10;
    wire signed [31:0] biased_sum_11;
    wire signed [15:0] result_00_next;
    wire signed [15:0] result_01_next;
    wire signed [15:0] result_10_next;
    wire signed [15:0] result_11_next;

    assign bias_0 = bias_vector[15:0];
    assign bias_1 = bias_vector[31:16];

    // 第一阶段：Bias 按列广播，第 0 列使用 bias_0，第 1 列使用 bias_1。
    q8_8_bias_add bias_add_00 (
        .sum_in(sum00), .bias_in(bias_0), .biased_sum_out(biased_sum_00)
    );
    q8_8_bias_add bias_add_01 (
        .sum_in(sum01), .bias_in(bias_1), .biased_sum_out(biased_sum_01)
    );
    q8_8_bias_add bias_add_10 (
        .sum_in(sum10), .bias_in(bias_0), .biased_sum_out(biased_sum_10)
    );
    q8_8_bias_add bias_add_11 (
        .sum_in(sum11), .bias_in(bias_1), .biased_sum_out(biased_sum_11)
    );

    // 第二阶段：分别对加完 Bias 的四个矩阵元素执行 ReLU 和正数饱和。
    q8_8_relu relu_00 (
        .data_in(biased_sum_00), .data_out(result_00_next)
    );
    q8_8_relu relu_01 (
        .data_in(biased_sum_01), .data_out(result_01_next)
    );
    q8_8_relu relu_10 (
        .data_in(biased_sum_10), .data_out(result_10_next)
    );
    q8_8_relu relu_11 (
        .data_in(biased_sum_11), .data_out(result_11_next)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_matrix <= 64'd0;
        end else if (result_write_enable) begin
            result_matrix[15:0]  <= result_00_next;
            result_matrix[31:16] <= result_01_next;
            result_matrix[47:32] <= result_10_next;
            result_matrix[63:48] <= result_11_next;
        end
    end
endmodule
