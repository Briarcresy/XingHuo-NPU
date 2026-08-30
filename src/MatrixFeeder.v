`timescale 1ns / 1ps

// 将扁平的 2x2 矩阵端口转换为脉动阵列所需的逐拍边界输入。
// 本模块相当于教学版的输入 Buffer/调度器，只负责数据排布，不保存部分和。
module MatrixFeeder (
    input [ 1:0] phase,
    input [31:0] activation_matrix,
    input [31:0] weight_matrix,

    output reg signed [7:0] a_left_row0,
    output reg signed [7:0] a_left_row1,
    output reg signed [7:0] w_top_col0,
    output reg signed [7:0] w_top_col1
);
    // 每个矩阵元素都是8位二补码INT8；总线从低位到高位为00、01、10、11。
    wire signed [7:0] activation_00;
    wire signed [7:0] activation_01;
    wire signed [7:0] activation_10;
    wire signed [7:0] activation_11;
    wire signed [7:0] weight_00;
    wire signed [7:0] weight_01;
    wire signed [7:0] weight_10;
    wire signed [7:0] weight_11;

    assign activation_00 = activation_matrix[7:0];
    assign activation_01 = activation_matrix[15:8];
    assign activation_10 = activation_matrix[23:16];
    assign activation_11 = activation_matrix[31:24];
    assign weight_00     = weight_matrix[7:0];
    assign weight_01     = weight_matrix[15:8];
    assign weight_10     = weight_matrix[23:16];
    assign weight_11     = weight_matrix[31:24];

    // 不同行、列按它们到目标 PE 的距离错开进入阵列。
    always @(*) begin
        a_left_row0 = 8'sd0;
        a_left_row1 = 8'sd0;
        w_top_col0  = 8'sd0;
        w_top_col1  = 8'sd0;

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
