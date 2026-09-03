`timescale 1ns / 1ps

// Activation Skew Feeder（激活错拍馈送器）。第1个K列比第0个K列晚一拍注入，
// 使Activation与从左侧传来的Partial Sum在每个PE处对齐。
module MatrixFeeder (
    input [1:0] phase,
    input [31:0] activation_matrix,
    output reg signed [7:0] activation_top_col0,
    output reg signed [7:0] activation_top_col1,
    output reg activation_valid_col0,
    output reg activation_valid_col1
);
    wire signed [7:0] activation_00;
    wire signed [7:0] activation_01;
    wire signed [7:0] activation_10;
    wire signed [7:0] activation_11;

    assign activation_00 = activation_matrix[7:0];
    assign activation_01 = activation_matrix[15:8];
    assign activation_10 = activation_matrix[23:16];
    assign activation_11 = activation_matrix[31:24];

    always @(*) begin
        activation_top_col0   = 8'sd0;
        activation_top_col1   = 8'sd0;
        activation_valid_col0 = 1'b0;
        activation_valid_col1 = 1'b0;
        case (phase)
            2'd0: begin
                activation_top_col0   = activation_00;
                activation_valid_col0 = 1'b1;
            end
            2'd1: begin
                activation_top_col0   = activation_10;
                activation_top_col1   = activation_01;
                activation_valid_col0 = 1'b1;
                activation_valid_col1 = 1'b1;
            end
            2'd2: begin
                activation_top_col1   = activation_11;
                activation_valid_col1 = 1'b1;
            end
            default: begin
                // phase 3只排空Pipeline（流水线）。
            end
        endcase
    end
endmodule
