
// INT8推理VPU（向量处理单元）。
// 每路依次完成：INT32 Bias加法 -> 重量化到INT8 -> ReLU。
// quant_shift由一层计算共用，以较小硬件代价实现2的幂量化缩放。
module VPU (
    input                clk,
    input                rst,
    input                result_write_enable,
    input         [63:0] bias_vector,
    input         [ 4:0] quant_shift,
    input  signed [31:0] sum00,
    input  signed [31:0] sum01,
    input  signed [31:0] sum10,
    input  signed [31:0] sum11,
    output reg    [31:0] result_matrix
);
    // Bias按输出列广播。每个Bias是INT32，并与MAC累加值处于相同量化尺度。
    wire signed [31:0] bias_0;
    wire signed [31:0] bias_1;
    wire signed [31:0] biased_sum_00;
    wire signed [31:0] biased_sum_01;
    wire signed [31:0] biased_sum_10;
    wire signed [31:0] biased_sum_11;
    wire signed [7:0] requantized_00;
    wire signed [7:0] requantized_01;
    wire signed [7:0] requantized_10;
    wire signed [7:0] requantized_11;
    wire signed [7:0] result_00_next;
    wire signed [7:0] result_01_next;
    wire signed [7:0] result_10_next;
    wire signed [7:0] result_11_next;

    assign bias_0 = bias_vector[31:0];
    assign bias_1 = bias_vector[63:32];

    // 第一阶段：Bias 按列广播，第 0 列使用 bias_0，第 1 列使用 bias_1。
    Bias bias_00 (
        .sum_in(sum00),
        .bias_in(bias_0),
        .biased_sum_out(biased_sum_00)
    );
    Bias bias_01 (
        .sum_in(sum01),
        .bias_in(bias_1),
        .biased_sum_out(biased_sum_01)
    );
    Bias bias_10 (
        .sum_in(sum10),
        .bias_in(bias_0),
        .biased_sum_out(biased_sum_10)
    );
    Bias bias_11 (
        .sum_in(sum11),
        .bias_in(bias_1),
        .biased_sum_out(biased_sum_11)
    );

    // 第二阶段：统一进行右移、舍入和INT8饱和。
    Requantize requantize_00 (
        .data_in(biased_sum_00), .shift(quant_shift), .data_out(requantized_00)
    );
    Requantize requantize_01 (
        .data_in(biased_sum_01), .shift(quant_shift), .data_out(requantized_01)
    );
    Requantize requantize_10 (
        .data_in(biased_sum_10), .shift(quant_shift), .data_out(requantized_10)
    );
    Requantize requantize_11 (
        .data_in(biased_sum_11), .shift(quant_shift), .data_out(requantized_11)
    );

    // 第三阶段：执行ReLU。将该模块与重量化分开，便于以后替换其他激活函数。
    ReLU relu_00 (
        .data_in (requantized_00),
        .data_out(result_00_next)
    );
    ReLU relu_01 (
        .data_in (requantized_01),
        .data_out(result_01_next)
    );
    ReLU relu_10 (
        .data_in (requantized_10),
        .data_out(result_10_next)
    );
    ReLU relu_11 (
        .data_in (requantized_11),
        .data_out(result_11_next)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result_matrix <= 32'd0;
        end else if (result_write_enable) begin
            result_matrix[7:0]   <= result_00_next;
            result_matrix[15:8]  <= result_01_next;
            result_matrix[23:16] <= result_10_next;
            result_matrix[31:24] <= result_11_next;
        end
    end
endmodule
