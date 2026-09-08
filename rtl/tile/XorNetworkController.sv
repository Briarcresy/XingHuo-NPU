// 自动调度两次NPU Core任务，完成两层XOR分类网络。
// 可编程模式从外部Shared RAM读取参数；Demo模式使用固定网络常量。
module XorNetworkController (
    input  logic        clock,             // Tile工作时钟。
    input  logic        reset,             // 同步高有效复位。
    input  logic        start_programmable,// 单周期RAM参数任务启动脉冲。
    input  logic        start_demo,        // 单周期固定参数Demo启动脉冲。
    input  logic [ 1:0] demo_input,         // Demo的两个XOR输入位。
    input  logic        clear_status,       // 空闲时清除done/error的单周期脉冲。

    output logic [ 7:0] ram_address,       // 当前状态访问的共享RAM地址。
    output logic        ram_write_enable,  // 结果回写状态中的写使能。
    output logic [ 7:0] ram_write_data,    // 当前待写结果/状态字节。
    input  logic [ 7:0] ram_read_data,     // 当前地址对应的异步组合读数据。

    output logic        busy,              // 状态机非IDLE时保持为1。
    output logic        done,              // 完成后保持，直到清除或新任务。
    output logic        error,             // 任务错误的粘滞状态。
    output logic        classification,    // 最终二分类结果。
    output logic [31:0] hidden_result,     // 第一层四个INT8输出。
    output logic [31:0] final_result,      // 第二层四个INT8输出。
    output logic        core_busy_observed // 内部Core忙状态的调试旁路。
);
    import TileTypesPkg::*;

    // 任务分为四段：准备/第一层、隐藏层写回/第二层、最终写回、结束。
    // 使用enum而非裸数字编码，便于综合器检查，也让仿真波形直接显示状态名。
    network_state_t state;          // 当前调度状态。
    logic [3:0] byte_index;         // 多字节RAM装载/写回的片内索引。
    logic demo_run;                 // 本任务使用常量参数而非RAM参数。
    logic [31:0] activation_matrix; // 当前层2×2 INT8激活，小端打包。
    logic [31:0] weight_matrix;     // 当前层2×2 INT8权重，小端打包。
    logic [63:0] bias_vector;       // 当前层两个INT32 Bias，小端打包。
    logic [4:0] quant_shift;        // 当前层统一重量化右移量。

    logic core_start;
    logic core_clear_error;
    logic core_weight_load;
    wire core_busy;
    wire core_done;
    wire [31:0] core_result;
    wire core_error;
    wire [4:0] core_error_code;
    wire weight_valid;
    wire [15:0] cycle_count;
    wire [31:0] task_count;

    // busy也作为顶层RAM仲裁选择信号：离开IDLE后，本模块立即独占RAM。
    assign busy = (state != NET_IDLE);
    assign core_busy_observed = core_busy;

    // RAM地址和写数据完全由状态译码；busy期间本控制器独占RAM端口。
    // RAM为异步读，因此状态/索引改变后数据在下一个采样沿之前已经跟随新地址。
    always_comb begin
        ram_address      = 8'h00;
        ram_write_enable = 1'b0;
        ram_write_data   = 8'h00;

        case (state)
            NET_LOAD_INPUT:   ram_address = RAM_ADDR_INPUT + {4'b0, byte_index};
            NET_LOAD_WEIGHT1: ram_address = RAM_ADDR_WEIGHT1 + {4'b0, byte_index};
            NET_LOAD_BIAS1:   ram_address = RAM_ADDR_BIAS1 + {4'b0, byte_index};
            NET_LOAD_SHIFT1:  ram_address = RAM_ADDR_SHIFT1;
            NET_WRITE_HIDDEN: begin
                ram_address = RAM_ADDR_HIDDEN + {4'b0, byte_index};
                ram_write_enable = 1'b1;
                ram_write_data = hidden_result[byte_index*8 +: 8];
            end
            NET_LOAD_WEIGHT2: ram_address = RAM_ADDR_WEIGHT2 + {4'b0, byte_index};
            NET_LOAD_BIAS2:   ram_address = RAM_ADDR_BIAS2 + {4'b0, byte_index};
            NET_LOAD_SHIFT2:  ram_address = RAM_ADDR_SHIFT2;
            NET_WRITE_OUTPUT: begin
                ram_address = RAM_ADDR_OUTPUT + {4'b0, byte_index};
                ram_write_enable = 1'b1;
                ram_write_data = final_result[byte_index*8 +: 8];
            end
            NET_WRITE_CLASS: begin
                ram_address = RAM_ADDR_CLASS;
                ram_write_enable = 1'b1;
                ram_write_data = {7'b0, classification};
            end
            NET_WRITE_STATUS: begin
                ram_address = RAM_ADDR_STATUS;
                ram_write_enable = 1'b1;
                ram_write_data = {4'b0, demo_run, error, 1'b0, 1'b1};
            end
            NET_WRITE_ERROR: begin
                ram_address = RAM_ADDR_ERROR;
                ram_write_enable = 1'b1;
                ram_write_data = {3'b0, core_error_code};
            end
            default: begin
            end
        endcase
    end

    // Core控制信号为单状态脉冲，避免跨层或跨任务重复触发。WLOAD先把完整
    // 32-bit权重矩阵装入四个PE，下一状态才发START，满足单Bank权重接口时序。
    always_comb begin
        core_start         = (state == NET_CORE_START1) || (state == NET_CORE_START2);
        core_clear_error   = (state == NET_CORE_CLEAR)
                           || ((state == NET_IDLE) && clear_status);
        core_weight_load   = (state == NET_CORE_WLOAD1) || (state == NET_CORE_WLOAD2);
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            state           <= NET_IDLE;
            byte_index      <= 4'd0;
            demo_run        <= 1'b0;
            activation_matrix <= '0;
            weight_matrix   <= '0;
            bias_vector     <= '0;
            quant_shift     <= '0;
            hidden_result   <= '0;
            final_result    <= '0;
            classification  <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;
        end else begin
            case (state)
                NET_IDLE: begin
                    // 状态清除不启动任务。若两个启动同拍到达，Demo拥有优先级。
                    if (clear_status) begin
                        done  <= 1'b0;
                        error <= 1'b0;
                    end
                    if (start_demo) begin
                        done       <= 1'b0;
                        error      <= 1'b0;
                        demo_run   <= 1'b1;
                        // 只使用第0行作为单个XOR样本，第1行补零。
                        activation_matrix <= {
                            16'h0000, 7'h00, demo_input[1], 7'h00, demo_input[0]
                        };
                        weight_matrix <= 32'h01ff_ff01;
                        bias_vector   <= 64'h0;
                        quant_shift   <= 5'd0;
                        state         <= NET_CORE_CLEAR;
                    end else if (start_programmable) begin
                        done       <= 1'b0;
                        error      <= 1'b0;
                        demo_run   <= 1'b0;
                        byte_index <= 4'd0;
                        state      <= NET_CORE_CLEAR;
                    end
                end

                NET_CORE_CLEAR: begin
                    // 清除Core粘滞错误和上一任务流水；下一拍开始准备第一层。
                    byte_index <= 4'd0;
                    if (demo_run) state <= NET_CORE_WLOAD1;
                    else state <= NET_LOAD_INPUT;
                end

                NET_LOAD_INPUT: begin
                    // 地址0x00..0x03，每拍把当前异步读字节装入activation_matrix。
                    activation_matrix[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= NET_LOAD_WEIGHT1;
                    end else byte_index <= byte_index + 1'b1;
                end

                NET_LOAD_WEIGHT1: begin
                    // 地址0x10..0x13，装入第一层四个INT8权重。
                    weight_matrix[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= NET_LOAD_BIAS1;
                    end else byte_index <= byte_index + 1'b1;
                end

                NET_LOAD_BIAS1: begin
                    // 地址0x14..0x1b，装入第一层两个小端INT32 Bias。
                    bias_vector[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd7) begin
                        byte_index <= 4'd0;
                        state <= NET_LOAD_SHIFT1;
                    end else byte_index <= byte_index + 1'b1;
                end

                NET_LOAD_SHIFT1: begin
                    // 地址0x1c，只使用低5位作为第一层算术右移量。
                    quant_shift <= ram_read_data[4:0];
                    state <= NET_CORE_WLOAD1;
                end
                NET_CORE_WLOAD1:   state <= NET_CORE_START1;
                NET_CORE_START1:   state <= NET_CORE_WAIT1;
                NET_CORE_WAIT1: begin
                    // 等待Core单周期done；在该拍锁存结果，下一状态逐字节写RAM。
                    if (core_done) begin
                        hidden_result <= core_result;
                        error <= error | core_error;
                        byte_index <= 4'd0;
                        state <= NET_WRITE_HIDDEN;
                    end
                end

                NET_WRITE_HIDDEN: begin
                    // 四拍写0x20..0x23；最后一拍同时把隐藏结果设为第二层激活。
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        activation_matrix <= hidden_result;
                        if (demo_run) begin
                            weight_matrix <= 32'h01ff_01ff;
                            bias_vector   <= 64'h0000_0000_0000_0001;
                            quant_shift   <= 5'd0;
                            state <= NET_CORE_WLOAD2;
                        end else state <= NET_LOAD_WEIGHT2;
                    end else byte_index <= byte_index + 1'b1;
                end

                NET_LOAD_WEIGHT2: begin
                    // 地址0x30..0x33，装入第二层四个INT8权重。
                    weight_matrix[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= NET_LOAD_BIAS2;
                    end else byte_index <= byte_index + 1'b1;
                end

                NET_LOAD_BIAS2: begin
                    // 地址0x34..0x3b，装入第二层两个小端INT32 Bias。
                    bias_vector[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd7) begin
                        byte_index <= 4'd0;
                        state <= NET_LOAD_SHIFT2;
                    end else byte_index <= byte_index + 1'b1;
                end

                NET_LOAD_SHIFT2: begin
                    // 地址0x3c，只使用低5位作为第二层算术右移量。
                    quant_shift <= ram_read_data[4:0];
                    state <= NET_CORE_WLOAD2;
                end
                NET_CORE_WLOAD2:   state <= NET_CORE_START2;
                NET_CORE_START2:   state <= NET_CORE_WAIT2;
                NET_CORE_WAIT2: begin
                    // 锁存最终矩阵，并用结果字节1与字节0的大小关系产生类别。
                    if (core_done) begin
                        final_result <= core_result;
                        classification <= (core_result[15:8] > core_result[7:0]);
                        error <= error | core_error;
                        byte_index <= 4'd0;
                        state <= NET_WRITE_OUTPUT;
                    end
                end

                NET_WRITE_OUTPUT: begin
                    // 四拍把final_result按低字节优先写到0x40..0x43。
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= NET_WRITE_CLASS;
                    end else byte_index <= byte_index + 1'b1;
                end
                // 后续三拍分别写分类、状态和Core错误码。
                NET_WRITE_CLASS:  state <= NET_WRITE_STATUS;
                NET_WRITE_STATUS: state <= NET_WRITE_ERROR;
                NET_WRITE_ERROR:  state <= NET_FINISH;
                NET_FINISH: begin
                    // done在Tile层采用粘滞语义；回到IDLE后RAM控制权交还输入模式。
                    done  <= 1'b1;
                    state <= NET_IDLE;
                end
                default: begin
                    state <= NET_IDLE;
                    done  <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
    end

    // 同一个Core先后执行两层；每层都先覆盖单Bank权重再启动。
    XingHuo_NPU npu_core (
        .clk(clock),
        .rst(reset),
        .start(core_start),
        .clear_error(core_clear_error),
        .weight_load(core_weight_load),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(core_busy),
        .done(core_done),
        .result_matrix(core_result),
        .error(core_error),
        .error_code(core_error_code),
        .weight_valid(weight_valid),
        .cycle_count(cycle_count),
        .task_count(task_count)
    );
endmodule
