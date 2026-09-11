`timescale 1ns / 1ps

// Core控制与状态模块。
//
// 本模块把任务/权重/结果握手、执行时序、错误状态和性能计数集中在一起。
// 数据通路只接收已经解码好的clear、step、phase和write信号，不需要理解
// 外部握手协议；Core顶层也因此只负责连接功能模块。
module CoreController (
    input clk,
    input rst,

    input  start_valid,
    output start_ready,
    input  clear_error,

    input  weight_valid,
    output weight_ready,
    output weight_load,

    output busy,
    output result_valid,
    input  result_ready,

    input bias_overflow,

    output [1:0] phase,
    output       array_clear,
    output       array_step,
    output       result_write_enable,

    output       error,
    output [4:0] error_code,
    output       weights_loaded,
    output reg [15:0] cycle_count,
    output reg [31:0] task_count
);
    wire control_busy;
    wire control_done;
    wire start_fire;

    reg bias_overflow_error;
    reg start_without_weight_error;
    reg weight_valid_reg;
    reg result_valid_reg;
    reg [15:0] current_cycle_count;

    // 外部通道统一采用valid-ready握手；真正改变状态的事件用fire/load表示。
    assign busy         = control_busy || result_valid_reg;
    assign start_ready  = !busy && weight_valid_reg;
    assign start_fire   = start_valid && start_ready;
    assign weight_ready = !busy;
    assign weight_load  = weight_valid && weight_ready;

    assign result_valid   = result_valid_reg;
    assign weights_loaded = weight_valid_reg;
    assign error_code = {1'b0, start_without_weight_error,
                         1'b0, bias_overflow_error, 1'b0};
    assign error = |error_code;

    // ComputeSequencer只描述一次矩阵任务内部的执行顺序。
    ComputeSequencer compute_sequencer (
        .clk(clk),
        .rst(rst),
        .start(start_fire),
        .busy(control_busy),
        .done(control_done),
        .phase(phase),
        .array_clear(array_clear),
        .array_step(array_step),
        .result_write_enable(result_write_enable)
    );

    // 每类Sticky Error使用独立寄存器。事件置位优先于软件清除，避免同拍漏错。
    always @(posedge clk) begin
        if (rst) bias_overflow_error <= 1'b0;
        else if (result_write_enable && bias_overflow) bias_overflow_error <= 1'b1;
        else if (clear_error) bias_overflow_error <= 1'b0;
    end

    always @(posedge clk) begin
        if (rst) start_without_weight_error <= 1'b0;
        else if (start_valid && !busy && !weight_valid_reg)
            start_without_weight_error <= 1'b1;
        else if (clear_error) start_without_weight_error <= 1'b0;
    end

    // 单Bank有效位：复位后必须先在空闲状态装载一次完整权重矩阵。
    always @(posedge clk) begin
        if (rst) weight_valid_reg <= 1'b0;
        else if (weight_load) weight_valid_reg <= 1'b1;
    end

    // 结果产生后保持valid，直到下游以ready完成握手。
    always @(posedge clk) begin
        if (rst) result_valid_reg <= 1'b0;
        else if (result_write_enable) result_valid_reg <= 1'b1;
        else if (result_valid_reg && result_ready) result_valid_reg <= 1'b0;
    end

    // 运行周期计数饱和于16'hffff，成功完成时保存最近一次延迟。
    always @(posedge clk) begin
        if (rst) current_cycle_count <= 16'd0;
        else if (start_fire) current_cycle_count <= 16'd0;
        else if (busy && current_cycle_count != 16'hffff)
            current_cycle_count <= current_cycle_count + 1'b1;
    end

    always @(posedge clk) begin
        if (rst) cycle_count <= 16'd0;
        else if (control_done) cycle_count <= current_cycle_count;
    end

    // 成功完成任务的总数按32位自然回绕。
    always @(posedge clk) begin
        if (rst) task_count <= 32'd0;
        else if (control_done) task_count <= task_count + 1'b1;
    end
endmodule
