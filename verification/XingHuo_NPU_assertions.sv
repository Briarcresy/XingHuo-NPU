`timescale 1ns / 1ps

// 当前NPU Core周期级接口断言。该文件只参与验证，不进入正式综合流程。
module XingHuo_NPU_assertions (
    input logic        clk,
    input logic        rst,
    input logic        start,
    input logic        clear_error,
    input logic        weight_load,
    input logic        busy,
    input logic        done,
    input logic        error,
    input logic [4:0]  error_code,
    input logic [15:0] cycle_count,
    input logic [31:0] task_count,
    input logic        weight_valid
);
    // error必须始终等于所有具体错误位的归约或。
    assert property (@(posedge clk) error == (|error_code))
        else $error("error summary does not match error_code");

    // done出现时任务已经离开busy状态。
    assert property (@(posedge clk) disable iff (rst) done |-> !busy)
        else $error("done and busy asserted together");

    // 空闲时接受start，下一个周期必须进入busy。
    assert property (@(posedge clk) disable iff (rst)
        (start && !busy && weight_valid) |=> busy)
        else $error("accepted start did not enter busy");

    // busy期间的start不会重启任务，而是在下一周期留下Sticky Error（粘滞错误）。
    assert property (@(posedge clk) disable iff (rst)
        (start && busy) |=> error_code[0])
        else $error("start while busy was not reported");

    // True Weight Stationary实现包含COLLECT阶段，最近任务周期数固定为7。
    assert property (@(posedge clk) disable iff (rst)
        done |=> cycle_count == 16'd7)
        else $error("completed task cycle count is not 7");

    // 每个done只把累计任务数增加一次。
    assert property (@(posedge clk) disable iff (rst)
        done |=> task_count == ($past(task_count) + 1'b1))
        else $error("task_count did not increment after done");

    // clear_error本身不允许改变busy，也不承担任务复位功能。
    assert property (@(posedge clk) disable iff (rst)
        (clear_error && busy) |=> busy || done)
        else $error("clear_error interrupted the active task");

    // 当前权重未准备好时，Weight-resident Mode（权重驻留模式）启动必须被拒绝。
    assert property (@(posedge clk) disable iff (rst)
        (start && !busy && !weight_valid)
        |=> (!busy && error_code[3]))
        else $error("resident start without weight was not rejected");

    // 单Bank在busy期间不允许更新权重。
    assert property (@(posedge clk) disable iff (rst)
        (weight_load && busy) |=> error_code[2])
        else $error("weight load while busy was not reported");

    // 空闲时装载一拍后当前权重必须有效。
    assert property (@(posedge clk) disable iff (rst)
        (weight_load && !busy) |=> weight_valid)
        else $error("weight load did not validate the single bank");
endmodule

bind XingHuo_NPU XingHuo_NPU_assertions core_assertions (
    .clk(clk),
    .rst(rst),
    .start(start),
    .clear_error(clear_error),
    .weight_load(weight_load),
    .busy(busy),
    .done(done),
    .error(error),
    .error_code(error_code),
    .cycle_count(cycle_count),
    .task_count(task_count),
    .weight_valid(weight_valid)
);
