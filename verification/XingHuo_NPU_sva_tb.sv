`timescale 1ns / 1ps

// 定向验证Core的请求握手、结果背压、错误状态和单Bank权重复用。
module XingHuo_NPU_sva_tb;
    logic clk, rst;
    logic start_valid, clear_error, weight_valid, result_ready;
    logic [31:0] activation_matrix, weight_matrix;
    logic [63:0] bias_vector;
    logic [4:0] quant_shift;
    wire start_ready, weight_ready, busy, result_valid;
    wire [31:0] result_matrix;
    wire error;
    wire [4:0] error_code;
    wire [15:0] cycle_count;
    wire [31:0] task_count;
    wire weights_loaded;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    XingHuo_NPU dut (
        .clk(clk), .rst(rst),
        .start_valid(start_valid), .start_ready(start_ready),
        .clear_error(clear_error),
        .weight_valid(weight_valid), .weight_ready(weight_ready),
        .activation_matrix(activation_matrix), .weight_matrix(weight_matrix),
        .bias_vector(bias_vector), .quant_shift(quant_shift),
        .busy(busy), .result_valid(result_valid), .result_ready(result_ready),
        .result_matrix(result_matrix), .error(error), .error_code(error_code),
        .weights_loaded(weights_loaded), .cycle_count(cycle_count),
        .task_count(task_count)
    );

    initial begin
        rst = 1'b1;
        start_valid = 1'b0;
        clear_error = 1'b0;
        weight_valid = 1'b0;
        result_ready = 1'b0;
        activation_matrix = 32'h04030201;
        weight_matrix = 32'h08070605;
        bias_vector = 64'hfffffffe00000001;
        quant_shift = 5'd0;

        repeat (3) @(posedge clk);
        @(negedge clk) rst = 1'b0;

        @(negedge clk) weight_valid = 1'b1;
        @(negedge clk) weight_valid = 1'b0;
        if (!weights_loaded) $fatal(1, "single-bank weight was not loaded");

        @(negedge clk) start_valid = 1'b1;
        @(negedge clk) start_valid = 1'b0;
        wait (busy);
        @(negedge clk) begin
            start_valid = 1'b1;
        end
        @(negedge clk) begin
            start_valid = 1'b0;
        end

        // 下游故意停三拍；结果与valid必须保持，且Core继续占用。
        wait (result_valid);
        repeat (3) begin
            @(posedge clk); #1ns;
            if (!result_valid || !busy || result_matrix !== 32'h302c1414)
                $fatal(1, "result channel did not hold under backpressure");
        end
        if (error_code[0])
            $fatal(1, "legal valid-before-ready request was treated as an error");

        @(negedge clk) result_ready = 1'b1;
        @(posedge clk); #1ns;
        if (result_valid || busy) $fatal(1, "result handshake did not release Core");

        @(negedge clk) clear_error = 1'b1;
        @(negedge clk) clear_error = 1'b0;
        @(posedge clk); #1ns;
        if (error || error_code != 5'd0)
            $fatal(1, "clear_error did not clear sticky status");

        // 第二次运行验证驻留权重复用。
        @(negedge clk) start_valid = 1'b1;
        @(negedge clk) start_valid = 1'b0;
        wait (result_valid);
        if (result_matrix !== 32'h302c1414)
            $fatal(1, "resident weight result is incorrect");
        @(posedge clk); #1ns;

        $display("NPU CORE SVA TEST PASS");
        $finish;
    end
endmodule
