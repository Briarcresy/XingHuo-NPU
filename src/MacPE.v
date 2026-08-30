`timescale 1ns / 1ps

// 一个最小的脉动阵列处理单元（PE）。
// 每拍完成：acc = acc + activation * weight。
// activation 向右传，weight 向下传，累加结果保存在本 PE 内。


module MacPE (
    input  clk,
    input  rst,
    input  clear,
    input  enable,
    input  signed [15:0] activation_in,
    input  signed [15:0] weight_in,
    output reg signed  [15:0] activation_out,
    output reg signed  [15:0] weight_out,
    output reg signed  [31:0] accumulator
);
    // Q8.8 × Q8.8 得到 Q16.16；算术右移 8 位后恢复为 Q8.8。
    reg signed [31:0] product_q16_16;
    reg signed [31:0] product_q8_8;

    always @(*) begin
        product_q16_16 = activation_in * weight_in;
        product_q8_8   = product_q16_16 >>> 8;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            activation_out <= 16'sd0;
            weight_out     <= 16'sd0;
            accumulator    <= 32'sd0;
        end else if (clear) begin
            activation_out <= 16'sd0;
            weight_out     <= 16'sd0;
            accumulator    <= 32'sd0;
        end else if (enable) begin
            activation_out <= activation_in;
            weight_out     <= weight_in;
            accumulator    <= accumulator + product_q8_8;
        end
    end
endmodule
