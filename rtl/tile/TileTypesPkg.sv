// Tile层共享的协议常量和强类型定义。
// 将“魔数”集中在package中，是SystemVerilog工程常用的接口维护方式：协议字段、
// RAM Map或状态编码变化时只需修改一处，波形工具也能显示enum名称而非裸数字。
package TileTypesPkg;
    typedef enum logic [2:0] {
        HOST_OP_SET_ADDRESS = 3'd0,
        HOST_OP_WRITE_BYTE  = 3'd1,
        HOST_OP_READ_NEXT   = 3'd2,
        HOST_OP_START       = 3'd3,
        HOST_OP_START_DEMO  = 3'd4,
        HOST_OP_CLEAR       = 3'd5
    } host_opcode_t;

    typedef enum logic [3:0] {
        PAGE_STATUS  = 4'd0,
        PAGE_RAM     = 4'd1,
        PAGE_HIDDEN0 = 4'd2,
        PAGE_HIDDEN1 = 4'd3,
        PAGE_HIDDEN2 = 4'd4,
        PAGE_HIDDEN3 = 4'd5,
        PAGE_FINAL0  = 4'd6,
        PAGE_FINAL1  = 4'd7,
        PAGE_FINAL2  = 4'd8,
        PAGE_FINAL3  = 4'd9,
        PAGE_CLASS   = 4'd10
    } display_page_t;

    typedef enum logic [4:0] {
        NET_IDLE          = 5'd0,
        NET_CORE_CLEAR    = 5'd1,
        NET_LOAD_INPUT    = 5'd2,
        NET_LOAD_WEIGHT1  = 5'd3,
        NET_LOAD_BIAS1    = 5'd4,
        NET_LOAD_SHIFT1   = 5'd5,
        NET_CORE_WLOAD1   = 5'd6,
        NET_CORE_START1   = 5'd7,
        NET_CORE_WAIT1    = 5'd8,
        NET_WRITE_HIDDEN  = 5'd9,
        NET_LOAD_WEIGHT2  = 5'd10,
        NET_LOAD_BIAS2    = 5'd11,
        NET_LOAD_SHIFT2   = 5'd12,
        NET_CORE_WLOAD2   = 5'd13,
        NET_CORE_START2   = 5'd14,
        NET_CORE_WAIT2    = 5'd15,
        NET_WRITE_OUTPUT  = 5'd16,
        NET_WRITE_CLASS   = 5'd17,
        NET_WRITE_STATUS  = 5'd18,
        NET_WRITE_ERROR   = 5'd19,
        NET_FINISH        = 5'd20
    } network_state_t;

    localparam logic [7:0] RAM_ADDR_INPUT   = 8'h00; // 00..03
    localparam logic [7:0] RAM_ADDR_WEIGHT1 = 8'h10; // 10..13
    localparam logic [7:0] RAM_ADDR_BIAS1   = 8'h14; // 14..1b
    localparam logic [7:0] RAM_ADDR_SHIFT1  = 8'h1c;
    localparam logic [7:0] RAM_ADDR_HIDDEN  = 8'h20; // 20..23
    localparam logic [7:0] RAM_ADDR_WEIGHT2 = 8'h30; // 30..33
    localparam logic [7:0] RAM_ADDR_BIAS2   = 8'h34; // 34..3b
    localparam logic [7:0] RAM_ADDR_SHIFT2  = 8'h3c;
    localparam logic [7:0] RAM_ADDR_OUTPUT  = 8'h40; // 40..43
    localparam logic [7:0] RAM_ADDR_CLASS   = 8'h44;
    localparam logic [7:0] RAM_ADDR_STATUS  = 8'h45;
    localparam logic [7:0] RAM_ADDR_ERROR   = 8'h46;
endpackage
