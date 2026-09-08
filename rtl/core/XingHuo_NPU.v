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
    input start,
    // 清除Sticky Error（粘滞错误）；不影响当前计算、结果和Performance Counter。
    input clear_error,
    // Weight-resident（权重驻留）接口：空闲时weight_load直接更新各PE的当前权重。
    input weight_load,

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

    // 可观测性接口；各错误位定义见docs/interfaces.md。
    output       error,
    // bit0=start while busy，bit1=bias overflow，bit2=weight load while busy，
    // bit3=start without weight，bit4保留为0。
    output [4:0] error_code,
    output       weight_valid,
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

    reg start_while_busy_error;
    reg bias_overflow_error;
    reg weight_load_busy_error;
    reg start_without_weight_error;
    reg [15:0] current_cycle_count;
    reg weight_valid_reg;

    // 将命令入口写成常见的valid-ready-fire形式。调用者给出valid；Core根据
    // 当前状态给出ready；只有fire成立的上升沿才真正修改体系状态。
    wire start_valid;
    wire start_ready;
    wire start_fire;
    wire weight_load_valid;
    wire weight_load_ready;
    wire weight_load_fire;

    assign start_valid       = start;
    assign start_ready       = !busy && weight_valid_reg;
    assign start_fire        = start_valid && start_ready;
    assign weight_load_valid = weight_load;
    assign weight_load_ready = !busy;
    assign weight_load_fire  = weight_load_valid && weight_load_ready;
    assign weight_valid = weight_valid_reg;
    assign error_code = {1'b0, start_without_weight_error,
                         weight_load_busy_error, bias_overflow_error,
                         start_while_busy_error};
    assign error      = |error_code;

    ControlUnit control_unit (
        .clk(clk),
        .rst(rst),
        .start(start_fire),
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
        .weight_load(weight_load_fire),
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

    // 每类Sticky Error使用独立寄存器块：事件置位，clear_error或复位清零。
    // 分开后每个块只有一个置位原因，便于审查优先级和在波形中定位来源。
    always @(posedge clk) begin
        if (rst) start_while_busy_error <= 1'b0;
        else if (start && busy) start_while_busy_error <= 1'b1;
        else if (clear_error) start_while_busy_error <= 1'b0;
    end

    always @(posedge clk) begin
        if (rst) bias_overflow_error <= 1'b0;
        else if (result_write_enable && bias_overflow) bias_overflow_error <= 1'b1;
        else if (clear_error) bias_overflow_error <= 1'b0;
    end

    always @(posedge clk) begin
        if (rst) weight_load_busy_error <= 1'b0;
        else if (weight_load && busy) weight_load_busy_error <= 1'b1;
        else if (clear_error) weight_load_busy_error <= 1'b0;
    end

    always @(posedge clk) begin
        if (rst) start_without_weight_error <= 1'b0;
        else if (start && !busy && !weight_valid_reg)
            start_without_weight_error <= 1'b1;
        else if (clear_error) start_without_weight_error <= 1'b0;
    end

    // 单Bank有效位：复位后必须先在空闲状态装载一次完整权重矩阵。
    always @(posedge clk) begin
        if (rst) begin
            weight_valid_reg <= 1'b0;
        end else begin
            if (weight_load_fire) weight_valid_reg <= 1'b1;
        end
    end

    // 当前任务周期计数器只负责运行中的饱和计数。
    always @(posedge clk) begin
        if (rst) begin
            current_cycle_count <= 16'd0;
        end else begin
            if (start_fire) current_cycle_count <= 16'd0;
            else if (busy && current_cycle_count != 16'hffff)
                current_cycle_count <= current_cycle_count + 1'b1;
        end
    end

    // 最近一次延迟只在任务完成事件上锁存。
    always @(posedge clk) begin
        if (rst) cycle_count <= 16'd0;
        else if (done) cycle_count <= current_cycle_count;
    end

    // 完成任务总数是独立事件计数器，按32位自然回绕。
    always @(posedge clk) begin
        if (rst) task_count <= 32'd0;
        else if (done) task_count <= task_count + 1'b1;
    end
endmodule
