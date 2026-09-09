// 在手动控制与外部主机控制之间安全切换所有权。
// 只有网络空闲且两侧都没有尚待消费的单周期事件时，实际模式才跟随请求。
module TileModeController (
    input  logic clock,
    input  logic reset,
    input  logic external_mode_request,
    input  logic network_busy,
    input  logic manual_ram_write_request,
    input  logic host_ram_write_request,
    input  logic manual_start_programmable,
    input  logic manual_start_demo,
    input  logic host_start_programmable,
    input  logic host_start_demo,
    input  logic manual_clear_status,
    input  logic host_clear_status,
    output logic external_mode,
    output logic manual_enable,
    output logic host_enable
);
    logic handoff_ready;

    always_comb begin
        handoff_ready = !network_busy
                     && !manual_ram_write_request
                     && !host_ram_write_request
                     && !manual_start_programmable
                     && !manual_start_demo
                     && !host_start_programmable
                     && !host_start_demo
                     && !manual_clear_status
                     && !host_clear_status;
        // 请求改变期间先关闭旧接口，完成交接后再打开新接口。
        manual_enable = !external_mode && !external_mode_request;
        host_enable   = external_mode && external_mode_request;
    end

    always_ff @(posedge clock) begin
        if (reset) external_mode <= 1'b0;
        else if (handoff_ready) external_mode <= external_mode_request;
    end
endmodule
