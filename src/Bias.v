`timescale 1ns / 1ps


// Bias 加法单元。
// sum_in 是采用 Q8.8 数值尺度的 32 位累加结果，bias_in 是 16 位 Q8.8。
// 先对 bias 做符号扩展，再与 sum_in 相加；输出仍保留 32 位，避免提前截断。

module Bias (
    input  signed [31:0] sum_in,
    input  signed [15:0] bias_in,
    output signed [31:0] biased_sum_out
);
    wire signed [31:0] bias_extended;

    assign bias_extended  = {{16{bias_in[15]}}, bias_in};
    assign biased_sum_out = sum_in + bias_extended;
endmodule
