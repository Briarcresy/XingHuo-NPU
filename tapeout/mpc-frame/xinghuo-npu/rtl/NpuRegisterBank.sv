// NPU软件可见寄存器组。
//
// 本模块解释寄存器地址，把8位SPI数据拼成NPU Core需要的并行输入，并将
// Core状态和结果转换成8位读数据。它不依赖SPI时序，将来可以在保持本模块
// 和Core不变的情况下，把SpiSlave换成APB或AXI-Lite适配器。
module NpuRegisterBank (
    input wire clock,
    input wire reset,

    // 来自SpiSlave的内部寄存器接口。
    input  wire [6:0] register_read_address,
    input  wire [6:0] register_write_address,
    input  wire [7:0] register_write_data,
    input  wire       register_write_enable,
    output reg  [7:0] register_read_data,

    // 与NPU Core连接的原生并行接口。
    output reg  [31:0] activation_matrix,
    output reg  [31:0] weight_matrix,
    output reg  [63:0] bias_vector,
    output reg  [ 4:0] quant_shift,
    output reg         core_start,
    input  wire        core_busy,
    input  wire        core_done,
    input  wire [31:0] result_matrix,
    output wire        interrupt
);
    // ---------------------------------------------------------------------
    // 1. 软件可见地址表
    // ---------------------------------------------------------------------
    // 多字节数据采用小端地址顺序：低地址保存低8位。
    localparam [6:0] ADDR_ACT0 = 7'h00;
    localparam [6:0] ADDR_ACT1 = 7'h01;
    localparam [6:0] ADDR_ACT2 = 7'h02;
    localparam [6:0] ADDR_ACT3 = 7'h03;

    localparam [6:0] ADDR_WGT0 = 7'h04;
    localparam [6:0] ADDR_WGT1 = 7'h05;
    localparam [6:0] ADDR_WGT2 = 7'h06;
    localparam [6:0] ADDR_WGT3 = 7'h07;

    localparam [6:0] ADDR_BIAS0 = 7'h08;
    localparam [6:0] ADDR_BIAS1 = 7'h09;
    localparam [6:0] ADDR_BIAS2 = 7'h0a;
    localparam [6:0] ADDR_BIAS3 = 7'h0b;
    localparam [6:0] ADDR_BIAS4 = 7'h0c;
    localparam [6:0] ADDR_BIAS5 = 7'h0d;
    localparam [6:0] ADDR_BIAS6 = 7'h0e;
    localparam [6:0] ADDR_BIAS7 = 7'h0f;

    localparam [6:0] ADDR_SHIFT = 7'h10;
    localparam [6:0] ADDR_CONTROL = 7'h11;
    localparam [6:0] ADDR_STATUS = 7'h12;

    localparam [6:0] ADDR_RESULT0 = 7'h14;
    localparam [6:0] ADDR_RESULT1 = 7'h15;
    localparam [6:0] ADDR_RESULT2 = 7'h16;
    localparam [6:0] ADDR_RESULT3 = 7'h17;

    // ---------------------------------------------------------------------
    // 2. 操作数和量化参数寄存器
    // ---------------------------------------------------------------------
    // Core忙时忽略这些写操作，保证一次计算期间输入保持稳定。
    wire operand_write_enable = register_write_enable && !core_busy;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            activation_matrix <= 32'd0;
            weight_matrix <= 32'd0;
            bias_vector <= 64'd0;
            quant_shift <= 5'd0;
        end else if (operand_write_enable) begin
            case (register_write_address)
                ADDR_ACT0: activation_matrix[7:0] <= register_write_data;
                ADDR_ACT1: activation_matrix[15:8] <= register_write_data;
                ADDR_ACT2: activation_matrix[23:16] <= register_write_data;
                ADDR_ACT3: activation_matrix[31:24] <= register_write_data;

                ADDR_WGT0: weight_matrix[7:0] <= register_write_data;
                ADDR_WGT1: weight_matrix[15:8] <= register_write_data;
                ADDR_WGT2: weight_matrix[23:16] <= register_write_data;
                ADDR_WGT3: weight_matrix[31:24] <= register_write_data;

                ADDR_BIAS0: bias_vector[7:0] <= register_write_data;
                ADDR_BIAS1: bias_vector[15:8] <= register_write_data;
                ADDR_BIAS2: bias_vector[23:16] <= register_write_data;
                ADDR_BIAS3: bias_vector[31:24] <= register_write_data;
                ADDR_BIAS4: bias_vector[39:32] <= register_write_data;
                ADDR_BIAS5: bias_vector[47:40] <= register_write_data;
                ADDR_BIAS6: bias_vector[55:48] <= register_write_data;
                ADDR_BIAS7: bias_vector[63:56] <= register_write_data;

                ADDR_SHIFT: quant_shift <= register_write_data[4:0];
                default: begin
                    // CONTROL等非操作数地址由其他逻辑处理。
                end
            endcase
        end
    end

    // ---------------------------------------------------------------------
    // 3. Core控制与完成状态
    // ---------------------------------------------------------------------
    // core_done可能只持续一个clock，SPI主机可能错过，因此锁存成interrupt。
    // CONTROL.bit0=start，CONTROL.bit1=clear_done。
    reg done_latched;
    assign interrupt = done_latched;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            core_start   <= 1'b0;
            done_latched <= 1'b0;
        end else begin
            // start默认每拍清零，因此软件一次写入只产生一个clock宽的脉冲。
            core_start <= 1'b0;

            if (core_done) done_latched <= 1'b1;

            if (register_write_enable && (register_write_address == ADDR_CONTROL)) begin
                if (register_write_data[1]) done_latched <= 1'b0;

                if (register_write_data[0] && !core_busy) begin
                    core_start   <= 1'b1;
                    done_latched <= 1'b0;
                end
            end
        end
    end

    // ---------------------------------------------------------------------
    // 4. 组合读回多路选择器
    // ---------------------------------------------------------------------
    // 不增加读等待周期；未定义地址返回0，避免X值进入SPI发送移位寄存器。
    always @(*) begin
        case (register_read_address)
            ADDR_ACT0: register_read_data = activation_matrix[7:0];
            ADDR_ACT1: register_read_data = activation_matrix[15:8];
            ADDR_ACT2: register_read_data = activation_matrix[23:16];
            ADDR_ACT3: register_read_data = activation_matrix[31:24];

            ADDR_WGT0: register_read_data = weight_matrix[7:0];
            ADDR_WGT1: register_read_data = weight_matrix[15:8];
            ADDR_WGT2: register_read_data = weight_matrix[23:16];
            ADDR_WGT3: register_read_data = weight_matrix[31:24];

            ADDR_BIAS0: register_read_data = bias_vector[7:0];
            ADDR_BIAS1: register_read_data = bias_vector[15:8];
            ADDR_BIAS2: register_read_data = bias_vector[23:16];
            ADDR_BIAS3: register_read_data = bias_vector[31:24];
            ADDR_BIAS4: register_read_data = bias_vector[39:32];
            ADDR_BIAS5: register_read_data = bias_vector[47:40];
            ADDR_BIAS6: register_read_data = bias_vector[55:48];
            ADDR_BIAS7: register_read_data = bias_vector[63:56];

            ADDR_SHIFT:  register_read_data = {3'd0, quant_shift};
            // STATUS.bit0=busy，bit1=done_latched，其余位保留为0。
            ADDR_STATUS: register_read_data = {6'd0, done_latched, core_busy};

            ADDR_RESULT0: register_read_data = result_matrix[7:0];
            ADDR_RESULT1: register_read_data = result_matrix[15:8];
            ADDR_RESULT2: register_read_data = result_matrix[23:16];
            ADDR_RESULT3: register_read_data = result_matrix[31:24];
            default:      register_read_data = 8'd0;
        endcase
    end
endmodule
