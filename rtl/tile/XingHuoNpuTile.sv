// XingHuo NPU 的 MPSoC-Digital Tile v1 用户模块。
// 端口名、方向和位宽与官方接口契约完全一致；最终Tile顶层由官方工具生成。
module XingHuoNpuTile #(
    // 默认按100 MHz时钟提供约10 ms机械按键稳定窗口。
    parameter integer BUTTON_DEBOUNCE_CYCLES = 1000000
) (
    input  logic        clock,
    input  logic        reset,
    output logic [ 7:0] io_led,
    output logic        io_ledUpdate,
    input  logic [ 7:0] io_btn,
    input  logic [ 7:0] io_dip,
    output logic [ 3:0] io_hex7seg_0,
    output logic [ 3:0] io_hex7seg_1,
    output logic        io_hex7segUpdate,
    output logic [15:0] io_customOut,
    input  logic [15:0] io_customIn,
    output logic [ 7:0] io_ramAddr,
    output logic        io_ramWen,
    output logic [ 7:0] io_ramWdata,
    input  logic [ 7:0] io_ramRdata
);
    logic [7:0] buttons_stable;
    logic [7:0] button_pressed;
    // 标记同步链供后端CDC/布局工具识别；多位DIP仍须在按键采样前稳定。
    (* ASYNC_REG = "TRUE" *) logic [7:0] dip_meta;
    (* ASYNC_REG = "TRUE" *) logic [7:0] dip_sync;

    always_ff @(posedge clock) begin
        if (reset) begin
            dip_meta <= '0;
            dip_sync <= '0;
        end else begin
            dip_meta <= io_dip;
            dip_sync <= dip_meta;
        end
    end

    logic external_mode_request;
    logic external_mode;

    logic [7:0] manual_ram_address;
    logic manual_ram_write_request;
    logic [7:0] manual_ram_write_data;
    logic manual_start_programmable;
    logic manual_start_demo;
    logic [1:0] manual_demo_input;
    logic manual_clear_status;
    logic [3:0] display_page;

    logic [7:0] host_ram_address;
    logic host_ram_write_request;
    logic [7:0] host_ram_write_data;
    logic host_start_programmable;
    logic host_start_demo;
    logic [1:0] host_demo_input;
    logic host_clear_status;
    logic [7:0] host_read_data;
    logic host_acknowledge_toggle;

    logic controller_start_programmable;
    logic controller_start_demo;
    logic [1:0] controller_demo_input;
    logic controller_clear_status;
    logic [7:0] controller_ram_address;
    logic controller_ram_write_enable;
    logic [7:0] controller_ram_write_data;
    logic network_busy;
    logic network_done;
    logic network_error;
    logic classification;
    logic [31:0] hidden_result;
    logic [31:0] final_result;
    logic core_busy;

    logic [7:0] led_value;
    logic [3:0] hex_low;
    logic [3:0] hex_high;

    ButtonConditioner #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) button_conditioner (
        .clock(clock),
        .reset(reset),
        .buttons_async(io_btn),
        .buttons_stable(buttons_stable),
        .button_pressed(button_pressed)
    );

    ManualInputController manual_controller (
        .clock(clock),
        .reset(reset),
        .enable(!external_mode && !external_mode_request),
        .network_busy(network_busy),
        .dip_value(dip_sync),
        .button_pressed(button_pressed),
        .ram_address(manual_ram_address),
        .ram_write_request(manual_ram_write_request),
        .ram_write_data(manual_ram_write_data),
        .start_programmable(manual_start_programmable),
        .start_demo(manual_start_demo),
        .demo_input(manual_demo_input),
        .clear_status(manual_clear_status),
        .display_page(display_page)
    );

    ExternalHostInterface host_interface (
        .clock(clock),
        .reset(reset),
        .enable(external_mode && external_mode_request),
        .network_busy(network_busy),
        .custom_in_async(io_customIn),
        .ram_read_data(io_ramRdata),
        .external_mode_request(external_mode_request),
        .ram_address(host_ram_address),
        .ram_write_request(host_ram_write_request),
        .ram_write_data(host_ram_write_data),
        .start_programmable(host_start_programmable),
        .start_demo(host_start_demo),
        .demo_input(host_demo_input),
        .clear_status(host_clear_status),
        .read_data(host_read_data),
        .acknowledge_toggle(host_acknowledge_toggle)
    );

    // 模式不匹配时停止接收旧模式的新命令，已接受的脉冲先消费再交接。
    // 不能只等busy：启动脉冲与network_busy之间存在一个交接周期。
    always_ff @(posedge clock) begin
        if (reset) external_mode <= 1'b0;
        else if (!network_busy && !manual_ram_write_request && !host_ram_write_request
                 && !manual_start_programmable && !manual_start_demo
                 && !host_start_programmable && !host_start_demo
                 && !manual_clear_status && !host_clear_status)
            external_mode <= external_mode_request;
    end

    always_comb begin
        if (external_mode) begin
            controller_start_programmable = host_start_programmable;
            controller_start_demo = host_start_demo;
            controller_demo_input = host_demo_input;
            controller_clear_status = host_clear_status;
        end else begin
            controller_start_programmable = manual_start_programmable;
            controller_start_demo = manual_start_demo;
            controller_demo_input = manual_demo_input;
            controller_clear_status = manual_clear_status;
        end
    end

    XorNetworkController xor_controller (
        .clock(clock),
        .reset(reset),
        .start_programmable(controller_start_programmable),
        .start_demo(controller_start_demo),
        .demo_input(controller_demo_input),
        .clear_status(controller_clear_status),
        .ram_address(controller_ram_address),
        .ram_write_enable(controller_ram_write_enable),
        .ram_write_data(controller_ram_write_data),
        .ram_read_data(io_ramRdata),
        .busy(network_busy),
        .done(network_done),
        .error(network_error),
        .classification(classification),
        .hidden_result(hidden_result),
        .final_result(final_result),
        .core_busy_observed(core_busy)
    );

    // Shared RAM端口仲裁：网络运行时控制器独占；空闲时交给所选输入模式。
    always_comb begin
        if (network_busy) begin
            io_ramAddr  = controller_ram_address;
            io_ramWen   = controller_ram_write_enable;
            io_ramWdata = controller_ram_write_data;
        end else if (external_mode) begin
            io_ramAddr  = host_ram_address;
            io_ramWen   = host_ram_write_request;
            io_ramWdata = host_ram_write_data;
        end else begin
            io_ramAddr  = manual_ram_address;
            io_ramWen   = manual_ram_write_request;
            io_ramWdata = manual_ram_write_data;
        end
        // Shared RAM不一定由Tile reset复位；禁止复位采样沿遗留一次写入。
        if (reset) io_ramWen = 1'b0;
    end

    DisplayController display_controller (
        .external_mode(external_mode),
        .display_page(display_page),
        .manual_address(manual_ram_address),
        .current_ram_data(io_ramRdata),
        .network_busy(network_busy),
        .core_busy(core_busy),
        .done(network_done),
        .error(network_error),
        .classification(classification),
        .hidden_result(hidden_result),
        .final_result(final_result),
        .led_value(led_value),
        .hex_low(hex_low),
        .hex_high(hex_high)
    );

    // Harness仅在Update为1时锁存显示值；持续置1表示每拍都反映最新状态。
    always_comb begin
        io_led             = led_value;
        io_ledUpdate       = 1'b1;
        io_hex7seg_0       = hex_low;
        io_hex7seg_1       = hex_high;
        io_hex7segUpdate   = 1'b1;
        io_customOut[7:0]  = host_read_data;
        io_customOut[8]    = host_acknowledge_toggle;
        io_customOut[9]    = network_busy;
        io_customOut[10]   = network_done;
        io_customOut[11]   = core_busy;
        io_customOut[12]   = network_error;
        io_customOut[13]   = classification;
        io_customOut[14]   = external_mode;
        io_customOut[15]   = 1'b1; // 外部命令协议版本1。
    end
endmodule
