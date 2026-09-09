// Shared RAM固定优先级仲裁器：运行中的网络控制器 > 外部主机 > 手动控制器。
module TileRamArbiter (
    input  logic       reset,
    input  logic       network_busy,
    input  logic       external_mode,
    input  logic [7:0] controller_address,
    input  logic       controller_write_enable,
    input  logic [7:0] controller_write_data,
    input  logic [7:0] host_address,
    input  logic       host_write_request,
    input  logic [7:0] host_write_data,
    input  logic [7:0] manual_address,
    input  logic       manual_write_request,
    input  logic [7:0] manual_write_data,
    output logic [7:0] ram_address,
    output logic       ram_write_enable,
    output logic [7:0] ram_write_data
);
    always_comb begin
        if (network_busy) begin
            ram_address      = controller_address;
            ram_write_enable = controller_write_enable;
            ram_write_data   = controller_write_data;
        end else if (external_mode) begin
            ram_address      = host_address;
            ram_write_enable = host_write_request;
            ram_write_data   = host_write_data;
        end else begin
            ram_address      = manual_address;
            ram_write_enable = manual_write_request;
            ram_write_data   = manual_write_data;
        end
        // 平台RAM未必随Tile复位，复位采样沿禁止遗留写操作。
        if (reset) ram_write_enable = 1'b0;
    end
endmodule
