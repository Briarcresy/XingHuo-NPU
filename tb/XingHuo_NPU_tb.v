`timescale 1ns / 1ps

// 星火NPU的自检行为仿真。
// 测试数据都直接使用整数编码，因此不依赖Python或外部模型。
module XingHuo_NPU_tb;
    reg clk;
    reg rst;
    reg start;
    reg [31:0] activation_matrix;
    reg [31:0] weight_matrix;
    reg [63:0] bias_vector;
    reg [4:0] quant_shift;
    wire busy;
    wire done;
    wire [31:0] result_matrix;

    integer failures;

    XingHuo_NPU dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(busy),
        .done(done),
        .result_matrix(result_matrix)
    );

    always #5 clk = ~clk;

    // 启动一次运算并检查打包后的四个INT8结果。
    task run_and_check;
        input [31:0] expected;
        input [255:0] case_name;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done == 1'b1);
            #1;
            if (result_matrix !== expected) begin
                $display("FAIL: %0s expected=%h actual=%h", case_name, expected, result_matrix);
                failures = failures + 1;
            end else begin
                $display("PASS: %0s result=%h", case_name, result_matrix);
            end
            @(negedge clk);
        end
    endtask

    initial begin
        clk               = 1'b0;
        rst               = 1'b1;
        start             = 1'b0;
        activation_matrix = 32'd0;
        weight_matrix     = 32'd0;
        bias_vector       = 64'd0;
        quant_shift       = 5'd0;
        failures          = 0;

        repeat (2) @(negedge clk);
        rst = 1'b0;

        // A=[[1,2],[3,4]], W=[[5,6],[7,8]]。
        // A*W=[[19,22],[43,50]]；按列Bias=[1,-2]后为[[20,20],[44,48]]。
        activation_matrix = {8'sd4, 8'sd3, 8'sd2, 8'sd1};
        weight_matrix     = {8'sd8, 8'sd7, 8'sd6, 8'sd5};
        bias_vector       = {-32'sd2, 32'sd1};
        quant_shift       = 5'd0;
        run_and_check({8'd48, 8'd44, 8'd20, 8'd20}, "basic_int8_matmul");

        // 相同累加值右移1位，验证重量化路径：[[10,10],[22,24]]。
        quant_shift = 5'd1;
        run_and_check({8'd24, 8'd22, 8'd10, 8'd10}, "requantize_shift");

        // 极大负Bias应在重量化后被ReLU钳位为0。
        bias_vector = {-32'sd100, -32'sd100};
        quant_shift = 5'd0;
        run_and_check(32'h00000000, "relu_negative_to_zero");

        if (failures == 0) begin
            $display("ALL TESTS PASSED");
            $finish;
        end else begin
            // $fatal属于SystemVerilog；为保持Verilog-2005兼容，使用display和finish。
            $display("ERROR: %0d test(s) failed", failures);
            $finish;
        end
    end
endmodule
