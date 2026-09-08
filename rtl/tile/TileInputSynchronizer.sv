// 集中处理来自Tile边界、可能与clock异步的数字输入。
// 本模块只完成两级CDC同步；多位总线的事务一致性仍由上层稳定窗口/握手保证。
module TileInputSynchronizer (
    input  logic        clock,           // Tile目标时钟域。
    input  logic        reset,           // 同步高有效复位。
    input  logic [ 7:0] buttons_async,   // 来自Tile边界的原始按钮电平。
    input  logic [ 7:0] dip_async,       // 来自Tile边界的原始DIP电平。
    input  logic [15:0] custom_in_async, // 来自外部主机的原始命令总线。
    output logic [ 7:0] buttons_sync,    // 已进入clock域的按钮电平。
    output logic [ 7:0] dip_sync,        // 已进入clock域的DIP电平。
    output logic [15:0] custom_in_sync   // 已进入clock域的主机总线。
);
    // 每一组都是两级同步链。第一级可能进入亚稳态；第二级给第一级一个完整周期
    // 的恢复时间，业务逻辑只能使用第二级输出。ASYNC_REG属性提示综合与布局工具
    // 保留同步链结构并尽量缩短两级寄存器之间的物理连线。
    (* ASYNC_REG = "TRUE" *)logic [ 7:0] buttons_meta;
    (* ASYNC_REG = "TRUE" *)logic [ 7:0] buttons_sync_reg;
    (* ASYNC_REG = "TRUE" *)logic [ 7:0] dip_meta;
    (* ASYNC_REG = "TRUE" *)logic [ 7:0] dip_sync_reg;
    (* ASYNC_REG = "TRUE" *)logic [15:0] custom_in_meta;
    (* ASYNC_REG = "TRUE" *)logic [15:0] custom_in_sync_reg;

    always_ff @(posedge clock) begin
        if (reset) begin
            buttons_meta       <= '0;
            buttons_sync_reg   <= '0;
            dip_meta           <= '0;
            dip_sync_reg       <= '0;
            custom_in_meta     <= '0;
            custom_in_sync_reg <= '0;
        end else begin
            // 非阻塞赋值使sync_reg在本拍读取旧的meta，因此形成真正的两级流水，
            // 而不是同一拍穿过两级。总延迟通常为两个目标时钟采样沿。
            buttons_meta       <= buttons_async;
            buttons_sync_reg   <= buttons_meta;
            dip_meta           <= dip_async;
            dip_sync_reg       <= dip_meta;
            custom_in_meta     <= custom_in_async;
            custom_in_sync_reg <= custom_in_meta;
        end
    end

    // 使用独立内部寄存器承载ASYNC_REG属性，端口只作为同步后信号的清晰别名。
    assign buttons_sync = buttons_sync_reg;
    assign dip_sync = dip_sync_reg;
    assign custom_in_sync = custom_in_sync_reg;
endmodule
