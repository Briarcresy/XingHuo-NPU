`timescale 1ns / 1ps

// Result Collector（结果收集器）把阵列右边界按周期流出的结果重新组合为2×2矩阵。
module ResultCollector (
    input clk,
    input rst,
    input clear,
    input signed [31:0] result_col0_stream,
    input result_col0_valid,
    input signed [31:0] result_col1_stream,
    input result_col1_valid,
    output reg signed [31:0] sum00,
    output reg signed [31:0] sum01,
    output reg signed [31:0] sum10,
    output reg signed [31:0] sum11
);
    reg result_col0_index;
    reg result_col1_index;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sum00 <= 32'sd0;
            sum01 <= 32'sd0;
            sum10 <= 32'sd0;
            sum11 <= 32'sd0;
            result_col0_index <= 1'b0;
            result_col1_index <= 1'b0;
        end else if (clear) begin
            sum00 <= 32'sd0;
            sum01 <= 32'sd0;
            sum10 <= 32'sd0;
            sum11 <= 32'sd0;
            result_col0_index <= 1'b0;
            result_col1_index <= 1'b0;
        end else begin
            if (result_col0_valid) begin
                if (!result_col0_index) sum00 <= result_col0_stream;
                else sum10 <= result_col0_stream;
                result_col0_index <= 1'b1;
            end
            if (result_col1_valid) begin
                if (!result_col1_index) sum01 <= result_col1_stream;
                else sum11 <= result_col1_stream;
                result_col1_index <= 1'b1;
            end
        end
    end
endmodule
