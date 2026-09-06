// Manual Mode（手动模式）控制器。
// DIP给出一个完整字节；经过去抖的按钮脉冲负责写入、寻址、启动和翻页。
module ManualInputController (
    input  logic       clock,
    input  logic       reset,
    input  logic       enable,
    input  logic       network_busy,
    input  logic [7:0] dip_value,
    input  logic [7:0] button_pressed,
    output logic [7:0] ram_address,
    output logic       ram_write_request,
    output logic [7:0] ram_write_data,
    output logic       start_programmable,
    output logic       start_demo,
    output logic [1:0] demo_input,
    output logic       clear_status,
    output logic [3:0] display_page
);
    localparam logic [3:0] LAST_DISPLAY_PAGE = 4'd10;
    logic [7:0] address_pointer;
    logic [7:0] write_address;

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
            display_page       <= 4'd0;
        end else begin
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
                    if (display_page == LAST_DISPLAY_PAGE) display_page <= 4'd0;
                    else display_page <= display_page + 1'b1;
                end
                if (button_pressed[5]) begin
                    if (display_page == 4'd0) display_page <= LAST_DISPLAY_PAGE;
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
