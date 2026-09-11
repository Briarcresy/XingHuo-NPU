`timescale 1ns / 1ps

// 教学用对称INT8纯推理星火NPU顶层（IEEE Verilog-2005）。
// 计算：Y_int8 = ReLU(Requantize(A_int8 x W_int8 + bias_int32))。
// A/W/Y均为2x2；Bias按列广播；zero-point固定为0。
//
// 顶层只连接各功能模块，不在这里实现具体算法：
// control -> feeder -> systolic array -> result collector -> VPU。
module XingHuo_NPU (
    input clk,
    input rst,
    input start_valid,
    output start_ready,
    // 清除Sticky Error（粘滞错误）；不影响当前计算、结果和Performance Counter。
    input clear_error,
    // Weight-resident（权重驻留）请求通道：握手后更新各PE的当前权重。
    input weight_valid,
    output weight_ready,

    // A和W每个元素为8位有符号INT8，从低位到高位依次为00、01、10、11。
    input [31:0] activation_matrix,
    input [31:0] weight_matrix,
    // 两个INT32 Bias从低位到高位依次为bias0、bias1，分别广播到输出第0/1列。
    input [63:0] bias_vector,
    // 输出重量化右移位数。一层内四个输出共用，0表示不缩放，范围0～31。
    input [4:0] quant_shift,

    output busy,
    output result_valid,
    input  result_ready,
    // 四个INT8结果从低位到高位依次为00、01、10、11。
    output [31:0] result_matrix,

    // 可观测性接口；各错误位定义见docs/interfaces.md。
    output       error,
    // bit1=bias overflow，bit3=start without weight；其余位保留为0。
    output [4:0] error_code,
    output       weights_loaded,
    // 最近一个成功任务从接受start到产生结果所经历的Core工作周期数。
    output [15:0] cycle_count,
    // 复位以来成功完成的任务总数；自然按32位回绕。
    output [31:0] task_count
);
    // 控制通路信号。
    wire        [ 1:0] phase;
    wire               array_clear;
    wire               array_step;
    wire               result_write_enable;
    wire               weight_load;

    wire signed [7:0] activation_top_col0;
    wire signed [7:0] activation_top_col1;
    wire activation_valid_col0;
    wire activation_valid_col1;
    wire signed [31:0] result_col0_stream;
    wire signed [31:0] result_col1_stream;
    wire result_col0_valid;
    wire result_col1_valid;

    // Systolic Array保存的四个32位输出Partial Sum（部分和）。
    wire signed [31:0] sum00;
    wire signed [31:0] sum01;
    wire signed [31:0] sum10;
    wire signed [31:0] sum11;
    wire               bias_overflow;

    CoreController core_controller (
        .clk(clk),
        .rst(rst),
        .start_valid(start_valid),
        .start_ready(start_ready),
        .clear_error(clear_error),
        .weight_valid(weight_valid),
        .weight_ready(weight_ready),
        .weight_load(weight_load),
        .busy(busy),
        .result_valid(result_valid),
        .result_ready(result_ready),
        .bias_overflow(bias_overflow),
        .phase(phase),
        .array_clear(array_clear),
        .array_step(array_step),
        .result_write_enable(result_write_enable),
        .error(error),
        .error_code(error_code),
        .weights_loaded(weights_loaded),
        .cycle_count(cycle_count),
        .task_count(task_count)
    );

    MatrixFeeder matrix_feeder (
        .phase(phase),
        .activation_matrix(activation_matrix),
        .activation_top_col0(activation_top_col0),
        .activation_top_col1(activation_top_col1),
        .activation_valid_col0(activation_valid_col0),
        .activation_valid_col1(activation_valid_col1)
    );

    SystolicArray systolic_array (
        .clk(clk),
        .rst(rst),
        .clear(array_clear),
        .step(array_step),
        .weight_load(weight_load),
        .weight_matrix(weight_matrix),
        .activation_top_col0(activation_top_col0),
        .activation_top_col1(activation_top_col1),
        .activation_valid_col0(activation_valid_col0),
        .activation_valid_col1(activation_valid_col1),
        .result_col0_stream(result_col0_stream),
        .result_col0_valid(result_col0_valid),
        .result_col1_stream(result_col1_stream),
        .result_col1_valid(result_col1_valid)
    );

    ResultCollector result_collector (
        .clk(clk),
        .rst(rst),
        .clear(array_clear),
        .result_col0_stream(result_col0_stream),
        .result_col0_valid(result_col0_valid),
        .result_col1_stream(result_col1_stream),
        .result_col1_valid(result_col1_valid),
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

endmodule
