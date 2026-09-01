// XingHuo NPU 的 MPSoC-Digital Tile v1 适配层。
//
// 本模块严格保留官方 Tile v1 契约的全部端口。共享 RAM 位于 Tile 外部，
// 本模块只产生地址、写使能和写数据。NPU Core 保持平台无关，不感知 Tile 协议。
module XinghuoNpuTile (
    input  logic        clock,
    input  logic        reset,
    output logic [ 7:0] io_led,
    output logic        io_ledUpdate,
    input  logic [ 7:0] io_btn,
    input  logic [ 7:0] io_dip,
    output logic [ 3:0] io_hex7seg_0,
    output logic [ 3:0] io_hex7seg_1,
    output logic        io_hex7segUpdate,
    output logic [15:0] io_customOut,
    input  logic [15:0] io_customIn,
    output logic [ 7:0] io_ramAddr,
    output logic        io_ramWen,
    output logic [ 7:0] io_ramWdata,
    input  logic [ 7:0] io_ramRdata
);

    // --------------------------------------------------------------------------
    // 主机接口约定（全部复用官方固定输入，不增加任何端口）
    // --------------------------------------------------------------------------
    // io_customIn[7:0]   命令载荷：地址、写数据或控制位
    // io_customIn[8]     请求 toggle；每发送一条命令翻转一次
    // io_customIn[10:9]  操作码：00设置地址，01写并自增，10读地址自增，11控制
    // io_customIn[15:11] 保留，必须由主机驱动为 0
    //
    // io_customOut[7:0]  空闲时为当前地址指针指向的 RAM 读数据
    // io_customOut[8]    命令应答 toggle
    // io_customOut[9]    Tile busy：装载、计算或回写期间为 1
    // io_customOut[10]   done：结果已经写回 RAM，清除前保持为 1
    // io_customOut[11]   NPU Core 自身的 busy
    // io_customOut[15:12] 接口版本，目前固定为 4'b0001

    localparam logic [1:0] OP_SET_ADDRESS = 2'b00;
    localparam logic [1:0] OP_WRITE_BYTE  = 2'b01;
    localparam logic [1:0] OP_READ_NEXT   = 2'b10;
    localparam logic [1:0] OP_CONTROL     = 2'b11;

    localparam logic [4:0] STATE_IDLE = 5'd0;
    localparam logic [4:0] STATE_HOST_WRITE = 5'd1;
    localparam logic [4:0] STATE_LOAD_ACT0 = 5'd2;
    localparam logic [4:0] STATE_LOAD_ACT1 = 5'd3;
    localparam logic [4:0] STATE_LOAD_ACT2 = 5'd4;
    localparam logic [4:0] STATE_LOAD_ACT3 = 5'd5;
    localparam logic [4:0] STATE_LOAD_WEIGHT0 = 5'd6;
    localparam logic [4:0] STATE_LOAD_WEIGHT1 = 5'd7;
    localparam logic [4:0] STATE_LOAD_WEIGHT2 = 5'd8;
    localparam logic [4:0] STATE_LOAD_WEIGHT3 = 5'd9;
    localparam logic [4:0] STATE_LOAD_BIAS0 = 5'd10;
    localparam logic [4:0] STATE_LOAD_BIAS1 = 5'd11;
    localparam logic [4:0] STATE_LOAD_BIAS2 = 5'd12;
    localparam logic [4:0] STATE_LOAD_BIAS3 = 5'd13;
    localparam logic [4:0] STATE_LOAD_BIAS4 = 5'd14;
    localparam logic [4:0] STATE_LOAD_BIAS5 = 5'd15;
    localparam logic [4:0] STATE_LOAD_BIAS6 = 5'd16;
    localparam logic [4:0] STATE_LOAD_BIAS7 = 5'd17;
    localparam logic [4:0] STATE_LOAD_SHIFT = 5'd18;
    localparam logic [4:0] STATE_START_CORE = 5'd19;
    localparam logic [4:0] STATE_WAIT_CORE = 5'd20;
    localparam logic [4:0] STATE_WRITE_RESULT0 = 5'd21;
    localparam logic [4:0] STATE_WRITE_RESULT1 = 5'd22;
    localparam logic [4:0] STATE_WRITE_RESULT2 = 5'd23;
    localparam logic [4:0] STATE_WRITE_RESULT3 = 5'd24;

    // 共享 RAM 内存布局。
    localparam logic [7:0] ADDR_ACTIVATION = 8'h00;  // 00～03，共4字节
    localparam logic [7:0] ADDR_WEIGHT = 8'h04;  // 04～07，共4字节
    localparam logic [7:0] ADDR_BIAS = 8'h08;  // 08～0F，共8字节
    localparam logic [7:0] ADDR_SHIFT = 8'h10;  // 低5位有效
    localparam logic [7:0] ADDR_RESULT = 8'h20;  // 20～23，共4字节

    // 外部输入可能与 Tile 时钟异步。完整命令经过两级采样。主机必须先稳定
    // payload和opcode，再翻转请求位，并保持全部信号直到应答位变为相同值。
    logic [15:0] custom_in_meta;
    logic [15:0] custom_in_sync;

    always_ff @(posedge clock) begin
        if (reset) begin
            custom_in_meta <= '0;
            custom_in_sync <= '0;
        end else begin
            custom_in_meta <= io_customIn;
            custom_in_sync <= custom_in_meta;
        end
    end

    logic [ 4:0] state;
    logic [ 7:0] ram_address_pointer;
    logic [ 7:0] host_write_data;
    logic        request_ack_toggle;
    logic        done_latched;

    logic [31:0] activation_matrix;
    logic [31:0] weight_matrix;
    logic [63:0] bias_vector;
    logic [ 4:0] quant_shift;
    logic        core_start;
    logic        core_reset;
    wire         core_busy;
    wire         core_done;
    wire  [31:0] result_matrix;

    XingHuo_NPU npu_core (
        .clk(clock),
        .rst(core_reset),
        .start(core_start),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(core_busy),
        .done(core_done),
        .result_matrix(result_matrix)
    );

    // 控制器按固定地址依次装载操作数，启动不变的 NPU Core，再把四个结果字节
    // 写回 0x20～0x23。装载利用官方约定的 RAM 异步读语义。
    // Tile v1契约只规定reset高有效，不限定同步或异步。本适配层遵循官方模板和
    // Harness的同步写法；原NPU Core使用异步复位，故生成独立core_reset网络。
    always_ff @(posedge clock) core_reset <= reset;

    always_ff @(posedge clock) begin
        if (reset) begin
            state                 <= STATE_IDLE;
            ram_address_pointer   <= '0;
            host_write_data       <= '0;
            request_ack_toggle    <= 1'b0;
            done_latched          <= 1'b0;
            activation_matrix     <= '0;
            weight_matrix         <= '0;
            bias_vector           <= '0;
            quant_shift           <= '0;
            core_start            <= 1'b0;
        end else begin
            core_start <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (custom_in_sync[8] != request_ack_toggle) begin
                        case (custom_in_sync[10:9])
                            OP_SET_ADDRESS: begin
                                ram_address_pointer <= custom_in_sync[7:0];
                                request_ack_toggle  <= custom_in_sync[8];
                            end
                            OP_WRITE_BYTE: begin
                                host_write_data <= custom_in_sync[7:0];
                                state           <= STATE_HOST_WRITE;
                            end
                            OP_READ_NEXT: begin
                                ram_address_pointer <= ram_address_pointer + 1'b1;
                                request_ack_toggle  <= custom_in_sync[8];
                            end
                            OP_CONTROL: begin
                                request_ack_toggle <= custom_in_sync[8];
                                if (custom_in_sync[1]) done_latched <= 1'b0;
                                if (custom_in_sync[0]) begin
                                    done_latched <= 1'b0;
                                    state        <= STATE_LOAD_ACT0;
                                end
                            end
                            default: begin end
                        endcase
                    end
                end

                // 在整个 STATE_HOST_WRITE 周期保持稳定地址、数据和写使能；该状态结束的
                // 时钟上升沿完成 RAM 写入，随后才返回应答。
                STATE_HOST_WRITE: begin
                    ram_address_pointer <= ram_address_pointer + 1'b1;
                    request_ack_toggle  <= custom_in_sync[8];
                    state               <= STATE_IDLE;
                end

                STATE_LOAD_ACT0: begin
                    activation_matrix[7:0] <= io_ramRdata;
                    state <= STATE_LOAD_ACT1;
                end
                STATE_LOAD_ACT1: begin
                    activation_matrix[15:8] <= io_ramRdata;
                    state <= STATE_LOAD_ACT2;
                end
                STATE_LOAD_ACT2: begin
                    activation_matrix[23:16] <= io_ramRdata;
                    state <= STATE_LOAD_ACT3;
                end
                STATE_LOAD_ACT3: begin
                    activation_matrix[31:24] <= io_ramRdata;
                    state <= STATE_LOAD_WEIGHT0;
                end

                STATE_LOAD_WEIGHT0: begin
                    weight_matrix[7:0] <= io_ramRdata;
                    state <= STATE_LOAD_WEIGHT1;
                end
                STATE_LOAD_WEIGHT1: begin
                    weight_matrix[15:8] <= io_ramRdata;
                    state <= STATE_LOAD_WEIGHT2;
                end
                STATE_LOAD_WEIGHT2: begin
                    weight_matrix[23:16] <= io_ramRdata;
                    state <= STATE_LOAD_WEIGHT3;
                end
                STATE_LOAD_WEIGHT3: begin
                    weight_matrix[31:24] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS0;
                end

                STATE_LOAD_BIAS0: begin
                    bias_vector[7:0] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS1;
                end
                STATE_LOAD_BIAS1: begin
                    bias_vector[15:8] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS2;
                end
                STATE_LOAD_BIAS2: begin
                    bias_vector[23:16] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS3;
                end
                STATE_LOAD_BIAS3: begin
                    bias_vector[31:24] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS4;
                end
                STATE_LOAD_BIAS4: begin
                    bias_vector[39:32] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS5;
                end
                STATE_LOAD_BIAS5: begin
                    bias_vector[47:40] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS6;
                end
                STATE_LOAD_BIAS6: begin
                    bias_vector[55:48] <= io_ramRdata;
                    state <= STATE_LOAD_BIAS7;
                end
                STATE_LOAD_BIAS7: begin
                    bias_vector[63:56] <= io_ramRdata;
                    state <= STATE_LOAD_SHIFT;
                end

                STATE_LOAD_SHIFT: begin
                    quant_shift <= io_ramRdata[4:0];
                    state       <= STATE_START_CORE;
                end

                STATE_START_CORE: begin
                    core_start <= 1'b1;
                    state      <= STATE_WAIT_CORE;
                end

                STATE_WAIT_CORE: begin
                    if (core_done) state <= STATE_WRITE_RESULT0;
                end

                STATE_WRITE_RESULT0: state <= STATE_WRITE_RESULT1;
                STATE_WRITE_RESULT1: state <= STATE_WRITE_RESULT2;
                STATE_WRITE_RESULT2: state <= STATE_WRITE_RESULT3;
                STATE_WRITE_RESULT3: begin
                    done_latched <= 1'b1;
                    state        <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    // RAM 单端口复用。空闲时地址使用内部主机指针以支持异步读取；运行期间地址归
    // NPU 控制器所有。只有主机写状态和结果回写状态会拉高写使能。
    always_comb begin
        io_ramAddr  = ram_address_pointer;
        io_ramWen   = 1'b0;
        io_ramWdata = 8'h00;

        case (state)
            STATE_HOST_WRITE: begin
                io_ramAddr  = ram_address_pointer;
                io_ramWen   = 1'b1;
                io_ramWdata = host_write_data;
            end

            STATE_LOAD_ACT0:    io_ramAddr = ADDR_ACTIVATION + 8'd0;
            STATE_LOAD_ACT1:    io_ramAddr = ADDR_ACTIVATION + 8'd1;
            STATE_LOAD_ACT2:    io_ramAddr = ADDR_ACTIVATION + 8'd2;
            STATE_LOAD_ACT3:    io_ramAddr = ADDR_ACTIVATION + 8'd3;
            STATE_LOAD_WEIGHT0: io_ramAddr = ADDR_WEIGHT + 8'd0;
            STATE_LOAD_WEIGHT1: io_ramAddr = ADDR_WEIGHT + 8'd1;
            STATE_LOAD_WEIGHT2: io_ramAddr = ADDR_WEIGHT + 8'd2;
            STATE_LOAD_WEIGHT3: io_ramAddr = ADDR_WEIGHT + 8'd3;
            STATE_LOAD_BIAS0:   io_ramAddr = ADDR_BIAS + 8'd0;
            STATE_LOAD_BIAS1:   io_ramAddr = ADDR_BIAS + 8'd1;
            STATE_LOAD_BIAS2:   io_ramAddr = ADDR_BIAS + 8'd2;
            STATE_LOAD_BIAS3:   io_ramAddr = ADDR_BIAS + 8'd3;
            STATE_LOAD_BIAS4:   io_ramAddr = ADDR_BIAS + 8'd4;
            STATE_LOAD_BIAS5:   io_ramAddr = ADDR_BIAS + 8'd5;
            STATE_LOAD_BIAS6:   io_ramAddr = ADDR_BIAS + 8'd6;
            STATE_LOAD_BIAS7:   io_ramAddr = ADDR_BIAS + 8'd7;
            STATE_LOAD_SHIFT:   io_ramAddr = ADDR_SHIFT;

            STATE_WRITE_RESULT0: begin
                io_ramAddr  = ADDR_RESULT + 8'd0;
                io_ramWen   = 1'b1;
                io_ramWdata = result_matrix[7:0];
            end
            STATE_WRITE_RESULT1: begin
                io_ramAddr  = ADDR_RESULT + 8'd1;
                io_ramWen   = 1'b1;
                io_ramWdata = result_matrix[15:8];
            end
            STATE_WRITE_RESULT2: begin
                io_ramAddr  = ADDR_RESULT + 8'd2;
                io_ramWen   = 1'b1;
                io_ramWdata = result_matrix[23:16];
            end
            STATE_WRITE_RESULT3: begin
                io_ramAddr  = ADDR_RESULT + 8'd3;
                io_ramWen   = 1'b1;
                io_ramWdata = result_matrix[31:24];
            end
            default: begin
            end
        endcase
    end

    // 展示资源也保持确定值。LED 用于板级观察，数码管显示状态和低4位结果。
    always_comb begin
        io_led              = {4'b0000, core_busy, done_latched, (state != STATE_IDLE), reset};
        io_ledUpdate        = 1'b1;
        io_hex7seg_0        = io_ramRdata[3:0];
        io_hex7seg_1        = state[3:0];
        io_hex7segUpdate    = 1'b1;
        io_customOut[7:0]   = io_ramRdata;
        io_customOut[8]     = request_ack_toggle;
        io_customOut[9]     = (state != STATE_IDLE);
        io_customOut[10]    = done_latched;
        io_customOut[11]    = core_busy;
        io_customOut[15:12] = 4'b0001;
    end

endmodule
