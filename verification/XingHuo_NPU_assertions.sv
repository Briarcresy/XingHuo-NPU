`timescale 1ns / 1ps

// NPU Core的ready-valid协议与周期级行为断言。仅参与验证，不进入综合。
module XingHuo_NPU_assertions (
    input logic clk, rst,
    input logic start_valid, start_ready, clear_error,
    input logic weight_valid, weight_ready,
    input logic busy, result_valid, result_ready,
    input logic [31:0] result_matrix,
    input logic error,
    input logic [4:0] error_code,
    input logic [15:0] cycle_count,
    input logic [31:0] task_count,
    input logic weights_loaded
);
    assert property (@(posedge clk) error == (|error_code))
        else $error("error summary does not match error_code");

    // 背压时，生产者必须保持valid和payload，直至ready完成握手。
    assert property (@(posedge clk) disable iff (rst)
        (result_valid && !result_ready) |=>
        (result_valid && $stable(result_matrix)))
        else $error("result changed while stalled");

    assert property (@(posedge clk)
        result_valid |-> (busy && !start_ready && !weight_ready))
        else $error("pending result did not block new requests");

    assert property (@(posedge clk) disable iff (rst)
        (start_valid && start_ready) |=> busy)
        else $error("accepted start did not enter busy");
    assert property (@(posedge clk) disable iff (rst)
        result_valid |=> cycle_count == 16'd7)
        else $error("completed task cycle count is not 7");
    assert property (@(posedge clk) disable iff (rst)
        (result_valid && !$past(result_valid))
        |=> task_count == ($past(task_count) + 1'b1))
        else $error("task_count did not increment once for a result");
    assert property (@(posedge clk) disable iff (rst)
        (start_valid && !busy && !weights_loaded)
        |=> (!busy && error_code[3]))
        else $error("resident start without weight was not rejected");
    assert property (@(posedge clk) disable iff (rst)
        (weight_valid && weight_ready) |=> weights_loaded)
        else $error("accepted weight did not validate the single bank");
endmodule

bind XingHuo_NPU XingHuo_NPU_assertions core_assertions (
    .clk(clk), .rst(rst),
    .start_valid(start_valid), .start_ready(start_ready),
    .clear_error(clear_error),
    .weight_valid(weight_valid), .weight_ready(weight_ready),
    .busy(busy), .result_valid(result_valid), .result_ready(result_ready),
    .result_matrix(result_matrix), .error(error), .error_code(error_code),
    .cycle_count(cycle_count), .task_count(task_count),
    .weights_loaded(weights_loaded)
);
