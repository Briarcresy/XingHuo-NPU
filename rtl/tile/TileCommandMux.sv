// 根据已经完成交接的实际模式，选择唯一一组网络控制命令。
module TileCommandMux (
    input  logic       external_mode,
    input  logic       manual_start_programmable,
    input  logic       manual_start_demo,
    input  logic [1:0] manual_demo_input,
    input  logic       manual_clear_status,
    input  logic       host_start_programmable,
    input  logic       host_start_demo,
    input  logic [1:0] host_demo_input,
    input  logic       host_clear_status,
    output logic       controller_start_programmable,
    output logic       controller_start_demo,
    output logic [1:0] controller_demo_input,
    output logic       controller_clear_status
);
    always_comb begin
        if (external_mode) begin
            controller_start_programmable = host_start_programmable;
            controller_start_demo         = host_start_demo;
            controller_demo_input         = host_demo_input;
            controller_clear_status       = host_clear_status;
        end else begin
            controller_start_programmable = manual_start_programmable;
            controller_start_demo         = manual_start_demo;
            controller_demo_input         = manual_demo_input;
            controller_clear_status       = manual_clear_status;
        end
    end
endmodule
