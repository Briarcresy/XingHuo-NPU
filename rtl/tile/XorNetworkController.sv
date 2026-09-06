// 自动调度两次NPU Core任务，完成两层XOR分类网络。
// 可编程模式从外部Shared RAM读取参数；Demo模式使用固定网络常量。
module XorNetworkController (
    input  logic        clock,
    input  logic        reset,
    input  logic        start_programmable,
    input  logic        start_demo,
    input  logic [ 1:0] demo_input,
    input  logic        clear_status,

    output logic [ 7:0] ram_address,
    output logic        ram_write_enable,
    output logic [ 7:0] ram_write_data,
    input  logic [ 7:0] ram_read_data,

    output logic        busy,
    output logic        done,
    output logic        error,
    output logic        classification,
    output logic [31:0] hidden_result,
    output logic [31:0] final_result,
    output logic        core_busy_observed
);
    // Shared RAM Map（共享存储器地址表）。
    localparam logic [7:0] ADDR_INPUT       = 8'h00; // 00..03
    localparam logic [7:0] ADDR_WEIGHT1     = 8'h10; // 10..13
    localparam logic [7:0] ADDR_BIAS1       = 8'h14; // 14..1b
    localparam logic [7:0] ADDR_SHIFT1      = 8'h1c;
    localparam logic [7:0] ADDR_HIDDEN      = 8'h20; // 20..23
    localparam logic [7:0] ADDR_WEIGHT2     = 8'h30; // 30..33
    localparam logic [7:0] ADDR_BIAS2       = 8'h34; // 34..3b
    localparam logic [7:0] ADDR_SHIFT2      = 8'h3c;
    localparam logic [7:0] ADDR_OUTPUT      = 8'h40; // 40..43
    localparam logic [7:0] ADDR_CLASS       = 8'h44;
    localparam logic [7:0] ADDR_STATUS      = 8'h45;
    localparam logic [7:0] ADDR_ERROR       = 8'h46;

    localparam logic [4:0] ST_IDLE          = 5'd0;
    localparam logic [4:0] ST_CORE_CLEAR    = 5'd1;
    localparam logic [4:0] ST_LOAD_INPUT    = 5'd2;
    localparam logic [4:0] ST_LOAD_WEIGHT1  = 5'd3;
    localparam logic [4:0] ST_LOAD_BIAS1    = 5'd4;
    localparam logic [4:0] ST_LOAD_SHIFT1   = 5'd5;
    localparam logic [4:0] ST_CORE_WLOAD1   = 5'd6;
    localparam logic [4:0] ST_CORE_WSWITCH1 = 5'd7;
    localparam logic [4:0] ST_CORE_START1   = 5'd8;
    localparam logic [4:0] ST_CORE_WAIT1    = 5'd9;
    localparam logic [4:0] ST_WRITE_HIDDEN  = 5'd10;
    localparam logic [4:0] ST_LOAD_WEIGHT2  = 5'd11;
    localparam logic [4:0] ST_LOAD_BIAS2    = 5'd12;
    localparam logic [4:0] ST_LOAD_SHIFT2   = 5'd13;
    localparam logic [4:0] ST_CORE_WLOAD2   = 5'd14;
    localparam logic [4:0] ST_CORE_WSWITCH2 = 5'd15;
    localparam logic [4:0] ST_CORE_START2   = 5'd16;
    localparam logic [4:0] ST_CORE_WAIT2    = 5'd17;
    localparam logic [4:0] ST_WRITE_OUTPUT  = 5'd18;
    localparam logic [4:0] ST_WRITE_CLASS   = 5'd19;
    localparam logic [4:0] ST_WRITE_STATUS  = 5'd20;
    localparam logic [4:0] ST_WRITE_ERROR   = 5'd21;
    localparam logic [4:0] ST_FINISH        = 5'd22;

    logic [4:0] state;
    logic [3:0] byte_index;
    logic demo_run;
    logic [31:0] activation_matrix;
    logic [31:0] weight_matrix;
    logic [63:0] bias_vector;
    logic [4:0] quant_shift;

    logic core_start;
    logic core_clear_error;
    logic core_weight_load;
    logic core_weight_switch;
    wire core_busy;
    wire core_done;
    wire [31:0] core_result;
    wire core_error;
    wire [4:0] core_error_code;
    wire active_weight_valid;
    wire shadow_weight_valid;
    wire [15:0] cycle_count;
    wire [31:0] task_count;

    assign busy = (state != ST_IDLE);
    assign core_busy_observed = core_busy;

    // RAM地址和写数据完全由状态译码；busy期间本控制器独占RAM端口。
    always_comb begin
        ram_address      = 8'h00;
        ram_write_enable = 1'b0;
        ram_write_data   = 8'h00;

        case (state)
            ST_LOAD_INPUT:   ram_address = ADDR_INPUT + {4'b0, byte_index};
            ST_LOAD_WEIGHT1: ram_address = ADDR_WEIGHT1 + {4'b0, byte_index};
            ST_LOAD_BIAS1:   ram_address = ADDR_BIAS1 + {4'b0, byte_index};
            ST_LOAD_SHIFT1:  ram_address = ADDR_SHIFT1;
            ST_WRITE_HIDDEN: begin
                ram_address = ADDR_HIDDEN + {4'b0, byte_index};
                ram_write_enable = 1'b1;
                ram_write_data = hidden_result[byte_index*8 +: 8];
            end
            ST_LOAD_WEIGHT2: ram_address = ADDR_WEIGHT2 + {4'b0, byte_index};
            ST_LOAD_BIAS2:   ram_address = ADDR_BIAS2 + {4'b0, byte_index};
            ST_LOAD_SHIFT2:  ram_address = ADDR_SHIFT2;
            ST_WRITE_OUTPUT: begin
                ram_address = ADDR_OUTPUT + {4'b0, byte_index};
                ram_write_enable = 1'b1;
                ram_write_data = final_result[byte_index*8 +: 8];
            end
            ST_WRITE_CLASS: begin
                ram_address = ADDR_CLASS;
                ram_write_enable = 1'b1;
                ram_write_data = {7'b0, classification};
            end
            ST_WRITE_STATUS: begin
                ram_address = ADDR_STATUS;
                ram_write_enable = 1'b1;
                ram_write_data = {4'b0, demo_run, error, 1'b0, 1'b1};
            end
            ST_WRITE_ERROR: begin
                ram_address = ADDR_ERROR;
                ram_write_enable = 1'b1;
                ram_write_data = {3'b0, core_error_code};
            end
            default: begin
            end
        endcase
    end

    // Core控制信号为单状态脉冲，避免跨层或跨任务重复触发。
    always_comb begin
        core_start         = (state == ST_CORE_START1) || (state == ST_CORE_START2);
        core_clear_error   = (state == ST_CORE_CLEAR)
                           || ((state == ST_IDLE) && clear_status);
        core_weight_load   = (state == ST_CORE_WLOAD1) || (state == ST_CORE_WLOAD2);
        core_weight_switch = (state == ST_CORE_WSWITCH1) || (state == ST_CORE_WSWITCH2);
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            state           <= ST_IDLE;
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
                ST_IDLE: begin
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
                        state         <= ST_CORE_CLEAR;
                    end else if (start_programmable) begin
                        done       <= 1'b0;
                        error      <= 1'b0;
                        demo_run   <= 1'b0;
                        byte_index <= 4'd0;
                        state      <= ST_CORE_CLEAR;
                    end
                end

                ST_CORE_CLEAR: begin
                    byte_index <= 4'd0;
                    if (demo_run) state <= ST_CORE_WLOAD1;
                    else state <= ST_LOAD_INPUT;
                end

                ST_LOAD_INPUT: begin
                    activation_matrix[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= ST_LOAD_WEIGHT1;
                    end else byte_index <= byte_index + 1'b1;
                end

                ST_LOAD_WEIGHT1: begin
                    weight_matrix[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= ST_LOAD_BIAS1;
                    end else byte_index <= byte_index + 1'b1;
                end

                ST_LOAD_BIAS1: begin
                    bias_vector[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd7) begin
                        byte_index <= 4'd0;
                        state <= ST_LOAD_SHIFT1;
                    end else byte_index <= byte_index + 1'b1;
                end

                ST_LOAD_SHIFT1: begin
                    quant_shift <= ram_read_data[4:0];
                    state <= ST_CORE_WLOAD1;
                end
                ST_CORE_WLOAD1:   state <= ST_CORE_WSWITCH1;
                ST_CORE_WSWITCH1: state <= ST_CORE_START1;
                ST_CORE_START1:   state <= ST_CORE_WAIT1;
                ST_CORE_WAIT1: begin
                    if (core_done) begin
                        hidden_result <= core_result;
                        error <= error | core_error;
                        byte_index <= 4'd0;
                        state <= ST_WRITE_HIDDEN;
                    end
                end

                ST_WRITE_HIDDEN: begin
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        activation_matrix <= hidden_result;
                        if (demo_run) begin
                            weight_matrix <= 32'h01ff_01ff;
                            bias_vector   <= 64'h0000_0000_0000_0001;
                            quant_shift   <= 5'd0;
                            state <= ST_CORE_WLOAD2;
                        end else state <= ST_LOAD_WEIGHT2;
                    end else byte_index <= byte_index + 1'b1;
                end

                ST_LOAD_WEIGHT2: begin
                    weight_matrix[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= ST_LOAD_BIAS2;
                    end else byte_index <= byte_index + 1'b1;
                end

                ST_LOAD_BIAS2: begin
                    bias_vector[byte_index*8 +: 8] <= ram_read_data;
                    if (byte_index == 4'd7) begin
                        byte_index <= 4'd0;
                        state <= ST_LOAD_SHIFT2;
                    end else byte_index <= byte_index + 1'b1;
                end

                ST_LOAD_SHIFT2: begin
                    quant_shift <= ram_read_data[4:0];
                    state <= ST_CORE_WLOAD2;
                end
                ST_CORE_WLOAD2:   state <= ST_CORE_WSWITCH2;
                ST_CORE_WSWITCH2: state <= ST_CORE_START2;
                ST_CORE_START2:   state <= ST_CORE_WAIT2;
                ST_CORE_WAIT2: begin
                    if (core_done) begin
                        final_result <= core_result;
                        classification <= (core_result[15:8] > core_result[7:0]);
                        error <= error | core_error;
                        byte_index <= 4'd0;
                        state <= ST_WRITE_OUTPUT;
                    end
                end

                ST_WRITE_OUTPUT: begin
                    if (byte_index == 4'd3) begin
                        byte_index <= 4'd0;
                        state <= ST_WRITE_CLASS;
                    end else byte_index <= byte_index + 1'b1;
                end
                ST_WRITE_CLASS:  state <= ST_WRITE_STATUS;
                ST_WRITE_STATUS: state <= ST_WRITE_ERROR;
                ST_WRITE_ERROR:  state <= ST_FINISH;
                ST_FINISH: begin
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end
                default: begin
                    state <= ST_IDLE;
                    done  <= 1'b0;
                    error <= 1'b1;
                end
            endcase
        end
    end

    XingHuo_NPU npu_core (
        .clk(clock),
        .rst(reset),
        .start(core_start),
        .clear_error(core_clear_error),
        .weight_load(core_weight_load),
        .weight_switch(core_weight_switch),
        .activation_matrix(activation_matrix),
        .weight_matrix(weight_matrix),
        .bias_vector(bias_vector),
        .quant_shift(quant_shift),
        .busy(core_busy),
        .done(core_done),
        .result_matrix(core_result),
        .error(core_error),
        .error_code(core_error_code),
        .active_weight_valid(active_weight_valid),
        .shadow_weight_valid(shadow_weight_valid),
        .cycle_count(cycle_count),
        .task_count(task_count)
    );
endmodule
