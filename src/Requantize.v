`timescale 1ns / 1ps

// INT32到INT8的重量化单元。
//
// 完整的神经网络INT8量化常写成：
//   output_int8 = saturate(round(accumulator * scale) + zero_point)
//
// 本教学版采用低面积的“对称、2的幂缩放”方案：
//   zero_point = 0
//   scale       = 1 / 2^shift
// 因此硬件只需右移、舍入和饱和，不需要额外的32位乘法器。
module Requantize (
    input  signed     [31:0] data_in,
    input             [ 4:0] shift,
    output reg signed [ 7:0] data_out
);
    reg signed [32:0] data_extended;
    reg signed [32:0] rounding_offset;
    reg signed [32:0] shifted_value;

    always @(*) begin
        // 多扩展一位，避免正数加舍入偏置时在32位边界溢出。
        data_extended   = {data_in[31], data_in};
        rounding_offset = 33'sd0;

        if (shift == 0) begin
            shifted_value = data_extended;
        end else begin
            // 加上半个量化步长后再算术右移，实现就近舍入；半值向正方向舍入。
            rounding_offset = 33'sd1 <<< (shift - 1'b1);
            shifted_value   = (data_extended + rounding_offset) >>> shift;
        end

        // 将结果饱和到INT8的合法范围[-128, 127]，避免直接截断产生回绕。
        if (shifted_value > 33'sd127) data_out = 8'sd127;
        else if (shifted_value < -33'sd128) data_out = -8'sd128;
        else data_out = shifted_value[7:0];
    end
endmodule
