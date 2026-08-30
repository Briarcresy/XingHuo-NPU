`timescale 1ns / 1ps

// ReLU 激活单元。
// 负数和零输出 0；超过 16 位有符号 Q8.8 正数上限时饱和为 0x7fff；
// 其余数值直接保留低 16 位。该行为与拆分前的 q8_8_bias_relu 完全一致。
module ReLU (
    input signed [31:0] data_in,
    output reg signed [15:0] data_out
);
    always @(*) begin
        if (data_in <= 0) data_out = 16'sh0000;
        else if (data_in > 32'sh7fff) data_out = 16'sh7fff;
        else data_out = data_in[15:0];
    end
endmodule
