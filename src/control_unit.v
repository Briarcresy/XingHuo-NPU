`timescale 1ns / 1ps

// 纯推理流程的控制单元。
// 只负责控制时序，不处理矩阵数据：
// IDLE -> CLEAR -> RUN(phase 0~3) -> WRITE_RESULT -> IDLE。
module control_unit (
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
    localparam [1:0] IDLE = 2'd0;
    localparam [1:0] CLEAR = 2'd1;
    localparam [1:0] RUN = 2'd2;
    localparam [1:0] WRITE_RESULT = 2'd3;

    reg [1:0] state;

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
                    if (phase == 2'd3) state <= WRITE_RESULT;
                    else phase <= phase + 1'b1;
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
