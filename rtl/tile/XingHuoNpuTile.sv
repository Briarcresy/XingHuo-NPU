// XingHuo NPU 的 MPSoC-Digital Tile v1 用户模块。
// 端口名、方向和位宽与官方接口契约完全一致；最终Tile顶层由官方工具生成。
module XingHuoNpuTile #(
    // 默认按200 MHz时钟提供约10 ms机械按键稳定窗口。
    parameter integer BUTTON_DEBOUNCE_CYCLES = 2000000
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
    logic external_mode;         // 已安全完成交接的实际模式。
    logic manual_enable;
    logic host_enable;

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
    logic core_start_valid;
    logic core_start_ready;
    logic core_clear_error;
    logic core_weight_valid;
    logic core_weight_ready;
    logic [31:0] core_activation_matrix;
    logic [31:0] core_weight_matrix;
    logic [63:0] core_bias_vector;
    logic [4:0] core_quant_shift;
    logic core_result_valid;
    logic core_result_ready;
    logic [31:0] core_result;
    logic core_error;
    logic [4:0] core_error_code;
    logic core_weights_loaded;
    logic [15:0] core_cycle_count;
    logic [31:0] core_task_count;

    logic [7:0] led_value;
    logic [3:0] hex_low;
    logic [3:0] hex_high;

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
        .enable(manual_enable),
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
        .enable(host_enable),
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

    TileModeController mode_controller (
        .clock(clock),
        .reset(reset),
        .external_mode_request(external_mode_request),
        .network_busy(network_busy),
        .manual_ram_write_request(manual_ram_write_request),
        .host_ram_write_request(host_ram_write_request),
        .manual_start_programmable(manual_start_programmable),
        .manual_start_demo(manual_start_demo),
        .host_start_programmable(host_start_programmable),
        .host_start_demo(host_start_demo),
        .manual_clear_status(manual_clear_status),
        .host_clear_status(host_clear_status),
        .external_mode(external_mode),
        .manual_enable(manual_enable),
        .host_enable(host_enable)
    );

    TileCommandMux command_mux (
        .external_mode(external_mode),
        .manual_start_programmable(manual_start_programmable),
        .manual_start_demo(manual_start_demo),
        .manual_demo_input(manual_demo_input),
        .manual_clear_status(manual_clear_status),
        .host_start_programmable(host_start_programmable),
        .host_start_demo(host_start_demo),
        .host_demo_input(host_demo_input),
        .host_clear_status(host_clear_status),
        .controller_start_programmable(controller_start_programmable),
        .controller_start_demo(controller_start_demo),
        .controller_demo_input(controller_demo_input),
        .controller_clear_status(controller_clear_status)
    );

    // 网络控制器和计算Core是并列模块：控制器调度两层，Core只执行单层矩阵任务。
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
        .core_start_valid(core_start_valid),
        .core_start_ready(core_start_ready),
        .core_clear_error(core_clear_error),
        .core_weight_valid(core_weight_valid),
        .core_weight_ready(core_weight_ready),
        .core_activation_matrix(core_activation_matrix),
        .core_weight_matrix(core_weight_matrix),
        .core_bias_vector(core_bias_vector),
        .core_quant_shift(core_quant_shift),
        .core_busy(core_busy),
        .core_result_valid(core_result_valid),
        .core_result_ready(core_result_ready),
        .core_result(core_result),
        .core_error(core_error),
        .core_error_code(core_error_code)
    );

    XingHuo_NPU npu_core (
        .clk(clock),
        .rst(reset),
        .start_valid(core_start_valid),
        .start_ready(core_start_ready),
        .clear_error(core_clear_error),
        .weight_valid(core_weight_valid),
        .weight_ready(core_weight_ready),
        .activation_matrix(core_activation_matrix),
        .weight_matrix(core_weight_matrix),
        .bias_vector(core_bias_vector),
        .quant_shift(core_quant_shift),
        .busy(core_busy),
        .result_valid(core_result_valid),
        .result_ready(core_result_ready),
        .result_matrix(core_result),
        .error(core_error),
        .error_code(core_error_code),
        .weights_loaded(core_weights_loaded),
        .cycle_count(core_cycle_count),
        .task_count(core_task_count)
    );

    TileRamArbiter ram_arbiter (
        .reset(reset),
        .network_busy(network_busy),
        .external_mode(external_mode),
        .controller_address(controller_ram_address),
        .controller_write_enable(controller_ram_write_enable),
        .controller_write_data(controller_ram_write_data),
        .host_address(host_ram_address),
        .host_write_request(host_ram_write_request),
        .host_write_data(host_ram_write_data),
        .manual_address(manual_ram_address),
        .manual_write_request(manual_ram_write_request),
        .manual_write_data(manual_ram_write_data),
        .ram_address(io_ramAddr),
        .ram_write_enable(io_ramWen),
        .ram_write_data(io_ramWdata)
    );

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

    TileOutputAdapter output_adapter (
        .led_value(led_value),
        .hex_low(hex_low),
        .hex_high(hex_high),
        .host_read_data(host_read_data),
        .host_acknowledge_toggle(host_acknowledge_toggle),
        .network_busy(network_busy),
        .network_done(network_done),
        .core_busy(core_busy),
        .network_error(network_error),
        .classification(classification),
        .external_mode(external_mode),
        .io_led(io_led),
        .io_ledUpdate(io_ledUpdate),
        .io_hex7seg_0(io_hex7seg_0),
        .io_hex7seg_1(io_hex7seg_1),
        .io_hex7segUpdate(io_hex7segUpdate),
        .io_customOut(io_customOut)
    );
endmodule
