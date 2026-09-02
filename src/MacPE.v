`timescale 1ns / 1ps

// True Weight Stationary（真正的权重固定）Processing Element（处理单元，PE）。
// 每个PE只保存一个Active Weight和一个Shadow Weight：Activation纵向传播，
// INT32 Partial Sum（部分和）横向传播。
module MacPE (
    input clk,
    input rst,
    input clear,
    input enable,
    input weight_load,
    input weight_switch,
    input signed [7:0] shadow_weight_in,
    input signed [7:0] activation_in,
    input activation_valid_in,
    output reg signed [7:0] activation_out,
    output reg activation_valid_out,
    input signed [31:0] partial_sum_in,
    input partial_sum_valid_in,
    output reg signed [31:0] partial_sum_out,
    output reg partial_sum_valid_out
);
    reg signed [7:0] active_weight;
    reg signed [7:0] shadow_weight;

    wire signed [15:0] product;
    wire signed [31:0] product_extended;
    wire compute_valid;

    assign product = activation_in * active_weight;
    assign product_extended = {{16{product[15]}}, product};
    assign compute_valid = activation_valid_in && partial_sum_valid_in;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active_weight         <= 8'sd0;
            shadow_weight         <= 8'sd0;
            activation_out        <= 8'sd0;
            activation_valid_out  <= 1'b0;
            partial_sum_out       <= 32'sd0;
            partial_sum_valid_out <= 1'b0;
        end else begin
            if (weight_load) shadow_weight <= shadow_weight_in;
            if (weight_switch) active_weight <= shadow_weight;

            // clear只清流水数据，不清Weight Bank，从而允许跨任务Weight Reuse。
            if (clear) begin
                activation_out        <= 8'sd0;
                activation_valid_out  <= 1'b0;
                partial_sum_out       <= 32'sd0;
                partial_sum_valid_out <= 1'b0;
            end else if (enable) begin
                activation_out        <= activation_in;
                activation_valid_out  <= activation_valid_in;
                partial_sum_valid_out <= compute_valid;
                if (compute_valid) partial_sum_out <= partial_sum_in + product_extended;
            end else begin
                activation_valid_out  <= 1'b0;
                partial_sum_valid_out <= 1'b0;
            end
        end
    end
endmodule
