`timescale 1ns / 1ps

// True Weight Stationary（真正的权重固定）Processing Element（处理单元，PE）。
// 每个PE保存一个当前权重：Activation纵向传播，INT32 Partial Sum（部分和）横向传播。
module MacPE (
    input clk,
    input rst,
    input clear,
    input enable,
    input weight_load,
    input signed [7:0] weight_in,
    input signed [7:0] activation_in,
    input activation_valid_in,
    output reg signed [7:0] activation_out,
    output reg activation_valid_out,
    input signed [31:0] partial_sum_in,
    input partial_sum_valid_in,
    output reg signed [31:0] partial_sum_out,
    output reg partial_sum_valid_out
);
    reg signed [7:0] weight;

    wire signed [15:0] product;
    wire signed [31:0] product_extended;
    wire compute_valid;
    wire pipeline_fire;

    assign product = activation_in * weight;
    assign product_extended = {{16{product[15]}}, product};
    assign compute_valid = activation_valid_in && partial_sum_valid_in;
    // pipeline_fire表示本级在这个时钟沿接收一笔有效MAC事务。valid与数据沿
    // 相同寄存器边界传播，这是流式数据通路最基本的控制方法。
    assign pipeline_fire = enable && compute_valid;

    // 驻留权重有独立的写使能，不与流水寄存器的clear/enable混在一起。
    always @(posedge clk) begin
        if (rst) weight <= 8'sd0;
        else if (weight_load) weight <= weight_in;
    end

    // 流水寄存器统一推进或清空；clear不影响上面的驻留权重。
    always @(posedge clk) begin
        if (rst) begin
            activation_out        <= 8'sd0;
            activation_valid_out  <= 1'b0;
            partial_sum_out       <= 32'sd0;
            partial_sum_valid_out <= 1'b0;
        end else if (clear) begin
                activation_out        <= 8'sd0;
                activation_valid_out  <= 1'b0;
                partial_sum_out       <= 32'sd0;
                partial_sum_valid_out <= 1'b0;
        end else if (enable) begin
                activation_out        <= activation_in;
                activation_valid_out  <= activation_valid_in;
                partial_sum_valid_out <= pipeline_fire;
                if (pipeline_fire) partial_sum_out <= partial_sum_in + product_extended;
        end else begin
                activation_valid_out  <= 1'b0;
                partial_sum_valid_out <= 1'b0;
        end
    end
endmodule
