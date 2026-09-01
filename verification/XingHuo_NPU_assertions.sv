`timescale 1ns / 1ps

// NPU1.1周期级接口断言。该文件只参与验证，不进入正式RTL filelist和综合流程。
module XingHuo_NPU_assertions (
    input logic        clk,
    input logic        rst,
    input logic        start,
    input logic        clear_error,
    input logic        busy,
    input logic        done,
    input logic        error,
    input logic [7:0]  error_code,
    input logic [15:0] cycle_count,
    input logic [31:0] task_count
);
    // error必须始终等于所有具体错误位的归约或。
    assert property (@(posedge clk) error == (|error_code))
        else $error("error summary does not match error_code");

    // done出现时任务已经离开busy状态。
    assert property (@(posedge clk) disable iff (rst) done |-> !busy)
        else $error("done and busy asserted together");

    // 空闲时接受start，下一个周期必须进入busy。
    assert property (@(posedge clk) disable iff (rst)
        (start && !busy) |=> busy)
        else $error("accepted start did not enter busy");

    // busy期间的start不会重启任务，而是在下一周期留下粘滞错误。
    assert property (@(posedge clk) disable iff (rst)
        (start && busy) |=> error_code[0])
        else $error("start while busy was not reported");

    // 当前2x2实现的最近任务周期数固定为6；计数器在done后的时钟沿锁存。
    assert property (@(posedge clk) disable iff (rst)
        done |=> cycle_count == 16'd6)
        else $error("completed task cycle count is not 6");

    // 每个done只把累计任务数增加一次。
    assert property (@(posedge clk) disable iff (rst)
        done |=> task_count == ($past(task_count) + 1'b1))
        else $error("task_count did not increment after done");

    // NPU1.1只定义低两位，保留位必须一直为0。
    assert property (@(posedge clk) error_code[7:2] == 6'd0)
        else $error("reserved error bits are non-zero");

    // clear_error本身不允许改变busy，也不承担任务复位功能。
    assert property (@(posedge clk) disable iff (rst)
        (clear_error && busy) |=> busy || done)
        else $error("clear_error interrupted the active task");
endmodule

bind XingHuo_NPU XingHuo_NPU_assertions npu11_assertions (
    .clk(clk),
    .rst(rst),
    .start(start),
    .clear_error(clear_error),
    .busy(busy),
    .done(done),
    .error(error),
    .error_code(error_code),
    .cycle_count(cycle_count),
    .task_count(task_count)
);
