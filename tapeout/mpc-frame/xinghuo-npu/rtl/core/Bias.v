

// INT8量化数据通路的Bias加法单元。
// INT8乘法使用INT32累加器，因此Bias也直接使用INT32，并且必须与累加器采用
// 相同的量化尺度。软件侧通常计算：bias_int32 = round(real_bias / (Sa * Sw))。

module Bias (
    input  signed [31:0] sum_in,
    input  signed [31:0] bias_in,
    output signed [31:0] biased_sum_out
);
    assign biased_sum_out = sum_in + bias_in;
endmodule
