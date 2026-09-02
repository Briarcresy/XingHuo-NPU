`timescale 1ns / 1ps

// 纯推理流程的控制单元。
// 只负责控制时序，不处理矩阵数据：
// IDLE -> CLEAR -> RUN(phase 0~3) -> COLLECT -> WRITE_RESULT -> IDLE。
module ControlUnit (
    input clk,
    input rst,
    input start,

    output reg        busy,
    output reg        done,
    output reg  [1:0] phase,
    output array_clear,
    output array_step,
    output result_write_enable
);
    localparam [2:0] IDLE = 3'd0;
    localparam [2:0] CLEAR = 3'd1;
    localparam [2:0] RUN = 3'd2;
    localparam [2:0] COLLECT = 3'd3;
    localparam [2:0] WRITE_RESULT = 3'd4;

    reg [2:0] state;

    // 这些控制信号由当前状态直接译码，数据通路无需了解状态编码。
    assign array_clear         = (state == CLEAR);
    assign array_step          = (state == RUN);
    assign result_write_enable = (state == WRITE_RESULT);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            phase <= 2'd0;
            busy  <= 1'b0;
            done  <= 1'b0;
        end else begin
            // done 是单周期脉冲，只有 WRITE_RESULT 状态会将它置 1。
            done <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        phase <= 2'd0;
                        state <= CLEAR;
                    end
                end

                CLEAR: begin
                    phase <= 2'd0;
                    state <= RUN;
                end

                RUN: begin
                    if (phase == 2'd3) state <= COLLECT;
                    else phase <= phase + 1'b1;
                end

                COLLECT: begin
                    // 给Result Collector一个周期锁存最后一个流水结果。
                    state <= WRITE_RESULT;
                end

                WRITE_RESULT: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    phase <= 2'd0;
                    busy  <= 1'b0;
                end
            endcase
        end
    end
endmodule
