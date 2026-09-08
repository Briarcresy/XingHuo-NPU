`timescale 1ns / 1ps

// 纯推理流程的控制单元。
// 只负责控制时序，不处理矩阵数据：
// IDLE -> CLEAR -> RUN(phase 0~3) -> COLLECT -> WRITE_RESULT -> IDLE。
module ControlUnit (
    input clk,
    input rst,
    input start,

    output            busy,
    output reg        done,
    output reg  [1:0] phase,
    output array_clear,
    output array_step,
    output result_write_enable
);
    localparam [2:0] STATE_IDLE         = 3'd0;
    localparam [2:0] STATE_CLEAR        = 3'd1;
    localparam [2:0] STATE_RUN          = 3'd2;
    localparam [2:0] STATE_COLLECT      = 3'd3;
    localparam [2:0] STATE_WRITE_RESULT = 3'd4;

    reg [2:0] state;
    reg [2:0] next_state;

    // Moore型输出只由当前状态决定。数据通路只看有意义的控制信号，无需了解
    // FSM编码；busy也由状态派生，避免状态和单独busy寄存器发生不一致。
    assign busy                = (state != STATE_IDLE);
    assign array_clear         = (state == STATE_CLEAR);
    assign array_step          = (state == STATE_RUN);
    assign result_write_enable = (state == STATE_WRITE_RESULT);

    // 两段式FSM的组合部分：先给“保持当前状态”的默认值，各分支只描述真正的
    // 转移条件。default让非法编码能够自恢复到IDLE，也避免组合锁存器。
    always @(*) begin
        next_state = state;
        case (state)
            STATE_IDLE:
                if (start) next_state = STATE_CLEAR;
            STATE_CLEAR:
                next_state = STATE_RUN;
            STATE_RUN:
                if (phase == 2'd3) next_state = STATE_COLLECT;
            STATE_COLLECT:
                next_state = STATE_WRITE_RESULT;
            STATE_WRITE_RESULT:
                next_state = STATE_IDLE;
            default:
                next_state = STATE_IDLE;
        endcase
    end

    // 状态寄存器只负责保存FSM状态。
    always @(posedge clk) begin
        if (rst) state <= STATE_IDLE;
        else state <= next_state;
    end

    // phase是RUN状态内部的微步骤计数器，与主状态寄存器分开。
    always @(posedge clk) begin
        if (rst) phase <= 2'd0;
        else begin
            case (state)
                STATE_IDLE:
                    if (start) phase <= 2'd0;
                STATE_CLEAR:
                    phase <= 2'd0;
                STATE_RUN:
                    if (phase != 2'd3) phase <= phase + 1'b1;
                default:
                    phase <= 2'd0;
            endcase
        end
    end

    // done是独立的单周期事件：离开WRITE_RESULT的采样沿上，VPU也正好锁存结果。
    always @(posedge clk) begin
        if (rst) done <= 1'b0;
        else done <= (state == STATE_WRITE_RESULT);
    end
endmodule
