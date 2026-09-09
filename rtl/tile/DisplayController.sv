/* verilator lint_off IMPORTSTAR */
import TileTypesPkg::*;
/* verilator lint_on IMPORTSTAR */

// 将有限的LED和两个十六进制数码管组织成多个可翻页的观察窗口。
module DisplayController (
    input  logic        external_mode,   // 当前实际模式，页面0显示。
    input  logic [ 3:0] display_page,    // 页面选择0..10。
    input  logic [ 7:0] manual_address,  // 页面1显示的手动RAM地址。
    input  logic [ 7:0] current_ram_data,// 当前实际RAM端口上的组合读数据。
    input  logic        network_busy,    // 两层网络忙状态。
    input  logic        core_busy,       // NPU Core忙状态。
    input  logic        done,            // 最近任务完成的粘滞状态。
    input  logic        error,           // 最近任务错误的粘滞状态。
    input  logic        classification,  // 二分类结果0或1。
    input  logic [31:0] hidden_result,    // 第一层四个INT8结果。
    input  logic [31:0] final_result,     // 第二层四个INT8结果。
    output logic [ 7:0] led_value,        // 送往八个LED的当前页数据。
    output logic [ 3:0] hex_low,          // 低位十六进制数字，不是段码。
    output logic [ 3:0] hex_high          // 高位十六进制数字，不是段码。
);
    // 本模块是纯组合显示Mux。先给出完整默认值可避免case分支漏赋值而推断Latch；
    // 页面2..9只覆盖LED，因此两个数码管自然保留默认页码显示。
    always_comb begin
        led_value = 8'h00;
        hex_low   = display_page;
        hex_high  = 4'h0;

        case (display_page)
            PAGE_STATUS: begin
                // 状态首页：LED[5:0]={外部模式,错误,Core忙,网络忙,完成,分类}；
                // 数码管显示00或01，便于直接查看最终类别。
                led_value = {
                    2'b00, external_mode, error, core_busy, network_busy, done, classification
                };
                hex_low = {3'b000, classification};
                hex_high = 4'h0;
            end
            PAGE_RAM: begin
                // RAM观察页：数码管显示手动地址，LED显示当前RAM口读数据。
                led_value = current_ram_data;
                hex_low   = manual_address[3:0];
                hex_high  = manual_address[7:4];
            end
            // 结果页：数码管显示页号，LED逐字节显示小端打包的矩阵结果。
            PAGE_HIDDEN0: led_value = hidden_result[7:0];
            PAGE_HIDDEN1: led_value = hidden_result[15:8];
            PAGE_HIDDEN2: led_value = hidden_result[23:16];
            PAGE_HIDDEN3: led_value = hidden_result[31:24];
            PAGE_FINAL0:  led_value = final_result[7:0];
            PAGE_FINAL1:  led_value = final_result[15:8];
            PAGE_FINAL2:  led_value = final_result[23:16];
            PAGE_FINAL3:  led_value = final_result[31:24];
            PAGE_CLASS: begin
                // 分类专页：C0/C1；仅LED0反映类别，其他LED熄灭。
                led_value = {7'b0, classification};
                hex_low   = {3'b000, classification};
                hex_high  = 4'hc;
            end
            default: begin
                // 非法页保持always_comb开头的默认显示：LED清零，HEX显示页号。
            end
        endcase
    end
endmodule
