// 将已经同步的机械按键转换成去抖后的单周期按下脉冲。
// 八个按键共用稳定计数器：任一位变化都会重新开始稳定时间计数。
module ButtonConditioner #(
    parameter integer DEBOUNCE_CYCLES = 1000000
) (
    input  logic       clock,
    input  logic       reset,
    input  logic [7:0] buttons_sync,
    output logic [7:0] buttons_stable,
    output logic [7:0] button_pressed
);
    localparam integer COUNTER_WIDTH = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);

    logic [7:0] candidate;
    logic [COUNTER_WIDTH-1:0] stable_counter;

    // 去抖与边沿检测：输入已经由TileInputSynchronizer同步到clock域。
    always_ff @(posedge clock) begin
        if (reset) begin
            candidate      <= '0;
            buttons_stable <= '0;
            stable_counter <= '0;
            button_pressed <= '0;
        end else begin
            button_pressed <= '0;

            if (buttons_sync != candidate) begin
                candidate      <= buttons_sync;
                stable_counter <= '0;
            end else if (candidate != buttons_stable) begin
                if ((DEBOUNCE_CYCLES <= 1)
                    || (stable_counter == COUNTER_WIDTH'(DEBOUNCE_CYCLES - 1))) begin
                    button_pressed <= candidate & ~buttons_stable;
                    buttons_stable <= candidate;
                    stable_counter <= '0;
                end else begin
                    stable_counter <= stable_counter + 1'b1;
                end
            end else begin
                stable_counter <= '0;
            end
        end
    end
endmodule
