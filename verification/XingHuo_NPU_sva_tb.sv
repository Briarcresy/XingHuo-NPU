`timescale 1ns / 1ps

// 用定向激励触发NPU1.1/1.2断言，包括错误状态、权重装载、切换和驻留计算。
module XingHuo_NPU_sva_tb;
    logic clk;
    logic rst;
    logic start;
    logic clear_error;
    logic weight_load;
    logic weight_switch;
    logic [31:0] activation_matrix;
    logic [31:0] weight_matrix;
    logic [63:0] bias_vector;
    logic [4:0] quant_shift;
    wire busy;
    wire done;
    wire [31:0] result_matrix;
    wire error;
    wire [7:0] error_code;
    wire [15:0] cycle_count;
    wire [31:0] task_count;
    wire active_weight_valid;
    wire shadow_weight_valid;

    // 单一Clock Generator（时钟发生进程），避免声明初始化和always块同时驱动clk。
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    XingHuo_NPU dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .clear_error(clear_error),
        .weight_load(weight_load),
        .weight_switch(weight_switch),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(busy),
        .done(done),
        .result_matrix(result_matrix),
        .error(error),
        .error_code(error_code),
        .active_weight_valid(active_weight_valid),
        .shadow_weight_valid(shadow_weight_valid),
        .cycle_count(cycle_count),
        .task_count(task_count)
    );

    initial begin
        rst                    = 1'b1;
        start                  = 1'b0;
        clear_error            = 1'b0;
        weight_load            = 1'b0;
        weight_switch          = 1'b0;
        activation_matrix      = 32'h04030201;
        weight_matrix          = 32'h08070605;
        bias_vector            = 64'hfffffffe00000001;
        quant_shift            = 5'd0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // 纯Weight-resident Mode必须先装Shadow，再Atomic Switch（原子切换）为Active。
        @(negedge clk);
        weight_load = 1'b1;
        @(negedge clk);
        weight_load = 1'b0;
        if (!shadow_weight_valid) $fatal(1, "shadow weight was not loaded");

        weight_switch = 1'b1;
        @(negedge clk);
        weight_switch = 1'b0;
        if (!active_weight_valid || shadow_weight_valid)
            $fatal(1, "weight bank switch produced wrong validity");

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

        // 不重新加载权重，再次使用Active Weight验证Weight Reuse（权重复用）。
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done);
        repeat (2) @(posedge clk);
        if (result_matrix !== 32'h302c1414)
            $fatal(1, "resident weight result is incorrect");

        $display("NPU1.2 SVA TEST PASS");
        $finish;
    end
endmodule
