`timescale 1ns / 1ps

// 一个INT8脉动阵列处理单元（PE）。
// 每拍完成：INT32 accumulator += INT8 activation * INT8 weight。
// activation 向右传，weight 向下传，累加结果保存在本 PE 内。
module MacPE (
    input clk,
    input rst,
    input clear,
    input enable,
    input signed [7:0] activation_in,
    input signed [7:0] weight_in,
    output reg signed [7:0] activation_out,
    output reg signed [7:0] weight_out,
    output reg signed [31:0] accumulator
);
    // 两个8位有符号数相乘得到完整的16位有符号乘积。
    // 乘积不做右移、不提前截断，而是先符号扩展到32位再累加，避免损失精度。
    wire signed [15:0] product;

    assign product = activation_in * weight_in;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            activation_out <= 8'sd0;
            weight_out     <= 8'sd0;
            accumulator    <= 32'sd0;
        end else if (clear) begin
            activation_out <= 8'sd0;
            weight_out     <= 8'sd0;
            accumulator    <= 32'sd0;
        end else if (enable) begin
            activation_out <= activation_in;
            weight_out     <= weight_in;
            accumulator    <= accumulator + {{16{product[15]}}, product};
        end
    end
endmodule
