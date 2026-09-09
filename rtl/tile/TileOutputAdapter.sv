// 把内部显示值、主机响应和运行状态打包到固定的MPSoC-Digital Tile端口。
module TileOutputAdapter (
    input  logic [7:0] led_value,
    input  logic [3:0] hex_low,
    input  logic [3:0] hex_high,
    input  logic [7:0] host_read_data,
    input  logic       host_acknowledge_toggle,
    input  logic       network_busy,
    input  logic       network_done,
    input  logic       core_busy,
    input  logic       network_error,
    input  logic       classification,
    input  logic       external_mode,
    output logic [7:0] io_led,
    output logic       io_ledUpdate,
    output logic [3:0] io_hex7seg_0,
    output logic [3:0] io_hex7seg_1,
    output logic       io_hex7segUpdate,
    output logic [15:0] io_customOut
);
    always_comb begin
        io_led           = led_value;
        io_ledUpdate     = 1'b1;
        io_hex7seg_0     = hex_low;
        io_hex7seg_1     = hex_high;
        io_hex7segUpdate = 1'b1;
        io_customOut     = {1'b1, external_mode, classification, network_error,
                            core_busy, network_done, network_busy,
                            host_acknowledge_toggle, host_read_data};
    end
endmodule
