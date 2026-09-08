// 将已经同步的机械按键转换成去抖后的单周期按下脉冲。
// 八个按键共用稳定计数器：任一位变化都会重新开始稳定时间计数。
module ButtonConditioner #(
    // 新状态必须连续保持的周期数；100 MHz下1,000,000周期约为10 ms。
    parameter integer DEBOUNCE_CYCLES = 1000000
) (
    input  logic       clock,          // 去抖逻辑工作时钟。
    input  logic       reset,          // 同步高有效复位。
    input  logic [7:0] buttons_sync,   // 已由同步器处理的当前按钮采样值。
    output logic [7:0] buttons_stable, // 已确认的按钮保持电平。
    output logic [7:0] button_pressed  // 确认按下时产生的单周期脉冲。
);
    // 至少保留1 bit，避免DEBOUNCE_CYCLES=1时出现零宽向量。
    localparam integer COUNTER_WIDTH = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);

    logic [7:0] candidate; // 当前正在计时确认的完整8-bit候选状态。
    logic [COUNTER_WIDTH-1:0] stable_counter; // candidate连续不变的周期数。
    logic debounce_accept;

    // 当前候选值是否已经满足稳定时间。把判定、状态更新和事件生成分开后，
    // 每个时序块只管理一类寄存器，但三者仍在同一个时钟沿观察相同条件。
    always_comb begin
        debounce_accept = (candidate != buttons_stable)
                       && ((DEBOUNCE_CYCLES <= 1)
                       || (stable_counter == COUNTER_WIDTH'(DEBOUNCE_CYCLES - 1)));
    end

    // 候选值和稳定计数器负责判断输入是否连续保持。
    always_ff @(posedge clock) begin
        if (reset) begin
            candidate      <= '0;
            stable_counter <= '0;
        end else begin
            if (buttons_sync != candidate) begin
                // 任何一位再次变化都说明机械触点尚未稳定，换候选值并重新计时。
                candidate      <= buttons_sync;
                stable_counter <= '0;
            end else if (candidate != buttons_stable) begin
                // 候选值未再变化，但还不同于正式状态：继续新状态正在等待确认。
                if (debounce_accept) begin
                    stable_counter <= '0;
                end else begin
                    stable_counter <= stable_counter + 1'b1;
                end
            end else begin
                // 当前采样、候选值和正式状态一致，不存在待确认变化。
                stable_counter <= '0;
            end
        end
    end

    // 正式去抖电平只在候选值通过稳定检查时更新。
    always_ff @(posedge clock) begin
        if (reset) buttons_stable <= '0;
        else if (debounce_accept) buttons_stable <= candidate;
    end

    // 按下事件是去抖状态更新沿上的单周期脉冲；松开只更新保持电平。
    always_ff @(posedge clock) begin
        if (reset) button_pressed <= '0;
        else if (debounce_accept) button_pressed <= candidate & ~buttons_stable;
        else button_pressed <= '0;
    end
endmodule
