
// INT8 ReLU激活单元。
// ReLU(x)=max(0,x)。重量化模块已经负责INT8饱和，因此这里仅处理正负号。
module ReLU (
    input signed [7:0] data_in,
    output reg signed [7:0] data_out
);
    always @(*) begin
        if (data_in <= 0) data_out = 8'sd0;
        else data_out = data_in;
    end
endmodule
