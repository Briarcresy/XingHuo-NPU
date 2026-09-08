// XingHuo NPU 的 MPSoC-Digital Tile v1 用户模块。
// 端口名、方向和位宽与官方接口契约完全一致；最终Tile顶层由官方工具生成。
module XingHuoNpuTile #(
    // 默认按100 MHz时钟提供约10 ms机械按键稳定窗口。
    parameter integer BUTTON_DEBOUNCE_CYCLES = 1000000
) (
    input  logic        clock,            // MPSoC-Digital分配的Tile工作时钟。
    input  logic        reset,            // 平台提供的同步高有效Tile复位。
    output logic [ 7:0] io_led,           // 八个LED的待显示值。
    output logic        io_ledUpdate,     // LED值更新有效，当前持续为1。
    input  logic [ 7:0] io_btn,           // 外部机械按钮，属于异步输入。
    input  logic [ 7:0] io_dip,           // 外部DIP开关，属于异步输入。
    output logic [ 3:0] io_hex7seg_0,     // 低位十六进制显示值。
    output logic [ 3:0] io_hex7seg_1,     // 高位十六进制显示值。
    output logic        io_hex7segUpdate, // 数码管值更新有效，当前持续为1。
    output logic [15:0] io_customOut,      // 外部主机响应、状态和协议版本。
    input  logic [15:0] io_customIn,       // 外部主机模式/命令/Payload总线。
    output logic [ 7:0] io_ramAddr,        // 共享256×8 RAM单端口地址。
    output logic        io_ramWen,         // 共享RAM上升沿写使能。
    output logic [ 7:0] io_ramWdata,       // 共享RAM写数据。
    input  logic [ 7:0] io_ramRdata        // 当前地址对应的异步组合读数据。
);
    // Tile边界的三组异步输入在进入功能模块前统一同步。RAM读数据属于同一
    // clock域资源的组合读口，必须保持与地址对应，因此不经过普通CDC同步器。
    logic [7:0] buttons_stable;
    logic [7:0] button_pressed;
    logic [7:0] buttons_sync;
    logic [7:0] dip_sync;
    logic [15:0] custom_in_sync;

    logic external_mode_request; // 主机同步后的期望模式。
    logic external_mode;         // 顶层已安全完成交接的实际模式。

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

    // 组合条件先命名再使用，波形和代码审查中都能直接看到“是否可交接”以及
    // “哪个主设备获得RAM”这两个设计意图。这是总线仲裁器常见的grant写法。
    logic mode_handoff_ready;
    logic controller_ram_grant;
    logic host_ram_grant;

    always_comb begin
        mode_handoff_ready = !network_busy
                           && !manual_ram_write_request
                           && !host_ram_write_request
                           && !manual_start_programmable
                           && !manual_start_demo
                           && !host_start_programmable
                           && !host_start_demo
                           && !manual_clear_status
                           && !host_clear_status;
        controller_ram_grant = network_busy;
        host_ram_grant       = !controller_ram_grant && external_mode;
    end

    // CDC边界：后续模块只能看到buttons_sync/dip_sync/custom_in_sync。
    TileInputSynchronizer input_synchronizer (
        .clock(clock),
        .reset(reset),
        .buttons_async(io_btn),
        .dip_async(io_dip),
        .custom_in_async(io_customIn),
        .buttons_sync(buttons_sync),
        .dip_sync(dip_sync),
        .custom_in_sync(custom_in_sync)
    );

    // 将同步按钮的机械抖动过滤，并把一次按下转换为一个周期事件。
    ButtonConditioner #(
        .DEBOUNCE_CYCLES(BUTTON_DEBOUNCE_CYCLES)
    ) button_conditioner (
        .clock(clock),
        .reset(reset),
        .buttons_sync(buttons_sync),
        .buttons_stable(buttons_stable),
        .button_pressed(button_pressed)
    );

    // 手动控制器始终保存自己的地址和页面；只有手动模式且网络空闲时接收按钮。
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

    // 主机接口始终观察同步模式请求；只有交接到外部模式后才执行新命令。
    ExternalHostInterface host_interface (
        .clock(clock),
        .reset(reset),
        .enable(external_mode && external_mode_request),
        .network_busy(network_busy),
        .custom_in_sync(custom_in_sync),
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
        else if (mode_handoff_ready)
            external_mode <= external_mode_request;
    end

    // 只把实际选中模式产生的控制事件送给两层网络控制器。
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

    // 两层任务调度器内部复用同一个2×2 NPU Core，并在运行时取得RAM独占权。
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
    // 优先级为网络 > 外部主机/手动。三个来源都使用同一地址、写使能和数据口。
    always_comb begin
        if (controller_ram_grant) begin
            io_ramAddr  = controller_ram_address;
            io_ramWen   = controller_ram_write_enable;
            io_ramWdata = controller_ram_write_data;
        end else if (host_ram_grant) begin
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

    // 显示逻辑只旁路观察内部状态，不参与任务控制或计算数据路径。
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
    // customOut位定义：7:0读数据，8 ACK，9网络忙，10完成，11 Core忙，
    // 12错误，13分类，14实际外部模式，15协议版本1。
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
