`timescale 1ns / 1ps

// 教学用对称INT8纯推理星火NPU顶层（IEEE Verilog-2005）。
// 计算：Y_int8 = ReLU(Requantize(A_int8 x W_int8 + bias_int32))。
// A/W/Y均为2x2；Bias按列广播；zero-point固定为0。
//
// 顶层只连接各功能模块，不在这里实现具体算法：
// control -> feeder -> systolic array -> VPU。
module XingHuo_NPU (
    input clk,
    input rst,
    input start,
    // 清除粘滞错误标志；不影响当前计算、结果和性能计数器。
    input clear_error,

    // A和W每个元素为8位有符号INT8，从低位到高位依次为00、01、10、11。
    input [31:0] activation_matrix,
    input [31:0] weight_matrix,
    // 两个INT32 Bias从低位到高位依次为bias0、bias1，分别广播到输出第0/1列。
    input [63:0] bias_vector,
    // 输出重量化右移位数。一层内四个输出共用，0表示不缩放，范围0～31。
    input [4:0] quant_shift,

    output busy,
    output done,
    // 四个INT8结果从低位到高位依次为00、01、10、11。
    output [31:0] result_matrix,

    // NPU1.1可观测性接口。error_code[0]表示busy期间收到start；
    // error_code[1]表示至少一路Bias INT32加法发生二补码溢出，其余位保留为0。
    output       error,
    output [7:0] error_code,
    // 最近一个成功任务从接受start到产生done所经历的Core工作周期数。
    output reg [15:0] cycle_count,
    // 复位以来成功完成的任务总数；自然按32位回绕。
    output reg [31:0] task_count
);
    // 控制通路信号。
    wire        [ 1:0] phase;
    wire               array_clear;
    wire               array_step;
    wire               result_write_enable;

    // Feeder 到脉动阵列的四路边界数据。
    wire signed [7:0] a_left_row0;
    wire signed [7:0] a_left_row1;
    wire signed [7:0] w_top_col0;
    wire signed [7:0] w_top_col1;

    // 脉动阵列保存的四个 32 位输出部分和。
    wire signed [31:0] sum00;
    wire signed [31:0] sum01;
    wire signed [31:0] sum10;
    wire signed [31:0] sum11;
    wire               bias_overflow;

    reg start_while_busy_error;
    reg bias_overflow_error;
    reg [15:0] current_cycle_count;

    assign error_code = {6'd0, bias_overflow_error, start_while_busy_error};
    assign error      = |error_code;

    ControlUnit control_unit (
        .clk(clk),
        .rst(rst),
        .start(start),
        .busy(busy),
        .done(done),
        .phase(phase),
        .array_clear(array_clear),
        .array_step(array_step),
        .result_write_enable(result_write_enable)
    );

    MatrixFeeder matrix_feeder (
        .phase(phase),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .a_left_row0(a_left_row0),
        .a_left_row1(a_left_row1),
        .w_top_col0(w_top_col0),
        .w_top_col1(w_top_col1)
    );

    SystolicArray systolic_array (
        .clk(clk),
        .rst(rst),
        .clear(array_clear),
        .step(array_step),
        .a_left_row0(a_left_row0),
        .a_left_row1(a_left_row1),
        .w_top_col0(w_top_col0),
        .w_top_col1(w_top_col1),
        .sum00(sum00),
        .sum01(sum01),
        .sum10(sum10),
        .sum11(sum11)
    );

    VPU vpu (
        .clk(clk),
        .rst(rst),
        .result_write_enable(result_write_enable),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .sum00(sum00),
        .sum01(sum01),
        .sum10(sum10),
        .sum11(sum11),
        .result_matrix(result_matrix),
        .bias_overflow(bias_overflow)
    );

    // 错误位采用粘滞语义：事件发生后保持为1，直到clear_error或复位。
    // 重复start不会打断正在执行的任务，ControlUnit会继续原有计算。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_while_busy_error <= 1'b0;
            bias_overflow_error    <= 1'b0;
        end else begin
            if (clear_error) begin
                start_while_busy_error <= 1'b0;
                bias_overflow_error    <= 1'b0;
            end
            if (start && busy) start_while_busy_error <= 1'b1;
            if (result_write_enable && bias_overflow) bias_overflow_error <= 1'b1;
        end
    end

    // 性能计数只观察通用Core握手，不依赖任何流片平台。接受start时从0开始，
    // busy期间每周期加1；done脉冲到来时锁存最近任务周期数并累计任务数。
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            current_cycle_count <= 16'd0;
            cycle_count         <= 16'd0;
            task_count          <= 32'd0;
        end else begin
            if (start && !busy) current_cycle_count <= 16'd0;
            else if (busy && current_cycle_count != 16'hffff)
                current_cycle_count <= current_cycle_count + 1'b1;

            if (done) begin
                cycle_count <= current_cycle_count;
                task_count  <= task_count + 1'b1;
            end
        end
    end
endmodule
