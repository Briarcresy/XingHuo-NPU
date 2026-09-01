`timescale 1ns / 1ps

// 用定向激励触发NPU1.1断言，包括正常任务、重复start和clear_error。
module XingHuo_NPU_sva_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;
    logic start = 1'b0;
    logic clear_error = 1'b0;
    logic [31:0] activation_matrix = 32'h04030201;
    logic [31:0] weight_matrix = 32'h08070605;
    logic [63:0] bias_vector = 64'hfffffffe00000001;
    logic [4:0] quant_shift = 5'd0;
    wire busy;
    wire done;
    wire [31:0] result_matrix;
    wire error;
    wire [7:0] error_code;
    wire [15:0] cycle_count;
    wire [31:0] task_count;

    always #5 clk = ~clk;

    XingHuo_NPU dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .clear_error(clear_error),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(busy),
        .done(done),
        .result_matrix(result_matrix),
        .error(error),
        .error_code(error_code),
        .cycle_count(cycle_count),
        .task_count(task_count)
    );

    initial begin
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // 正常启动，然后在busy期间再次给start，验证任务不会重启且错误被记录。
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (busy);
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done);
        repeat (2) @(posedge clk);

        if (result_matrix !== 32'h302c1414 || !error_code[0])
            $fatal(1, "NPU1.1 directed SVA stimulus produced wrong state");

        @(negedge clk);
        clear_error = 1'b1;
        @(negedge clk);
        clear_error = 1'b0;
        @(posedge clk);
        #1ns;
        if (error || error_code != 8'd0)
            $fatal(1, "clear_error did not clear sticky status");

        $display("NPU1.1 SVA TEST PASS");
        $finish;
    end
endmodule
