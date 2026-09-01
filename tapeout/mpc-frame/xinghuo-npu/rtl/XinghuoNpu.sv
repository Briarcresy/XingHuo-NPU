// MPC-Frame用户顶层，只负责IO映射和模块互连。
//
// 数据路径：外部SPI引脚 -> SpiSlave -> NpuRegisterBank -> XingHuo_NPU。
// 该顶层不实现协议状态机，也不保存软件寄存器；它只把三个独立模块连接起来。
// 这样修改SPI、寄存器表或NPU Core中的任意一层时，不必重写另外两层。
module XinghuoNpu #(
    parameter integer IO_WIDTH = 66
) (
    input  wire                clock,
    input  wire                reset,
    input  wire [IO_WIDTH-1:0] io_in,
    output reg  [IO_WIDTH-1:0] io_out,
    output reg  [IO_WIDTH-1:0] io_oe
);
    // MPC-Frame向用户提供66位双向payload。这里只使用最低6位：
    //   [0] SCLK：SPI时钟输入；       [1] CS_N：低有效片选输入；
    //   [2] MOSI：串行数据输入；      [3] MISO：串行数据输出；
    //   [4] IRQ：计算完成输出；       [5] BUSY：Core忙状态输出。
    // [65:6]保持释放，留给将来扩展或直接节省外部连线。
    localparam integer MISO_INDEX = 3;
    localparam integer IRQ_INDEX  = 4;
    localparam integer BUSY_INDEX = 5;

    // SpiSlave与寄存器组之间是一组与具体外部协议无关的简单内部总线。
    wire spi_miso;
    wire spi_miso_oe;
    wire [6:0] register_read_address;
    wire [6:0] register_write_address;
    wire [7:0] register_write_data;
    wire register_write_enable;
    wire [7:0] register_read_data;

    // 寄存器组把8位SPI数据重新拼成NPU Core原生的宽并行接口。
    wire [31:0] activation_matrix;
    wire [31:0] weight_matrix;
    wire [63:0] bias_vector;
    wire [4:0] quant_shift;
    wire core_start;
    wire core_busy;
    wire core_done;
    wire [31:0] result_matrix;
    wire interrupt;

    // 第一层：将SPI串行事务转换为寄存器读写操作。
    SpiSlave spi_slave (
        .clock(clock),
        .reset(reset),
        .spi_sclk(io_in[0]),
        .spi_cs_n(io_in[1]),
        .spi_mosi(io_in[2]),
        .spi_miso(spi_miso),
        .spi_miso_oe(spi_miso_oe),
        .register_read_address(register_read_address),
        .register_write_address(register_write_address),
        .register_write_data(register_write_data),
        .register_write_enable(register_write_enable),
        .register_read_data(register_read_data)
    );

    // 第二层：解释寄存器地址，保存输入，并产生Core控制信号。
    NpuRegisterBank register_bank (
        .clock(clock),
        .reset(reset),
        .register_read_address(register_read_address),
        .register_write_address(register_write_address),
        .register_write_data(register_write_data),
        .register_write_enable(register_write_enable),
        .register_read_data(register_read_data),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .core_start(core_start),
        .core_busy(core_busy),
        .core_done(core_done),
        .result_matrix(result_matrix),
        .interrupt(interrupt)
    );

    // 第三层：原有NPU计算核心。外围模块化没有改变Core端口或内部结构。
    XingHuo_NPU npu_core (
        .clk(clock),
        .rst(reset),
        .start(core_start),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(core_busy),
        .done(core_done),
        .result_matrix(result_matrix)
    );

    // MPC-Frame的io_out给出输出值，io_oe逐位决定是否真正驱动引脚。
    // 先释放所有位，再只开启必要输出，可避免双向IO冲突：
    //   MISO仅在SPI读事务中开启；IRQ和BUSY始终由本设计驱动。
    always @(*) begin
        io_out = {IO_WIDTH{1'b0}};
        io_oe  = {IO_WIDTH{1'b0}};
        io_out[MISO_INDEX] = spi_miso;
        io_oe[MISO_INDEX] = spi_miso_oe;
        io_out[IRQ_INDEX] = interrupt;
        io_out[BUSY_INDEX] = core_busy;
        io_oe[IRQ_INDEX] = 1'b1;
        io_oe[BUSY_INDEX] = 1'b1;
    end
endmodule
