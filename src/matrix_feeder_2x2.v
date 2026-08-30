`timescale 1ns / 1ps

// 将扁平的 2x2 矩阵端口转换为脉动阵列所需的逐拍边界输入。
// 本模块相当于教学版的输入 Buffer/调度器，只负责数据排布，不保存部分和。
module matrix_feeder_2x2 (
    input [ 1:0] phase,
    input [63:0] activation_matrix,
    input [63:0] weight_matrix,

    output reg signed [15:0] a_left_row0,
    output reg signed [15:0] a_left_row1,
    output reg signed [15:0] w_top_col0,
    output reg signed [15:0] w_top_col1
);
    // 总线元素顺序从低位到高位为 00、01、10、11。
    wire signed [15:0] activation_00;
    wire signed [15:0] activation_01;
    wire signed [15:0] activation_10;
    wire signed [15:0] activation_11;
    wire signed [15:0] weight_00;
    wire signed [15:0] weight_01;
    wire signed [15:0] weight_10;
    wire signed [15:0] weight_11;

    assign activation_00 = activation_matrix[15:0];
    assign activation_01 = activation_matrix[31:16];
    assign activation_10 = activation_matrix[47:32];
    assign activation_11 = activation_matrix[63:48];
    assign weight_00     = weight_matrix[15:0];
    assign weight_01     = weight_matrix[31:16];
    assign weight_10     = weight_matrix[47:32];
    assign weight_11     = weight_matrix[63:48];

    // 不同行、列按它们到目标 PE 的距离错开进入阵列。
    always @(*) begin
        a_left_row0 = 16'sd0;
        a_left_row1 = 16'sd0;
        w_top_col0  = 16'sd0;
        w_top_col1  = 16'sd0;

        case (phase)
            2'd0: begin
                a_left_row0 = activation_00;
                w_top_col0  = weight_00;
            end

            2'd1: begin
                a_left_row0 = activation_01;
                a_left_row1 = activation_10;
                w_top_col0  = weight_10;
                w_top_col1  = weight_01;
            end

            2'd2: begin
                a_left_row1 = activation_11;
                w_top_col1  = weight_11;
            end

            default: begin
                // phase 3 注入 0，让阵列内部最后一组数据完成传播。
            end
        endcase
    end
endmodule
