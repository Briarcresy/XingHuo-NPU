// SPI Mode 0从机：把串行SPI事务转换成简单的8位寄存器读写接口。
//
// 事务格式（MSB first）：
//   写：{1'b1, address[6:0]}，随后发送一个或多个数据字节；
//   读：{1'b0, address[6:0]}，随后继续提供时钟并读取MISO。
// 每完成一个数据字节，地址自动加1，支持连续访问。
//
// SCLK不直接作为内部时钟，而由clock过采样。clock至少应为SCLK的4倍，
// 实际建议8倍以上。这样整个用户设计只有一个内部时钟域，更容易综合和约束。
module SpiSlave (
    input wire clock,
    input wire reset,

    // 芯片外部SPI引脚。
    input  wire spi_sclk,
    input  wire spi_cs_n,
    input  wire spi_mosi,
    output wire spi_miso,
    output wire spi_miso_oe,

    // 与NpuRegisterBank连接的内部寄存器接口。
    output reg  [6:0] register_read_address,
    output reg  [6:0] register_write_address,
    output reg  [7:0] register_write_data,
    output reg        register_write_enable,
    input  wire [7:0] register_read_data
);
    // ---------------------------------------------------------------------
    // 1. 外部异步输入同步到系统clock域
    // ---------------------------------------------------------------------
    // 第一级meta可能出现亚稳态；第二级sync供功能逻辑使用。
    // sclk_previous保存同步SCLK的上一拍，用于产生单周期边沿脉冲。
    reg  sclk_meta;
    reg  sclk_sync;
    reg  sclk_previous;
    reg  cs_n_meta;
    reg  cs_n_sync;
    reg  mosi_meta;
    reg  mosi_sync;

    wire sclk_rising = sclk_sync && !sclk_previous;
    wire sclk_falling = !sclk_sync && sclk_previous;

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            sclk_meta     <= 1'b0;
            sclk_sync     <= 1'b0;
            sclk_previous <= 1'b0;
            cs_n_meta     <= 1'b1;
            cs_n_sync     <= 1'b1;
            mosi_meta     <= 1'b0;
            mosi_sync     <= 1'b0;
        end else begin
            sclk_meta     <= spi_sclk;
            sclk_sync     <= sclk_meta;
            sclk_previous <= sclk_sync;
            cs_n_meta     <= spi_cs_n;
            cs_n_sync     <= cs_n_meta;
            mosi_meta     <= spi_mosi;
            mosi_sync     <= mosi_meta;
        end
    end

    // ---------------------------------------------------------------------
    // 2. SPI字节收发与事务状态
    // ---------------------------------------------------------------------
    localparam STATE_COMMAND = 2'd0;
    localparam STATE_WRITE = 2'd1;
    localparam STATE_READ = 2'd2;

    reg  [1:0] state;
    reg  [7:0] receive_shift;
    reg  [7:0] transmit_shift;
    reg  [2:0] receive_bit_count;
    reg  [2:0] transmit_bit_count;
    reg        skip_command_falling_edge;
    reg        load_read_data;

    // 第8位到达时receive_shift尚未被非阻塞赋值更新，因此显式把当前
    // MOSI与旧的低7位拼接，得到可在同一clock内解析的完整字节。
    wire [7:0] received_byte = {receive_shift[6:0], mosi_sync};

    // 发送移位寄存器最高位直接连接MISO。只有读事务才允许驱动引脚。
    assign spi_miso    = transmit_shift[7];
    assign spi_miso_oe = !cs_n_sync && (state == STATE_READ);

    always @(posedge clock or posedge reset) begin
        if (reset) begin
            state                     <= STATE_COMMAND;
            receive_shift             <= 8'd0;
            transmit_shift            <= 8'd0;
            receive_bit_count         <= 3'd0;
            transmit_bit_count        <= 3'd0;
            skip_command_falling_edge <= 1'b0;
            load_read_data            <= 1'b0;
            register_read_address     <= 7'd0;
            register_write_address    <= 7'd0;
            register_write_data       <= 8'd0;
            register_write_enable     <= 1'b0;
        end else begin
            // 写使能默认拉低；每完成一个写数据字节时才产生一个clock宽脉冲。
            register_write_enable <= 1'b0;

            // 读地址使用非阻塞赋值更新，下一拍再装载数据可确保地址已经稳定。
            if (load_read_data) begin
                transmit_shift <= register_read_data;
                load_read_data <= 1'b0;
            end

            // CS_N拉高结束事务。这里只清除协议状态，不清除NPU寄存器。
            if (cs_n_sync) begin
                state                     <= STATE_COMMAND;
                receive_shift             <= 8'd0;
                transmit_shift            <= 8'd0;
                receive_bit_count         <= 3'd0;
                transmit_bit_count        <= 3'd0;
                skip_command_falling_edge <= 1'b0;
                load_read_data            <= 1'b0;
            end else begin
                // Mode 0：在SCLK上升沿采样MOSI。
                if (sclk_rising) begin
                    receive_shift <= received_byte;

                    case (state)
                        STATE_COMMAND: begin
                            // 事务首字节：bit7选择读写，bit6:0给出起始地址。
                            if (receive_bit_count == 3'd7) begin
                                register_read_address <= received_byte[6:0];
                                receive_bit_count <= 3'd0;

                                if (received_byte[7]) begin
                                    state <= STATE_WRITE;
                                end else begin
                                    state <= STATE_READ;
                                    transmit_bit_count <= 3'd0;
                                    skip_command_falling_edge <= 1'b1;
                                    load_read_data <= 1'b1;
                                end
                            end else begin
                                receive_bit_count <= receive_bit_count + 1'b1;
                            end
                        end

                        STATE_WRITE: begin
                            // 数据阶段每收齐8位，发出一次内部寄存器写操作。
                            if (receive_bit_count == 3'd7) begin
                                // 写地址必须保存自增前的值，供寄存器组下一拍使用。
                                register_write_address <= register_read_address;
                                register_write_data <= received_byte;
                                register_write_enable <= 1'b1;
                                register_read_address <= register_read_address + 1'b1;
                                receive_bit_count <= 3'd0;
                            end else begin
                                receive_bit_count <= receive_bit_count + 1'b1;
                            end
                        end

                        default: begin
                            // STATE_READ不接收有效数据；MOSI上的dummy位被忽略。
                        end
                    endcase
                end

                // Mode 0：主机在上升沿采样MISO，从机在下降沿准备下一位。
                if (sclk_falling && (state == STATE_READ)) begin
                    if (skip_command_falling_edge) begin
                        // 命令字节尾部的下降沿不能移位，否则会丢失返回字节bit7。
                        skip_command_falling_edge <= 1'b0;
                    end else if (transmit_bit_count == 3'd7) begin
                        // 当前返回字节完成，地址加1并装载下一个连续读字节。
                        transmit_bit_count <= 3'd0;
                        register_read_address <= register_read_address + 1'b1;
                        load_read_data <= 1'b1;
                    end else begin
                        transmit_bit_count <= transmit_bit_count + 1'b1;
                        transmit_shift <= {transmit_shift[6:0], 1'b0};
                    end
                end
            end
        end
    end
endmodule
