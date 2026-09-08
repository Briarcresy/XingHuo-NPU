// Manual Mode（手动模式）控制器。
// DIP给出一个完整字节；经过去抖的按钮脉冲负责写入、寻址、启动和翻页。
module ManualInputController (
    input  logic       clock,              // Tile工作时钟。
    input  logic       reset,              // 同步高有效复位。
    input  logic       enable,             // 当前确实处于手动模式时为1。
    input  logic       network_busy,       // 网络运行时禁止修改RAM或重复启动。
    input  logic [7:0] dip_value,           // 已同步DIP，作为数据、地址或Demo输入。
    input  logic [7:0] button_pressed,      // 八个按钮的单周期确认按下事件。
    output logic [7:0] ram_address,         // 当前要呈现给共享RAM的地址。
    output logic       ram_write_request,   // 单周期RAM写使能。
    output logic [7:0] ram_write_data,      // 与写请求配套的锁存数据。
    output logic       start_programmable, // 单周期可编程网络启动脉冲。
    output logic       start_demo,         // 单周期固定参数Demo启动脉冲。
    output logic [1:0] demo_input,          // 启动Demo时锁存的两个XOR输入位。
    output logic       clear_status,        // 单周期状态清除脉冲。
    output logic [3:0] display_page         // 当前显示页，循环范围0..10。
);
    import TileTypesPkg::*;
    logic [7:0] address_pointer; // 下一次普通读写所使用并显示的地址。
    logic [7:0] write_address;   // 接受BTN0时锁存的旧地址。

    // BTN0同一上升沿既发出写请求又递增address_pointer。单独保存write_address，
    // 可保证写请求有效的整个周期内，RAM看到的仍是递增前的目标地址。
    always_comb begin
        if (ram_write_request) ram_address = write_address;
        else ram_address = address_pointer;
    end

    always_ff @(posedge clock) begin
        if (reset) begin
            address_pointer    <= 8'h00;
            write_address      <= 8'h00;
            ram_write_request  <= 1'b0;
            ram_write_data     <= 8'h00;
            start_programmable <= 1'b0;
            start_demo         <= 1'b0;
            demo_input         <= 2'b00;
            clear_status       <= 1'b0;
            display_page       <= PAGE_STATUS;
        end else begin
            // 这些输出表示事件而非状态，每个周期先清零，再由本拍按钮覆盖。
            ram_write_request  <= 1'b0;
            start_programmable <= 1'b0;
            start_demo         <= 1'b0;
            clear_status       <= 1'b0;

            if (enable && !network_busy) begin
                // BTN0：写入当前DIP字节，然后地址自动加一。
                if (button_pressed[0]) begin
                    ram_write_data    <= dip_value;
                    write_address     <= address_pointer;
                    ram_write_request <= 1'b1;
                    address_pointer   <= address_pointer + 1'b1;
                end
                // BTN1：地址归零；BTN2：把当前DIP字节直接装入地址指针。
                if (button_pressed[1]) address_pointer <= 8'h00;
                if (button_pressed[2]) address_pointer <= dip_value;
                // BTN3：使用RAM中的可编程参数运行完整两层网络。
                if (button_pressed[3]) start_programmable <= 1'b1;
                // BTN4/BTN5：循环切换显示页面。
                if (button_pressed[4]) begin
                    if (display_page == PAGE_CLASS) display_page <= PAGE_STATUS;
                    else display_page <= display_page + 1'b1;
                end
                if (button_pressed[5]) begin
                    if (display_page == PAGE_STATUS) display_page <= PAGE_CLASS;
                    else display_page <= display_page - 1'b1;
                end
                // BTN6：清除完成和错误状态。
                if (button_pressed[6]) clear_status <= 1'b1;
                // BTN7：用DIP[1:0]启动固定参数的一键XOR演示。
                if (button_pressed[7]) begin
                    demo_input <= dip_value[1:0];
                    start_demo <= 1'b1;
                end
            end
        end
    end
endmodule
