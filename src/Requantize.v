`timescale 1ns / 1ps

// INT32到INT8的Requantization Unit（重量化单元）。
//
// 完整的神经网络INT8量化常写成：
//   output_int8 = saturate(accumulator * scale + zero_point)
//
// 本教学版采用低面积的“对称、2的幂缩放”方案：
//   zero_point = 0
//   scale       = 1 / 2^shift
// 因此硬件只需Arithmetic Right Shift（算术右移）和Saturation（饱和），
// 不需要舍入加法器或额外的32位乘法器。被移出的低位直接丢弃；对于负数，
// 算术右移向负无穷取整，例如-3 >>> 1 = -2。
module Requantize (
    input  signed     [31:0] data_in,
    input             [ 4:0] shift,
    output reg signed [ 7:0] data_out
);
    reg signed [31:0] shifted_value;

    always @(*) begin
        // data_in声明为signed，因此>>>会复制符号位。shift为0时表达式自然保持原值，
        // 不再需要单独分支，也不会出现计算shift-1导致的负移位量。
        shifted_value = data_in >>> shift;

        // 将结果饱和到INT8的合法范围[-128, 127]，避免直接截断产生回绕。
        if (shifted_value > 32'sd127) data_out = 8'sd127;
        else if (shifted_value < -32'sd128) data_out = -8'sd128;
        else data_out = shifted_value[7:0];
    end
endmodule
