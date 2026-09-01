`timescale 1ns / 1ps

// 一个INT8 Systolic Array Processing Element（脉动阵列处理单元，PE）。
// 每拍完成：INT32 Accumulator（累加器）+= INT8 Activation × INT8 Weight。
// Activation向右传播，Weight驻留在本PE，累加结果也保存在本PE内。
module MacPE (
    input clk,
    input rst,
    input clear,
    input enable,
    // NPU1.2 Weight-resident（权重驻留）控制。当前Output Stationary PE完成长度为2
    // 的Dot Product（点积），因此每个Weight Bank保存两个权重。
    input weight_load,
    input weight_switch,
    input weight_select,
    input signed [7:0] shadow_weight_0_in,
    input signed [7:0] shadow_weight_1_in,
    input signed [7:0] activation_in,
    output reg signed [7:0] activation_out,
    output reg signed [31:0] accumulator
);
    reg signed [7:0] active_weight_0;
    reg signed [7:0] active_weight_1;
    reg signed [7:0] shadow_weight_0;
    reg signed [7:0] shadow_weight_1;

    // 两个8位有符号数相乘得到完整的16位有符号乘积。
    // 乘积不做右移、不提前截断，而是先符号扩展到32位再累加，避免损失精度。
    wire signed [15:0] product;
    wire signed [ 7:0] resident_weight;

    assign resident_weight = weight_select ? active_weight_1 : active_weight_0;
    assign product         = activation_in * resident_weight;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            activation_out <= 8'sd0;
            accumulator    <= 32'sd0;
            active_weight_0 <= 8'sd0;
            active_weight_1 <= 8'sd0;
            shadow_weight_0 <= 8'sd0;
            shadow_weight_1 <= 8'sd0;
        end else begin
            // Shadow Bank可在PE计算期间更新，不会影响当前Active Weight。
            if (weight_load) begin
                shadow_weight_0 <= shadow_weight_0_in;
                shadow_weight_1 <= shadow_weight_1_in;
            end

            // 顶层只在Core空闲且Shadow有效时产生weight_switch。
            // load与switch同拍时，Active取得旧Shadow，Shadow取得新输入。
            if (weight_switch) begin
                active_weight_0 <= shadow_weight_0;
                active_weight_1 <= shadow_weight_1;
            end

            // clear只清计算状态，不清Weight Bank，从而允许Weight Reuse（权重复用）。
            if (clear) begin
                activation_out <= 8'sd0;
                accumulator    <= 32'sd0;
            end else if (enable) begin
                activation_out <= activation_in;
                accumulator    <= accumulator + {{16{product[15]}}, product};
            end
        end
    end
endmodule
