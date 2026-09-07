// 集中处理来自Tile边界、可能与clock异步的数字输入。
// 本模块只完成两级CDC同步；多位总线的事务一致性仍由上层稳定窗口/握手保证。
module TileInputSynchronizer (
    input  logic        clock,
    input  logic        reset,
    input  logic [ 7:0] buttons_async,
    input  logic [ 7:0] dip_async,
    input  logic [15:0] custom_in_async,
    output logic [ 7:0] buttons_sync,
    output logic [ 7:0] dip_sync,
    output logic [15:0] custom_in_sync
);
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
            buttons_meta       <= buttons_async;
            buttons_sync_reg   <= buttons_meta;
            dip_meta           <= dip_async;
            dip_sync_reg       <= dip_meta;
            custom_in_meta     <= custom_in_async;
            custom_in_sync_reg <= custom_in_meta;
        end
    end

    assign buttons_sync = buttons_sync_reg;
    assign dip_sync = dip_sync_reg;
    assign custom_in_sync = custom_in_sync_reg;
endmodule
