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

    // 去抖与边沿检测：输入已经由TileInputSynchronizer同步到clock域。
    always_ff @(posedge clock) begin
        if (reset) begin
            candidate      <= '0;
            buttons_stable <= '0;
            stable_counter <= '0;
            button_pressed <= '0;
        end else begin
            // 默认每拍清零；只有确认0->1变化的那一拍会被下面的赋值覆盖。
            button_pressed <= '0;

            if (buttons_sync != candidate) begin
                // 任何一位再次变化都说明机械触点尚未稳定，换候选值并重新计时。
                candidate      <= buttons_sync;
                stable_counter <= '0;
            end else if (candidate != buttons_stable) begin
                // 候选值未再变化，但还不同于正式状态：继续新状态正在等待确认。
                if ((DEBOUNCE_CYCLES <= 1)
                    || (stable_counter == COUNTER_WIDTH'(DEBOUNCE_CYCLES - 1))) begin
                    // 只对确认后的上升沿产生事件；确认松开仅更新stable状态。
                    button_pressed <= candidate & ~buttons_stable;
                    buttons_stable <= candidate;
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
endmodule
