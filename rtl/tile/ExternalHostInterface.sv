// External Host Mode（外部主机模式）命令接口。
// 主机先稳定payload/opcode/mode，再翻转request，并保持到ack与request相等。
module ExternalHostInterface (
    input  logic        clock,
    input  logic        reset,
    input  logic        enable,
    input  logic        network_busy,
    input  logic [15:0] custom_in_async,
    input  logic [ 7:0] ram_read_data,
    output logic        external_mode_request,
    output logic [ 7:0] ram_address,
    output logic        ram_write_request,
    output logic [ 7:0] ram_write_data,
    output logic        start_programmable,
    output logic        start_demo,
    output logic [ 1:0] demo_input,
    output logic        clear_status,
    output logic [ 7:0] read_data,
    output logic        acknowledge_toggle
);
    localparam logic [2:0] OP_SET_ADDRESS = 3'd0;
    localparam logic [2:0] OP_WRITE_BYTE  = 3'd1;
    localparam logic [2:0] OP_READ_NEXT   = 3'd2;
    localparam logic [2:0] OP_START       = 3'd3;
    localparam logic [2:0] OP_START_DEMO  = 3'd4;
    localparam logic [2:0] OP_CLEAR       = 3'd5;

    (* ASYNC_REG = "TRUE" *) logic [15:0] custom_in_meta;
    (* ASYNC_REG = "TRUE" *) logic [15:0] custom_in_sync;
    logic [7:0] address_pointer;
    logic [7:0] write_address;
    logic write_pending;
    logic pending_request_toggle;

    wire [7:0] payload = custom_in_sync[7:0];
    wire request_toggle = custom_in_sync[8];
    wire [2:0] opcode = custom_in_sync[11:9];

    assign external_mode_request = custom_in_sync[15];
    always_comb begin
        if (ram_write_request) ram_address = write_address;
        else ram_address = address_pointer;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            custom_in_meta      <= '0;
            custom_in_sync      <= '0;
            address_pointer     <= 8'h00;
            write_address       <= 8'h00;
            ram_write_request   <= 1'b0;
            ram_write_data      <= 8'h00;
            start_programmable  <= 1'b0;
            start_demo          <= 1'b0;
            demo_input          <= 2'b00;
            clear_status        <= 1'b0;
            read_data           <= 8'h00;
            acknowledge_toggle  <= 1'b0;
            write_pending       <= 1'b0;
            pending_request_toggle <= 1'b0;
        end else begin
            custom_in_meta <= custom_in_async;
            custom_in_sync <= custom_in_meta;

            ram_write_request  <= 1'b0;
            start_programmable <= 1'b0;
            start_demo         <= 1'b0;
            clear_status       <= 1'b0;

            // 写应答延迟到下一个上升沿：此时外部Shared RAM已经采样写请求。
            if (write_pending) begin
                write_pending      <= 1'b0;
                acknowledge_toggle <= pending_request_toggle;
            end else if (enable && !network_busy
                && (request_toggle != acknowledge_toggle)) begin
                case (opcode)
                    OP_SET_ADDRESS: begin
                        address_pointer <= payload;
                        acknowledge_toggle <= request_toggle;
                    end
                    OP_WRITE_BYTE: begin
                        ram_write_data    <= payload;
                        write_address     <= address_pointer;
                        ram_write_request <= 1'b1;
                        address_pointer   <= address_pointer + 1'b1;
                        write_pending     <= 1'b1;
                        pending_request_toggle <= request_toggle;
                    end
                    OP_READ_NEXT: begin
                        read_data  <= ram_read_data;
                        address_pointer <= address_pointer + 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    OP_START: begin
                        start_programmable <= 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    OP_START_DEMO: begin
                        demo_input <= payload[1:0];
                        start_demo <= 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    OP_CLEAR: begin
                        clear_status <= 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    default: begin
                        acknowledge_toggle <= request_toggle;
                    end
                endcase
            end
        end
    end
endmodule
