`timescale 1ns / 1ps


// INT8量化数据通路的Bias加法单元。
// INT8乘法使用INT32 Accumulator（累加器），因此Bias也直接使用INT32，并且必须与Accumulator采用
// 相同的量化尺度。软件侧通常计算：bias_int32 = round(real_bias / (Sa * Sw))。

module Bias (
    input  signed [31:0] sum_in,
    input  signed [31:0] bias_in,
    output signed [31:0] biased_sum_out,
    output               overflow
);
    assign biased_sum_out = sum_in + bias_in;

    // Two's-complement Overflow（二补码溢出）：两个操作数同号，但结果与操作数异号。
    // 数据结果仍保持NPU1.0定义的低32位回绕；overflow只负责报告数值事件。
    assign overflow = ~(sum_in[31] ^ bias_in[31])
                    &  (biased_sum_out[31] ^ sum_in[31]);
endmodule
