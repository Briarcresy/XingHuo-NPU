// External Host Mode（外部主机模式）命令接口。
// 主机先稳定payload/opcode/mode，再翻转request，并保持到ack与request相等。
module ExternalHostInterface (
    input  logic        clock,                // Tile工作时钟。
    input  logic        reset,                // 同步高有效复位。
    input  logic        enable,               // 外部模式交接完成后允许执行命令。
    input  logic        network_busy,         // 忙时保留请求，空闲后再处理。
    input  logic [15:0] custom_in_sync,       // 已同步的模式/Opcode/Toggle/Payload总线。
    input  logic [ 7:0] ram_read_data,        // 当前ram_address对应的异步读数据。
    output logic        external_mode_request,// custom_in_sync[15]的同步模式请求。
    output logic [ 7:0] ram_address,           // 主机当前访问的共享RAM地址。
    output logic        ram_write_request,     // WRITE_BYTE产生的单周期写请求。
    output logic [ 7:0] ram_write_data,        // WRITE_BYTE锁存的数据。
    output logic        start_programmable,   // START产生的单周期脉冲。
    output logic        start_demo,           // START_DEMO产生的单周期脉冲。
    output logic [ 1:0] demo_input,            // START_DEMO锁存的Payload低2位。
    output logic        clear_status,          // CLEAR产生的单周期脉冲。
    output logic [ 7:0] read_data,             // 最近READ_NEXT锁存的数据。
    output logic        acknowledge_toggle     // 完成事务后回送的应答Toggle。
);
    import TileTypesPkg::*;

    // Opcode占customIn[11:9]；6和7未定义，但仍正常应答，避免主机死等。

    logic [7:0] address_pointer; // 顺序访问指针，读写后自然8-bit回绕。
    logic [7:0] write_address;   // 写请求发出时锁存的旧地址。
    logic write_pending;         // 等待共享RAM在上升沿实际采样本次写请求。
    logic pending_request_toggle;// 与待完成写事务配套的请求Toggle。

    wire [7:0] payload = custom_in_sync[7:0];   // 命令数据字段。
    wire request_toggle = custom_in_sync[8];    // 每条新命令翻转一次。
    wire host_opcode_t opcode = host_opcode_t'(custom_in_sync[11:9]); // 命令类型。

    // 在Tile内部显式采用主流valid-ready命名：valid表示存在未完成请求，ready
    // 表示当前周期能够接收。fire只在两者同时为1时成立。外部CDC仍使用Toggle，
    // 因为普通valid-ready本身不能安全跨异步边界。
    wire command_valid = (request_toggle != acknowledge_toggle);
    wire command_ready = enable && !network_busy && !write_pending;
    wire command_fire  = command_valid && command_ready;

    assign external_mode_request = custom_in_sync[15];
    always_comb begin
        // 写请求期间使用锁存地址；其余时间让异步读口跟随地址指针。
        if (ram_write_request) ram_address = write_address;
        else ram_address = address_pointer;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
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
            // 命令输出均为单周期事件，默认撤销。
            ram_write_request  <= 1'b0;
            start_programmable <= 1'b0;
            start_demo         <= 1'b0;
            clear_status       <= 1'b0;

            // 写应答延迟到下一个上升沿：此时外部Shared RAM已经采样写请求。
            if (write_pending) begin
                write_pending      <= 1'b0;
                acknowledge_toggle <= pending_request_toggle;
            end else if (command_fire) begin
                // Request与ACK不同表示存在一条尚未执行的新命令。协议要求主机在
                // ACK返回前保持Opcode、Payload、模式和Request不变。
                case (opcode)
                    HOST_OP_SET_ADDRESS: begin
                        address_pointer <= payload;
                        acknowledge_toggle <= request_toggle;
                    end
                    HOST_OP_WRITE_BYTE: begin
                        ram_write_data    <= payload;
                        write_address     <= address_pointer;
                        ram_write_request <= 1'b1;
                        address_pointer   <= address_pointer + 1'b1;
                        write_pending     <= 1'b1;
                        pending_request_toggle <= request_toggle;
                    end
                    HOST_OP_READ_NEXT: begin
                        read_data  <= ram_read_data;
                        address_pointer <= address_pointer + 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    HOST_OP_START: begin
                        start_programmable <= 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    HOST_OP_START_DEMO: begin
                        demo_input <= payload[1:0];
                        start_demo <= 1'b1;
                        acknowledge_toggle <= request_toggle;
                    end
                    HOST_OP_CLEAR: begin
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
