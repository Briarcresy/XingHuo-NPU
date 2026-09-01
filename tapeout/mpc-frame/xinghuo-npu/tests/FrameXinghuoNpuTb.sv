// 中文：这是“Frame 集成测试”。信号会经过外部 user_io、FrameTop 和你的设计。
//       它检查 design 编号能否被选中，以及输入和输出能否通过真实连接传递。
//       标有“通常保留”的选择流程不要随意修改；标有“按设计修改”的功能检查
//       应替换为你自己的输入和期望输出。
// English: This is the Frame integration test. Signals travel through user_io,
//          FrameTop, and your design. Keep the selection sequence unless the
//          frame protocol changes. Edit the marked functional checks.

module FrameXinghuoNpuTb;

`ifndef FRAME_TEST_DESIGN_ID
    initial $error("FRAME_TEST_DESIGN_ID must be provided by the build tool");
`endif

    localparam int IO_WIDTH = 73;
    localparam int DESIGN_ID_WIDTH = 7;
    localparam logic [DESIGN_ID_WIDTH-1:0] DESIGN_ID = `FRAME_TEST_DESIGN_ID;
    localparam time HALF_PERIOD = 5ns;

    logic clock = 1'b0;
    logic reset = 1'b1;
    logic [IO_WIDTH-1:0] test_io_out = '0;
    logic [IO_WIDTH-1:0] test_io_oe = '0;
    tri [IO_WIDTH-1:0] user_io;

    always #(HALF_PERIOD) clock = ~clock;

    for (genvar io_index = 0; io_index < IO_WIDTH; io_index++) begin : gen_test_io
        assign user_io[io_index] = test_io_oe[io_index] ? test_io_out[io_index] : 1'bz;
    end

    FrameTop dut (
        .clock  (clock),
        .reset  (reset),
        .user_io(user_io)
    );

    // 设计payload[n]对应外部user_io[n+7]。
    task automatic write_register(input logic [4:0] address, input logic [7:0] data);
        begin
            @(negedge clock);
            test_io_out[19:15] = address;
            test_io_out[14:7] = data;
            test_io_oe[14:7] = 8'hff;
            test_io_out[20] = 1'b1;
            test_io_out[21] = 1'b0;
            @(posedge clock);
            #1ns;
            @(negedge clock);
            test_io_out[20] = 1'b0;
        end
    endtask

    task automatic read_register(input logic [4:0] address, output logic [7:0] data);
        begin
            @(negedge clock);
            test_io_out[19:15] = address;
            test_io_out[20] = 1'b0;
            test_io_out[21] = 1'b1;
            test_io_oe[14:7] = 8'h00;
            #1ns;
            data = user_io[14:7];
            @(negedge clock);
            test_io_out[21]  = 1'b0;
            test_io_oe[14:7] = 8'hff;
        end
    endtask

    task automatic load_word32(input logic [4:0] base_address, input logic [31:0] value);
        begin
            write_register(base_address + 0, value[7:0]);
            write_register(base_address + 1, value[15:8]);
            write_register(base_address + 2, value[23:16]);
            write_register(base_address + 3, value[31:24]);
        end
    endtask

    task automatic load_word64(input logic [4:0] base_address, input logic [63:0] value);
        begin
            write_register(base_address + 0, value[7:0]);
            write_register(base_address + 1, value[15:8]);
            write_register(base_address + 2, value[23:16]);
            write_register(base_address + 3, value[31:24]);
            write_register(base_address + 4, value[39:32]);
            write_register(base_address + 5, value[47:40]);
            write_register(base_address + 6, value[55:48]);
            write_register(base_address + 7, value[63:56]);
        end
    endtask

    initial begin
        logic [31:0] result;
        logic [7:0] read_data;
        integer wait_cycles;

        // reset期间用外部低7位选择本设计。
        test_io_oe[6:0] = 7'h7f;
        test_io_out[6:0] = DESIGN_ID;

        // 地址和读写控制始终由外部驱动；数据位只在写操作期间驱动。
        test_io_oe[19:15] = 5'h1f;
        test_io_oe[20] = 1'b1;
        test_io_oe[21] = 1'b1;
        test_io_oe[14:7] = 8'hff;

        repeat (20) @(posedge clock);
        @(negedge clock);
        reset = 1'b0;
        repeat (4) @(posedge clock);
        #1ns;

        if (!dut.selection_valid || !dut.design_selected[DESIGN_ID])
            $fatal(1, "XingHuo NPU was not selected through FrameTop");

        load_word32(5'h00, 32'h04030201);
        load_word32(5'h04, 32'h08070605);
        load_word64(5'h08, 64'hfffffffe00000001);
        write_register(5'h10, 8'd0);
        write_register(5'h11, 8'b00000001);

        wait_cycles = 0;
        while (user_io[23] !== 1'b1 && wait_cycles < 32) begin
            @(posedge clock);
            #1ns;
            wait_cycles = wait_cycles + 1;
        end
        if (user_io[23] !== 1'b1) $fatal(1, "Frame-connected NPU operation timed out");

        read_register(5'h14, read_data);
        result[7:0] = read_data;
        read_register(5'h15, read_data);
        result[15:8] = read_data;
        read_register(5'h16, read_data);
        result[23:16] = read_data;
        read_register(5'h17, read_data);
        result[31:24] = read_data;
        if (result !== 32'h302c1414)
            $fatal(1, "Frame-connected result mismatch: actual=%08h", result);

        $display("XINGHUO NPU MPC-FRAME INTEGRATION TEST PASS");
        $finish;
    end
endmodule


