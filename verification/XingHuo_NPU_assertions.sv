`timescale 1ns / 1ps

// NPU1.1/1.2周期级接口断言。该文件只参与验证，不进入正式RTL filelist和综合流程。
module XingHuo_NPU_assertions (
    input logic        clk,
    input logic        rst,
    input logic        start,
    input logic        clear_error,
    input logic        weight_load,
    input logic        weight_switch,
    input logic        busy,
    input logic        done,
    input logic        error,
    input logic [7:0]  error_code,
    input logic [15:0] cycle_count,
    input logic [31:0] task_count,
    input logic        active_weight_valid,
    input logic        shadow_weight_valid
);
    // error必须始终等于所有具体错误位的归约或。
    assert property (@(posedge clk) error == (|error_code))
        else $error("error summary does not match error_code");

    // done出现时任务已经离开busy状态。
    assert property (@(posedge clk) disable iff (rst) done |-> !busy)
        else $error("done and busy asserted together");

    // 空闲时接受start，下一个周期必须进入busy。
    assert property (@(posedge clk) disable iff (rst)
        (start && !busy && active_weight_valid) |=> busy)
        else $error("accepted start did not enter busy");

    // busy期间的start不会重启任务，而是在下一周期留下Sticky Error（粘滞错误）。
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

    // NPU1.2定义低五位，保留位必须一直为0。
    assert property (@(posedge clk) error_code[7:5] == 3'd0)
        else $error("reserved error bits are non-zero");

    // clear_error本身不允许改变busy，也不承担任务复位功能。
    assert property (@(posedge clk) disable iff (rst)
        (clear_error && busy) |=> busy || done)
        else $error("clear_error interrupted the active task");

    // Active Weight未准备好时，Weight-resident Mode（权重驻留模式）启动必须被拒绝。
    assert property (@(posedge clk) disable iff (rst)
        (start && !busy && !active_weight_valid)
        |=> (!busy && error_code[3]))
        else $error("resident start without active weight was not rejected");

    // busy期间不允许切换active权重。
    assert property (@(posedge clk) disable iff (rst)
        (weight_switch && busy) |=> error_code[2])
        else $error("weight switch while busy was not reported");

    // 空闲但shadow无效时，切换请求也必须留下错误。
    assert property (@(posedge clk) disable iff (rst)
        (weight_switch && !busy && !shadow_weight_valid) |=> error_code[4])
        else $error("weight switch without shadow was not reported");

    // 单独load一拍后shadow必须有效；合法switch后active有效且shadow被消费。
    assert property (@(posedge clk) disable iff (rst)
        (weight_load && !weight_switch) |=> shadow_weight_valid)
        else $error("weight load did not validate shadow bank");
    assert property (@(posedge clk) disable iff (rst)
        (weight_switch && !busy && shadow_weight_valid && !weight_load)
        |=> (active_weight_valid && !shadow_weight_valid))
        else $error("legal weight switch did not update bank validity");
endmodule

bind XingHuo_NPU XingHuo_NPU_assertions npu12_assertions (
    .clk(clk),
    .rst(rst),
    .start(start),
    .clear_error(clear_error),
    .weight_load(weight_load),
    .weight_switch(weight_switch),
    .busy(busy),
    .done(done),
    .error(error),
    .error_code(error_code),
    .cycle_count(cycle_count),
    .task_count(task_count),
    .active_weight_valid(active_weight_valid),
    .shadow_weight_valid(shadow_weight_valid)
);
